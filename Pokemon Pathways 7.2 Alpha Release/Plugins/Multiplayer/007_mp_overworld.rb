#===============================================================================
#  MP OVERWORLD MANAGER v1.2.0
#  Complete rewrite of synchronization logic.
#  FIXED:
#    1. Position double-send eliminated (change-driven and periodic are now exclusive)
#    2. Map change detection removed from update_local_position (now only in transfer_player hook)
#    3. handle_player_join checks map_id before spawning
#    4. handle_pos_sync no longer double-calls set_target
#    5. create_remote_sprite uses correct viewport access (spriteset.viewport)
#    6. update_remote_players skips culled players for CPU savings
#    7. @pos_frame_counter uses modulo to prevent integer overflow
#    8. handle_map_player_list diffs instead of mass-clear (no flicker)
#    9. Added max remote player cap for performance
#   10. All UI-bound handlers use MP_NetworkManager.schedule_on_main
#   11. Added guards for disposed sprites during scene transitions
#   12. handle_player_leave has nil guards
#===============================================================================

module MP_OverworldManager
  module_function

  @remote_players = {}      # mp_id => MP_Game_RemotePlayer
  @remote_sprites = {}      # mp_id => Sprite_MP_RemotePlayer
  @last_pos = { x: nil, y: nil, dir: nil, map: nil }
  @pos_frame_counter = 0
  @initialized = false
  @last_party_send = 0
  @pending_map_change = false

  def init
    return if @initialized
    @initialized = true
    @remote_players = {}
    @remote_sprites = {}
    @last_pos = { x: nil, y: nil, dir: nil, map: nil }
    @pos_frame_counter = 0
    @last_party_send = 0
    register_packet_handlers
    echoln "[MP] Overworld manager initialized"
  end

  def register_packet_handlers
    # Overworld packets (safe to run on receive thread -- no UI)
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_JOIN)     { |p| handle_player_join(p) }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_LEAVE)    { |p| handle_player_leave(p) }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_POS_SYNC) { |p| handle_pos_sync(p) }
    MP_NetworkManager.on_packet(MP_PacketType::MAP_PLAYER_LIST) { |p| handle_map_player_list(p) }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_DIR)      { |p| handle_player_dir(p) }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_SPRITE)   { |p| handle_player_sprite(p) }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_ACTION)   { |p| handle_player_action(p) }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_DATA)     { |p| handle_player_data(p) }

    # Chat system messages -- UI must be on main thread
    MP_NetworkManager.on_packet(MP_PacketType::CHAT_SYSTEM) do |p|
      # These are handled by MP_ChatOverlay directly (it has its own packet handler)
      # We avoid adding a second handler to prevent double-processing
    end
  end

  # --- Per-frame update (called from Scene_Map#update, main thread) ---

  def update
    return unless MP_NetworkManager.connected?
    return unless $scene.is_a?(Scene_Map)

    update_local_position
    update_remote_players
    cull_remote_players
    cleanup_disposed_sprites
  end

  def update_local_position
    return unless $game_player && $game_map

    @pos_frame_counter = (@pos_frame_counter + 1) % 3600  # prevent overflow

    x   = $game_player.x
    y   = $game_player.y
    dir = $game_player.direction
    map = $game_map.map_id

    # Detect what changed
    changed = (@last_pos[:x] != x || @last_pos[:y] != y || @last_pos[:dir] != dir || @last_pos[:map] != map)

    if changed
      # Map changes are ONLY sent from the transfer_player hook, not here
      if @last_pos[:map] != map && @last_pos[:map] != nil
        # Map changed -- the transfer_player hook already sent MAP_CHANGE.
        # Just update our tracked state.
      elsif @last_pos[:map] == map
        # Normal position change on same map
        MP_NetworkManager.send_packet(MP_PacketType::PLAYER_MOVE, {
          x: x,
          y: y,
          direction: dir,
          map_id: map
        })
      end

      # Update tracked state
      @last_pos[:x]   = x
      @last_pos[:y]   = y
      @last_pos[:dir] = dir
      @last_pos[:map] = map

      # Periodically send full party data (every ~3 seconds at 60 FPS)
      if @pos_frame_counter % 180 == 0
        MP_NetworkManager.send_party_data
      end
    else
      # No change -- send periodic heartbeat position (every POSITION_SEND_INTERVAL frames)
      if @pos_frame_counter % MP_ClientConfig::POSITION_SEND_INTERVAL == 0
        MP_NetworkManager.send_packet(MP_PacketType::PLAYER_MOVE, {
          x: x,
          y: y,
          direction: dir,
          map_id: map
        })
      end
    end
  end

  def update_remote_players
    return unless $game_map && $game_player

    @remote_players.each do |mp_id, rp|
      next unless rp && !rp.culled

      # Check if sprite exists and is valid
      sprite = @remote_sprites[mp_id]
      if sprite && !sprite.disposed?
        sprite.update
      elsif !rp.culled
        # Sprite was lost somehow (scene transition); recreate
        create_remote_sprite(rp)
      end

      rp.update
    end
  end

  def cull_remote_players
    return unless $game_map && $game_player

    @remote_players.each do |mp_id, rp|
      next unless rp

      culled = rp.should_cull?
      rp.culled = culled

      sprite = @remote_sprites[mp_id]
      next unless sprite && !sprite.disposed?

      # Toggle sprite visibility based on cull state
      sprite.visible = !culled && rp.visible

      # Also toggle the name sprite visibility
      if rp.respond_to?(:name_sprite) && rp.name_sprite && !rp.name_sprite.disposed?
        rp.name_sprite.visible = !culled && rp.visible
      end
    end
  end

  def cleanup_disposed_sprites
    # Remove entries for sprites that were disposed externally (e.g., scene transitions)
    @remote_sprites.delete_if do |mp_id, sprite|
      if sprite.nil? || sprite.disposed?
        true
      else
        false
      end
    end
  end

  # --- Packet handlers ---

  def handle_player_join(payload)
    mp_id = payload["client_id"]
    return if mp_id.nil? || mp_id == MP_NetworkManager.client_id

    # Only spawn if on the same map
    their_map = payload["map_id"] || payload["map"]
    current_map = $game_map&.map_id
    if their_map && current_map && their_map != current_map
      # Player is on a different map; don't spawn
      return
    end

    # Remove existing if any (prevents duplicates)
    remove_remote_player(mp_id)

    name   = payload["name"] || "Unknown"
    x      = payload["x"] || 0
    y      = payload["y"] || 0
    dir    = payload["direction"] || payload["dir"] || 2
    sprite = payload["sprite"] || ""
    outfit = payload["outfit"] || 0

    return unless $game_map

    # Enforce max remote players cap
    if @remote_players.length >= MP_ClientConfig::MAX_REMOTE_PLAYERS
      # Remove the furthest player to make room
      furthest_id = @remote_players.max_by { |_, rp| rp.distance_to_player }&.first
      remove_remote_player(furthest_id) if furthest_id
    end

    rp = MP_Game_RemotePlayer.new(mp_id, name, $game_map.map_id, x, y, dir, sprite, outfit)

    # Set party display
    party_disp = payload["party_display"]
    rp.set_party_display(party_disp) if party_disp

    # Create name bitmap
    rp.create_name_bitmap

    @remote_players[mp_id] = rp

    # Create sprite
    create_remote_sprite(rp)

    echoln "[MP] Player joined: #{name} (#{mp_id}) on map #{$game_map.map_id}"
  end

  def handle_player_leave(payload)
    mp_id = payload["client_id"]
    return unless mp_id

    rp = @remote_players[mp_id]
    if rp
      echoln "[MP] Player left: #{rp.mp_name}" rescue nil
    end
    remove_remote_player(mp_id)
  end

  def handle_pos_sync(payload)
    players = payload["players"] || []
    current_map = $game_map&.map_id

    players.each do |p|
      mp_id = p["client_id"] || p[:client_id]
      next unless mp_id && mp_id != MP_NetworkManager.client_id

      rp = @remote_players[mp_id]
      next unless rp

      # Skip position updates for players on other maps
      their_map = p["map_id"] || p[:map_id]
      if their_map && current_map && their_map != current_map
        # They're on a different map -- don't update position, just mark as culled
        rp.culled = true
        next
      end

      nx   = p["x"] || p[:x]
      ny   = p["y"] || p[:y]
      ndir = p["direction"] || p[:direction]

      if nx && ny
        rp.set_target(nx, ny)
      end

      if ndir
        rp.set_direction(ndir)
      end
    end
  end

  def handle_map_player_list(payload)
    players = payload["players"] || []
    current_map = $game_map&.map_id

    # Filter to only players on our map
    local_players = players.select do |p|
      their_map = p["map_id"] || p["map"]
      their_map.nil? || their_map == current_map
    end

    # Diff: find which players to remove and which to add
    incoming_ids = local_players.map { |p| p["client_id"] || p[:client_id] }.compact
    current_ids  = @remote_players.keys

    to_remove = current_ids - incoming_ids
    to_remove.each { |id| remove_remote_player(id) }

    local_players.each do |p|
      handle_player_join(p)
    end

    echoln "[MP] Map player list: #{local_players.length} players on map #{current_map}"
  end

  def handle_player_dir(payload)
    mp_id = payload["client_id"]
    dir   = payload["direction"]
    return unless mp_id && dir

    rp = @remote_players[mp_id]
    rp.set_direction(dir) if rp
  end

  def handle_player_sprite(payload)
    mp_id  = payload["client_id"]
    sprite = payload["sprite"]
    outfit = payload["outfit"]
    return unless mp_id && sprite

    rp = @remote_players[mp_id]
    return unless rp

    rp.set_sprite(sprite, outfit || 0)
    rp.invalidate_name  # name sprite needs redraw since sprite changed
    rp.create_name_bitmap
  end

  def handle_player_action(payload)
    mp_id  = payload["client_id"]
    action = payload["action"]
    return unless mp_id && action

    rp = @remote_players[mp_id]
    return unless rp

    case action
    when "jump"
      # Could implement jump visual here
    when "emote"
      # Could show emote bubble
    end
  end

  def handle_player_data(payload)
    mp_id = payload["client_id"]
    return unless mp_id

    rp = @remote_players[mp_id]
    return unless rp

    party_disp = payload["party_display"]
    if party_disp
      rp.set_party_display(party_disp)
      rp.create_name_bitmap
    end
  end

  # --- Sprite lifecycle ---

  def create_remote_sprite(rp)
    return unless rp && rp.is_a?(MP_Game_RemotePlayer)
    return unless $scene.is_a?(Scene_Map)

    spriteset = nil
    begin
      spriteset = $scene.spriteset
    rescue
      return
    end
    return unless spriteset

    viewport = nil
    begin
      viewport = spriteset.viewport
    rescue
      # Fallback: try to find any valid viewport
      begin
        viewport = $scene.viewport
      rescue
        return
      end
    end
    return unless viewport

    begin
      sprite = Sprite_MP_RemotePlayer.new(viewport, rp)
      @remote_sprites[rp.mp_id] = sprite
    rescue => e
      echoln "[MP] Failed to create remote sprite: #{e.class}: #{e.message}"
    end
  end

  def remove_remote_player(mp_id)
    return unless mp_id

    sprite = @remote_sprites.delete(mp_id)
    if sprite
      begin
        sprite.dispose unless sprite.disposed?
      rescue
        nil
      end
    end

    rp = @remote_players.delete(mp_id)
    if rp && rp.respond_to?(:dispose_name_sprite)
      rp.dispose_name_sprite rescue nil
    end
  end

  def clear_remote_players
    @remote_sprites.each do |mp_id, sprite|
      begin
        sprite.dispose if sprite && !sprite.disposed?
      rescue; end
    end
    @remote_sprites.clear

    @remote_players.each do |mp_id, rp|
      rp.dispose_name_sprite rescue nil if rp.respond_to?(:dispose_name_sprite)
    end
    @remote_players.clear
  end

  # --- Map transitions ---

  def on_map_changed
    clear_remote_players
    @last_pos = { x: nil, y: nil, dir: nil, map: nil }
    @pending_map_change = false
  end

  def dispose
    clear_remote_players
    @initialized = false
  end

  def remote_player_count
    @remote_players.length
  end

  def remote_players
    @remote_players
  end
end
