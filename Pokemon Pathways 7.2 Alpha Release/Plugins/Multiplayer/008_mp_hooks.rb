#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Core Game Hooks
#  FIXED v3:
#    - Connection now triggered from Scene_Map#main (fires on BOTH new game AND
#      loaded save), not Events.onMapSceneChange (which only fires on new game)
#    - class reopening at top level (RGSS compatible)
#    - All hooks wrapped in rescue to never break single-player
#===============================================================================

module MP_Hooks
  module_function

  @installed = false

  def install
    return if @installed
    @installed = true
    echoln "[MP] All hooks installed successfully"
  end
end

# ── Hook: Scene_Map#main ──────────────────────────────────────────────────────
# This fires for BOTH new game AND continue/load save — the correct place to
# start the network connection. update fires every frame; main fires once on
# scene entry and runs until scene exits.
class Scene_Map
  alias_method :mp_orig_main, :main
  def main
    # Start multiplayer when entering the map scene (new game OR loaded save)
    unless $mp_network_started
      $mp_network_started = true
      begin
        echoln "[MP] Scene_Map#main entered — starting network..."
        MP_NetworkManager.start
        MP_OverworldManager.init
      rescue => e
        echoln "[MP] Startup error: #{e.class}: #{e.message}"
      end
    end
    mp_orig_main
  ensure
    # Clean up when scene exits (title screen, game over, etc.)
    # Reset flag so reconnect works if player returns to map
    $mp_network_started = false
    MP_NetworkManager.stop      rescue nil
    MP_OverworldManager.dispose rescue nil
  end

  alias_method :mp_orig_update, :update
  def update
    mp_orig_update
    return unless defined?(MP_NetworkManager)
    if MP_NetworkManager.connected?
      MP_NetworkManager.process_outgoing rescue nil
      MP_OverworldManager.update         rescue nil
    end
  rescue => e
    echoln "[MP] Scene_Map#update error: #{e.class}" if $DEBUG
  end

  alias_method :mp_orig_transfer_player, :transfer_player
  def transfer_player(cancel_vehicles = true)
    result = mp_orig_transfer_player(cancel_vehicles)
    if defined?(MP_NetworkManager) && MP_NetworkManager.connected?
      MP_OverworldManager.on_map_changed rescue nil
      MP_NetworkManager.send_packet(MP_PacketType::MAP_CHANGE, {
        map_id:    $game_map.map_id,
        x:         $game_player.x,
        y:         $game_player.y,
        direction: $game_player.direction
      }) rescue nil
    end
    result
  end
end

# ── Hook: Game_Player#move_generic ────────────────────────────────────────────
class Game_Player
  alias_method :mp_orig_move_generic, :move_generic
  def move_generic(dir, turn_enabled = true)
    result = mp_orig_move_generic(dir, turn_enabled)
    if defined?(MP_NetworkManager) && MP_NetworkManager.connected?
      MP_OverworldManager.update_local_position rescue nil
    end
    result
  end
end

# Global flag — false means not yet started this session
$mp_network_started = false

MP_Hooks.install
