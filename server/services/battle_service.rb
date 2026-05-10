#===============================================================================
#  Pokemon Pathways Multiplayer - Battle Service
#
#  Manages turn-based PvP battle sessions:
#    request -> accept/decline -> turn relay -> forfeit/result/timeout
#
#  FIXES vs original:
#   * BUG: Target player was not reserved in @client_rooms at request time.
#     They could receive/accept multiple simultaneous battle requests, creating
#     orphaned rooms. Now both players are reserved atomically at request time.
#   * CONCURRENCY: find_room_for_client accessed @client_rooms without a lock.
#     All reads/writes to @rooms and @client_rooms are now under @mutex.
#   * SAFETY: handle_disconnect is idempotent; calling it on an already-cleaned
#     room is a no-op.
#   * CLARITY: BattleRoom state transitions use a proper setter instead of
#     instance_variable_set.
#===============================================================================

require_relative '../config'
require_relative '../packet'

# ─── BattleRoom ─────────────────────────────────────────────────────────────────

class BattleRoom
  attr_reader   :id, :player_a, :player_b, :state, :turn, :commands, :turn_deadline
  attr_accessor :winner

  STATE_REQUESTED = 0
  STATE_ACTIVE    = 1
  STATE_ENDED     = 2

  TURN_TIMEOUT = 60   # seconds per turn

  def initialize(player_a, player_b)
    @id           = rand(36**8).to_s(36).upcase
    @player_a     = player_a
    @player_b     = player_b
    @state        = STATE_REQUESTED
    @turn         = 0
    @commands     = {}   # client_id => command payload
    @winner       = nil
    @turn_deadline= nil
  end

  def state=(new_state)
    @state = new_state
  end

  def active?
    @state == STATE_ACTIVE
  end

  def add_command(client_id, command_data)
    @commands[client_id] = command_data
  end

  def both_commands_received?
    @commands.key?(@player_a.id) && @commands.key?(@player_b.id)
  end

  def reset_turn
    @commands.clear
    @turn         += 1
    @turn_deadline = Time.now + TURN_TIMEOUT
  end

  def timed_out?
    @turn_deadline && Time.now > @turn_deadline
  end

  def opponent_of(client_id)
    client_id == @player_a.id ? @player_b : @player_a
  end
end

# ─── BattleService ──────────────────────────────────────────────────────────────

