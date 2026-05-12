#===============================================================================
#  Pokemon Pathways Multiplayer Client - PvP Battle Integration (STABLE v2.1)
#
#  FIXES v2.1:
#   * Added exception handling around all battle scene operations
#   * Safe cleanup of battle state on any failure path
#   * NPCTrainer creation guarded with rescue
#   * Pokemon.new calls wrapped in begin/rescue
#   * Scene creation deferred to reduce init-time crashes
#===============================================================================

module MP_BattleManager
  module_function

  @in_mp_battle         = false
  @battle_room_id       = nil
  @remote_opponent      = nil
  @command_queue        = []
  @battle_result        = nil
  @initialized          = false

  @pending_request      = nil
  @pending_battle_start = nil

  def init
    return if @initialized
    @initialized = true
    @command_queue = []
    register_packet_handlers
    mp_log("BATTLE: initialized v2.1") if defined?(mp_log)
  end

  def update
    begin
      handle_pending_request
      handle_pending_battle_start
    rescue => e
      mp_log_exception("BATTLE: update", e) if defined?(mp_log_exception)
      reset_battle_state
    end
  end

  def request_battle(target_name)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_REQUEST, {
      "target_name" => target_name.to_s
    })
    mp_log("BATTLE: requested vs #{target_name}") if defined?(mp_log)
  end

  def accept_battle(room_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_ACCEPT, { "room_id" => room_id.to_s })
  end

  def decline_battle(room_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_DECLINE, { "room_id" => room_id.to_s })
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

  def in_mp_battle?;    @in_mp_battle;    end
  def battle_room_id;   @battle_room_id;  end
  def remote_opponent;  @remote_opponent; end

  def get_next_command
    @command_queue.shift
  end

  private

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_REQUEST) do |payload|
      begin
        @pending_request = {
          from_name: payload["from_name"].to_s,
          room_id:   payload["room_id"].to_s
        }
      rescue => e
        mp_log_exception("BATTLE: BATTLE_REQUEST handler", e) if defined?(mp_log_exception)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_START) do |payload|
      begin
        @battle_room_id = payload["room_id"]
        @in_mp_battle   = true
        @command_queue.clear
        @battle_result  = nil
        opponent = ($Trainer&.name == payload["player_a"]) ? payload["player_b"] : payload["player_a"]
        @remote_opponent = opponent.to_s
        @pending_battle_start = { room_id: payload["room_id"], opponent: @remote_opponent }
      rescue => e
        mp_log_exception("BATTLE: BATTLE_START handler", e) if defined?(mp_log_exception)
        reset_battle_state
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_COMMAND) do |payload|
      begin
        next unless @in_mp_battle && @battle_room_id == payload["room_id"]
        @command_queue << {
          turn:             payload["turn"],
          opponent_command: payload["opponent_command"]
        }
      rescue => e
        mp_log_exception("BATTLE: BATTLE_COMMAND handler", e) if defined?(mp_log_exception)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_RESULT) do |payload|
      begin
        @battle_result  = payload
        @in_mp_battle   = false
        @battle_room_id = nil
        winner  = payload["winner"]
        message = payload["message"]
        if message && !message.to_s.empty?
          pbMessage(message.to_s) rescue nil
        elsif winner
          pbMessage(_INTL("Battle ended. {1} wins!", winner.to_s)) rescue nil
        end
        mp_log("BATTLE: result winner=#{winner}") if defined?(mp_log)
      rescue => e
        mp_log_exception("BATTLE: BATTLE_RESULT handler", e) if defined?(mp_log_exception)
      ensure
        reset_battle_state
      end
    end
  end

  def handle_pending_request
    return unless @pending_request
    req = @pending_request
    @pending_request = nil
    return unless $Trainer

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
  rescue => e
    mp_log_exception("BATTLE: handle_pending_request", e) if defined?(mp_log_exception)
  end

  def handle_pending_battle_start
    return unless @pending_battle_start
    pending = @pending_battle_start
    @pending_battle_start = nil

    begin
      start_remote_battle(pending[:opponent])
    rescue => e
      mp_log_exception("BATTLE: handle_pending_battle_start", e) if defined?(mp_log_exception)
      reset_battle_state
    end
  end

  def start_remote_battle(opponent_name)
    return unless $Trainer

    opponent = nil
    begin
      opponent = NPCTrainer.new(opponent_name.to_s, :PVP_TRAINER)
    rescue => e
      mp_log_exception("BATTLE: NPCTrainer create", e) if defined?(mp_log_exception)
      return
    end
    return unless opponent

    # Build mirror party
    opponent_party = []
    begin
      opponent_party = $Trainer.party.first(3).map do |pkmn|
        begin
          Pokemon.new(pkmn.species, pkmn.level)
        rescue
          nil
        end
      end.compact
    rescue => e
      mp_log_exception("BATTLE: party build", e) if defined?(mp_log_exception)
    end

    if opponent_party.empty?
      begin
        opponent_party << Pokemon.new(:PIDGEY, 5)
      rescue
        mp_log("BATTLE: cannot create fallback Pokemon") if defined?(mp_log)
        return
      end
    end

    $game_temp.in_battle = true if $game_temp.respond_to?(:in_battle=)
    $game_player.straighten rescue nil

    begin
      scene  = PokeBattle_Scene.new
      battle = PokeBattle_Battle.new(scene, $Trainer.party, opponent_party, $Trainer, [opponent])
      battle.internalBattle = false
      battle.canRun         = false
      battle.startBattle
    rescue => e
      mp_log_exception("BATTLE: startBattle", e) if defined?(mp_log_exception)
    end
  ensure
    begin
      $game_temp.in_battle = false if $game_temp.respond_to?(:in_battle=)
    rescue
      nil
    end
    reset_battle_state unless @pending_battle_start
  end

  def reset_battle_state
    @in_mp_battle         = false
    @battle_room_id       = nil
    @remote_opponent      = nil
    @command_queue        = []
    @battle_result        = nil
    @pending_battle_start = nil
    @pending_request      = nil
  end
end

