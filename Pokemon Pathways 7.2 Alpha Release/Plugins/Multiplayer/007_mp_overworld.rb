#===============================================================================
#  Pokemon Pathways Multiplayer Client - Overworld Sync Manager (STABLE v2.1)
#
#  CRITICAL FIXES for Root Causes #2 and #3:
#
#  Root Cause 2 — Remote sprites never updated:
#    Added update_remote_sprites() that calls update_safe on every sprite.
#    This replaces the missing Spriteset_Map integration.
#
#  Root Cause 3 — Viewport invalidation race:
#    Added @map_changing flag set during transfer. Blocks sprite creation
#    while a transition is in progress. Added viewport revalidation before
#    every use.
#
#  ADDITIONAL FIXES:
#    * create_sprite_for checks SAFE_MODE and REMOTE_RENDERING_ENABLED
#    * handle_player_join defers sprite creation by 1 frame if viewport unstable
#    * remove_remote_player_safe catches ALL exceptions
#    * update_remote_players removes crashed players automatically
#    * map_viewport aggressively refetches from current spriteset
#===============================================================================

module MP_OverworldManager
  module_function

  @remote_players  = {}   # mp_id => MP_Game_RemotePlayer
  @remote_sprites  = {}   # mp_id => Sprite_MP_RemotePlayer
  @map_viewport    = nil  # Viewport from Spriteset_Map
  @viewport_valid  = false # whether @map_viewport has been validated this frame

  @last_x          = nil
  @last_y          = nil
  @last_dir        = nil
  @last_map        = nil
  @frame_count     = 0
  @initialized     = false
  @map_changing    = false  # TRUE during map transfer transition

  # Players who joined while viewport was unavailable — retry next frame
  @pending_sprite_creations = []

  # ── Lifecycle ───────────────────────────────────────────────────────────────

  def init
    return if @initialized
    @initialized = true
    @remote_players  = {}
    @remote_sprites  = {}
    @pending_sprite_creations = []
    @map_changing = false
    @map_viewport = nil
    @viewport_valid = false
    register_packet_handlers
    mp_log("OW: initialized v2.1") if defined?(mp_log)
  end

  def leave_scene_map
    clear_remote_players
    @map_viewport = nil
    @viewport_valid = false
    @map_changing = false
    @pending_sprite_creations.clear
    @last_x = @last_y = @last_dir = @last_map = nil
    @frame_count = 0
    mp_log("OW: leave_scene_map") if defined?(mp_log)
  end

  def dispose
    leave_scene_map
    @initialized = false
    mp_log("OW: disposed") if defined?(mp_log)
  end

  def mp_ow_diag?
    MP_ClientConfig::NETWORK_DIAGNOSTICS
  rescue NameError
    false
  end

  def in_safe_mode?
    MP_ClientConfig::SAFE_MODE rescue false
  end

  def rendering_enabled?
    MP_ClientConfig::REMOTE_RENDERING_ENABLED rescue true
  end

  # ── Per-frame update (called from Scene_Map#update) ─────────────────────────

  def update
    return unless MP_NetworkManager.connected?
    @frame_count += 1
    @viewport_valid = false  # Revalidate each frame

    # Process any deferred sprite creations first
    process_pending_sprite_creations

    begin
      update_local_position
    rescue => e
      mp_log_exception("OW: update_local_position", e) if defined?(mp_log_exception)
    end

    begin
      update_remote_players
    rescue => e
      mp_log_exception("OW: update_remote_players", e) if defined?(mp_log_exception)
    end

    begin
      update_remote_sprites  # CRITICAL FIX: manually update sprites
    rescue => e
      mp_log_exception("OW: update_remote_sprites", e) if defined?(mp_log_exception)
    end

    begin
      update_culling
    rescue => e
      mp_log_exception("OW: update_culling", e) if defined?(mp_log_exception)
    end
  end

  # ── Viewport management ─────────────────────────────────────────────────────

  def set_viewport(vp)
    old_vp = @map_viewport
    if vp && !vp.disposed?
      @map_viewport = vp
      @viewport_valid = true
      mp_log("OW: set_viewport map=#{$game_map&.map_id} vp=#{vp.object_id}") if defined?(mp_log) && mp_ow_diag?
    else
      @map_viewport = nil
      @viewport_valid = false
      mp_log("OW: set_viewport REJECTED (disposed/nil)") if defined?(mp_log) && mp_ow_diag?
    end
  end

  def on_map_changed
    mp_log("OW: on_map_changed map=#{$game_map&.map_id}") if defined?(mp_log) && mp_ow_diag?
    @map_changing = true
    clear_remote_players
    @pending_sprite_creations.clear
    @map_viewport = nil
    @viewport_valid = false
    @last_x = @last_y = @last_dir = @last_map = nil
    # Release transition lock after a short delay (map needs time to load)
    @map_change_frame = @frame_count
  end

  def on_map_change_complete
    # Called from Scene_Map hook after transfer_player finishes
    @map_changing = false
    @map_change_frame = nil
    mp_log("OW: map_change_complete") if defined?(mp_log) && mp_ow_diag?
  end

  def on_disconnect
    clear_remote_players
    @pending_sprite_creations.clear
    @map_changing = false
    @last_x = @last_y = @last_dir = @last_map = nil
    mp_log("OW: cleared on disconnect") if defined?(mp_log)
  end

  # ── Packet handler registration ─────────────────────────────────────────────

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_JOIN)     { |p| handle_player_join(p)     }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_LEAVE)    { |p| handle_player_leave(p)    }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_POS_SYNC) { |p| handle_pos_sync(p)        }
    MP_NetworkManager.on_packet(MP_PacketType::MAP_PLAYER_LIST) { |p| handle_map_player_list(p) }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_DIR)      { |p| handle_player_dir(p)      }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_SPRITE)   { |p| handle_player_sprite(p)   }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_DATA)     { |p| handle_player_data(p)     }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_ACTION)   { |p| handle_player_action(p)   }
    MP_NetworkManager.on_disconnect { on_disconnect }
  end

  # ── Local player movement ───────────────────────────────────────────────────

  def update_local_position
    return unless $game_player && $game_map

    x   = $game_player.x
    y   = $game_player.y
    dir = $game_player.direction
    map = $game_map.map_id

    pos_changed = (x != @last_x || y != @last_y || dir != @last_dir)

    if pos_changed
      MP_NetworkManager.send_packet(MP_PacketType::PLAYER_MOVE, {
        "x"         => x,
        "y"         => y,
        "direction" => dir
      })
      @last_x   = x
      @last_y   = y
      @last_dir = dir
    end

    if @frame_count % MP_ClientConfig::POSITION_RESEND_INTERVAL == 0
      MP_NetworkManager.send_packet(MP_PacketType::PLAYER_MOVE, {
        "x"         => x,
        "y"         => y,
        "direction" => dir
      })
    end

    if @frame_count % 300 == 0
      MP_NetworkManager.send_party_data
    end
  end

  # ── Remote player update loop ───────────────────────────────────────────────

  def update_remote_players
    to_remove = []
    @remote_players.each do |mp_id, rp|
      begin
        rp.update
      rescue => e
        mp_log_exception("OW: update_remote_players id=#{mp_id}", e) if defined?(mp_log_exception)
        to_remove << mp_id
      end
    end
    to_remove.each { |mp_id| remove_remote_player_safe(mp_id) }
  end

  # CRITICAL FIX (Root Cause #2): Manually update all remote sprites.
  # Spriteset_Map doesn't know about our sprites, so we must call update_safe.
  def update_remote_sprites
    return unless rendering_enabled?
    return if in_safe_mode?

    to_remove = []
    @remote_sprites.each do |mp_id, sprite|
      begin
        if sprite.nil? || sprite.disposed?
          to_remove << mp_id
          next
        end
        # Validate the sprite's viewport hasn't been disposed
        vp = sprite.viewport rescue nil
        if vp && vp.respond_to?(:disposed?) && vp.disposed?
          to_remove << mp_id
          next
        end
        sprite.update_safe
      rescue => e
        mp_log_exception("OW: update_remote_sprites id=#{mp_id}", e) if defined?(mp_log_exception)
        to_remove << mp_id
      end
    end
    to_remove.each { |mp_id| remove_remote_player_safe(mp_id) }
  end

  def update_culling
    return unless $game_player && $game_map
    @remote_players.each do |mp_id, rp|
      begin
        cull = rp.data.should_cull?
        sprite = @remote_sprites[mp_id]
        next if sprite.nil? || sprite.disposed?
        sprite.visible = !cull if sprite.respond_to?(:visible=)
        rp.data.visible = !cull
        rp.instance_variable_set(:@transparent, cull)
      rescue => e
        mp_log_exception("OW: update_culling id=#{mp_id}", e) if defined?(mp_log_exception)
      end
    end
  end

  # ── Incoming packet handlers (all run on main thread via event queue) ────────

  def handle_player_join(payload)
    payload = {} if payload.nil?
    mp_id = payload["client_id"]
    return unless mp_id
    return if mp_id == MP_NetworkManager.client_id

    mp_log("OW: PLAYER_JOIN id=#{mp_id} name=#{payload['name']} x=#{payload['x']} y=#{payload['y']}") if defined?(mp_log)

    remove_remote_player_safe(mp_id)

    data = RemotePlayerData.new(
      mp_id,
      payload["name"] || "???",
      $game_map&.map_id,
      payload["x"] || 0,
      payload["y"] || 0,
      payload["direction"] || 2,
      payload["sprite"] || "",
      payload["outfit"] || 0
    )
    data.party_display = payload["party_display"]

    rp = MP_Game_RemotePlayer.new(data)
    @remote_players[mp_id] = rp

    # SAFE MODE: do not create any sprites
    if in_safe_mode?
      mp_log("OW: SAFE MODE — sprite creation skipped id=#{mp_id}") if defined?(mp_log)
      return
    end

    if rendering_enabled?
      create_sprite_for(rp)
    end

    mp_log("OW: PLAYER_JOIN done id=#{mp_id}") if defined?(mp_log)
  rescue => e
    mp_log_exception("OW: handle_player_join FAILED id=#{mp_id}", e) if defined?(mp_log_exception)
    remove_remote_player_safe(mp_id)
  end

  def handle_player_leave(payload)
    mp_id = payload["client_id"]
    return unless mp_id
    name = @remote_players[mp_id]&.mp_name
    mp_log("OW: PLAYER_LEAVE id=#{mp_id} name=#{name}") if defined?(mp_log)
    remove_remote_player_safe(mp_id)
  end

  def handle_pos_sync(payload)
    (payload["players"] || []).each do |p|
      begin
        mp_id = p["client_id"]
        next unless mp_id && mp_id != MP_NetworkManager.client_id
        rp = @remote_players[mp_id]
        next unless rp
        rp.data.set_target(p["x"], p["y"]) if p["x"] && p["y"]
        rp.set_direction(p["direction"])   if p["direction"]
      rescue => e
        mp_log_exception("OW: handle_pos_sync client=#{p['client_id']}", e) if defined?(mp_log_exception)
      end
    end
  end

  def handle_map_player_list(payload)
    n = payload["players"]&.length || 0
    mp_log("OW: MAP_PLAYER_LIST n=#{n}") if defined?(mp_log)
    clear_remote_players
    (payload["players"] || []).each do |p|
      begin
        handle_player_join(p)
      rescue => e
        mp_log_exception("OW: MAP_PLAYER_LIST entry", e) if defined?(mp_log_exception)
      end
    end
    mp_log("OW: MAP_PLAYER_LIST applied n=#{n}") if defined?(mp_log)
  end

  def handle_player_dir(payload)
    mp_id = payload["client_id"]
    rp = @remote_players[mp_id]
    rp.set_direction(payload["direction"]) if rp && payload["direction"]
  rescue => e
    mp_log_exception("OW: handle_player_dir id=#{mp_id}", e) if defined?(mp_log_exception)
  end

  def handle_player_sprite(payload)
    mp_id = payload["client_id"]
    rp = @remote_players[mp_id]
    return unless rp && payload["sprite"]
    mp_log("OW: PLAYER_SPRITE id=#{mp_id} -> #{payload['sprite']}") if defined?(mp_log) && mp_ow_diag?
    rp.data.sprite_name = payload["sprite"]
    rp.data.outfit      = payload["outfit"].to_i
    rp.set_character_graphic(payload["sprite"])
    sprite = @remote_sprites[mp_id]
    if sprite && !sprite.disposed?
      # Force re-check bitmap on next update_safe
      begin
        sprite.instance_variable_set(:@character_name, nil) if sprite.respond_to?(:instance_variable_set)
      rescue
        nil
      end
    end
    rp.refresh_name_sprite(@map_viewport)
  rescue => e
    mp_log_exception("OW: handle_player_sprite id=#{mp_id}", e) if defined?(mp_log_exception)
  end

  def handle_player_data(payload)
    mp_id = payload["client_id"]
    rp = @remote_players[mp_id]
    return unless rp && payload["party_display"]
    rp.data.party_display = payload["party_display"]
    rp.refresh_name_sprite(@map_viewport)
  rescue => e
    mp_log_exception("OW: handle_player_data id=#{mp_id}", e) if defined?(mp_log_exception)
  end

  def handle_player_action(payload)
    # reserved
  end

  # ── Sprite management (main thread only) ────────────────────────────────────

  def create_sprite_for(rp)
    return unless rp
    return if in_safe_mode?
    return unless rendering_enabled?

    unless in_scene_map?
      mp_log("OW: create_sprite_for SKIP (not Scene_Map) id=#{rp.mp_id}") if defined?(mp_log)
      return
    end

    # Block creation during map transitions
    if @map_changing
      mp_log("OW: create_sprite_for DEFERRED (map changing) id=#{rp.mp_id}") if defined?(mp_log)
      @pending_sprite_creations << rp.mp_id
      return
    end

    vp = map_viewport
    unless viewport_ok?(vp)
      mp_log("OW: create_sprite_for DEFERRED (no viewport) id=#{rp.mp_id}") if defined?(mp_log)
      @pending_sprite_creations << rp.mp_id
      return
    end

    mp_log("OW: create_sprite_for START id=#{rp.mp_id} charset=#{rp.character_name}") if defined?(mp_log)

    begin
      sprite = Sprite_MP_RemotePlayer.new(vp, rp)
      @remote_sprites[rp.mp_id] = sprite
      rp.mp_sprite = sprite
      rp.create_name_sprite(vp)
      mp_log("OW: REMOTE PLAYER CREATED id=#{rp.mp_id} oid=#{sprite.object_id}") if defined?(mp_log)
    rescue => e
      mp_log_exception("OW: create_sprite_for FAILED id=#{rp.mp_id}", e) if defined?(mp_log_exception)
      # Don't remove the player — they can still be tracked without a sprite
      # The next MAP_PLAYER_LIST or PLAYER_JOIN will retry
    end
  end

  def process_pending_sprite_creations
    return if @pending_sprite_creations.empty?
    return if @map_changing
    return if in_safe_mode?
    return unless rendering_enabled?

    vp = map_viewport
    return unless viewport_ok?(vp)

    # Retry pending sprites
    retry_ids = @pending_sprite_creations.dup
    @pending_sprite_creations.clear

    retry_ids.each do |mp_id|
      rp = @remote_players[mp_id]
      next unless rp
      next if @remote_sprites[mp_id] && !@remote_sprites[mp_id].disposed?
      begin
        create_sprite_for(rp)
      rescue => e
        mp_log_exception("OW: pending_sprite retry id=#{mp_id}", e) if defined?(mp_log_exception)
      end
    end
  end

  def remove_remote_player_safe(mp_id)
    return unless mp_id

    sprite = @remote_sprites.delete(mp_id)
    if sprite && !sprite.disposed?
      begin
        sprite.dispose
      rescue => e
        mp_log_exception("OW: remove sprite.dispose id=#{mp_id}", e) if defined?(mp_log_exception)
      end
    end

    rp = @remote_players.delete(mp_id)
    if rp && rp.respond_to?(:dispose)
      begin
        rp.dispose
      rescue => e
        mp_log_exception("OW: remove rp.dispose id=#{mp_id}", e) if defined?(mp_log_exception)
      end
    end

    @pending_sprite_creations.delete(mp_id)

    mp_log("OW: removed id=#{mp_id}") if defined?(mp_log) && mp_ow_diag?
  end

  def clear_remote_players
    # Dispose sprites first
    @remote_sprites.each do |mp_id, sprite|
      next unless sprite
      begin
        sprite.dispose unless sprite.disposed?
      rescue => e
        mp_log_exception("OW: clear sprite id=#{mp_id}", e) if defined?(mp_log_exception)
      end
    end
    @remote_sprites.clear

    # Dispose characters
    @remote_players.each do |mp_id, rp|
      begin
        rp.dispose if rp.respond_to?(:dispose)
      rescue => e
        mp_log_exception("OW: clear rp id=#{mp_id}", e) if defined?(mp_log_exception)
      end
    end
    @remote_players.clear
    @pending_sprite_creations.clear

    mp_log("OW: cleared all") if defined?(mp_log)
  end

  def remote_player_count
    @remote_players.length
  end

  def remote_sprite_count
    @remote_sprites.count { |_, s| s && !s.disposed? }
  end

  # ─── Private helpers ────────────────────────────────────────────────────────

  private

  def in_scene_map?
    $scene.is_a?(Scene_Map)
  rescue
    false
  end

  def viewport_ok?(vp)
    vp && vp.respond_to?(:disposed?) && !vp.disposed?
  rescue
    false
  end

  # Aggressively refetch viewport from current spriteset every time.
  # This ensures we never use a stale/disposed viewport.
  def map_viewport
    # Return cached if still valid
    if @map_viewport && !@map_viewport.disposed?
      return @map_viewport
    end

    @map_viewport = nil
    return nil unless in_scene_map?

    begin
      spriteset = $scene.spriteset
      return nil unless spriteset

      vp = nil
      # Try multiple viewport ivar names (different PE versions)
      ivar_names = [:@viewport1, :@viewport, :@map_viewport, :@tilemap_viewport]
      ivar_names.each do |ivar|
        v = spriteset.instance_variable_get(ivar)
        if v && v.respond_to?(:disposed?) && !v.disposed?
          vp = v
          break
        end
      end

      @map_viewport = vp
      @viewport_valid = true if vp

      mp_log("OW: map_viewport refetched vp=#{vp&.object_id}") if defined?(mp_log) && vp && mp_ow_diag?
      vp
    rescue => e
      mp_log_exception("OW: map_viewport refetch", e) if defined?(mp_log_exception)
      nil
    end
  end
end

