#===============================================================================
#  MP HOOKS v1.2.0
#  Single, idempotent hook installation.
#  FIXED:
#    1. Only ONE Scene_Map#main hook (merged diagnostic + network hooks)
#    2. Removed redundant Game_Player#move_generic hook (was double-sending positions)
#    3. Added MP_NetworkManager.drain_main_thread_queue to Scene_Map#update
#    4. Added guards for $scene type in update hook
#    5. transfer_player hook sends MAP_CHANGE only from this single location
#    6. Hooks are wrapped in begin/rescue to never break single-player
#    7. Added at_exit hook for graceful disconnect on window close
#===============================================================================

module MP_Hooks
  module_function

  @installed = false

  def install
    return if @installed
    @installed = true
    echoln "[MP] Hooks installed"
    mp_log("HOOKS: installed") if defined?(mp_log)
  end
end

# ── Scene_Map ─────────────────────────────────────────────────────────────────

class Scene_Map
  # Guard: only install once even if file reloads
  unless method_defined?(:mp_hook_main)
    alias_method :mp_hook_main, :main

    def main
      # Start multiplayer networking (once per session)
      unless $mp_network_started
        $mp_network_started = true
        begin
          mp_log("HOOK: Scene_Map#main start") if defined?(mp_log)
          MP_NetworkManager.start
          MP_OverworldManager.init
        rescue => e
          echoln "[MP] Startup error: #{e.class}: #{e.message}"
        end
      end

      mp_hook_main
    ensure
      # Clean up when leaving map scene (title screen, game over, etc.)
      $mp_network_started = false
      begin; MP_NetworkManager.stop; rescue; end
      begin; MP_OverworldManager.dispose; rescue; end
      begin; MP_ChatOverlay.dispose; rescue; end
    end
  end

  unless method_defined?(:mp_hook_update)
    alias_method :mp_hook_update, :update

    def update
      mp_hook_update

      # Process multiplayer on main thread (guaranteed main thread here)
      return unless defined?(MP_NetworkManager)

      if MP_NetworkManager.connected?
        # Drain any UI work marshalled from network thread
        begin
          MP_NetworkManager.drain_main_thread_queue
        rescue => e
          echoln "[MP] drain_main_thread_queue error: #{e.class}" if $DEBUG
        end

        # Update overworld (only when in Scene_Map)
        begin
          if $scene.is_a?(Scene_Map)
            MP_OverworldManager.update
          end
        rescue => e
          echoln "[MP] Overworld update error: #{e.class}" if $DEBUG
        end

        # Update chat overlay
        begin
          if $scene.is_a?(Scene_Map)
            MP_ChatOverlay.update
          end
        rescue => e
          echoln "[MP] Chat update error: #{e.class}" if $DEBUG
        end
      end
    rescue => e
      echoln "[MP] Scene_Map#update hook error: #{e.class}" if $DEBUG
    end
  end

  unless method_defined?(:mp_hook_transfer_player)
    alias_method :mp_hook_transfer_player, :transfer_player

    def transfer_player(cancel_vehicles = true)
      # Perform the actual transfer first
      result = mp_hook_transfer_player(cancel_vehicles)

      # Then notify the server (player is now on the new map)
      if defined?(MP_NetworkManager) && MP_NetworkManager.connected?
        begin
          # Clear remote players (we're changing maps)
          MP_OverworldManager.on_map_changed rescue nil

          # Send map change notification
          if $game_map && $game_player
            MP_NetworkManager.send_packet(MP_PacketType::MAP_CHANGE, {
              map_id:    $game_map.map_id,
              x:         $game_player.x,
              y:         $game_player.y,
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

# ── Graceful disconnect on window close ──────────────────────────────────────

begin
  at_exit do
    if defined?(MP_NetworkManager)
      MP_NetworkManager.graceful_shutdown rescue nil
    end
  end
rescue
  # at_exit may not be available in all RGSS runtimes
end

# Global flag -- false means not yet started this session
$mp_network_started = false

MP_Hooks.install
