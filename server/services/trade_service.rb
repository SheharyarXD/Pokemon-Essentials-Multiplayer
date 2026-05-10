#===============================================================================
#  Pokemon Pathways Multiplayer - Trade Service
#  Manages TradeSession: request, accept/decline, offer, confirm, complete
#  Includes trade timeout (120s) and validation (no eggs, must be in party)
#===============================================================================

require_relative '../config'
require_relative '../packet'

class TradeSession
  attr_reader :id, :player_a, :player_b, :state
  attr_accessor :offer_a, :offer_b, :confirmed_a, :confirmed_b, :deadline

  STATE_REQUESTED = 0
  STATE_OPEN = 1
  STATE_OFFERING = 2
  STATE_CONFIRMED = 3
  STATE_COMPLETE = 4
  STATE_CANCELLED = 5

  TRADE_TIMEOUT = 120 # seconds

  def initialize(player_a, player_b)
    @id = rand(36**8).to_s(36).upcase
    @player_a = player_a
    @player_b = player_b
    @state = STATE_REQUESTED
    @offer_a = nil
    @offer_b = nil
    @confirmed_a = false
    @confirmed_b = false
    @deadline = Time.now + TRADE_TIMEOUT
  end

  def timed_out?
    Time.now > @deadline
  end

  def other(client_id)
    client_id == @player_a.id ? @player_b : @player_a
  end

  def set_offer(client_id, pokemon_data)
    if client_id == @player_a.id
      @offer_a = pokemon_data
    else
      @offer_b = pokemon_data
    end
  end

  def set_confirmed(client_id)
    if client_id == @player_a.id
      @confirmed_a = true
    else
      @confirmed_b = true
    end
  end

  def both_confirmed?
    @confirmed_a && @confirmed_b
  end
end

