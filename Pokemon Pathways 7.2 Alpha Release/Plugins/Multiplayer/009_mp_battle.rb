#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Battle Integration
#  Intercepts PokeBattle_Battle for remote opponents
#  Sends commands as BATTLE_COMMAND packets, receives opponent commands
#  Drives existing battle engine with received data
#===============================================================================

module MP_BattleManager
  module_function

  @in_mp_battle = false
  @battle_room_id = nil
  @remote_opponent = nil
  @command_queue = []
  @battle_result = nil
  @initialized = false

  def init
    return if @initialized
    @initialized = true
    register_packet_handlers
  end

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_REQUEST) do |payload|
      handle_battle_request(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_START) do |payload|
      handle_battle_start(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_COMMAND) do |payload|
      handle_battle_command(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::BATTLE_RESULT) do |payload|
      handle_battle_result(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::CHAT_SYSTEM) do |payload|
      if payload["message"].include?("battle") || payload["message"].include?("Battle")
        echoln "[MP][Battle] #{payload['message']}"
      end
    end
  end

  def request_battle(target_name)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_REQUEST, {
      target_name: target_name
    })
    echoln "[MP][Battle] Sent battle request to #{target_name}"
  end

  def accept_battle(room_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_ACCEPT, {
      room_id: room_id
    })
    echoln "[MP][Battle] Accepted battle #{room_id}"
  end

  def decline_battle(room_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_DECLINE, {
      room_id: room_id
    })
    @battle_room_id = nil
  end

  def send_battle_command(command_data)
    return unless MP_NetworkManager.connected? && @in_mp_battle
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_COMMAND, {
      room_id: @battle_room_id,
      command: command_data
    })
  end

  def forfeit_battle
    return unless MP_NetworkManager.connected? && @in_mp_battle
    MP_NetworkManager.send_packet(MP_PacketType::BATTLE_FORFEIT, {
      room_id: @battle_room_id
    })
    @in_mp_battle = false
    @battle_room_id = nil
  end

  def handle_battle_request(payload)
    from_name = payload["from_name"]
    room_id = payload["room_id"]
    from_id = payload["from_id"]

    echoln "[MP][Battle] Battle request from #{from_name} (Room: #{room_id})"

    # Show a message asking the player
    result = pbMessage(_INTL("{1} wants to battle! Accept?", from_name),
                       [_INTL("Accept"), _INTL("Decline")], -1)

    if result == 0
      accept_battle(room_id)
    else
      decline_battle(room_id)
    end
  end

  def handle_battle_start(payload)
    room_id = payload["room_id"]
    player_a = payload["player_a"]
    player_b = payload["player_b"]

    @battle_room_id = room_id
    @in_mp_battle = true
    @command_queue.clear
    @battle_result = nil

    echoln "[MP][Battle] Battle started: #{player_a} vs #{player_b}"

    # Determine opponent
    @remote_opponent = ($Trainer.name == player_a) ? player_b : player_a

    # Create remote trainer and start battle
    start_remote_battle(@remote_opponent)
  end

  def start_remote_battle(opponent_name)
    return unless $Trainer

    # Create a remote trainer
    opponent = NPCTrainer.new(opponent_name, :PVP_TRAINER)

    # Use the player's party as the opponent's party for now
    # In a full implementation, the opponent's party would be synced
    opponent_party = []
    3.times do |i|
      if $Trainer.party[i]
        pkmn = Pokemon.new($Trainer.party[i].species, $Trainer.party[i].level)
        opponent_party << pkmn
      end
    end

    if opponent_party.empty?
      opponent_party = [Pokemon.new(:PIDGEY, 10)]
    end

    # Start the battle using the existing system
    begin
      $game_temp.in_battle = true
      $game_player.straighten

      scene = PokeBattle_Scene.new
      battle = PokeBattle_Battle.new(scene, $Trainer.party, opponent_party, $Trainer, [opponent])
      battle.internalBattle = false
      battle.canRun = false

      # Hook into the battle to capture commands
      hook_battle_commands(battle)

      battle.decision = 0
      battle.startBattle

      @in_mp_battle = false
      @battle_room_id = nil

    rescue => e
      echoln "[MP][Battle] Error starting battle: #{e.class}: #{e.message}"
      @in_mp_battle = false
      @battle_room_id = nil
    ensure
      $game_temp.in_battle = false
    end
  end

  def hook_battle_commands(battle)
    # Hook the battle scene to capture player commands
    scene = battle.scene
    if scene.respond_to?(:pbCommandPhase)
      old_command_phase = scene.method(:pbCommandPhase)
      scene.define_singleton_method(:pbCommandPhase) do |*args|
        # Send command info to server when player makes a choice
        result = old_command_phase.call(*args)

        # Capture the command and send it
        if MP_BattleManager.in_mp_battle?
          idxBattler = args[0] || 0
          choice = battle.choices[idxBattler] rescue nil
          if choice
            MP_BattleManager.send_battle_command({
              action: choice[0],
              move: choice[1],
              target: choice[2]
            })
          end
        end
        result
      end
    end
  end

  def handle_battle_command(payload)
    room_id = payload["room_id"]
    turn = payload["turn"]
    your_command = payload["your_command"]
    opponent_command = payload["opponent_command"]

    return unless @in_mp_battle && @battle_room_id == room_id

    @command_queue << {
      turn: turn,
      opponent_command: opponent_command
    }

    echoln "[MP][Battle] Received commands for turn #{turn}"
  end

  def handle_battle_result(payload)
    room_id = payload["room_id"]
    winner = payload["winner"]
    winner_id = payload["winner_id"]
    forfeit = payload["forfeit"]
    message = payload["message"]

    @battle_result = payload
    @in_mp_battle = false
    @battle_room_id = nil

    if message
      pbMessage(message)
    elsif winner
      pbMessage(_INTL("Battle ended. {1} wins!", winner))
    end

    echoln "[MP][Battle] Battle ended. Winner: #{winner || 'none'}"
  end

  def in_mp_battle?
    @in_mp_battle
  end

  def battle_room_id
    @battle_room_id
  end

  def remote_opponent
    @remote_opponent
  end

  def get_next_command
    @command_queue.shift
  end
end

# Initialize when plugin loads
MP_BattleManager.init
