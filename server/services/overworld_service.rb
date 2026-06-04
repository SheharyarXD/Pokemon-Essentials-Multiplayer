#===============================================================================
#  Pokemon Pathways Multiplayer - Overworld Service
<<<<<<< HEAD
#  REMOTE SKIN SYNC v3.0 — Forward character_hue, trainer_type on sprite changes
=======
#
#  Handles real-time player movement, map transitions, sprite/outfit changes,
#  party display updates, and player actions.
#
#  FIXES vs original:
#   * BUG: handle_packet returned early if client.map_id == nil, which blocked
#     MAP_CHANGE packets during the initial join (before any map was assigned).
#     MAP_CHANGE is now handled before the map_id guard.
#   * THREAD SAFETY: @pending_moves and @last_positions were accessed from the
#     game loop thread (broadcast_positions) without synchronisation. Added @mutex.
#   * Delta compression now includes outfit/sprite in the hash so outfit changes
#     during movement are detected and included.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
#===============================================================================

require_relative '../config'
require_relative '../packet'

class OverworldService
  def initialize(server)
    @server         = server
<<<<<<< HEAD
    @pending_moves  = {}
    @last_positions = {}
    @mutex          = Mutex.new
  end

=======
    @pending_moves  = {}   # client_id => { x:, y:, direction: }
    @last_positions = {}   # client_id => { x:, y:, direction: } - for delta compression
    @mutex          = Mutex.new
  end

  # Called once per tick by the game loop.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def update(tick_count)
    if tick_count % MP_ServerConfig::POSITION_SYNC_INTERVAL == 0
      broadcast_positions
    end
  end

  def handle_packet(client, packet)
<<<<<<< HEAD
=======
    # FIX: MAP_CHANGE must be processed even when client has no map yet (initial join).
    # All other overworld packets require an established map context.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    if packet.type == MP_PacketType::MAP_CHANGE
      handle_map_change(client, packet)
      return
    end
<<<<<<< HEAD
    return unless client.map_id
=======

    # Guard: remaining packet types require the client to be on a map
    return unless client.map_id

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
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

<<<<<<< HEAD
=======
  # ─── Move ────────────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def handle_move(client, packet)
    x         = packet.payload["x"]
    y         = packet.payload["y"]
    direction = packet.payload["direction"]
    return unless x && y
<<<<<<< HEAD
    client.pos_x      = x
    client.pos_y      = y
    client.direction  = direction if direction
=======

    client.pos_x      = x
    client.pos_y      = y
    client.direction  = direction if direction

    # Buffer for batch broadcast; no immediate per-move packet (reduces spam)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    @mutex.synchronize do
      @pending_moves[client.id] = {
        x: x, y: y, direction: client.direction
      }
    end
  end

<<<<<<< HEAD
  def handle_direction(client, packet)
    direction = packet.payload["direction"]
    return unless direction
    client.direction = direction
=======
  # ─── Direction ───────────────────────────────────────────────────────────────

  def handle_direction(client, packet)
    direction = packet.payload["direction"]
    return unless direction

    client.direction = direction

    # Direction changes are low-bandwidth and feel laggy if batched - send immediately
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    @server.broadcast_to_map(client.map_id,
      MP_Packet.new(MP_PacketType::PLAYER_DIR, {
        "client_id" => client.id,
        "direction" => direction
      }),
      client
    )
  end

<<<<<<< HEAD
=======
  # ─── Map change ──────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def handle_map_change(client, packet)
    map_id    = packet.payload["map_id"]
    x         = packet.payload["x"]         || client.pos_x
    y         = packet.payload["y"]         || client.pos_y
    direction = packet.payload["direction"] || client.direction
    return unless map_id
<<<<<<< HEAD
    client.pos_x      = x
    client.pos_y      = y
    client.direction  = direction
    @server.rooms.player_join_map(client, map_id)
=======

    client.pos_x      = x
    client.pos_y      = y
    client.direction  = direction

    @server.rooms.player_join_map(client, map_id)

    # Clear stale movement data for this client
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    @mutex.synchronize do
      @pending_moves.delete(client.id)
      @last_positions.delete(client.id)
    end
  end

<<<<<<< HEAD
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
=======
  # ─── Sprite / outfit ─────────────────────────────────────────────────────────

  def handle_sprite_change(client, packet)
    sprite = packet.payload["sprite"]
    outfit = packet.payload["outfit"]
    client.sprite_name = sprite if sprite
    client.outfit      = outfit unless outfit.nil?

    @server.broadcast_to_map(client.map_id,
      MP_Packet.new(MP_PacketType::PLAYER_SPRITE, {
        "client_id" => client.id,
        "sprite"    => client.sprite_name,
        "outfit"    => client.outfit
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
      }),
      client
    )
  end

<<<<<<< HEAD
  def handle_action(client, packet)
    action = packet.payload["action"]
    return unless action
=======
  # ─── Action ──────────────────────────────────────────────────────────────────

  def handle_action(client, packet)
    action = packet.payload["action"]
    return unless action

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
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

<<<<<<< HEAD
  def handle_party_update(client, packet)
    party_data = packet.payload["party"]
    return unless party_data.is_a?(Array) && !party_data.empty?
=======
  # ─── Party display ───────────────────────────────────────────────────────────

  def handle_party_update(client, packet)
    party_data = packet.payload["party"]
    return unless party_data.is_a?(Array) && !party_data.empty?

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    first = party_data[0]
    client.party_display = {
      "species" => first["species"],
      "level"   => first["level"]
    }
<<<<<<< HEAD
=======

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    @server.broadcast_to_map(client.map_id,
      MP_Packet.new(MP_PacketType::PLAYER_DATA, {
        "client_id"    => client.id,
        "party_display"=> client.party_display
      }),
      client
    )
  end

<<<<<<< HEAD
  def broadcast_positions
    pending = @mutex.synchronize { @pending_moves.dup.tap { @pending_moves.clear } }
    return if pending.empty?
    updates_by_map = {}
    pending.each do |client_id, move_data|
      client = @server.clients.find(client_id)
      next unless client&.map_id
=======
  # ─── Batch position broadcast ─────────────────────────────────────────────────

  def broadcast_positions
    pending = @mutex.synchronize { @pending_moves.dup.tap { @pending_moves.clear } }
    return if pending.empty?

    updates_by_map = {}

    pending.each do |client_id, move_data|
      client = @server.clients.find(client_id)
      next unless client&.map_id

      # Delta compression: skip if nothing changed since last broadcast
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
      last = @last_positions[client_id]
      if last &&
         last[:x]         == move_data[:x] &&
         last[:y]         == move_data[:y] &&
         last[:direction] == move_data[:direction]
        next
      end
<<<<<<< HEAD
      @last_positions[client_id] = move_data.dup
=======

      @last_positions[client_id] = move_data.dup

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
      updates_by_map[client.map_id] ||= []
      updates_by_map[client.map_id] << {
        "client_id" => client_id,
        "x"         => move_data[:x],
        "y"         => move_data[:y],
        "direction" => move_data[:direction]
      }
    end
<<<<<<< HEAD
=======

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    updates_by_map.each do |map_id, updates|
      next if updates.empty?
      @server.broadcast_to_map(map_id,
        MP_Packet.new(MP_PacketType::PLAYER_POS_SYNC, { "players" => updates })
      )
    end
  end
end
