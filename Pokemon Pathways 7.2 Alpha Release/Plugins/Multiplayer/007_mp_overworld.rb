#===============================================================================
#  Pokemon Pathways Multiplayer Client - Overworld Sync Manager
#
#  Responsibilities:
#    • Track remote players: data (RemotePlayerData) + character (MP_Game_RemotePlayer)
#      + sprite (Sprite_MP_RemotePlayer).
#    • Update local position and send movement packets.
#    • Apply incoming server packets to remote player state.
#    • Cull players outside the visible radius.
#
#  ARCHITECTURE (thread safety):
#    All methods here run on the MAIN (game loop) thread, called from
#    Scene_Map#update. Remote player data is only mutated here.
#    MP_NetworkManager.tick dispatches incoming events before this runs,
#    so by the time update() is called, all queued packets have been
#    processed synchronously on the main thread. No mutex needed here.
#
#  FIXES vs original:
#   * RACE: @remote_players was mutated from receive_thread + iterated on main
#     thread. Fixed by the event-queue architecture in MP_NetworkManager.
#   * SPRITE CREATION ON WRONG THREAD: create_remote_player now runs on the
#     main thread (deferred via event queue).
#   * VIEWPORT: stored from Spriteset_Map instance, not called as class method.
#   * DOUBLE MAP_CHANGE: update_local_position no longer sends MAP_CHANGE (that
#     is the transfer_player hook's job). It only sends PLAYER_MOVE.
#   * DOUBLE POSITION SEND: removed redundant unconditional resend every 3 frames.
#     Resend only happens every POSITION_RESEND_INTERVAL frames (2 sec default).
#   * GHOST PLAYERS: clear_remote_players called on disconnect and map change.
#   * RESILIENCE: join/create/update/dispose wrapped — one bad remote player
#     logs + is removed instead of closing the game (OW Shadows / charset / nil).
#===============================================================================

