#===============================================================================
#  Pokemon Pathways Multiplayer - Room Manager
<<<<<<< HEAD
#  PHASE 2 v4.0 — Include rank in PLAYER_JOIN and MAP_PLAYER_LIST payloads
=======
#
#  Maps each map_id to the set of client IDs currently on it.
#  Handles join/leave broadcasts and initial player-list sync.
#
#  FIXES vs original:
#   * clients_on_map held @mutex then called @server.clients.find which is safe,
#     but player_join_map held @mutex across server.broadcast_to_map which calls
#     clients_on_map -> @mutex: deadlock. Resolved by releasing the lock before
#     any broadcasts.
#   * player_leave_map called from disconnect while other code may still hold
#     map locks; ordering is now consistent (mutate state -> release -> broadcast).
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
#===============================================================================

require_relative 'config'
require_relative 'packet'

class RoomManager
  def initialize(server)
    @server      = server
<<<<<<< HEAD
    @map_clients = {}
    @mutex       = Mutex.new
  end

  def player_join_map(client, map_id)
    old_map = client.map_id
    player_leave_map(client) if old_map && old_map != map_id

=======
    @map_clients = {}   # map_id (Integer) => Array<String client_id>
    @mutex       = Mutex.new
  end

  # ─── Join ────────────────────────────────────────────────────────────────────

  def player_join_map(client, map_id)
    old_map = client.map_id
    # Leave previous map first (broadcasts PLAYER_LEAVE there)
    player_leave_map(client) if old_map && old_map != map_id

    # Mutate state under lock; broadcast outside
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    @mutex.synchronize do
      @map_clients[map_id] ||= []
      @map_clients[map_id] << client.id unless @map_clients[map_id].include?(client.id)
    end
    client.map_id = map_id

<<<<<<< HEAD
    join_packet = MP_Packet.new(MP_PacketType::PLAYER_JOIN, {
      "client_id"     => client.id,
      "name"          => client.player_name,
      "x"             => client.pos_x,
      "y"             => client.pos_y,
      "direction"     => client.direction,
      "sprite"        => client.sprite_name,
      "character_hue" => client.character_hue,
      "trainer_type"  => client.trainer_type,
      "outfit"        => client.outfit,
      "party_display" => client.party_display,
      # Phase 2
      "rank"          => client.rank,
      "rank_tier"     => client.rank_tier
    })
    @server.broadcast_to_map(map_id, join_packet, client)

=======
    # Notify existing players on this map of the new arrival
    join_packet = MP_Packet.new(MP_PacketType::PLAYER_JOIN, {
      "client_id"    => client.id,
      "name"         => client.player_name,
      "x"            => client.pos_x,
      "y"            => client.pos_y,
      "direction"    => client.direction,
      "sprite"       => client.sprite_name,
      "outfit"       => client.outfit,
      "party_display"=> client.party_display
    })
    @server.broadcast_to_map(map_id, join_packet, client)

    # Send the joiner the current player list for this map
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    send_map_player_list(client, map_id)

    count = player_count_on_map(map_id)
    puts "[ROOM] #{client.player_name} joined map #{map_id} (#{count} player#{'s' if count != 1})"
  end

<<<<<<< HEAD
  def player_leave_map(client)
    return unless client.map_id
    old_map_id  = client.map_id
    client.map_id = nil
=======
  # ─── Leave ───────────────────────────────────────────────────────────────────

  def player_leave_map(client)
    return unless client.map_id
    old_map_id  = client.map_id
    client.map_id = nil   # clear before broadcast so this client is excluded
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095

    @mutex.synchronize do
      @map_clients[old_map_id]&.delete(client.id)
      @map_clients.delete(old_map_id) if @map_clients[old_map_id]&.empty?
    end

<<<<<<< HEAD
    @server.broadcast_to_map(old_map_id,
      MP_Packet.new(MP_PacketType::PLAYER_LEAVE, { "client_id" => client.id })
    )
    puts "[ROOM] #{client.player_name || client.id[0, 8]} left map #{old_map_id}"
  end

=======
    leave_packet = MP_Packet.new(MP_PacketType::PLAYER_LEAVE, {
      "client_id" => client.id
    })
    @server.broadcast_to_map(old_map_id, leave_packet)
    puts "[ROOM] #{client.player_name || client.id[0, 8]} left map #{old_map_id}"
  end

  # ─── Player list ─────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def send_map_player_list(client, map_id)
    player_list = clients_on_map(map_id)
      .reject { |c| c.id == client.id }
      .map do |c|
        {
<<<<<<< HEAD
          "client_id"     => c.id,
          "name"          => c.player_name,
          "x"             => c.pos_x,
          "y"             => c.pos_y,
          "direction"     => c.direction,
          "sprite"        => c.sprite_name,
          "character_hue" => c.character_hue,
          "trainer_type"  => c.trainer_type,
          "outfit"        => c.outfit,
          "party_display" => c.party_display,
          # Phase 2
          "rank"          => c.rank,
          "rank_tier"     => c.rank_tier
=======
          "client_id"    => c.id,
          "name"         => c.player_name,
          "x"            => c.pos_x,
          "y"            => c.pos_y,
          "direction"    => c.direction,
          "sprite"       => c.sprite_name,
          "outfit"       => c.outfit,
          "party_display"=> c.party_display
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
        }
      end

    client.send_packet(MP_Packet.new(MP_PacketType::MAP_PLAYER_LIST, {
      "map_id"  => map_id,
      "players" => player_list
    }))
  end

<<<<<<< HEAD
=======
  # ─── Queries ─────────────────────────────────────────────────────────────────

  # Returns live MP_Client objects for all players on a map.
  # NOTE: takes a snapshot of IDs under lock, then resolves outside - safe.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def clients_on_map(map_id)
    ids = @mutex.synchronize { (@map_clients[map_id] || []).dup }
    ids.map { |id| @server.clients.find(id) }.compact
  end

  def player_count_on_map(map_id)
    @mutex.synchronize { (@map_clients[map_id] || []).length }
  end

  def total_players
    @mutex.synchronize { @map_clients.values.flatten.uniq.length }
  end

<<<<<<< HEAD
=======
  # Returns players on the same map within VISIBLE_DISTANCE tiles, excluding self.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def visible_clients(client)
    return [] unless client.map_id
    clients_on_map(client.map_id).reject do |other|
      other.id == client.id ||
        distance(client, other) > MP_ServerConfig::VISIBLE_DISTANCE
    end
  end

  private

  def distance(a, b)
    dx = a.pos_x - b.pos_x
    dy = a.pos_y - b.pos_y
    Math.sqrt(dx * dx + dy * dy)
  end
end
