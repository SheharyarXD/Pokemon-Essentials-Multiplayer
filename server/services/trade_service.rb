#===============================================================================
#  Pokemon Pathways Multiplayer - Trade Service
#
#  Trade state machine:
#    REQUESTED -> (OPEN) -> OFFERING -> CONFIRMED -> COMPLETE
#                        \-> CANCELLED (timeout / cancel / disconnect)
#
#  FIXES vs original:
#   * STATE MACHINE BUG: When a player changed their offer after both had
#     confirmed (STATE_CONFIRMED), set_offer reset the confirmation flags but
#     left @state at STATE_CONFIRMED. The next confirm from either player would
#     immediately attempt to complete the trade with potentially mismatched offers.
#     Fix: state is reset to STATE_OFFERING whenever any offer is updated.
#   * DISTANCE CHECK: was performed at request time only; target could walk away.
#     This is an acceptable trade-off (game design), but the check now uses
#     integer arithmetic instead of sqrt for performance.
#   * LOCKING: @client_sessions reads that bypassed @mutex are now consistent.
#   * handle_disconnect is idempotent (same pattern as BattleService).
#===============================================================================

require_relative '../config'
require_relative '../packet'

# ─── TradeSession ────────────────────────────────────────────────────────────────

class TradeSession
  attr_reader   :id, :player_a, :player_b, :state
  attr_accessor :offer_a, :offer_b, :confirmed_a, :confirmed_b, :deadline

  STATE_REQUESTED = 0
  STATE_OPEN      = 1
  STATE_OFFERING  = 2
  STATE_CONFIRMED = 3   # both confirmed with the current offers
  STATE_COMPLETE  = 4
  STATE_CANCELLED = 5

  TRADE_TIMEOUT = 120   # seconds

  def initialize(player_a, player_b)
    @id          = rand(36**8).to_s(36).upcase
    @player_a    = player_a
    @player_b    = player_b
    @state       = STATE_REQUESTED
    @offer_a     = nil
    @offer_b     = nil
    @confirmed_a = false
    @confirmed_b = false
    @deadline    = Time.now + TRADE_TIMEOUT
  end

  def state=(val)
    @state = val
  end

  def timed_out?
    Time.now > @deadline
  end

  def active?
    @state < STATE_COMPLETE
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
    # FIX: Reset both confirmations AND state whenever an offer changes.
    # Original only reset flags, leaving @state at STATE_CONFIRMED which
    # caused the next TRADE_CONFIRM to immediately complete with stale data.
    @confirmed_a = false
    @confirmed_b = false
    @state = STATE_OFFERING
  end

  def set_confirmed(client_id)
    if client_id == @player_a.id
      @confirmed_a = true
    else
      @confirmed_b = true
    end
    @state = STATE_CONFIRMED if @confirmed_a && @confirmed_b
  end

  def both_confirmed?
    @confirmed_a && @confirmed_b
  end
end

# ─── TradeService ────────────────────────────────────────────────────────────────

