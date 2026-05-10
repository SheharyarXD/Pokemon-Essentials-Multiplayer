#===============================================================================
#  Pokemon Pathways Multiplayer Client - PvP Battle Integration
#
#  Manages the battle request/accept/forfeit flow with the server.
#
#  ARCHITECTURE NOTE on battle execution:
#  Pokemon Essentials battles run a synchronous scene loop (startBattle blocks
#  until battle ends). This MUST run on the main thread. In v1.x this tried to
#  start the battle from a packet callback on the receive thread — which crashes.
#
#  The correct approach:
#    1. Packet handlers set a @pending_action flag (or push to a queue).
#    2. Scene_Map#update detects the pending action and starts the battle
#       on the main thread.
#  This is the same pattern PE itself uses for trainer battles triggered by events.
#
#  FIXES vs original:
#   * BLOCKING ON WRONG THREAD: battle no longer started from packet callback.
#     It's deferred to the main thread via @pending_battle_start.
#   * CHAT_SYSTEM duplicate: removed; chat overlay registers its own handler.
#   * init is idempotent; called from mp_hooks (not at file-load time).
#   * Party sync: uses a simple mirror of the local party as stand-in.
#     A full implementation would exchange party data before battle start.
#===============================================================================

module MP_BattleManager
  module_function

  @in_mp_battle         = false
  @battle_room_id       = nil
  @remote_opponent      = nil
  @command_queue        = []
  @battle_result        = nil
  @initialized          = false

  # Pending inbound request (shown to player next frame)
  @pending_request      = nil   # { from_name:, room_id: }
  # Pending battle start (executed next frame on main thread)
  @pending_battle_start = nil   # { room_id:, opponent: }

  # ── Lifecycle ───────────────────────────────────────────────────────────────

  def init
    return if @initialized
    @initialized = true
    register_packet_handlers
    mp_log("BATTLE: initialized") if defined?(mp_log)
  end

  # Called from Scene_Map#update (main thread) so UI and battle can be shown.
  def update
    handle_pending_request
    handle_pending_battle_start
  end

  # ── Outbound actions ────────────────────────────────────────────────────────

  def request_battle(target_name)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_REQUEST, {
      "target_name" => target_name
    })
    mp_log("BATTLE: requested vs #{target_name}") if defined?(mp_log)
  end

  def accept_battle(room_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_ACCEPT, { "room_id" => room_id })
  end

  def decline_battle(room_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_DECLINE, { "room_id" => room_id })
    @battle_room_id = nil
  end

  def send_battle_command(command_data)
    return unless MP_NetworkManager.connected? && @in_mp_battle
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_COMMAND, {
      "room_id" => @battle_room_id,
      "command" => command_data
    })
  end

  def forfeit_battle
    return unless MP_NetworkManager.connected? && @in_mp_battle
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_FORFEIT, {
      "room_id" => @battle_room_id
    })
    reset_battle_state
  end

  # ── Accessors ───────────────────────────────────────────────────────────────

  def in_mp_battle?;    @in_mp_battle;    end
  def battle_room_id;   @battle_room_id;  end
  def remote_opponent;  @remote_opponent; end

  def get_next_command
    @command_queue.shift
  end

  # ── Packet handlers (run on main thread via event queue) ────────────────────

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_REQUEST) do |payload|
      # FIX: Store as pending — pbMessage must run on main thread, which update() ensures.
      @pending_request = {
        from_name: payload["from_name"],
        room_id:   payload["room_id"]
      }
    end

    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_START) do |payload|
      # FIX: Store as pending — battle must start on main thread.
      @battle_room_id = payload["room_id"]
      @in_mp_battle   = true
      @command_queue.clear
      @battle_result  = nil
      opponent = ($Trainer.name == payload["player_a"]) ? payload["player_b"] : payload["player_a"]
      @remote_opponent = opponent
      @pending_battle_start = { room_id: payload["room_id"], opponent: opponent }
    end

    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_COMMAND) do |payload|
      next unless @in_mp_battle && @battle_room_id == payload["room_id"]
      @command_queue << {
        turn:             payload["turn"],
        opponent_command: payload["opponent_command"]
      }
    end

    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_RESULT) do |payload|
      @battle_result  = payload
      @in_mp_battle   = false
      @battle_room_id = nil
      # Show result message on next update cycle (already on main thread)
      winner  = payload["winner"]
      message = payload["message"]
      if message && !message.empty?
        pbMessage(message) rescue nil
      elsif winner
        pbMessage(_INTL("Battle ended. {1} wins!", winner)) rescue nil
      end
      mp_log("BATTLE: result - winner=#{winner}") if defined?(mp_log)
    end
  end

  private

  def handle_pending_request
    return unless @pending_request
    req = @pending_request
    @pending_request = nil

    return unless $Trainer   # guard: trainer must exist

    result = pbMessage(
      _INTL("{1} wants to battle! Accept?", req[:from_name]),
      [_INTL("Accept"), _INTL("Decline")],
      -1
    ) rescue 1

    if result == 0
      accept_battle(req[:room_id])
    else
      decline_battle(req[:room_id])
    end
  end

  def handle_pending_battle_start
    return unless @pending_battle_start
    pending = @pending_battle_start
    @pending_battle_start = nil

    begin
      start_remote_battle(pending[:opponent])
    rescue => e
      mp_log("BATTLE: start error #{e.class}: #{e.message}") if defined?(mp_log)
      reset_battle_state
    end
  end

  def start_remote_battle(opponent_name)
    return unless $Trainer

    opponent = NPCTrainer.new(opponent_name, :PVP_TRAINER) rescue nil
    return unless opponent

    # Build a mirror party (real implementation would sync opponent party data)
    opponent_party = $Trainer.party.first(3).map do |pkmn|
      begin
        Pokemon.new(pkmn.species, pkmn.level)
      rescue
        nil
      end
    end.compact
    opponent_party << Pokemon.new(:PIDGEY, 5) if opponent_party.empty?

    $game_temp.in_battle = true
    $game_player.straighten rescue nil

    scene  = PokeBattle_Scene.new
    battle = PokeBattle_Battle.new(scene, $Trainer.party, opponent_party, $Trainer, [opponent])
    battle.internalBattle = false
    battle.canRun         = false
    battle.startBattle

  ensure
    $game_temp.in_battle = false
    reset_battle_state unless @pending_battle_start  # don't reset if new battle queued
  end

  def reset_battle_state
    @in_mp_battle         = false
    @battle_room_id       = nil
    @remote_opponent      = nil
    @command_queue.clear
    @battle_result        = nil
    @pending_battle_start = nil
    @pending_request      = nil
  end
end