module MP_OverworldManager
  module_function

  @remote_players  = {}   # mp_id => MP_Game_RemotePlayer
  @remote_sprites  = {}   # mp_id => Sprite_MP_RemotePlayer
  @map_viewport    = nil  # Viewport from Spriteset_Map; set by hook

  @last_x          = nil
  @last_y          = nil
  @last_dir        = nil
  @last_map        = nil
  @frame_count     = 0
  @initialized     = false

  # ── Lifecycle ───────────────────────────────────────────────────────────────

  def init
    return if @initialized
    @initialized = true
    register_packet_handlers
    mp_log("OW: initialized") if defined?(mp_log)
  end

  def leave_scene_map
    clear_remote_players
    @map_viewport = nil
    @last_x = @last_y = @last_dir = @last_map = nil
    @frame_count  = 0
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

  def update
    return unless MP_NetworkManager.connected?
    @frame_count += 1
    begin
      update_local_position
    rescue => e
      mp_log_exception("OW: update_local_position", e) if defined?(mp_log_exception)
    end
    update_remote_players
    begin
      update_culling
    rescue => e
      mp_log_exception("OW: update_culling", e) if defined?(mp_log_exception)
    end
  end

  def set_viewport(vp)
    @map_viewport = vp
    mp_log("OW: set_viewport map=#{$game_map&.map_id} vp=#{vp&.object_id} disposed=#{vp&.disposed? rescue 'n/a'}") if defined?(mp_log) && mp_ow_diag?
  end

  def on_map_changed
    mp_log("OW: on_map_changed clearing remotes (map=#{$game_map&.map_id})") if defined?(mp_log) && mp_ow_diag?
    clear_remote_players
    @last_x = @last_y = @last_dir = @last_map = nil
  end

  def on_disconnect
    clear_remote_players
    @last_x = @last_y = @last_dir = @last_map = nil
    mp_log("OW: cleared remote players on disconnect") if defined?(mp_log)
  end

  # ── Packet handler registration ─────────────────────────────────────────────

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_JOIN)     { |p| handle_player_join(p)     }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_LEAVE)    { |p| handle_player_leave(p)    }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_POS_SYNC) { |p| handle_pos_sync(p)        }
    MP_NetworkManager.on_packet(MP_PacketType::MAP_PLAYER_LIST) { |p| handle_map_player_list(p) }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_DIR)      { |p| handle_player_dir(p)      }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_SPRITE)   { |p| handle_player_sprite(p)   }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_DATA)     { |p| handle_player_data(p)   }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_ACTION)   { |p| handle_player_action(p)   }

    MP_NetworkManager.on_disconnect { on_disconnect }

    MP_NetworkManager.on_connect do
      on_map_changed
    end
  end

  # ── Local player movement ────────────────────────────────────────────────────

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
      mp_log("OW: PLAYER_MOVE local map=#{map} x=#{x} y=#{y} dir=#{dir}") if defined?(mp_log) && mp_ow_diag?
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

  # ── Remote player update loop ────────────────────────────────────────────────

  def update_remote_players
    @remote_players.each do |mp_id, rp|
      begin
        rp.update
      rescue => e
        mp_log_exception("OW: update_remote_players id=#{mp_id}", e) if defined?(mp_log_exception)
        remove_remote_player_safe(mp_id)
      end
    end
  end

  def update_culling
    return unless $game_player && $game_map
    @remote_players.each do |mp_id, rp|
      begin
        cull = rp.data.should_cull?
        sprite = @remote_sprites[mp_id]
        next if sprite&.disposed?
        if cull
          rp.data.visible      = false
          sprite.visible       = false if sprite && !sprite.disposed?
          rp.instance_variable_set(:@transparent, true)
        else
          rp.data.visible      = true
          sprite.visible       = true if sprite && !sprite.disposed?
          rp.instance_variable_set(:@transparent, false)
        end
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

    mp_log("OW: PLAYER_JOIN packet id=#{mp_id} name=#{payload['name']} map=#{$game_map&.map_id} sprite=#{payload['sprite']} x=#{payload['x']} y=#{payload['y']}") if defined?(mp_log)

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

    create_sprite_for(rp)

    mp_log("OW: handle_player_join done id=#{mp_id} name=#{data.name}") if defined?(mp_log)
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
    mp_log("OW: MAP_PLAYER_LIST RECEIVED n=#{n} local_map=#{$game_map&.map_id}") if defined?(mp_log)
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
    unless in_scene_map?
      mp_log("OW: create_sprite_for SKIP (not Scene_Map) id=#{rp&.mp_id}") if defined?(mp_log)
      return
    end
    vp = map_viewport
    unless viewport_ok?(vp)
      mp_log("OW: create_sprite_for SKIP (no viewport) id=#{rp&.mp_id} map=#{$game_map&.map_id}") if defined?(mp_log)
      return
    end

    mp_log("OW: create_sprite_for START id=#{rp.mp_id} charset=#{rp.character_name} map=#{$game_map&.map_id}") if defined?(mp_log)

    sprite = Sprite_MP_RemotePlayer.new(vp, rp)
    @remote_sprites[rp.mp_id] = sprite
    rp.create_name_sprite(vp)

    mp_log("OW: REMOTE PLAYER CREATED id=#{rp.mp_id} name=#{rp.mp_name} sprite_id=#{sprite.object_id}") if defined?(mp_log)
  rescue => e
    mp_log_exception("OW: create_sprite_for FAILED id=#{rp&.mp_id}", e) if defined?(mp_log_exception)
    remove_remote_player_safe(rp&.mp_id)
  end

  def remove_remote_player(mp_id)
    remove_remote_player_safe(mp_id)
  end

  def remove_remote_player_safe(mp_id)
    return unless mp_id
    sprite = @remote_sprites.delete(mp_id)
    if sprite && !sprite.disposed?
      begin
        sprite.dispose
      rescue => e
        mp_log_exception("OW: remove_remote_player sprite.dispose id=#{mp_id}", e) if defined?(mp_log_exception)
      end
    end
    @remote_players.delete(mp_id)
    mp_log("OW: remove_remote_player_safe id=#{mp_id}") if defined?(mp_log) && mp_ow_diag?
  end

  def clear_remote_players
    @remote_sprites.each do |mp_id, s|
      next unless s
      begin
        s.dispose unless s.disposed?
      rescue => e
        mp_log_exception("OW: clear_remote_players id=#{mp_id}", e) if defined?(mp_log_exception)
      end
    end
    @remote_sprites.clear
    @remote_players.clear
    mp_log("OW: cleared all remote players") if defined?(mp_log)
  end

  def remote_player_count
    @remote_players.length
  end

  private

  def in_scene_map?
    $scene.is_a?(Scene_Map)
  end

  def viewport_ok?(vp)
    vp && (!vp.respond_to?(:disposed?) || !vp.disposed?)
  end

  def map_viewport
    return @map_viewport if viewport_ok?(@map_viewport)
    @map_viewport = nil
    return nil unless in_scene_map?
    spriteset = $scene.spriteset rescue nil
    return nil unless spriteset
    vp = spriteset.instance_variable_get(:@viewport1) ||
         spriteset.instance_variable_get(:@viewport)  ||
         spriteset.instance_variable_get(:@map_viewport) rescue nil
    @map_viewport = vp if viewport_ok?(vp)
    @map_viewport
  end
end
