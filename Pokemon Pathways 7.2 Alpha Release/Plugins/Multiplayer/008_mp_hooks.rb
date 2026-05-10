#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Core Game Hooks
#  Hooks into Scene_Map#update, Game_Player#move_generic, map changes
#  Non-invasive: if multiplayer unavailable, single-player continues normally
#===============================================================================

# Store original methods for chaining
module MP_Hooks
  module_function

  @installed = false

  def install
    return if @installed
    @installed = true

    hook_scene_map
    hook_game_player
    hook_map_change
    hook_battle
    hook_game_start
    hook_game_end

    echoln "[MP] All hooks installed successfully"
  end

  def hook_scene_map
    # Hook Scene_Map#update for network processing
    class << Scene_Map
      alias_method :mp_old_update, :update
      def update
        mp_old_update
        # Update network and overworld if multiplayer is running
        if MP_NetworkManager
          MP_NetworkManager.process_outgoing if MP_NetworkManager.connected?
          MP_OverworldManager.update if MP_OverworldManager
        end
      rescue => e
        echoln "[MP] Scene_Map#update hook error: #{e.class}" if $DEBUG
      end
    end
  end

  def hook_game_player
    # Hook Game_Player#move_generic to detect movement
    class << Game_Player
      alias_method :mp_old_move_generic, :move_generic
      def move_generic(dir, turn_enabled = true)
        result = mp_old_move_generic(dir, turn_enabled)
        # Notify overworld manager of movement
        if MP_OverworldManager && MP_NetworkManager.connected?
          begin
            MP_OverworldManager.update_local_position
          rescue => e
            echoln "[MP] move_generic hook error: #{e.class}" if $DEBUG
          end
        end
        result
      end
    end
  end

  def hook_map_change
    # Hook map change via transfer_player
    class << Scene_Map
      alias_method :mp_old_transfer_player, :transfer_player
      def transfer_player(cancel_vehicles = true)
        result = mp_old_transfer_player(cancel_vehicles)
        # Notify overworld of map change
        if MP_OverworldManager
          begin
            MP_OverworldManager.on_map_changed
            # Send map change to server
            if MP_NetworkManager.connected? && $game_map && $game_player
              MP_NetworkManager.send_packet(MP_PacketType::MAP_CHANGE, {
                map_id: $game_map.map_id,
                x: $game_player.x,
                y: $game_player.y,
                direction: $game_player.direction
              })
            end
          rescue => e
            echoln "[MP] transfer_player hook error: #{e.class}" if $DEBUG
          end
        end
        result
      end
    end
  end

  def hook_battle
    # Hook battle start to notify other players or pause sync
    Events.onStartBattle += proc { |sender, e|
      if MP_NetworkManager.connected?
        # Could send a "busy" status to server
      end
    }

    Events.onEndBattle += proc { |sender, e|
      if MP_NetworkManager.connected?
        # Resume normal sync
      end
    }
  end

  def hook_game_start
    # Hook game start / new game / continue
    Events.onMapSceneChange += proc { |sender, e|
      begin
        # Start multiplayer connection when entering the map
        unless MP_NetworkManager.connected? || MP_NetworkManager.connecting?
          MP_NetworkManager.start
        end
        MP_OverworldManager.init
      rescue => e
        echoln "[MP] Game start hook error: #{e.class}" if $DEBUG
      end
    }
  end

  def hook_game_end
    # Hook when game ends / returns to title
    class << Scene_Map
      alias_method :mp_old_main, :main
      def main
        mp_old_main
      rescue SystemExit, Interrupt
        raise
      rescue => e
        # Game ended normally
        nil
      ensure
        begin
          MP_NetworkManager.stop if MP_NetworkManager
          MP_OverworldManager.dispose if MP_OverworldManager
        rescue
          nil
        end
      end
    end
  end
end

# Install hooks when the plugin loads
MP_Hooks.install
