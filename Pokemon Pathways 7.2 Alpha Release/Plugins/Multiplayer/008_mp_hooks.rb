#===============================================================================
#  Pokemon Pathways Multiplayer Client - Core Game Hooks
#
#  Hooks into three PE methods:
#    Scene_Map#main          - start/stop network on scene enter/exit
#    Scene_Map#update        - pump network I/O every frame
#    Scene_Map#transfer_player - send MAP_CHANGE on map transitions
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
#     FIX: use instance_variable_get(:@spriteset) because Scene_Map has no
#     `spriteset` reader method in Pokemon Essentials v19.1.
#   * CHAT / BATTLE MANAGERS: initialized here inside Scene_Map#main so they
#     can register their callbacks after MP_NetworkManager.start.
#   * UPDATE ORDER: viewport detection now runs AFTER tick() when needed,
#     because tick() may call handle_player_join which needs the viewport
#     immediately. The viewport is probed both before and after tick to ensure
#     it is available as early as possible.
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

    # ── Viewport detection ──────────────────────────────────────────────
    # We need the viewport so that handle_player_join (which may fire
    # inside tick()) can create sprites.  We probe it every frame because
    # map transfers create a new Spriteset_Map (and therefore a new
    # viewport).  FIX: Scene_Map stores the spriteset in @spriteset -
    # there is no `spriteset` accessor in PE v19.1.
    #
    # Detection runs both BEFORE and AFTER tick so that if tick()
    # triggers handle_player_join, the viewport is already available.
    try_set_viewport

    return unless defined?(MP_NetworkManager)

    begin
      # tick() = process_outgoing + dispatch_events (all on main thread)
      MP_NetworkManager.tick

      # Try again after tick in case spriteset was created during update
      try_set_viewport

      MP_OverworldManager.update if MP_NetworkManager.connected?
      MP_ChatOverlay.update      if MP_NetworkManager.connected?
    rescue => e
      mp_log("HOOK: update error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end

  unless method_defined?(:mp_orig_transfer_player)
    alias_method :mp_orig_transfer_player, :transfer_player
  end

  # Only this hook sends MAP_CHANGE. Overworld update no longer does.
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

  # ── Viewport helper ───────────────────────────────────────────────────
  # Extracts the map viewport from the Spriteset_Map stored in @spriteset.
  # FIX: Uses instance_variable_get because Scene_Map has no `spriteset` reader.
  private

  def try_set_viewport
    return unless defined?(MP_OverworldManager)
    current_vp = MP_OverworldManager.instance_variable_get(:@map_viewport) rescue nil
    if current_vp.nil? || (current_vp.respond_to?(:disposed?) && current_vp.disposed?)
      spriteset = self.instance_variable_get(:@spriteset) rescue nil
      if spriteset
        vp = spriteset.instance_variable_get(:@viewport1) ||
             spriteset.instance_variable_get(:@viewport)  rescue nil
        if vp
          MP_OverworldManager.set_viewport(vp)
          mp_log("HOOK: viewport set from @spriteset") if defined?(mp_log)
        end
      end
    end
  rescue => e
    # Silently ignore - viewport will be retried next frame
  end
end

# Global flag — false means network not yet started this scene session
$mp_network_started = false

MP_Hooks.install
