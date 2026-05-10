#===============================================================================
#  Pokemon Pathways Multiplayer Client - Core Game Hooks
#
#  Hooks into three PE methods:
#    Scene_Map#main          — start/stop network on scene enter/exit
#    Scene_Map#update        — pump network I/O every frame
#    Scene_Map#transfer_player — send MAP_CHANGE on map transitions
#
#  All hooks are wrapped in rescue so multiplayer issues NEVER break
#  single-player gameplay.
#
#  FIXES vs original:
#   * TICK: Scene_Map#update now calls MP_NetworkManager.tick instead of
#     process_outgoing directly. tick() flushes outbound AND dispatches all
#     pending inbound events to handlers on the main thread (thread-safety fix).
#   * MAP_CHANGE: transfer_player sends MAP_CHANGE; overworld update_local_position
#     no longer sends it. No more duplicate MAP_CHANGE packets.
#   * DISCONNECT CLEANUP: on_disconnect handler registered here calls
#     MP_OverworldManager.on_disconnect to clear ghost players.
#   * VIEWPORT: after spriteset is created, pass the viewport to OverworldManager.
#   * CHAT / BATTLE MANAGERS: initialized here inside Scene_Map#main so they
#     can register their callbacks after MP_NetworkManager.start.
#===============================================================================

module MP_Hooks
  module_function

  @installed = false

  def install
    return if @installed
    @installed = true
    mp_log("HOOKS: installed") if defined?(mp_log)
  end
end

# ── Scene_Map ─────────────────────────────────────────────────────────────────

class Scene_Map
  unless method_defined?(:mp_orig_main)
    alias_method :mp_orig_main, :main
  end

  def main
    unless $mp_network_started
      $mp_network_started = true
      begin
        mp_log("HOOK: Scene_Map#main → starting MP") if defined?(mp_log)

        # Start network first (sets up state machine; doesn't connect yet)
        MP_NetworkManager.start

        # Register top-level disconnect handler to clear remote players
        MP_NetworkManager.on_disconnect do |reason|
          mp_log("HOOK: disconnected (#{reason})") if defined?(mp_log)
          MP_OverworldManager.on_disconnect rescue nil
        end

        # Init subsystems — these register their packet handlers
        MP_OverworldManager.init
        MP_ChatOverlay.init
        MP_BattleManager.init
        MP_TradeManager.init

      rescue => e
        mp_log("HOOK: startup error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end

    mp_orig_main

  ensure
    $mp_network_started = false
    MP_NetworkManager.stop        rescue nil
    MP_OverworldManager.dispose   rescue nil
    MP_ChatOverlay.dispose        rescue nil
    mp_log("HOOK: Scene_Map#main exiting") if defined?(mp_log)
  end

  unless method_defined?(:mp_orig_update)
    alias_method :mp_orig_update, :update
  end

  def update
    mp_orig_update

    # Pass the map viewport once we know the spriteset exists
    if defined?(MP_OverworldManager) && MP_OverworldManager.instance_variable_get(:@map_viewport).nil?
      if spriteset = (self.spriteset rescue nil)
        vp = spriteset.instance_variable_get(:@viewport1) ||
             spriteset.instance_variable_get(:@viewport)  rescue nil
        MP_OverworldManager.set_viewport(vp) if vp
      end
    end

    return unless defined?(MP_NetworkManager)

    begin
      # FIX: tick() = process_outgoing + dispatch_events (all on main thread)
      MP_NetworkManager.tick
      MP_OverworldManager.update if MP_NetworkManager.connected?
      MP_ChatOverlay.update      if MP_NetworkManager.connected?
    rescue => e
      mp_log("HOOK: update error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end

  unless method_defined?(:mp_orig_transfer_player)
    alias_method :mp_orig_transfer_player, :transfer_player
  end

  # FIX: Only this hook sends MAP_CHANGE. Overworld update no longer does.
  def transfer_player(cancel_vehicles = true)
    result = mp_orig_transfer_player(cancel_vehicles)
    if defined?(MP_NetworkManager) && MP_NetworkManager.connected? && $game_map
      begin
        MP_OverworldManager.on_map_changed  # clear remote players for old map
        MP_NetworkManager.send_packet(MP_PacketType::MAP_CHANGE, {
          "map_id"    => $game_map.map_id,
          "x"         => $game_player.x,
          "y"         => $game_player.y,
          "direction" => $game_player.direction
        })
      rescue => e
        mp_log("HOOK: transfer_player error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end
    result
  end
end

# Global flag — false means network not yet started this scene session
$mp_network_started = false

MP_Hooks.install