class TradeService
  def initialize(server)
    @server = server
    @sessions = {}       # session_id => TradeSession
    @client_sessions = {} # client_id => session_id
    @mutex = Mutex.new
  end

  def update(tick_count)
    timed_out = []
    @mutex.synchronize do
      @sessions.each do |session_id, session|
        if session.state < TradeSession::STATE_COMPLETE && session.timed_out?
          timed_out << session
        end
      end
    end

    timed_out.each { |session| handle_trade_timeout(session) }
  end

  def handle_packet(client, packet)
    case packet.type
    when MP_PacketType::TRADE_REQUEST
      handle_trade_request(client, packet)
    when MP_PacketType::TRADE_ACCEPT
      handle_trade_accept(client, packet)
    when MP_PacketType::TRADE_DECLINE
      handle_trade_decline(client, packet)
    when MP_PacketType::TRADE_OFFER
      handle_trade_offer(client, packet)
    when MP_PacketType::TRADE_CONFIRM
      handle_trade_confirm(client, packet)
    when MP_PacketType::TRADE_CANCEL
      handle_trade_cancel(client, packet)
    end
  end

  def handle_trade_request(client, packet)
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
        message: "Cannot trade with yourself"
      }))
      return
    end

    # Check distance
    if client.map_id != target.map_id
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "#{target_name} is not on the same map"
      }))
      return
    end

    dx = client.pos_x - target.pos_x
    dy = client.pos_y - target.pos_y
    dist = Math.sqrt(dx * dx + dy * dy)
    if dist > 3
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "#{target_name} is too far away"
      }))
      return
    end

    # Check if either is already in a trade
    if @client_sessions[client.id] || @client_sessions[target.id]
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "One or both players are already in a trade"
      }))
      return
    end

    session = TradeSession.new(client, target)
    @mutex.synchronize do
      @sessions[session.id] = session
      @client_sessions[client.id] = session.id
    end

    target.send_packet(MP_Packet.new(MP_PacketType::TRADE_REQUEST, {
      session_id: session.id,
      from_name: client.player_name,
      from_id: client.id
    }))

    puts "[TRADE] #{client.player_name} requested trade with #{target.player_name}"
  end

  def handle_trade_accept(client, packet)
    session_id = packet.payload["session_id"]
    session = @mutex.synchronize { @sessions[session_id] }
    return unless session
    return if session.state != TradeSession::STATE_REQUESTED

    # Only player_b can accept
    if session.player_b.id != client.id
      return
    end

    session.instance_variable_set(:@state, TradeSession::STATE_OPEN)
    @client_sessions[client.id] = session.id

    # Notify both players
    open_packet = MP_Packet.new(MP_PacketType::TRADE_OPEN, {
      session_id: session.id,
      player_a: session.player_a.player_name,
      player_b: session.player_b.player_name,
      timeout: TradeSession::TRADE_TIMEOUT
    })
    session.player_a.send_packet(open_packet)
    session.player_b.send_packet(open_packet)

    puts "[TRADE] Trade session #{session.id} opened"
  end

  def handle_trade_decline(client, packet)
    session_id = packet.payload["session_id"]
    session = @mutex.synchronize { @sessions[session_id] }
    return unless session

    cleanup_session(session)
    session.player_a.send_packet(MP_Packet.new(MP_PacketType::TRADE_CANCEL, {
      session_id: session_id,
      reason: "declined",
      message: "#{client.player_name} declined the trade."
    }))

    puts "[TRADE] #{client.player_name} declined trade"
  end

  def handle_trade_offer(client, packet)
    session = find_session_for_client(client)
    return unless session
    return unless session.state >= TradeSession::STATE_OPEN

    pokemon_data = packet.payload["pokemon"]
    return unless pokemon_data

    # Validate: check if pokemon is an egg
    if pokemon_data["egg"] || pokemon_data[:egg]
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "Cannot trade Eggs"
      }))
      return
    end

    # Validate: check basic structure
    species = pokemon_data["species"] || pokemon_data[:species]
    level = pokemon_data["level"] || pokemon_data[:level]
    unless species && level
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "Invalid Pokemon data"
      }))
      return
    end

    session.set_offer(client.id, pokemon_data)

    # Reset confirmations when offer changes
    session.confirmed_a = false
    session.confirmed_b = false

    if session.state == TradeSession::STATE_OPEN
      session.instance_variable_set(:@state, TradeSession::STATE_OFFERING)
    end

    # Notify both players of offers
    offer_packet = MP_Packet.new(MP_PacketType::TRADE_OFFER, {
      session_id: session.id,
      offer_a: session.offer_a,
      offer_b: session.offer_b
    })
    session.player_a.send_packet(offer_packet)
    session.player_b.send_packet(offer_packet)

    puts "[TRADE] #{client.player_name} updated their offer"
  end

  def handle_trade_confirm(client, packet)
    session = find_session_for_client(client)
    return unless session
    return unless session.state >= TradeSession::STATE_OFFERING

    session.set_confirmed(client.id)

    # Notify both players of confirmation status
    confirm_packet = MP_Packet.new(MP_PacketType::TRADE_CONFIRM, {
      session_id: session.id,
      confirmed_a: session.confirmed_a,
      confirmed_b: session.confirmed_b
    })
    session.player_a.send_packet(confirm_packet)
    session.player_b.send_packet(confirm_packet)

    puts "[TRADE] #{client.player_name} confirmed trade"

    # If both confirmed, complete the trade
    if session.both_confirmed? && session.offer_a && session.offer_b
      complete_trade(session)
    end
  end

  def complete_trade(session)
    session.instance_variable_set(:@state, TradeSession::STATE_COMPLETE)

    # Notify both players of completion with swapped Pokemon
    complete_packet = MP_Packet.new(MP_PacketType::TRADE_COMPLETE, {
      session_id: session.id,
      received_pokemon: session.offer_a,  # B receives A's Pokemon
      sent_pokemon: session.offer_b       # B sent their Pokemon
    })
    session.player_b.send_packet(complete_packet)

    # Reverse for player A
    complete_packet_a = MP_Packet.new(MP_PacketType::TRADE_COMPLETE, {
      session_id: session.id,
      received_pokemon: session.offer_b,  # A receives B's Pokemon
      sent_pokemon: session.offer_a       # A sent their Pokemon
    })
    session.player_a.send_packet(complete_packet_a)

    puts "[TRADE] Trade #{session.id} completed: #{session.player_a.player_name} <=> #{session.player_b.player_name}"

    cleanup_session(session)
  end

  def handle_trade_cancel(client, packet)
    session = find_session_for_client(client)
    return unless session

    other = session.other(client.id)
    cleanup_session(session)

    if other
      other.send_packet(MP_Packet.new(MP_PacketType::TRADE_CANCEL, {
        session_id: session.id,
        reason: "cancelled",
        message: "#{client.player_name} cancelled the trade."
      }))
    end

    puts "[TRADE] #{client.player_name} cancelled trade"
  end

  def handle_trade_timeout(session)
    session.instance_variable_set(:@state, TradeSession::STATE_CANCELLED)

    cancel_packet = MP_Packet.new(MP_PacketType::TRADE_CANCEL, {
      session_id: session.id,
      reason: "timeout",
      message: "Trade timed out after #{TradeSession::TRADE_TIMEOUT} seconds."
    })
    session.player_a.send_packet(cancel_packet) if session.player_a
    session.player_b.send_packet(cancel_packet) if session.player_b

    cleanup_session(session)
    puts "[TRADE] Trade #{session.id} timed out"
  end

  def handle_disconnect(client)
    session = find_session_for_client(client)
    return unless session

    other = session.other(client.id)
    cleanup_session(session)

    if other
      other.send_packet(MP_Packet.new(MP_PacketType::TRADE_CANCEL, {
        session_id: session.id,
        reason: "disconnect",
        message: "#{client.player_name} disconnected."
      }))
    end

    puts "[TRADE] #{client.player_name} disconnected, trade cancelled"
  end

  def find_session_for_client(client)
    session_id = @client_sessions[client.id]
    return nil unless session_id
    @mutex.synchronize { @sessions[session_id] }
  end

  def cleanup_session(session)
    @mutex.synchronize do
      @client_sessions.delete(session.player_a.id) if session.player_a
      @client_sessions.delete(session.player_b.id) if session.player_b
      @sessions.delete(session.id)
    end
  end
end
