#===============================================================================
#  Pokemon Pathways Multiplayer Client - Overworld Sync Manager
#  REMOTE SKIN SYNC v3.1 — Sprite_Character cache invalidation fix,
#  live sprite change detection, full hue/trainer_type propagation.
#===============================================================================

module MP_OverworldManager

  @remote_players  = {}
  @remote_sprites  = {}

  @last_x          = nil
  @last_y          = nil
  @last_dir        = nil
  @last_map        = nil
  @last_local_sprite = nil
  @last_local_hue    = nil
  @last_local_outfit = nil
  @frame_count     = 0
  @initialized     = false

  @last_no_vp_log  = 0
  @sprite_retry_at = {}
  @fallback_viewport = nil

  def init
    return if @initialized
    @initialized     = true
    @sprite_retry_at = {}
    @remote_players  = {}
    @remote_sprites  = {}
    @last_local_sprite = nil
    @last_local_hue    = nil
    @last_local_outfit = nil
    register_packet_handlers
    mp_log("OW: initialized") if defined?(mp_log)
  end

  def clear_map_sprites
    mp_log("OW: clear_map_sprites called") if MP_ClientConfig::DEBUG_LIFECYCLE && defined?(mp_log)
    spriteset = current_spriteset
    if spriteset
      arr = spriteset.instance_variable_get(:@character_sprites)
      if arr
        @remote_sprites.each_value do |s|
          begin
            arr.delete(s) if !s.disposed?
          rescue => e
            mp_log("OW: spriteset delete error #{e.class}") if defined?(mp_log)
          end
        end
      end
    end
    @remote_sprites.each_value do |s|
      begin
        s.dispose unless s.disposed?
      rescue => e
        mp_log("OW: sprite dispose error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end
    @remote_sprites.clear
    @sprite_retry_at.clear
    dispose_fallback_viewport
  end

  def update
    return unless MP_NetworkManager.connected?
    @frame_count += 1
    update_local_position
    update_remote_players
    update_culling
    update_remote_sprites
  end

  def set_viewport(vp)
  end

  def on_map_changed
    mp_log("OW: on_map_changed — clearing sprites, NOT disposing core") if MP_ClientConfig::DEBUG_LIFECYCLE && defined?(mp_log)
    clear_map_sprites
    @remote_players.clear
    @last_x = @last_y = @last_dir = @last_map = nil
    @last_local_sprite = nil
    @last_local_hue = nil
    @last_local_outfit = nil
    @sprite_retry_at.clear
  end

  def on_disconnect
    mp_log("OW: on_disconnect — clearing sprites, NOT disposing core") if MP_ClientConfig::DEBUG_LIFECYCLE && defined?(mp_log)
    clear_map_sprites
    @remote_players.clear
    @last_x = @last_y = @last_dir = @last_map = nil
    @last_local_sprite = nil
    @last_local_hue = nil
    @last_local_outfit = nil
    @sprite_retry_at.clear
  end

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
    MP_NetworkManager.on_connect    { on_map_changed }
  end

  def update_local_position
    return unless $game_player && $game_map
    x   = $game_player.x
    y   = $game_player.y
    dir = $game_player.direction
    pos_changed = (x != @last_x || y != @last_y || dir != @last_dir)
    if pos_changed
      MP_NetworkManager.send_packet(MP_PacketType::PLAYER_MOVE, {
        "x" => x, "y" => y, "direction" => dir
      })
      @last_x = x; @last_y = y; @last_dir = dir
    end
    if @frame_count % MP_ClientConfig::POSITION_RESEND_INTERVAL == 0
      MP_NetworkManager.send_packet(MP_PacketType::PLAYER_MOVE, {
        "x" => x, "y" => y, "direction" => dir
      })
    end
    if @frame_count % 300 == 0
      MP_NetworkManager.send_party_data
    end
    check_local_sprite_change
  end

  def check_local_sprite_change
    return unless $game_player
    current_sprite = $game_player.character_name.to_s rescue ""
    current_hue    = $game_player.character_hue.to_i rescue 0
    current_outfit = (defined?($Trainer) && $Trainer) ? ($Trainer.outfit.to_i rescue 0) : 0

    if @last_local_sprite != current_sprite ||
       @last_local_hue != current_hue ||
       @last_local_outfit != current_outfit

      @last_local_sprite = current_sprite
      @last_local_hue    = current_hue
      @last_local_outfit = current_outfit

      mp_log("SYNC: local sprite changed -> '#{current_sprite}' (hue:#{current_hue}, outfit:#{current_outfit})") if defined?(mp_log)

      MP_NetworkManager.send_packet(MP_PacketType::PLAYER_SPRITE, {
        "sprite"        => current_sprite,
        "character_hue" => current_hue,
        "outfit"        => current_outfit
      })
    end
  end

  def update_remote_players
    @remote_players.each do |mp_id, rp|
      sprite = @remote_sprites[mp_id]
      need_create = false
      if sprite.nil?
        need_create = true
      else
        begin
          need_create = true if sprite.disposed?
          need_create = true if sprite.viewport && sprite.viewport.disposed?
        rescue; need_create = true; end
      end
      if need_create
        if $mp_map_loading
          rp.update
          next
        end
        next_retry = @sprite_retry_at[mp_id] || 0
        if @frame_count < next_retry
          rp.update
          next
        end
        @sprite_retry_at[mp_id] = @frame_count + 30
        create_sprite_for(rp)
      end
      rp.update
    end
  end

  def update_remote_sprites
    @remote_sprites.each_value do |sprite|
      begin
        sprite.update if sprite && !sprite.disposed?
      rescue => e
        mp_log("OW: sprite update error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end
  end

  def update_culling
    return unless $game_player && $game_map
    @remote_players.each do |mp_id, rp|
      same_map = rp.data.map_id == $game_map.map_id
      cull = !same_map || rp.data.should_cull?
      sprite = @remote_sprites[mp_id]
      if cull
        rp.data.visible = false
        begin; sprite.visible = false if sprite && !sprite.disposed?; rescue; end
        rp.instance_variable_set(:@transparent, true)
      else
        rp.data.visible = true
        begin; sprite.visible = true if sprite && !sprite.disposed?; rescue; end
        rp.instance_variable_set(:@transparent, false)
      end
    end
  end

  def handle_player_join(payload)
    mp_id = payload["client_id"]
    return unless mp_id
    return if mp_id == MP_NetworkManager.client_id
    remove_remote_player(mp_id)
    map_id = payload["map_id"] || $game_map&.map_id || 0
    data = RemotePlayerData.new(
      mp_id, payload["name"] || "???", map_id,
      payload["x"] || 0, payload["y"] || 0,
      payload["direction"] || 2,
      payload["sprite"] || "",
      payload["outfit"] || 0,
      payload["character_hue"] || 0,
      payload["trainer_type"] || ""
    )
    data.party_display = payload["party_display"]
    rp = MP_Game_RemotePlayer.new(data)
    @remote_players[mp_id] = rp
    @sprite_retry_at[mp_id] = 0
    create_sprite_for(rp)
    mp_log("OW: #{data.name} joined map #{map_id} (#{data.x},#{data.y}) sprite='#{data.sprite_name}' hue=#{data.character_hue}") if defined?(mp_log)
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
      rp.data.map_id = p["map_id"] if p["map_id"]
      rp.data.set_target(p["x"], p["y"]) if p["x"] && p["y"]
      rp.set_direction(p["direction"]) if p["direction"]
    end
  end

  def handle_map_player_list(payload)
    clear_map_sprites
    @remote_players.clear
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

    old_sprite = rp.character_name
    rp.set_character_graphic(payload["sprite"], payload["character_hue"].to_i)
    rp.data.outfit = payload["outfit"].to_i if payload["outfit"]
    rp.data.trainer_type = payload["trainer_type"].to_s if payload["trainer_type"]

    # CRITICAL FIX: Force Sprite_Character to discard its cached bitmap and reload
    # the new charset on the next update cycle.
    if old_sprite != payload["sprite"]
      sprite = @remote_sprites[mp_id]
      if sprite && !sprite.disposed?
        begin
          # Reset Sprite_Character's internal cache variables
          # These are the instance variables Sprite_Character uses to track
          # whether it needs to reload the bitmap
          sprite.instance_variable_set(:@tile_id, -1)
          sprite.instance_variable_set(:@character_name, "")
          sprite.instance_variable_set(:@character_hue, -1)
          mp_log("SPRITE: forced bitmap reload for #{rp.mp_name}") if defined?(mp_log)
        rescue => e
          mp_log("OW: sprite cache reset error #{e.class}: #{e.message}") if defined?(mp_log)
        end
      end
    end

    rp.refresh_name_sprite(current_viewport)
    mp_log("SPRITE: live charset update for #{rp.mp_name} -> '#{payload['sprite']}'") if defined?(mp_log)
  end

  def handle_player_data(payload)
    mp_id = payload["client_id"]
    rp = @remote_players[mp_id]
    return unless rp && payload["party_display"]
    rp.data.party_display = payload["party_display"]
    rp.refresh_name_sprite(current_viewport)
  end

  def handle_player_action(payload); end

  def create_sprite_for(rp)
    if $mp_map_loading
      mp_log("OW: create_sprite_for #{rp.mp_name} — BLOCKED by $mp_map_loading") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
      return
    end

    vp = current_viewport
    if !vp
      vp = ensure_fallback_viewport
      unless vp
        now = Time.now.to_f
        if now - @last_no_vp_log > 5.0
          mp_log("OW: create_sprite_for #{rp.mp_name} — no viewport, fallback failed") if defined?(mp_log)
          @last_no_vp_log = now
        end
        return
      end
    end

    old = @remote_sprites[rp.mp_id]
    if old
      begin
        if !old.disposed?
          mp_log("OW: create_sprite_for #{rp.mp_name} — sprite already exists") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
          return
        end
      rescue; end
    end

    begin
      sprite = Sprite_MP_RemotePlayer.new(vp, rp)
      @remote_sprites[rp.mp_id] = sprite

      spriteset = current_spriteset
      if spriteset
        arr = spriteset.instance_variable_get(:@character_sprites)
        if arr && !arr.include?(sprite)
          arr << sprite
          mp_log("OW: sprite added to spriteset for #{rp.mp_name}") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
        end
      end

      rp.create_name_sprite(vp)
      mp_log("OW: sprite created for #{rp.mp_name}") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
      @sprite_retry_at.delete(rp.mp_id)
    rescue => e
      mp_log("OW: create_sprite_for error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end

  def remove_remote_player(mp_id)
    sprite = @remote_sprites.delete(mp_id)
    if sprite
      begin
        spriteset = current_spriteset
        if spriteset
          arr = spriteset.instance_variable_get(:@character_sprites)
          arr&.delete(sprite)
        end
      rescue => e; mp_log("OW: remove from spriteset error #{e.class}") if defined?(mp_log); end
      begin; sprite.dispose unless sprite.disposed?; rescue => e; mp_log("OW: sprite dispose error #{e.class}: #{e.message}") if defined?(mp_log); end
    end
    @remote_players.delete(mp_id)
    @sprite_retry_at.delete(mp_id)
  end

  def ensure_fallback_viewport
    begin
      if @fallback_viewport && !@fallback_viewport.disposed?
        return @fallback_viewport
      end
      @fallback_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @fallback_viewport.z = 100
      mp_log("OW: created fallback viewport #{Graphics.width}x#{Graphics.height}") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
      @fallback_viewport
    rescue => e
      mp_log("OW: fallback viewport error #{e.class}: #{e.message}") if defined?(mp_log)
      nil
    end
  end

  def dispose_fallback_viewport
    if @fallback_viewport && !@fallback_viewport.disposed?
      begin
        @fallback_viewport.dispose
        mp_log("OW: disposed fallback viewport") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
      rescue => e
        mp_log("OW: dispose fallback error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end
    @fallback_viewport = nil
  end

  def remote_player_count; @remote_players.length; end

  private

  def in_scene_map?
    $scene.is_a?(Scene_Map)
  end

  def current_viewport
    return nil unless in_scene_map?
    scene_map = $scene
    return nil unless scene_map.is_a?(Scene_Map)

    spriteset = nil
    [:@spriteset, :@map_sprites, :@sprites, :@viewport_sprites].each do |name|
      begin
        val = scene_map.instance_variable_get(name)
        if val && !val.nil?
          spriteset = val
          break
        end
      rescue; end
    end

    if spriteset
      [:@viewport1, :@viewport, :@map_viewport, :@tilemap_viewport, :@base_viewport, :@vp1].each do |name|
        begin
          val = spriteset.instance_variable_get(name)
          if val && val.respond_to?(:disposed?) && !val.disposed?
            return val
          end
        rescue; end
      end
    end

    if @fallback_viewport && !@fallback_viewport.disposed?
      return @fallback_viewport
    end

    nil
  end

  def current_spriteset
    return nil unless in_scene_map?
    scene_map = $scene
    return nil unless scene_map.is_a?(Scene_Map)
    [:@spriteset, :@map_sprites, :@sprites, :@viewport_sprites].each do |name|
      begin
        val = scene_map.instance_variable_get(name)
        return val if val && !val.nil?
      rescue; end
    end
    nil
  end

  extend self
end
