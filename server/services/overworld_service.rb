#===============================================================================
#  Pokemon Pathways Multiplayer - Overworld Service
#  Handles PLAYER_MOVE, MAP_CHANGE, broadcasts positions to same-room players
#  Includes delta compression (only send if changed) and party display
#===============================================================================

require_relative '../config'
require_relative '../packet'

class OverworldService
  def initialize(server)
    @server = server
    @pending_moves = {}  # client_id => {x, y, direction, tick}
    @last_positions = {} # client_id => {x, y, dir} for delta compression
  end

  def update(tick_count)
    # Periodic position sync broadcast every N ticks
    if tick_count % MP_ServerConfig::POSITION_SYNC_INTERVAL == 0
      broadcast_positions
    end
  end

  def handle_packet(client, packet)
    return unless client.map_id

    case packet.type
    when MP_PacketType::PLAYER_MOVE
      handle_move(client, packet)
    when MP_PacketType::PLAYER_DIR
      handle_direction(client, packet)
    when MP_PacketType::MAP_CHANGE
      handle_map_change(client, packet)
    when MP_PacketType::PLAYER_SPRITE
      handle_sprite_change(client, packet)
    when MP_PacketType::PLAYER_ACTION
      handle_action(client, packet)
    when MP_PacketType::PLAYER_PARTY
      handle_party_update(client, packet)
    end
  end

  def handle_move(client, packet)
    x = packet.payload["x"]
    y = packet.payload["y"]
    direction = packet.payload["direction"]
    return unless x && y

    # Update client state
    client.pos_x = x
    client.pos_y = y
    client.direction = direction if direction

    # Store for batch broadcast
    @pending_moves[client.id] = {
      x: x,
      y: y,
      direction: client.direction,
      tick: Time.now.to_f
    }
  end

  def handle_direction(client, packet)
    direction = packet.payload["direction"]
    return unless direction

    client.direction = direction

    # Broadcast direction change immediately to visible players
    dir_packet = MP_Packet.new(MP_PacketType::PLAYER_DIR, {
      client_id: client.id,
      direction: direction
    })
    @server.broadcast_to_map(client.map_id, dir_packet, client)
  end

  def handle_map_change(client, packet)
    map_id = packet.payload["map_id"]
    x = packet.payload["x"] || client.pos_x
    y = packet.payload["y"] || client.pos_y
    direction = packet.payload["direction"] || client.direction
    return unless map_id

    client.pos_x = x
    client.pos_y = y
    client.direction = direction

    # Remove from old map, add to new map
    @server.rooms.player_join_map(client, map_id)

    # Clear pending moves during map transition
    @pending_moves.delete(client.id)
    @last_positions.delete(client.id)
  end

  def handle_sprite_change(client, packet)
    sprite = packet.payload["sprite"]
    outfit = packet.payload["outfit"]
    client.sprite_name = sprite if sprite
    client.outfit = outfit if outfit

    # Notify other players of sprite change
    sprite_packet = MP_Packet.new(MP_PacketType::PLAYER_SPRITE, {
      client_id: client.id,
      sprite: client.sprite_name,
      outfit: client.outfit
    })
    @server.broadcast_to_map(client.map_id, sprite_packet, client)
  end

  def handle_action(client, packet)
    action = packet.payload["action"]
    return unless action

    # Broadcast action to other players on same map
    action_packet = MP_Packet.new(MP_PacketType::PLAYER_ACTION, {
      client_id: client.id,
      action: action,
      x: client.pos_x,
      y: client.pos_y
    })
    @server.broadcast_to_map(client.map_id, action_packet, client)
  end

  def handle_party_update(client, packet)
    party_data = packet.payload["party"]
    return unless party_data && party_data.is_a?(Array) && !party_data.empty?

    first_pokemon = party_data[0]
    client.party_display = {
      species: first_pokemon["species"] || first_pokemon[:species],
      level: first_pokemon["level"] || first_pokemon[:level]
    }

    # Broadcast party display to other players
    party_packet = MP_Packet.new(MP_PacketType::PLAYER_DATA, {
      client_id: client.id,
      party_display: client.party_display
    })
    @server.broadcast_to_map(client.map_id, party_packet, client)
  end

  def broadcast_positions
    return if @pending_moves.empty?

    # Group updates by map for efficient broadcasting
    updates_by_map = {}

    @pending_moves.each do |client_id, move_data|
      client = @server.clients.find(client_id)
      next unless client && client.map_id

      # Delta compression: only include if position changed since last broadcast
      last = @last_positions[client_id]
      if last && last[:x] == move_data[:x] && last[:y] == move_data[:y] && last[:direction] == move_data[:direction]
        next
      end

      @last_positions[client_id] = move_data.dup

      updates_by_map[client.map_id] ||= []
      updates_by_map[client.map_id] << {
        client_id: client_id,
        x: move_data[:x],
        y: move_data[:y],
        direction: move_data[:direction]
      }
    end

    @pending_moves.clear

    # Broadcast per map
    updates_by_map.each do |map_id, updates|
      next if updates.empty?

      sync_packet = MP_Packet.new(MP_PacketType::PLAYER_POS_SYNC, {
        players: updates
      })
      @server.broadcast_to_map(map_id, sync_packet)
    end
  end
end
