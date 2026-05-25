#===============================================================================
#  Pokemon Pathways Multiplayer Client - Core Game Hooks
#  STABILIZED v2.1 — Session singleton bootstrap, update-driven lifecycle
#
#  CRITICAL ARCHITECTURAL CHANGES:
#   * Multiplayer NEVER starts from Scene_Map#main — only from update()
#   * MP_Bootstrap.ensure_started runs ONCE per game session
#   * All manager updates happen in Scene_Map#update (every frame)
#   * Heartbeat runs on dedicated thread — survives menus/transitions
#   * NO multiplayer dispose on scene exit — core lives for full session
#   * Map transfer sets $mp_map_loading lock to block sprite creation
#   * Viewport is fetched dynamically by overworld manager every frame
#
#  All hooks wrapped in rescue so MP issues NEVER break single-player.
#===============================================================================

# ── Session Singleton Bootstrap ───────────────────────────────────────────────

module MP_Bootstrap
  @started = false

  def self.ensure_started
    return if @started
    @started = true

    begin
      mp_log("BOOT: multiplayer session bootstrap starting") if defined?(mp_log)

      MP_NetworkManager.start
      MP_OverworldManager.init
      MP_ChatOverlay.init
      MP_BattleManager.init
      MP_TradeManager.init

      # Register disconnect handler to clear sprites (NOT dispose core)
      MP_NetworkManager.on_disconnect do |reason|
        mp_log("BOOT: disconnected (#{reason}) — clearing sprites only") if defined?(mp_log)
        MP_OverworldManager.on_disconnect rescue nil
      end

      mp_log("BOOT: multiplayer initialized ONCE for this session") if defined?(mp_log)
    rescue => e
      mp_log("BOOT: startup error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end

  def self.started?
    @started
  end

  def self.reset_for_testing
    @started = false
  end
end

# ── Scene_Map Hooks ──────────────────────────────────────────────────────────

class Scene_Map

  # ── UPDATE HOOK (the ONLY place MP runs every frame) ───────────────────────
  unless method_defined?(:mp_update)
    alias_method :mp_update, :update
  end

  def update
    # Bootstrap multiplayer exactly once per game session
    MP_Bootstrap.ensure_started if defined?(MP_Bootstrap)

    # Run original update FIRST so spriteset/viewport are valid
    mp_update

    # Pump network I/O and dispatch events (main thread only)
    if defined?(MP_NetworkManager)
      begin
        MP_NetworkManager.tick
      rescue => e
        mp_log("HOOK: MP_NetworkManager.tick error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end

    # Update all subsystems (safe to call even if not connected)
    if defined?(MP_OverworldManager)
      begin
        MP_OverworldManager.update if MP_NetworkManager.connected? rescue false
      rescue => e
        mp_log("HOOK: MP_OverworldManager.update error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end

    if defined?(MP_ChatOverlay)
      begin
        MP_ChatOverlay.update if MP_NetworkManager.connected? rescue false
      rescue => e
        mp_log("HOOK: MP_ChatOverlay.update error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end

    if defined?(MP_BattleManager)
      begin
        MP_BattleManager.update if MP_NetworkManager.connected? rescue false
      rescue => e
        mp_log("HOOK: MP_BattleManager.update error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end

    if defined?(MP_TradeManager)
      begin
        MP_TradeManager.update if MP_NetworkManager.connected? rescue false
      rescue => e
        mp_log("HOOK: MP_TradeManager.update error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end

    # Release map-loading lock after transfer settles (~60 frames)
    if $mp_map_loading
      $mp_map_loading_frames ||= 0
      $mp_map_loading_frames += 1
      if $mp_map_loading_frames >= 60
        $mp_map_loading = false
        $mp_map_loading_frames = 0
        mp_log("HOOK: $mp_map_loading released after 60 frames") if MP_ClientConfig::DEBUG_LIFECYCLE && defined?(mp_log)
      end
    end
  end

  # ── TRANSFER PLAYER HOOK ────────────────────────────────────────────────────
  unless method_defined?(:mp_transfer_player)
    alias_method :mp_transfer_player, :transfer_player
  end

  def transfer_player(cancel_vehicles = true)
    # Set map-loading lock BEFORE transfer so sprite creation is blocked
    $mp_map_loading = true
    $mp_map_loading_frames = 0
    mp_log("HOOK: transfer_player — $mp_map_loading = true") if MP_ClientConfig::DEBUG_LIFECYCLE && defined?(mp_log)

    result = mp_transfer_player(cancel_vehicles)

    if defined?(MP_NetworkManager) && MP_NetworkManager.connected? && $game_map
      begin
        # Notify overworld that map changed (clears sprites, NOT core)
        MP_OverworldManager.on_map_changed rescue nil
        # Send MAP_CHANGE packet to server
        MP_NetworkManager.send_packet(MP_PacketType::MAP_CHANGE, {
          "map_id"    => $game_map.map_id,
          "x"         => $game_player.x,
          "y"         => $game_player.y,
          "direction" => $game_player.direction
        })
        mp_log("HOOK: MAP_CHANGE sent — map #{$game_map.map_id} (#{$game_player.x},#{$game_player.y})") if defined?(mp_log)
      rescue => e
        mp_log("HOOK: transfer_player MP error #{e.class}: #{e.message}") if defined?(mp_log)
      end
    end

    result
  end

  # ── MAIN HOOK — ONLY diagnostic logging, NO MP startup/dispose ────────────
  unless method_defined?(:mp_main)
    alias_method :mp_main, :main
  end

  def main
    mp_log("HOOK: Scene_Map#main entered") if MP_ClientConfig::DEBUG_LIFECYCLE && defined?(mp_log)
    mp_main
  ensure
    mp_log("HOOK: Scene_Map#main exited — NO MP dispose") if MP_ClientConfig::DEBUG_LIFECYCLE && defined?(mp_log)
    # INTENTIONALLY: do NOT call MP_NetworkManager.stop, MP_OverworldManager.dispose, etc.
    # Multiplayer core lives for the entire game session.
  end
end

# Global flags
$mp_map_loading = false
$mp_map_loading_frames = 0

mp_log("HOOKS: MP v2.1 stabilized hooks installed") if defined?(mp_log)
