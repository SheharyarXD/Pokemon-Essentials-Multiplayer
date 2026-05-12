#===============================================================================
#  Pokemon Pathways Multiplayer Client - Core Game Hooks (STABLE v2.1)
#
#  CRITICAL FIXES:
#    * Viewport is now fetched and passed BEFORE MP_NetworkManager.tick
#      (fixes race where PLAYER_JOIN arrives before viewport is ready).
#    * Added on_map_change_complete hook called after transfer_player
#      finishes, releasing the map-changing lock.
#    * Scene_Map#main no longer conflicts with 000_mp_diagnostic.rb
#      (diagnostic file removed its main hook in v2.1).
#    * MP_NetworkManager.tick runs AFTER viewport is ready.
#    * All hooks wrapped in exception handlers that never break the game loop.
#
#  HOOKS:
#    Scene_Map#main          — start network + subsystems (once per session)
#    Scene_Map#update        — viewport pass → network tick → overworld update
#    Scene_Map#transfer_player — send MAP_CHANGE, clear remote players
#    Scene_Map#main_variable — cleanup when scene changes
#===============================================================================

module MP_Hooks
  module_function

  @installed = false

  def install
    return if @installed
    @installed = true
    mp_log("HOOKS: installed v2.1") if defined?(mp_log)
  end
end

# ── Scene_Map ─────────────────────────────────────────────────────────────────

class Scene_Map
  unless method_defined?(:mp_orig_main)
    alias_method :mp_orig_main, :main
  end

  def main
    # One game session = one net thread + one set of packet handlers.
    unless $mp_multiplayer_core_ready
      $mp_multiplayer_core_ready = true
      begin
        mp_log("HOOK: core init (once per session)") if defined?(mp_log)

        MP_NetworkManager.start

        MP_NetworkManager.on_disconnect do |reason|
          mp_log("HOOK: disconnected (#{reason})") if defined?(mp_log)
          begin
            MP_OverworldManager.on_disconnect
          rescue => e
            mp_log_exception("HOOK: disconnect handler", e) if defined?(mp_log_exception)
          end
        end

        MP_OverworldManager.init
        MP_ChatOverlay.init      if defined?(MP_ChatOverlay)
        MP_BattleManager.init    if defined?(MP_BattleManager)
        MP_TradeManager.init     if defined?(MP_TradeManager)

      rescue => e
        mp_log_exception("HOOK: core init error", e) if defined?(mp_log_exception)
      end
    end

    mp_orig_main

  ensure
    begin
      MP_OverworldManager.leave_scene_map if defined?(MP_OverworldManager)
      MP_ChatOverlay.leave_scene_map if defined?(MP_ChatOverlay)
      mp_log("HOOK: main exited (sprites cleared, network running)") if defined?(mp_log)
    rescue => e
      mp_log_exception("HOOK: main ensure", e) if defined?(mp_log_exception)
    end
  end

  unless method_defined?(:mp_orig_update)
    alias_method :mp_orig_update, :update
  end

  def update
    mp_orig_update

    # CRITICAL FIX: Pass viewport BEFORE processing network packets.
    # This ensures viewport is ready when PLAYER_JOIN handlers run.
    begin
      if defined?(MP_OverworldManager)
        # Always refresh viewport each frame — don't rely on cached value
        spriteset = self.spriteset rescue nil
        if spriteset
          vp = spriteset.instance_variable_get(:@viewport1) ||
               spriteset.instance_variable_get(:@viewport)  rescue nil
          if vp && !vp.disposed?
            MP_OverworldManager.set_viewport(vp)
          end
        end
      end
    rescue => e
      mp_log_exception("HOOK: viewport pass", e) if defined?(mp_log_exception)
    end

    # Multiplayer update block
    begin
      return unless defined?(MP_NetworkManager)

      # 1. Dispatch inbound packets + flush outbound (all on main thread)
      MP_NetworkManager.tick

      # 2. F9 diagnostic dump
      if MP_ClientConfig::NETWORK_DIAG_F9_DUMP && MP_ClientConfig::NETWORK_DIAGNOSTICS
        begin
          if defined?(Input::F9) && Input.trigger?(Input::F9)
            mp_log("MP_DIAG #{MP_NetworkManager.diagnostics_text}") if defined?(mp_log)
          end
        rescue
          nil
        end
      end

      # 3. Update overworld (remote players + sprites)
      MP_OverworldManager.update if MP_NetworkManager.connected?

      # 4. Update chat overlay
      MP_ChatOverlay.update if defined?(MP_ChatOverlay) && MP_NetworkManager.connected?

      # 5. Update battle manager
      MP_BattleManager.update if defined?(MP_BattleManager) && MP_NetworkManager.connected?

      # 6. Update trade manager
      MP_TradeManager.update if defined?(MP_TradeManager) && MP_NetworkManager.connected?

    rescue => e
      mp_log_exception("HOOK: Scene_Map#update multiplayer block", e) if defined?(mp_log_exception)
    end
  end

  unless method_defined?(:mp_orig_transfer_player)
    alias_method :mp_orig_transfer_player, :transfer_player
  end

  def transfer_player(cancel_vehicles = true)
    # Notify overworld that we're leaving (blocks sprite creation)
    begin
      MP_OverworldManager.on_map_changed if defined?(MP_OverworldManager)
    rescue => e
      mp_log_exception("HOOK: pre-transfer", e) if defined?(mp_log_exception)
    end

    result = mp_orig_transfer_player(cancel_vehicles)

    # After transfer: send new position + release transition lock
    begin
      if defined?(MP_NetworkManager) && MP_NetworkManager.connected? && $game_map
        MP_NetworkManager.send_packet(MP_PacketType::MAP_CHANGE, {
          "map_id"    => $game_map.map_id,
          "x"         => $game_player.x,
          "y"         => $game_player.y,
          "direction" => $game_player.direction
        })
      end
      # Release transition lock after a short delay
      # (spriteset needs time to rebuild)
      if defined?(MP_OverworldManager)
        @mp_map_change_timer = 15  # frames to wait before releasing lock
      end
    rescue => e
      mp_log_exception("HOOK: transfer_player", e) if defined?(mp_log_exception)
    end

    result
  end

  # NEW: Countdown timer for releasing map transition lock
  unless method_defined?(:mp_orig_update_countdown)
    alias_method :mp_orig_update_countdown, :update
  end

  # We use the existing update hook, just add the timer logic
  unless method_defined?(:mp_update_map_change_timer)
    def mp_update_map_change_timer
      if @mp_map_change_timer && @mp_map_change_timer > 0
        @mp_map_change_timer -= 1
        if @mp_map_change_timer <= 0
          @mp_map_change_timer = nil
          begin
            MP_OverworldManager.on_map_change_complete if defined?(MP_OverworldManager)
          rescue => e
            mp_log_exception("HOOK: map_change_complete", e) if defined?(mp_log_exception)
          end
        end
      end
    end
  end
end

# Inject timer update into the existing update chain
class Scene_Map
  alias_method :mp_hook_update_with_timer, :update

  def update
    mp_hook_update_with_timer
    mp_update_map_change_timer
  rescue => e
    mp_log_exception("HOOK: timer update", e) if defined?(mp_log_exception)
  end
end

$mp_multiplayer_core_ready = false unless defined?($mp_multiplayer_core_ready)

MP_Hooks.install