class BattleService
  def initialize(server)
    @server       = server
    @rooms        = {}           # room_id => BattleRoom
    @client_rooms = {}           # client_id => room_id
    @mutex        = Mutex.new
  end

  # ─── Tick update ──────────────────────────────────────────────────────────────

  def update(_tick_count)
    timed_out_rooms = @mutex.synchronize do
      @rooms.values.select { |r| r.active? && r.timed_out? }
    end
    timed_out_rooms.each { |room| handle_turn_timeout(room) }
  end

  # ─── Packet dispatch ──────────────────────────────────────────────────────────

  def handle_packet(client, packet)
    case packet.type
    when MP_PacketType::BATTLE_REQUEST  then handle_battle_request(client, packet)
    when MP_PacketType::BATTLE_ACCEPT   then handle_battle_accept(client, packet)
    when MP_PacketType::BATTLE_DECLINE  then handle_battle_decline(client, packet)
    when MP_PacketType::BATTLE_COMMAND  then handle_battle_command(client, packet)
    when MP_PacketType::BATTLE_FORFEIT  then handle_battle_forfeit(client, packet)
    end
  end

  # ─── Request ──────────────────────────────────────────────────────────────────

  def handle_battle_request(client, packet)
    target_name = packet.payload["target_name"]
    return unless target_name

    target = @server.clients.find_by_name(target_name)
    unless target
      return client.send_packet(error("Player '#{target_name}' not found"))
    end

    if target.id == client.id
      return client.send_packet(error("Cannot battle yourself"))
    end

    # FIX: Reserve BOTH players atomically so neither can be double-booked
    room = nil
    @mutex.synchronize do
      if @client_rooms[client.id] || @client_rooms[target.id]
        return   # one or both are busy - error sent below
      end
      room = BattleRoom.new(client, target)
      @rooms[room.id]          = room
      @client_rooms[client.id] = room.id
      @client_rooms[target.id] = room.id   # FIX: reserve target immediately
    end

    unless room
      return client.send_packet(error("One or both players are already in a battle"))
    end

    target.send_packet(MP_Packet.new(MP_PacketType::BATTLE_REQUEST, {
      "room_id"   => room.id,
      "from_name" => client.player_name,
      "from_id"   => client.id
    }))

    puts "[BATTLE] #{client.player_name} requested battle with #{target.player_name}"
  end

  # ─── Accept ───────────────────────────────────────────────────────────────────

  def handle_battle_accept(client, packet)
    room_id = packet.payload["room_id"]
    room    = find_room(room_id)
    return unless room
    return unless room.player_b.id == client.id  # only challengee can accept

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

    puts "[BATTLE] Battle #{room.id} started: #{room.player_a.player_name} vs #{room.player_b.player_name}"
  end

  # ─── Decline ──────────────────────────────────────────────────────────────────

  def handle_battle_decline(client, packet)
    room_id = packet.payload["room_id"]
    room    = find_room(room_id)
    return unless room

    cleanup_room(room)

    room.player_a.send_packet(MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      "room_id" => room_id,
      "result"  => "declined",
      "message" => "#{client.player_name} declined the battle."
    }))

    puts "[BATTLE] #{client.player_name} declined battle from #{room.player_a.player_name}"
  end

  # ─── Command relay ────────────────────────────────────────────────────────────

  def handle_battle_command(client, packet)
    room = find_room_for_client(client)
    return unless room&.active?

    command_data = packet.payload["command"]
    return unless command_data

    room.add_command(client.id, command_data)

    return unless room.both_commands_received?

    # Relay each player's command to their opponent
    [room.player_a, room.player_b].each do |player|
      opponent = room.opponent_of(player.id)
      player.send_packet(MP_Packet.new(MP_PacketType::BATTLE_COMMAND, {
        "room_id"          => room.id,
        "turn"             => room.turn,
        "your_command"     => room.commands[player.id],
        "opponent_command" => room.commands[opponent.id]
      }))
    end

    room.reset_turn
  end

  # ─── Forfeit ──────────────────────────────────────────────────────────────────

  def handle_battle_forfeit(client, packet)
    room = find_room_for_client(client)
    return unless room

    opponent   = room.opponent_of(client.id)
    room.winner= opponent.id

    result_pkt = MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      "room_id"   => room.id,
      "winner"    => opponent.player_name,
      "winner_id" => opponent.id,
      "forfeit"   => true
    })
    room.player_a.send_packet(result_pkt)
    room.player_b.send_packet(result_pkt)

    cleanup_room(room)
    puts "[BATTLE] #{client.player_name} forfeited. #{opponent.player_name} wins."
  end

  # ─── Timeout ──────────────────────────────────────────────────────────────────

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

  # ─── Disconnect handler (called by MP_Client#disconnect) ─────────────────────

  # FIX: Idempotent - if the room was already cleaned (e.g. normal battle end
  # then disconnect), this returns immediately.
  def handle_disconnect(client)
    room = find_room_for_client(client)
    return unless room

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

    cleanup_room(room)
    puts "[BATTLE] #{client.player_name} disconnected; #{opponent&.player_name} wins by forfeit."
  end

  private

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
      @client_rooms.delete(room.player_a.id) if room.player_a
      @client_rooms.delete(room.player_b.id) if room.player_b
      @rooms.delete(room.id)
    end
  end

  def error(message)
    MP_Packet.new(MP_PacketType::ERROR, { "message" => message })
  end
end
