#===============================================================================
#  Pokemon Pathways Multiplayer - Battle Service
#  Manages PvP BattleRoom sessions: request, accept/decline, turn-based relay
#  Includes battle timeout (60s per turn) and disconnect handling (auto-forfeit)
#===============================================================================

require_relative '../config'
require_relative '../packet'

class BattleRoom
  attr_reader :id, :player_a, :player_b, :state, :turn, :commands, :turn_deadline
  attr_accessor :winner

  STATE_REQUESTED = 0
  STATE_ACTIVE = 1
  STATE_ENDED = 2

  TURN_TIMEOUT = 60 # seconds per turn

  def initialize(player_a, player_b)
    @id = rand(36**8).to_s(36).upcase
    @player_a = player_a
    @player_b = player_b
    @state = STATE_REQUESTED
    @turn = 0
    @commands = {}  # client_id => command_data
    @winner = nil
    @turn_deadline = nil
  end

  def both_ready?
    @state == STATE_ACTIVE
  end

  def add_command(client_id, command_data)
    @commands[client_id] = command_data
  end

  def both_commands_received?
    @commands.key?(@player_a.id) && @commands.key?(@player_b.id)
  end

  def reset_turn
    @commands.clear
    @turn += 1
    @turn_deadline = Time.now + TURN_TIMEOUT
  end

  def timed_out?
    @turn_deadline && Time.now > @turn_deadline
  end

  def opponent_of(client_id)
    client_id == @player_a.id ? @player_b : @player_a
  end

  def to_h
    {
      id: @id,
      player_a: @player_a.player_name,
      player_b: @player_b&.player_name,
      state: @state,
      turn: @turn
    }
  end
end