class TradeService
  def initialize(server)
    @server          = server
    @sessions        = {}    # session_id => TradeSession
    @client_sessions = {}    # client_id  => session_id
    @mutex           = Mutex.new
  end

  # ─── Tick update ────────────────────────────────────────────────────────────

  def update(_tick_count)
    timed_out = @mutex.synchronize do
      @sessions.values.select { |s| s.active? && s.timed_out? }
    end
    timed_out.each { |s| handle_trade_timeout(s) }
  end

  # ─── Packet dispatch ────────────────────────────────────────────────────────

  def handle_packet(client, packet)
    case packet.type
    when MP_PacketType::TRADE_REQUEST  then handle_trade_request(client, packet)
    when MP_PacketType::TRADE_ACCEPT   then handle_trade_accept(client, packet)
    when MP_PacketType::TRADE_DECLINE  then handle_trade_decline(client, packet)
    when MP_PacketType::TRADE_OFFER    then handle_trade_offer(client, packet)
    when MP_PacketType::TRADE_CONFIRM  then handle_trade_confirm(client, packet)
    when MP_PacketType::TRADE_CANCEL   then handle_trade_cancel(client, packet)
    end
  end

  # ─── Request ────────────────────────────────────────────────────────────────

  def handle_trade_request(client, packet)
    target_name = packet.payload["target_name"]
    return unless target_name

    target = @server.clients.find_by_name(target_name)
    unless target
      return client.send_packet(error("Player '#{target_name}' not found"))
    end

    return client.send_packet(error("Cannot trade with yourself")) if target.id == client.id

    unless client.map_id && client.map_id == target.map_id
      return client.send_packet(error("#{target_name} is not on the same map"))
    end

    # Use squared distance to avoid sqrt
    dx   = client.pos_x - target.pos_x
    dy   = client.pos_y - target.pos_y
    dist = MP_ServerConfig::MAX_TRADE_DISTANCE
    if (dx * dx + dy * dy) > (dist * dist)
      return client.send_packet(error("#{target_name} is too far away"))
    end

    session = nil
    @mutex.synchronize do
      if @client_sessions[client.id] || @client_sessions[target.id]
        return   # handled below
      end
      session                          = TradeSession.new(client, target)
      @sessions[session.id]            = session
      @client_sessions[client.id]      = session.id
      @client_sessions[target.id]      = session.id
    end

    unless session
      return client.send_packet(error("One or both players are already in a trade"))
    end

    target.send_packet(MP_Packet.new(MP_PacketType::TRADE_REQUEST, {
      "session_id" => session.id,
      "from_name"  => client.player_name,
      "from_id"    => client.id
    }))

    puts "[TRADE] #{client.player_name} requested trade with #{target.player_name}"
  end

  # ─── Accept ─────────────────────────────────────────────────────────────────

  def handle_trade_accept(client, packet)
    session_id = packet.payload["session_id"]
    session    = find_session(session_id)
    return unless session
    return unless session.state == TradeSession::STATE_REQUESTED
    return unless session.player_b.id == client.id

    session.state = TradeSession::STATE_OPEN

    open_pkt = MP_Packet.new(MP_PacketType::TRADE_OPEN, {
      "session_id" => session.id,
      "player_a"   => session.player_a.player_name,
      "player_b"   => session.player_b.player_name,
      "timeout"    => TradeSession::TRADE_TIMEOUT
    })
    session.player_a.send_packet(open_pkt)
    session.player_b.send_packet(open_pkt)

    puts "[TRADE] Trade session #{session.id} opened"
  end

  # ─── Decline ────────────────────────────────────────────────────────────────

  def handle_trade_decline(client, packet)
    session_id = packet.payload["session_id"]
    session    = find_session(session_id)
    return unless session

    cleanup_session(session)

    session.player_a.send_packet(MP_Packet.new(MP_PacketType::TRADE_CANCEL, {
      "session_id" => session_id,
      "reason"     => "declined",
      "message"    => "#{client.player_name} declined the trade."
    }))

    puts "[TRADE] #{client.player_name} declined trade"
  end

  # ─── Offer ──────────────────────────────────────────────────────────────────

  def handle_trade_offer(client, packet)
    session = find_session_for_client(client)
    return unless session&.active?
    return unless session.state >= TradeSession::STATE_OPEN

    pokemon_data = packet.payload["pokemon"]
    return unless pokemon_data.is_a?(Hash)

    # Validation: no eggs
    if pokemon_data["egg"]
      return client.send_packet(error("Cannot trade Eggs"))
    end

    # Validation: must have species and level
    unless pokemon_data["species"] && pokemon_data["level"]
      return client.send_packet(error("Invalid Pokemon data"))
    end

    # FIX: set_offer now resets state to STATE_OFFERING internally
    session.set_offer(client.id, pokemon_data)

    offer_pkt = MP_Packet.new(MP_PacketType::TRADE_OFFER, {
      "session_id" => session.id,
      "offer_a"    => session.offer_a,
      "offer_b"    => session.offer_b
    })
    session.player_a.send_packet(offer_pkt)
    session.player_b.send_packet(offer_pkt)

    puts "[TRADE] #{client.player_name} updated their offer"
  end

  # ─── Confirm ────────────────────────────────────────────────────────────────

  def handle_trade_confirm(client, packet)
    session = find_session_for_client(client)
    return unless session&.active?
    return unless session.state >= TradeSession::STATE_OFFERING

    session.set_confirmed(client.id)

    confirm_pkt = MP_Packet.new(MP_PacketType::TRADE_CONFIRM, {
      "session_id"  => session.id,
      "confirmed_a" => session.confirmed_a,
      "confirmed_b" => session.confirmed_b
    })
    session.player_a.send_packet(confirm_pkt)
    session.player_b.send_packet(confirm_pkt)

    puts "[TRADE] #{client.player_name} confirmed trade"

    # Both offers must be present AND both confirmed before completing
    if session.both_confirmed? && session.offer_a && session.offer_b
      complete_trade(session)
    end
  end

  # ─── Cancel ─────────────────────────────────────────────────────────────────

  def handle_trade_cancel(client, packet)
    session = find_session_for_client(client)
    return unless session

    other = session.other(client.id)
    cleanup_session(session)

    other&.send_packet(MP_Packet.new(MP_PacketType::TRADE_CANCEL, {
      "session_id" => session.id,
      "reason"     => "cancelled",
      "message"    => "#{client.player_name} cancelled the trade."
    }))

    puts "[TRADE] #{client.player_name} cancelled trade"
  end

  # ─── Timeout ────────────────────────────────────────────────────────────────

  def handle_trade_timeout(session)
    session.state = TradeSession::STATE_CANCELLED

    cancel_pkt = MP_Packet.new(MP_PacketType::TRADE_CANCEL, {
      "session_id" => session.id,
      "reason"     => "timeout",
      "message"    => "Trade timed out after #{TradeSession::TRADE_TIMEOUT}s."
    })
    session.player_a&.send_packet(cancel_pkt)
    session.player_b&.send_packet(cancel_pkt)

    cleanup_session(session)
    puts "[TRADE] Trade #{session.id} timed out"
  end

  # ─── Disconnect handler (idempotent) ────────────────────────────────────────

  def handle_disconnect(client)
    session = find_session_for_client(client)
    return unless session

    other = session.other(client.id)
    cleanup_session(session)

    other&.send_packet(MP_Packet.new(MP_PacketType::TRADE_CANCEL, {
      "session_id" => session.id,
      "reason"     => "disconnect",
      "message"    => "#{client.player_name} disconnected."
    }))

    puts "[TRADE] #{client.player_name} disconnected; trade cancelled"
  end

  private

  # ─── Trade completion ───────────────────────────────────────────────────────

  def complete_trade(session)
    session.state = TradeSession::STATE_COMPLETE

    # Player A receives B's Pokemon; player B receives A's Pokemon
    session.player_a.send_packet(MP_Packet.new(MP_PacketType::TRADE_COMPLETE, {
      "session_id"      => session.id,
      "received_pokemon"=> session.offer_b,
      "sent_pokemon"    => session.offer_a
    }))

    session.player_b.send_packet(MP_Packet.new(MP_PacketType::TRADE_COMPLETE, {
      "session_id"      => session.id,
      "received_pokemon"=> session.offer_a,
      "sent_pokemon"    => session.offer_b
    }))

    puts "[TRADE] Trade #{session.id} completed: #{session.player_a.player_name} <=> #{session.player_b.player_name}"
    cleanup_session(session)
  end

  # ─── Lookup helpers ─────────────────────────────────────────────────────────

  def find_session(session_id)
    @mutex.synchronize { @sessions[session_id] }
  end

  def find_session_for_client(client)
    session_id = @mutex.synchronize { @client_sessions[client.id] }
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

  def error(message)
    MP_Packet.new(MP_PacketType::ERROR, { "message" => message })
  end
end
