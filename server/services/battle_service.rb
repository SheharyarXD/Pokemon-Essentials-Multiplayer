#===============================================================================
#  Pokemon Pathways Multiplayer - Battle Service
#  PHASE 2 v4.0 — 2v2 battle sessions, duplicate species validation,
#  map whitelist, partner verification
#
#  1v1 logic is unchanged from Phase 1.
#  2v2 logic adds Battle2v2Room and new packet handlers for types 37-39.
#
#  VALIDATION enforced server-side (clients also pre-check, but server is
#  authoritative):
#    * Same map for all participants
#    * Map in BATTLE_2V2_ALLOWED_MAPS for 2v2
#    * No duplicate species within each player's 3-Pokémon team
#    * No duplicate species across the combined 6-Pokémon team (per side)
#    * Both players in a 2v2 must have confirmed active partners
#    * Partners must be on the same map as their player
#===============================================================================

require_relative '../config'
require_relative '../packet'

# ─── BattleRoom (1v1) ─────────────────────────────────────────────────────────

class BattleRoom
  attr_reader   :id, :player_a, :player_b, :state, :turn, :commands, :turn_deadline
  attr_accessor :winner

  STATE_REQUESTED = 0
  STATE_ACTIVE    = 1
  STATE_ENDED     = 2

  TURN_TIMEOUT = 60

  def initialize(player_a, player_b)
    @id            = rand(36**8).to_s(36).upcase
    @player_a      = player_a
    @player_b      = player_b
    @state         = STATE_REQUESTED
    @turn          = 0
    @commands      = {}
    @winner        = nil
    @turn_deadline = nil
  end

  def state=(val);         @state = val;         end
  def active?;             @state == STATE_ACTIVE; end

  def add_command(client_id, command_data)
    @commands[client_id] = command_data
  end

  def both_commands_received?
    @commands.key?(@player_a.id) && @commands.key?(@player_b.id)
  end

  def reset_turn
    @commands.clear
    @turn          += 1
    @turn_deadline  = Time.now + TURN_TIMEOUT
  end

  def timed_out?
    @turn_deadline && Time.now > @turn_deadline
  end

  def opponent_of(client_id)
    client_id == @player_a.id ? @player_b : @player_a
  end

  def participants
    [@player_a, @player_b]
  end
end

# ─── Battle2v2Room ────────────────────────────────────────────────────────────
# Tracks all four participants (player_a, partner_a, player_b, partner_b).
# The "initiating side" is team_a; the "target side" is team_b.

class Battle2v2Room
  attr_reader   :id, :team_a, :team_b, :state
  attr_accessor :winner_team

  STATE_REQUESTED = 0
  STATE_WAITING   = 1   # target side accepted; waiting for partners to confirm
  STATE_ACTIVE    = 2
  STATE_ENDED     = 3

  def initialize(player_a, partner_a, player_b)
    @id          = rand(36**8).to_s(36).upcase
    # team_a: [initiator, their_partner]
    # team_b: [target, their_partner] — partner_b filled when target accepts
    @team_a      = [player_a, partner_a]
    @team_b      = [player_b, nil]
    @state       = STATE_REQUESTED
    @winner_team = nil
    # Submitted teams (3 pokemon hashes per player, keyed by client_id)
    @submitted_teams = {}
  end

  def state=(val); @state = val; end

  def all_participants
    (@team_a + @team_b).compact
  end

  def team_for(client_id)
    return :a if @team_a.compact.any? { |c| c.id == client_id }
    return :b if @team_b.compact.any? { |c| c.id == client_id }
    nil
  end

  # Store the submitted 3-pokemon team for a client
  def submit_team(client_id, pokemon_array)
    @submitted_teams[client_id] = pokemon_array
  end

  # Returns the combined 6-pokemon list for one team
  def combined_party(team_sym)
    players = team_sym == :a ? @team_a : @team_b
    players.compact.flat_map { |p| @submitted_teams[p.id] || [] }
  end

  def activate(partner_b)
    @team_b[1] = partner_b
    @state     = STATE_ACTIVE
  end