class BattleService
  def initialize(server)
    @server = server
    @rooms = {}      # room_id => BattleRoom
    @client_rooms = {}  # client_id => room_id
    @mutex = Mutex.new
  end

  def update(tick_count)
    # Check for timed out battles
    timed_out_rooms = []
    @mutex.synchronize do
      @rooms.each do |room_id, room|
        next unless room.state == BattleRoom::STATE_ACTIVE
        if room.timed_out?
          timed_out_rooms << room
        end
      end
    end

    timed_out_rooms.each do |room|
      handle_turn_timeout(room)
    end
  end

  def handle_packet(client, packet)
    case packet.type
    when MP_PacketType::BATTLE_REQUEST
      handle_battle_request(client, packet)
    when MP_PacketType::BATTLE_ACCEPT
      handle_battle_accept(client, packet)
    when MP_PacketType::BATTLE_DECLINE
      handle_battle_decline(client, packet)
    when MP_PacketType::BATTLE_COMMAND
      handle_battle_command(client, packet)
    when MP_PacketType::BATTLE_FORFEIT
      handle_battle_forfeit(client, packet)
    end
  end

  def handle_battle_request(client, packet)
    target_name = packet.payload["target_name"]
    return unless target_name

    target = @server.clients.find_by_name(target_name)
    unless target
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "Player '#{target_name}' not found"
      }))
      return
    end

    if target.id == client.id
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "Cannot battle yourself"
      }))
      return
    end

    # Check if either is already in a battle
    if @client_rooms[client.id] || @client_rooms[target.id]
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "One or both players are already in a battle"
      }))
      return
    end

    room = BattleRoom.new(client, target)
    @mutex.synchronize do
      @rooms[room.id] = room
      @client_rooms[client.id] = room.id
    end

    # Send request to target
    target.send_packet(MP_Packet.new(MP_PacketType::BATTLE_REQUEST, {
      room_id: room.id,
      from_name: client.player_name,
      from_id: client.id
    }))

    puts "[BATTLE] #{client.player_name} requested battle with #{target.player_name}"
  end

  def handle_battle_accept(client, packet)
    room_id = packet.payload["room_id"]
    room = @mutex.synchronize { @rooms[room_id] }
    return unless room

    # Only player_b can accept
    if room.player_b.id != client.id
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "Invalid battle accept"
      }))
      return
    end

    room.instance_variable_set(:@state, BattleRoom::STATE_ACTIVE)
    room.instance_variable_set(:@turn_deadline, Time.now + BattleRoom::TURN_TIMEOUT)
    @client_rooms[client.id] = room.id

    # Notify both players
    start_packet = MP_Packet.new(MP_PacketType::BATTLE_START, {
      room_id: room.id,
      player_a: room.player_a.player_name,
      player_b: room.player_b.player_name,
      turn_timeout: BattleRoom::TURN_TIMEOUT
    })
    room.player_a.send_packet(start_packet)
    room.player_b.send_packet(start_packet)

    puts "[BATTLE] Battle #{room.id} started: #{room.player_a.player_name} vs #{room.player_b.player_name}"
  end

  def handle_battle_decline(client, packet)
    room_id = packet.payload["room_id"]
    room = @mutex.synchronize { @rooms[room_id] }
    return unless room

    cleanup_room(room)

    # Notify requester
    room.player_a.send_packet(MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      room_id: room_id,
      result: "declined",
      message: "#{client.player_name} declined the battle."
    }))

    puts "[BATTLE] #{client.player_name} declined battle from #{room.player_a.player_name}"
  end

  def handle_battle_command(client, packet)
    room = find_room_for_client(client)
    return unless room
    return unless room.state == BattleRoom::STATE_ACTIVE

    command_data = packet.payload["command"]
    return unless command_data

    room.add_command(client.id, command_data)

    # If both players submitted commands, relay them
    if room.both_commands_received?
      # Send commands to each player
      room.player_a.send_packet(MP_Packet.new(MP_PacketType::BATTLE_COMMAND, {
        room_id: room.id,
        turn: room.turn,
        your_command: room.commands[room.player_a.id],
        opponent_command: room.commands[room.player_b.id]
      }))

      room.player_b.send_packet(MP_Packet.new(MP_PacketType::BATTLE_COMMAND, {
        room_id: room.id,
        turn: room.turn,
        your_command: room.commands[room.player_b.id],
        opponent_command: room.commands[room.player_a.id]
      }))

      room.reset_turn
    end
  end

  def handle_battle_forfeit(client, packet)
    room = find_room_for_client(client)
    return unless room

    opponent = room.opponent_of(client.id)
    room.winner = opponent.id

    result_packet = MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      room_id: room.id,
      winner: opponent.player_name,
      winner_id: opponent.id,
      forfeit: true
    })
    room.player_a.send_packet(result_packet)
    room.player_b.send_packet(result_packet)

    cleanup_room(room)
    puts "[BATTLE] #{client.player_name} forfeited. #{opponent.player_name} wins."
  end

  def handle_turn_timeout(room)
    # Both players forfeit on timeout
    result_packet = MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      room_id: room.id,
      result: "timeout",
      message: "Turn timed out after #{BattleRoom::TURN_TIMEOUT} seconds."
    })
    room.player_a.send_packet(result_packet)
    room.player_b.send_packet(result_packet)

    cleanup_room(room)
    puts "[BATTLE] Battle #{room.id} timed out on turn #{room.turn}"
  end

  def handle_disconnect(client)
    room = find_room_for_client(client)
    return unless room

    opponent = room.opponent_of(client.id)
    return unless opponent

    room.winner = opponent.id
    result_packet = MP_Packet.new(MP_PacketType::BATTLE_RESULT, {
      room_id: room.id,
      winner: opponent.player_name,
      winner_id: opponent.id,
      forfeit: true,
      message: "#{client.player_name} disconnected."
    })
    opponent.send_packet(result_packet)

    cleanup_room(room)
    puts "[BATTLE] #{client.player_name} disconnected. #{opponent.player_name} wins by forfeit."
  end

  def find_room_for_client(client)
    room_id = @client_rooms[client.id]
    return nil unless room_id
    @mutex.synchronize { @rooms[room_id] }
  end

  def cleanup_room(room)
    @mutex.synchronize do
      @client_rooms.delete(room.player_a.id) if room.player_a
      @client_rooms.delete(room.player_b.id) if room.player_b
      @rooms.delete(room.id)
    end
  end
end
