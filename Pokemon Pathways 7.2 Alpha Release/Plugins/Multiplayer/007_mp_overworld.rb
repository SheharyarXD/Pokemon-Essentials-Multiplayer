#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Overworld Sync
#  Hooks into Scene_Map#update and Game_Player#move_generic
#  Manages RemotePlayer instances, sends movement, handles incoming packets
#  Includes interpolation for smooth movement and 20-tile culling
#===============================================================================

module MP_OverworldManager
  module_function

  @remote_players = {}      # mp_id => MP_Game_RemotePlayer
  @remote_sprites = {}      # mp_id => Sprite_MP_RemotePlayer
  @last_pos = { x: nil, y: nil, dir: nil, map: nil }
  @pos_frame_counter = 0
  @initialized = false

  def init
    return if @initialized
    @initialized = true
    register_packet_handlers
  end

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_JOIN) do |payload|
      handle_player_join(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_LEAVE) do |payload|
      handle_player_leave(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_POS_SYNC) do |payload|
      handle_pos_sync(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::MAP_PLAYER_LIST) do |payload|
      handle_map_player_list(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_DIR) do |payload|
      handle_player_dir(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_SPRITE) do |payload|
      handle_player_sprite(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_ACTION) do |payload|
      handle_player_action(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::PLAYER_DATA) do |payload|
      handle_player_data(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::CHAT_SYSTEM) do |payload|
      MP_ChatOverlay.add_message("[SYSTEM] #{payload['message']}", :system)
    end
  end

  def update
    return unless MP_NetworkManager.connected?
    update_local_position
    update_remote_players
    cull_remote_players
  end

  def update_local_position
    return unless $game_player && $game_map

    @pos_frame_counter += 1

    x = $game_player.x
    y = $game_player.y
    dir = $game_player.direction
    map = $game_map.map_id

    # Send position if changed or every N frames
    changed = (@last_pos[:x] != x || @last_pos[:y] != y || @last_pos[:dir] != dir || @last_pos[:map] != map)

    if changed
      if @last_pos[:map] != map && @last_pos[:map] != nil
        # Map changed
        MP_NetworkManager.send_packet(MP_PacketType::MAP_CHANGE, {
          map_id: map,
          x: x,
          y: y,
          direction: dir
        })
      else
        # Position changed
        MP_NetworkManager.send_packet(MP_PacketType::PLAYER_MOVE, {
          x: x,
          y: y,
          direction: dir
        })
      end

      @last_pos[:x] = x
      @last_pos[:y] = y
      @last_pos[:dir] = dir
      @last_pos[:map] = map

      # Send party data periodically
      if @pos_frame_counter % 180 == 0
        MP_NetworkManager.send_party_data
      end
    end

    # Also send position periodically even if not changed
    if @pos_frame_counter % MP_ClientConfig::POSITION_SEND_INTERVAL == 0
      MP_NetworkManager.send_packet(MP_PacketType::PLAYER_MOVE, {
        x: x,
        y: y,
        direction: dir
      })
    end
  end

  def update_remote_players
    @remote_players.each do |mp_id, rp|
      rp.update
      sprite = @remote_sprites[mp_id]
      if sprite
        sprite.update
      end
    end
  end

  def cull_remote_players
    return unless $game_map && $game_player
    @remote_players.each do |mp_id, rp|
      next unless rp.respond_to?(:should_cull?)
      if rp.should_cull? && rp.visible
        rp.visible = false
        sprite = @remote_sprites[mp_id]
        sprite.visible = false if sprite
      elsif !rp.should_cull? && !rp.visible
        rp.visible = true
        sprite = @remote_sprites[mp_id]
        sprite.visible = true if sprite
      end
    end
  end

  def handle_player_join(payload)
    mp_id = payload["client_id"]
    return if mp_id == MP_NetworkManager.client_id
    return if mp_id.nil?

    # Remove existing if any
    remove_remote_player(mp_id)

    name = payload["name"]
    x = payload["x"] || 0
    y = payload["y"] || 0
    dir = payload["direction"] || 2
    sprite = payload["sprite"] || ""
    outfit = payload["outfit"] || 0
    party_disp = payload["party_display"]

    return unless $game_map

    rp = MP_Game_RemotePlayer.new(mp_id, name, $game_map.map_id, x, y, dir, sprite, outfit)
    rp.set_party_display(party_disp) if party_disp
    rp.create_name_bitmap
    @remote_players[mp_id] = rp

    # Create sprite
    create_remote_sprite(rp)

    echoln "[MP] Player joined: #{name} (#{mp_id})"
  end

  def handle_player_leave(payload)
    mp_id = payload["client_id"]
    return unless mp_id

    rp = @remote_players[mp_id]
    if rp
      echoln "[MP] Player left: #{rp.mp_name}" if rp.respond_to?(:mp_name)
    end
    remove_remote_player(mp_id)
  end

  def handle_pos_sync(payload)
    players = payload["players"] || []
    players.each do |p|
      mp_id = p["client_id"] || p[:client_id]
      next unless mp_id && mp_id != MP_NetworkManager.client_id

      rp = @remote_players[mp_id]
      if rp
        nx = p["x"] || p[:x]
        ny = p["y"] || p[:y]
        ndir = p["direction"] || p[:direction]

        if nx && ny
          rp.set_target(nx, ny)
          if MP_ClientConfig::INTERPOLATION_ENABLED
            rp.set_target(nx, ny)
          else
            rp.instance_variable_set(:@x, nx)
            rp.instance_variable_set(:@y, ny)
          end
        end

        if ndir
          rp.set_direction(ndir)
        end
      end
    end
  end

  def handle_map_player_list(payload)
    players = payload["players"] || []
    # Clear existing remote players first
    clear_remote_players
    players.each do |p|
      handle_player_join(p)
    end
    echoln "[MP] Received map player list: #{players.length} players"
  end

  def handle_player_dir(payload)
    mp_id = payload["client_id"]
    dir = payload["direction"]
    rp = @remote_players[mp_id]
    rp.set_direction(dir) if rp && dir
  end

  def handle_player_sprite(payload)
    mp_id = payload["client_id"]
    sprite = payload["sprite"]
    outfit = payload["outfit"]
    rp = @remote_players[mp_id]
    if rp && sprite
      rp.set_sprite(sprite, outfit || 0)
      # Recreate name sprite to refresh
      rp.create_name_bitmap
    end
  end

  def handle_player_action(payload)
    # Actions like jumping - could add visual feedback
    mp_id = payload["client_id"]
    action = payload["action"]
    rp = @remote_players[mp_id]
    if rp && action == "jump"
      # Could trigger jump animation
    end
  end

  def handle_player_data(payload)
    mp_id = payload["client_id"]
    party_disp = payload["party_display"]
    rp = @remote_players[mp_id]
    if rp && party_disp
      rp.set_party_display(party_disp)
      rp.create_name_bitmap
    end
  end

  def create_remote_sprite(rp)
    return unless $scene.is_a?(Scene_Map)
    spriteset = $scene.spriteset rescue nil
    return unless spriteset

    sprite = Sprite_MP_RemotePlayer.new(spriteset.class.viewport || Spriteset_Map.viewport, rp)
    @remote_sprites[rp.mp_id] = sprite
  end

  def remove_remote_player(mp_id)
    sprite = @remote_sprites.delete(mp_id)
    if sprite
      sprite.dispose if !sprite.disposed?
    end
    rp = @remote_players.delete(mp_id)
    rp.dispose_name_sprite if rp.respond_to?(:dispose_name_sprite)
  end

  def clear_remote_players
    @remote_sprites.each do |mp_id, sprite|
      sprite.dispose if sprite && !sprite.disposed?
    end
    @remote_sprites.clear
    @remote_players.each do |mp_id, rp|
      rp.dispose_name_sprite if rp.respond_to?(:dispose_name_sprite)
    end
    @remote_players.clear
  end

  def on_map_changed
    clear_remote_players
    @last_pos = { x: nil, y: nil, dir: nil, map: nil }
  end

  def dispose
    clear_remote_players
    @initialized = false
  end

  def remote_player_count
    @remote_players.length
  end
end