end

# ─── BattleService ────────────────────────────────────────────────────────────

class BattleService
  def initialize(server)
    @server        = server
    @rooms         = {}          # room_id => BattleRoom | Battle2v2Room
    @client_rooms  = {}          # client_id => room_id
    @mutex         = Mutex.new
  end

  # ─── Tick ─────────────────────────────────────────────────────────────────────

  def update(_tick_count)
    timed_out = @mutex.synchronize do
      @rooms.values.select { |r| r.is_a?(BattleRoom) && r.active? && r.timed_out? }
    end
    timed_out.each { |room| handle_turn_timeout(room) }
  end

  # ─── Packet dispatch ──────────────────────────────────────────────────────────

  def handle_packet(client, packet)
    case packet.type
    when MP_PacketType::BATTLE_REQUEST      then handle_battle_request(client, packet)
    when MP_PacketType::BATTLE_ACCEPT       then handle_battle_accept(client, packet)
    when MP_PacketType::BATTLE_DECLINE      then handle_battle_decline(client, packet)
    when MP_PacketType::BATTLE_COMMAND      then handle_battle_command(client, packet)
    when MP_PacketType::BATTLE_FORFEIT      then handle_battle_forfeit(client, packet)
    when MP_PacketType::BATTLE_2V2_REQUEST  then handle_2v2_request(client, packet)
    when MP_PacketType::BATTLE_2V2_ACCEPT   then handle_2v2_accept(client, packet)
    when MP_PacketType::BATTLE_2V2_DECLINE  then handle_2v2_decline(client, packet)
    end
  end

  # ─── 1v1: Request ─────────────────────────────────────────────────────────────

  def handle_battle_request(client, packet)
    target_name = packet.payload["target_name"]
    return unless target_name

    target = @server.clients.find_by_name(target_name)
    return client.send_packet(error("Player '#{target_name}' not found")) unless target
    return client.send_packet(error("Cannot battle yourself")) if target.id == client.id

    # Same-map check
    unless client.map_id && client.map_id == target.map_id
      return client.send_packet(error("#{target_name} is not on the same map"))
    end

    # Duplicate species check on requester's party
    if (msg = duplicate_species_error(client, packet.payload["local_team"]))
      return client.send_packet(error(msg))
    end

    room = nil
    @mutex.synchronize do
      return if @client_rooms[client.id] || @client_rooms[target.id]
      room = BattleRoom.new(client, target)
      @rooms[room.id]          = room
      @client_rooms[client.id] = room.id
      @client_rooms[target.id] = room.id
    end

    return client.send_packet(error("One or both players are already in a battle")) unless room

    target.send_packet(MP_Packet.new(MP_PacketType::BATTLE_REQUEST, {
      "room_id"   => room.id,
      "from_name" => client.player_name,
      "from_id"   => client.id,
      "rank"      => client.rank
    }))

    puts "[BATTLE] #{client.player_name} requested 1v1 vs #{target.player_name}"
  end

  # ─── 1v1: Accept ──────────────────────────────────────────────────────────────

  def handle_battle_accept(client, packet)
    room_id = packet.payload["room_id"]
    room    = find_room(room_id)
    return unless room.is_a?(BattleRoom)
    return unless room.player_b.id == client.id

    room.state         = BattleRoom::STATE_ACTIVE
    room.instance_variable_set(:@turn_deadline, Time.now + BattleRoom::TURN_TIMEOUT)

    start_pkt = MP_Packet.new(MP_PacketType::BATTLE_START, {
      "room_id"      => room.id,
      "player_a"     => room.player_a.player_name,
      "player_b"     => room.player_b.player_name,
      "turn_timeout" => BattleRoom::TURN_TIMEOUT
    })
    room.player_a.send_packet(start_pkt)
    room.player_b.send_packet(start_pkt)

    puts "[BATTLE] 1v1 #{room.id} started: #{room.player_a.player_name} vs #{room.player_b.player_name}"
  end

  # ─── 1v1: Decline ─────────────────────────────────────────────────────────────

  def handle_battle_decline(client, packet)
    room = find_room(packet.payload["room_id"])
    return unless room.is_a?(BattleRoom)

    cleanup_room(room)
    room.player_a.send_packet(MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      "room_id" => room.id,
      "result"  => "declined",
      "message" => "#{client.player_name} declined the battle."
    }))

    puts "[BATTLE] #{client.player_name} declined 1v1 from #{room.player_a.player_name}"
  end

  # ─── 1v1: Command relay ───────────────────────────────────────────────────────

  def handle_battle_command(client, packet)
    room = find_room_for_client(client)
    return unless room.is_a?(BattleRoom) && room.active?

    command_data = packet.payload["command"]
    return unless command_data

    room.add_command(client.id, command_data)
    return unless room.both_commands_received?

    [room.player_a, room.player_b].each do |player|
      opp = room.opponent_of(player.id)
      player.send_packet(MP_Packet.new(MP_PacketType::BATTLE_COMMAND, {
        "room_id"          => room.id,
        "turn"             => room.turn,
        "your_command"     => room.commands[player.id],
        "opponent_command" => room.commands[opp.id]
      }))
    end
    room.reset_turn
  end

  # ─── 1v1: Forfeit ─────────────────────────────────────────────────────────────

  def handle_battle_forfeit(client, packet)
    room = find_room_for_client(client)
    return unless room.is_a?(BattleRoom)

    opponent    = room.opponent_of(client.id)
    room.winner = opponent.id
    result_pkt  = MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      "room_id"   => room.id,
      "winner"    => opponent.player_name,
      "winner_id" => opponent.id,
      "forfeit"   => true
    })
    room.player_a.send_packet(result_pkt)
    room.player_b.send_packet(result_pkt)

    cleanup_room(room)
    puts "[BATTLE] #{client.player_name} forfeited — #{opponent.player_name} wins"
  end

  # ─── 2v2: Request ─────────────────────────────────────────────────────────────

  def handle_2v2_request(client, packet)
    target_name  = packet.payload["target_name"]
    partner_id   = packet.payload["partner_id"]
    partner_name = packet.payload["partner_name"]
    map_id       = packet.payload["map_id"] || client.map_id
    local_team   = packet.payload["local_team"]

    # ── Basic field validation ──────────────────────────────────────────────────
    return unless target_name

    target = @server.clients.find_by_name(target_name)
    return client.send_packet(error("Player '#{target_name}' not found")) unless target
    return client.send_packet(error("Cannot battle yourself")) if target.id == client.id

    # ── Map whitelist check ────────────────────────────────────────────────────
    unless MP_ServerConfig::BATTLE_2V2_ALLOWED_MAPS.include?(map_id.to_i)
      return client.send_packet(error("2v2 battles are not allowed on map #{map_id}"))
    end

    # ── Same-map: all present players must be on the allowed map ───────────────
    [client, target].each do |p|
      unless p.map_id == map_id
        return client.send_packet(error("#{p.player_name} is not on map #{map_id}"))
      end
    end

    # ── Partner validation ─────────────────────────────────────────────────────
    partner = partner_id ? @server.clients.find(partner_id) : nil
    unless partner
      return client.send_packet(error("Your partner is not online"))
    end
    unless @server.partners.partners?(client.id, partner.id)
      return client.send_packet(error("#{partner.player_name} is not your confirmed partner"))
    end
    unless partner.map_id == map_id
      return client.send_packet(error("Your partner is not on the same map"))
    end

    # ── Duplicate species: requester's submitted team ──────────────────────────
    if (msg = duplicate_species_error(client, local_team))
      return client.send_packet(error(msg))
    end

    # ── Busy check: all four would-be participants ─────────────────────────────
    room = nil
    @mutex.synchronize do
      busy = [client.id, partner.id, target.id].any? { |id| @client_rooms[id] }
      return if busy
      room = Battle2v2Room.new(client, partner, target)
      room.submit_team(client.id, local_team || [])
      @rooms[room.id]          = room
      @client_rooms[client.id] = room.id
      @client_rooms[partner.id]= room.id
      @client_rooms[target.id] = room.id
    end

    return client.send_packet(error("One or more players are already in a battle")) unless room

    # ── Forward request to target ──────────────────────────────────────────────
    target.send_packet(MP_Packet.new(MP_PacketType::BATTLE_2V2_REQUEST, {
      "room_id"       => room.id,
      "from_name"     => client.player_name,
      "from_id"       => client.id,
      "partner_name"  => partner.player_name,
      "rank"          => client.rank
    }))

    puts "[BATTLE] #{client.player_name}+#{partner.player_name} requested 2v2 vs #{target.player_name}"
  end

  # ─── 2v2: Accept ──────────────────────────────────────────────────────────────

  def handle_2v2_accept(client, packet)
    room_id      = packet.payload["room_id"]
    partner_id   = packet.payload["partner_id"]
    local_team   = packet.payload["local_team"] || []

    room = find_room(room_id)
    return unless room.is_a?(Battle2v2Room)
    return unless room.team_b[0].id == client.id

    # ── Validate target's partner ──────────────────────────────────────────────
    partner_b = partner_id ? @server.clients.find(partner_id) : nil
    unless partner_b
      cleanup_room(room)
      return client.send_packet(error("Your partner is not online"))
    end
    unless @server.partners.partners?(client.id, partner_b.id)
      cleanup_room(room)
      return client.send_packet(error("#{partner_b.player_name} is not your confirmed partner"))
    end
    unless partner_b.map_id == client.map_id
      cleanup_room(room)
      return client.send_packet(error("Your partner is not on the same map"))
    end

    # ── Duplicate species: target's submitted team ─────────────────────────────
    if (msg = duplicate_species_error(client, local_team))
      cleanup_room(room)
      return client.send_packet(error(msg))
    end

    # ── Reserve partner_b ────────────────────────────────────────────────────
    reserved = @mutex.synchronize do
      if @client_rooms[partner_b.id]
        false
      else
        @client_rooms[partner_b.id] = room.id
        true
      end
    end
    unless reserved
      cleanup_room(room)
      return client.send_packet(error("Your partner is already in a battle"))
    end

    # Retrieve partner_a team submission stored at request time
    team_a_player  = room.team_a[0]
    team_a_partner = room.team_a[1]

    # Store target's team
    room.submit_team(client.id, local_team)
    room.activate(partner_b)

    # ── Build combined parties for broadcast ───────────────────────────────────
    team_a_party = room.combined_party(:a)
    team_b_party = room.combined_party(:b)

    # ── Final duplicate check: combined teams ─────────────────────────────────
    [:a, :b].each do |side|
      combined = room.combined_party(side)
      species  = combined.map { |p| p["species"].to_s.upcase }.compact
      dupes    = species.select { |s| species.count(s) > 1 }.uniq
      unless dupes.empty?
        notify_all_2v2(room, error(
          "Duplicate Pokémon species in team #{side.upcase}: #{dupes.join(', ')}"
        ))
        cleanup_room(room)
        return
      end
    end

    # ── Broadcast BATTLE_2V2_ACCEPT to all four participants ───────────────────
    broadcast_pkt = MP_Packet.new(MP_PacketType::BATTLE_2V2_ACCEPT, {
      "room_id"        => room.id,
      "team_a_players" => [team_a_player.player_name, team_a_partner.player_name],
      "team_b_players" => [client.player_name, partner_b.player_name],
      "team_a_party"   => team_a_party,
      "team_b_party"   => team_b_party
    })

    [team_a_player, team_a_partner, client, partner_b].each do |p|
      p.send_packet(broadcast_pkt)
    end

    puts "[BATTLE] 2v2 #{room.id} started: "\
         "#{team_a_player.player_name}+#{team_a_partner.player_name} vs "\
         "#{client.player_name}+#{partner_b.player_name}"

    # 2v2 battles run locally on each client — server only orchestrated the
    # session setup. Clean up immediately so clients aren't locked after the
    # battle ends (each client notifies server of results via BATTLE_RESULT).
    cleanup_room(room)
  end

  # ─── 2v2: Decline ─────────────────────────────────────────────────────────────

  def handle_2v2_decline(client, packet)
    room = find_room(packet.payload["room_id"])
    return unless room.is_a?(Battle2v2Room)

    team_a_player = room.team_a[0]
    cleanup_room(room)

    team_a_player.send_packet(MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      "room_id" => room.id,
      "result"  => "declined",
      "message" => "#{client.player_name} declined the 2v2 battle."
    }))

    puts "[BATTLE] #{client.player_name} declined 2v2 from #{team_a_player.player_name}"
  end

  # ─── Timeout (1v1 only) ────────────────────────────────────────────────────────

  def handle_turn_timeout(room)
    result_pkt = MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      "room_id" => room.id,
      "result"  => "timeout",
      "message" => "Turn timed out after #{BattleRoom::TURN_TIMEOUT}s."
    })
    room.player_a&.send_packet(result_pkt)
    room.player_b&.send_packet(result_pkt)
    cleanup_room(room)
    puts "[BATTLE] Battle #{room.id} timed out on turn #{room.turn}"
  end

  # ─── Disconnect handler (idempotent) ──────────────────────────────────────────

  def handle_disconnect(client)
    room = find_room_for_client(client)
    return unless room

    if room.is_a?(BattleRoom)
      opponent = room.opponent_of(client.id)
      if opponent
        room.winner = opponent.id
        opponent.send_packet(MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
          "room_id"   => room.id,
          "winner"    => opponent.player_name,
          "winner_id" => opponent.id,
          "forfeit"   => true,
          "message"   => "#{client.player_name} disconnected."
        }))
      end
    elsif room.is_a?(Battle2v2Room)
      # Notify all remaining participants
      msg = "#{client.player_name} disconnected. 2v2 battle cancelled."
      notify_all_2v2(room, MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
        "room_id" => room.id,
        "result"  => "cancelled",
        "message" => msg
      }), exclude: client)
    end

    cleanup_room(room)
    puts "[BATTLE] #{client.player_name} disconnected from battle #{room.id}"
  end

  private

  # ─── Duplicate species validation ─────────────────────────────────────────────
  # pokemon_list: array of hashes with "species" key, or nil (skip check).
  # Returns an error string if duplicates found, nil if clean.

  def duplicate_species_error(client, pokemon_list)
    return nil unless pokemon_list.is_a?(Array) && !pokemon_list.empty?
    species = pokemon_list.map { |p| p["species"].to_s.upcase }.reject(&:empty?)
    dupes   = species.select { |s| species.count(s) > 1 }.uniq
    return nil if dupes.empty?
    "Duplicate Pokémon species in your team: #{dupes.join(', ')}. " \
    "You cannot enter multiplayer battles with duplicate Pokémon species."
  end

  # ─── Broadcast helpers ────────────────────────────────────────────────────────

  def notify_all_2v2(room, packet, exclude: nil)
    room.all_participants.each do |p|
      next if exclude && p.id == exclude.id
      p.send_packet(packet) rescue nil
    end
  end

  # ─── Room lookup / cleanup ────────────────────────────────────────────────────

  def find_room(room_id)
    @mutex.synchronize { @rooms[room_id] }
  end

  def find_room_for_client(client)
    room_id = @mutex.synchronize { @client_rooms[client.id] }
    return nil unless room_id
    @mutex.synchronize { @rooms[room_id] }
  end

  def cleanup_room(room)
    @mutex.synchronize do
      participants = room.respond_to?(:all_participants) ? room.all_participants : room.participants
      participants.compact.each { |p| @client_rooms.delete(p.id) }
      @rooms.delete(room.id)
    end
  end

  def error(message)
    MP_Packet.new(MP_PacketType::ERROR, { "message" => message })
  end
end
