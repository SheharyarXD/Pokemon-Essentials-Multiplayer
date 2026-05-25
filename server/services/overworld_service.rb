#===============================================================================
#  Pokemon Pathways Multiplayer - Overworld Service
#  REMOTE SKIN SYNC v3.0 — Forward character_hue, trainer_type on sprite changes
#===============================================================================

require_relative '../config'
require_relative '../packet'

class OverworldService
  def initialize(server)
    @server         = server
    @pending_moves  = {}
    @last_positions = {}
    @mutex          = Mutex.new
  end

  def update(tick_count)
    if tick_count % MP_ServerConfig::POSITION_SYNC_INTERVAL == 0
      broadcast_positions
    end
  end

  def handle_packet(client, packet)
    if packet.type == MP_PacketType::MAP_CHANGE
      handle_map_change(client, packet)
      return
    end
    return unless client.map_id
    case packet.type
    when MP_PacketType::PLAYER_MOVE
      handle_move(client, packet)
    when MP_PacketType::PLAYER_DIR
      handle_direction(client, packet)
    when MP_PacketType::PLAYER_SPRITE
      handle_sprite_change(client, packet)
    when MP_PacketType::PLAYER_ACTION
      handle_action(client, packet)
    when MP_PacketType::PLAYER_PARTY
      handle_party_update(client, packet)
    end
  end

  private

  def handle_move(client, packet)
    x         = packet.payload["x"]
    y         = packet.payload["y"]
    direction = packet.payload["direction"]
    return unless x && y
    client.pos_x      = x
    client.pos_y      = y
    client.direction  = direction if direction
    @mutex.synchronize do
      @pending_moves[client.id] = {
        x: x, y: y, direction: client.direction
      }
    end
  end

  def handle_direction(client, packet)
    direction = packet.payload["direction"]
    return unless direction
    client.direction = direction
    @server.broadcast_to_map(client.map_id,
      MP_Packet.new(MP_PacketType::PLAYER_DIR, {
        "client_id" => client.id,
        "direction" => direction
      }),
      client
    )
  end

  def handle_map_change(client, packet)
    map_id    = packet.payload["map_id"]
    x         = packet.payload["x"]         || client.pos_x
    y         = packet.payload["y"]         || client.pos_y
    direction = packet.payload["direction"] || client.direction
    return unless map_id
    client.pos_x      = x
    client.pos_y      = y
    client.direction  = direction
    @server.rooms.player_join_map(client, map_id)
    @mutex.synchronize do
      @pending_moves.delete(client.id)
      @last_positions.delete(client.id)
    end
  end

  def handle_sprite_change(client, packet)
    sprite = packet.payload["sprite"]
    hue    = packet.payload["character_hue"]
    ttype  = packet.payload["trainer_type"]
    outfit = packet.payload["outfit"]
    client.sprite_name   = sprite if sprite
    client.character_hue = hue.to_i if hue
    client.trainer_type  = ttype.to_s if ttype
    client.outfit        = outfit unless outfit.nil?

    @server.broadcast_to_map(client.map_id,
      MP_Packet.new(MP_PacketType::PLAYER_SPRITE, {
        "client_id"     => client.id,
        "sprite"        => client.sprite_name,
        "character_hue" => client.character_hue,
        "trainer_type"  => client.trainer_type,
        "outfit"        => client.outfit
      }),
      client
    )
  end

  def handle_action(client, packet)
    action = packet.payload["action"]
    return unless action
    @server.broadcast_to_map(client.map_id,
      MP_Packet.new(MP_PacketType::PLAYER_ACTION, {
        "client_id" => client.id,
        "action"    => action,
        "x"         => client.pos_x,
        "y"         => client.pos_y
      }),
      client
    )
  end

  def handle_party_update(client, packet)
    party_data = packet.payload["party"]
    return unless party_data.is_a?(Array) && !party_data.empty?
    first = party_data[0]
    client.party_display = {
      "species" => first["species"],
      "level"   => first["level"]
    }
    @server.broadcast_to_map(client.map_id,
      MP_Packet.new(MP_PacketType::PLAYER_DATA, {
        "client_id"    => client.id,
        "party_display"=> client.party_display
      }),
      client
    )
  end

  def broadcast_positions
    pending = @mutex.synchronize { @pending_moves.dup.tap { @pending_moves.clear } }
    return if pending.empty?
    updates_by_map = {}
    pending.each do |client_id, move_data|
      client = @server.clients.find(client_id)
      next unless client&.map_id
      last = @last_positions[client_id]
      if last &&
         last[:x]         == move_data[:x] &&
         last[:y]         == move_data[:y] &&
         last[:direction] == move_data[:direction]
        next
      end
      @last_positions[client_id] = move_data.dup
      updates_by_map[client.map_id] ||= []
      updates_by_map[client.map_id] << {
        "client_id" => client_id,
        "x"         => move_data[:x],
        "y"         => move_data[:y],
        "direction" => move_data[:direction]
      }
    end
    updates_by_map.each do |map_id, updates|
      next if updates.empty?
      @server.broadcast_to_map(map_id,
        MP_Packet.new(MP_PacketType::PLAYER_POS_SYNC, { "players" => updates })
      )
    end
  end
end
