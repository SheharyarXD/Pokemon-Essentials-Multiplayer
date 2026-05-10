#===============================================================================
#  Pokemon Pathways Multiplayer - Room Manager
#  Manages map rooms and player visibility (20 tile radius)
#  Handles join/leave broadcasts and map player lists
#===============================================================================

require_relative 'config'
require_relative 'packet'

class RoomManager
  def initialize(server)
    @server = server
    @map_clients = {}  # map_id => [client_ids]
    @mutex = Mutex.new
  end

  def player_join_map(client, map_id)
    old_map = client.map_id
    player_leave_map(client) if old_map && old_map != map_id

    client.map_id = map_id
    @mutex.synchronize do
      @map_clients[map_id] ||= []
      @map_clients[map_id] << client.id unless @map_clients[map_id].include?(client.id)
    end

    # Notify other players on this map about the new player
    join_packet = MP_Packet.new(MP_PacketType::PLAYER_JOIN, {
      client_id: client.id,
      name: client.player_name,
      x: client.pos_x,
      y: client.pos_y,
      direction: client.direction,
      sprite: client.sprite_name,
      outfit: client.outfit,
      party_display: client.party_display
    })
    @server.broadcast_to_map(map_id, join_packet, client)

    # Send existing players to the joining player
    send_map_player_list(client, map_id)

    puts "[ROOM] #{client.player_name} joined map #{map_id} (#{player_count_on_map(map_id)} players)"
  end

  def player_leave_map(client)
    return unless client.map_id
    old_map_id = client.map_id

    @mutex.synchronize do
      @map_clients[old_map_id]&.delete(client.id)
      @map_clients.delete(old_map_id) if @map_clients[old_map_id]&.empty?
    end

    # Notify remaining players
    leave_packet = MP_Packet.new(MP_PacketType::PLAYER_LEAVE, {
      client_id: client.id
    })
    @server.broadcast_to_map(old_map_id, leave_packet)
    puts "[ROOM] #{client.player_name} left map #{old_map_id}"
    client.map_id = nil
  end

  def send_map_player_list(client, map_id)
    existing = clients_on_map(map_id)
    player_list = existing.reject { |c| c.id == client.id }.map do |c|
      {
        client_id: c.id,
        name: c.player_name,
        x: c.pos_x,
        y: c.pos_y,
        direction: c.direction,
        sprite: c.sprite_name,
        outfit: c.outfit,
        party_display: c.party_display
      }
    end

    client.send_packet(MP_Packet.new(MP_PacketType::MAP_PLAYER_LIST, {
      map_id: map_id,
      players: player_list
    }))
  end

  def clients_on_map(map_id)
    @mutex.synchronize do
      ids = @map_clients[map_id] || []
      ids.map { |id| @server.clients.find(id) }.compact
    end
  end

  def player_count_on_map(map_id)
    @mutex.synchronize { (@map_clients[map_id] || []).length }
  end

  def total_players
    @mutex.synchronize do
      @map_clients.values.flatten.uniq.length
    end
  end

  def visible_clients(client)
    return [] unless client.map_id
    all = clients_on_map(client.map_id)
    all.reject do |other|
      other.id == client.id || distance(client, other) > MP_ServerConfig::VISIBLE_DISTANCE
    end
  end

  def distance(client_a, client_b)
    dx = client_a.pos_x - client_b.pos_x
    dy = client_a.pos_y - client_b.pos_y
    Math.sqrt(dx * dx + dy * dy)
  end
end
