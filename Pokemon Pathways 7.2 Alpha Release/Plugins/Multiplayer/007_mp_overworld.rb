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

  def dispose
    clear_remote_players
    @map_viewport  = nil
    @initialized   = false
    @last_x = @last_y = @last_dir = @last_map = nil
    mp_log("OW: disposed") if defined?(mp_log)
  end

  # Called by Scene_Map#update every frame.
  def update
    return unless MP_NetworkManager.connected?
    @frame_count += 1
    update_local_position
    update_remote_players
    update_culling
  end

  # Store the map viewport so we can pass it to sprites and name labels.
  # Called from Scene_Map#main after spriteset is created.
  def set_viewport(vp)
    @map_viewport = vp
  end

  # Called on map transfer (from Scene_Map#transfer_player hook).
  def on_map_changed
    clear_remote_players
    @last_x = @last_y = @last_dir = @last_map = nil
  end

  # Called on server disconnect.
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
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_DATA)     { |p| handle_player_data(p)     }
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_ACTION)   { |p| handle_player_action(p)   }

    MP_NetworkManager.on_disconnect { on_disconnect }

    MP_NetworkManager.on_connect do
      # On (re)connect, initial MAP_CHANGE is sent by MP_NetworkManager#initial_player_data
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
    # FIX: map changes are handled by transfer_player hook, not here.
    # Only send PLAYER_MOVE when position/direction has changed.

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

    # FIX: Periodic resend only - NOT every 3 frames (was causing 20 packets/sec).
    # Every ~2 seconds (POSITION_RESEND_INTERVAL frames) re-broadcast position
    # so server doesn't think client timed out mid-stand.
    if @frame_count % MP_ClientConfig::POSITION_RESEND_INTERVAL == 0
      MP_NetworkManager.send_packet(MP_PacketType::PLAYER_MOVE, {
        "x"         => x,
        "y"         => y,
        "direction" => dir
      })
    end

    # Party data every ~5 seconds
    if @frame_count % 300 == 0
      MP_NetworkManager.send_party_data
    end
  end

  # ── Remote player update loop ────────────────────────────────────────────────

  def update_remote_players
    @remote_players.each_value(&:update)
  end

  def update_culling
    return unless $game_player && $game_map
    @remote_players.each do |mp_id, rp|
      cull = rp.data.should_cull?
      sprite = @remote_sprites[mp_id]
      if cull
        rp.data.visible      = false
        sprite.visible       = false if sprite
        rp.instance_variable_set(:@transparent, true)
      else
        rp.data.visible      = true
        sprite.visible       = true if sprite
        rp.instance_variable_set(:@transparent, false)
      end
    end
  end

  # ── Incoming packet handlers (all run on main thread via event queue) ────────

  def handle_player_join(payload)
    mp_id = payload["client_id"]
    return unless mp_id
    return if mp_id == MP_NetworkManager.client_id

    remove_remote_player(mp_id)  # clean up stale entry if any

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

    mp_log("OW: #{data.name} joined") if defined?(mp_log)
  end

  def handle_player_leave(payload)
    mp_id = payload["client_id"]
    return unless mp_id
    name = @remote_players[mp_id]&.mp_name
    remove_remote_player(mp_id)
    mp_log("OW: #{name} left") if defined?(mp_log)
  end

  def handle_pos_sync(payload)
    (payload["players"] || []).each do |p|
      mp_id = p["client_id"]
      next unless mp_id && mp_id != MP_NetworkManager.client_id
      rp = @remote_players[mp_id]
      next unless rp
      rp.data.set_target(p["x"], p["y"]) if p["x"] && p["y"]
      rp.set_direction(p["direction"])   if p["direction"]
    end
  end

  def handle_map_player_list(payload)
    clear_remote_players
    (payload["players"] || []).each { |p| handle_player_join(p) }
    mp_log("OW: map player list received (#{payload['players']&.length || 0} players)") if defined?(mp_log)
  end

  def handle_player_dir(payload)
    mp_id = payload["client_id"]
    rp = @remote_players[mp_id]
    rp.set_direction(payload["direction"]) if rp && payload["direction"]
  end

  def handle_player_sprite(payload)
    mp_id = payload["client_id"]
    rp = @remote_players[mp_id]
    return unless rp && payload["sprite"]
    rp.data.sprite_name = payload["sprite"]
    rp.data.outfit      = payload["outfit"].to_i
    rp.set_character_graphic(payload["sprite"])
    rp.refresh_name_sprite(@map_viewport)
  end

  def handle_player_data(payload)
    mp_id = payload["client_id"]
    rp = @remote_players[mp_id]
    return unless rp && payload["party_display"]
    rp.data.party_display = payload["party_display"]
    rp.refresh_name_sprite(@map_viewport)
  end

  def handle_player_action(payload)
    # Extensible for emotes, animations, etc.
    # Currently no visual feedback needed.
  end

  # ── Sprite management (main thread only) ────────────────────────────────────

  def create_sprite_for(rp)
    return unless in_scene_map?
    vp = map_viewport
    return unless vp

    sprite = Sprite_MP_RemotePlayer.new(vp, rp)
    @remote_sprites[rp.mp_id] = sprite

    # Create name label on the same viewport
    rp.create_name_sprite(vp)
  end

  def remove_remote_player(mp_id)
    sprite = @remote_sprites.delete(mp_id)
    if sprite && !sprite.disposed?
      sprite.dispose   # also disposes rp name sprite via override
    end
    @remote_players.delete(mp_id)
  end

  def clear_remote_players
    @remote_sprites.each_value do |s|
      s.dispose unless s.disposed?
    end
    @remote_sprites.clear
    # remote_players entries are cleaned up via sprite.dispose chain
    @remote_players.clear
    mp_log("OW: cleared all remote players") if defined?(mp_log)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  def remote_player_count
    @remote_players.length
  end

  private

  def in_scene_map?
    $scene.is_a?(Scene_Map)
  end

  # FIX: Get the map viewport from the Spriteset_Map instance.
  # Spriteset_Map.viewport is NOT a class method; access via the instance.
  def map_viewport
    return @map_viewport if @map_viewport
    return nil unless in_scene_map?
    spriteset = $scene.spriteset rescue nil
    return nil unless spriteset
    # Try known viewport attribute names used by different PE versions
    vp = spriteset.instance_variable_get(:@viewport1) ||
         spriteset.instance_variable_get(:@viewport)  ||
         spriteset.instance_variable_get(:@map_viewport) rescue nil
    @map_viewport = vp
    vp
  end
end
