#===============================================================================
#  Pokemon Pathways Multiplayer - Client Manager
#
#  Central registry of all connected MP_Client instances.
#
#  FIXES vs original:
#   * DEADLOCK: clients.each held @mutex; route_packet -> find() re-acquired it.
#     Resolved by snapshotting the client list before iterating.
#   * DEADLOCK in disconnect_all: held @mutex while calling disconnect() which
#     calls remove_client() -> @mutex.  Resolved by clearing first, disconnecting
#     outside the lock.
#   * Routing bug: TRADE_CANCEL (type 57) had duplicate 'when 57' clause after
#     'when 50..59'; dead code removed.
#   * Heartbeat echo now carries original client timestamp for RTT measurement.
#   * check_timeouts no longer calls handle_disconnect separately; MP_Client#disconnect
#     is idempotent and does all cleanup internally.
#===============================================================================

require_relative 'config'
require_relative 'packet'

class ClientManager
  include Enumerable

  def initialize(server)
    @server  = server
    @clients = {}      # id => MP_Client
    @mutex   = Mutex.new
  end

  # ─── Enumerable / lookup ─────────────────────────────────────────────────────

  # FIX: snapshot the values array before yielding so callers that trigger
  # remove_client inside the block don't cause mutex re-entry or mutation errors.
  def each(&block)
    snapshot.each(&block)
  end

  def find(client_id)
    @mutex.synchronize { @clients[client_id] }
  end

  def find_by_name(name)
    snapshot.find { |c| c.player_name == name }
  end

  def count
    @mutex.synchronize { @clients.length }
  end

  def authenticated_count
    snapshot.count(&:authenticated)
  end

  # ─── Connection lifecycle ────────────────────────────────────────────────────

  def handle_new_connection(socket)
    if count >= MP_ServerConfig::MAX_CLIENTS
      socket.close rescue nil
      puts "[SERVER] Connection rejected: server full (#{MP_ServerConfig::MAX_CLIENTS})"
      return
    end

    client = MP_Client.new(socket, @server)
    @mutex.synchronize { @clients[client.id] = client }
    peer = socket.peeraddr rescue ["?", "?", "?", "?"]
    puts "[SERVER] New connection from #{peer[3]}:#{peer[1]} (ID: #{client.id})"
  end

  def remove_client(client)
    @mutex.synchronize { @clients.delete(client.id) }
  end

  # FIX: Disconnect all without holding the mutex during the disconnect calls,
  # which prevents the deadlock (disconnect -> remove_client -> mutex).
  def disconnect_all
    all = @mutex.synchronize { @clients.values.dup.tap { @clients.clear } }
    all.each do |client|
      begin
        client.disconnect
      rescue => e
        puts "[SHUTDOWN] Error disconnecting #{client.id[0, 8]}: #{e.message}"
      end
    end
  end

  # ─── Packet routing ──────────────────────────────────────────────────────────

  def route_packet(client, packet)
    case packet.type
    when MP_PacketType::HANDSHAKE
      @server.handle_handshake(client, packet)

    when MP_PacketType::HEARTBEAT
      client.last_heartbeat = Time.now
      # FIX: Echo the client's own timestamp so it can measure round-trip time
      client.send_packet(MP_Packet.new(MP_PacketType::HEARTBEAT, {
        "ts" => packet.payload["ts"]
      }))

    when MP_PacketType::DISCONNECT
      client.disconnect

    else
      # All other packets require authentication
      unless client.authenticated
        client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
          "message" => "Not authenticated"
        }))
        return
      end
      route_to_service(client, packet)
    end
  end

  # ─── Timeout sweep ───────────────────────────────────────────────────────────

  # FIX: No longer calls handle_disconnect separately; MP_Client#disconnect
  # is idempotent and handles battle/trade/room cleanup internally.
  def check_timeouts
    snapshot.each do |client|
      next unless client.timed_out?
      puts "[TIMEOUT] #{client.player_name || client.id[0, 8]} timed out"
      client.disconnect
    end
  end

  # ─── Persistence helpers ─────────────────────────────────────────────────────

  def save_all
    snapshot.each do |client|
      next unless client.authenticated
      @server.player_store.save_player(client) rescue nil
    end
  end

  # ─── Private ─────────────────────────────────────────────────────────────────

  private

  # Returns a consistent snapshot without holding the mutex during iteration.
  def snapshot
    @mutex.synchronize { @clients.values.dup }
  end

  def route_to_service(client, packet)
    case packet.type
    when 10..18   # Overworld packets (PLAYER_JOIN..PLAYER_ACTION)
      @server.overworld.handle_packet(client, packet)
    when 30..36   # Battle packets
      @server.battles.handle_packet(client, packet)
    when 50..57   # Trade packets (TRADE_REQUEST..TRADE_CANCEL)
      # FIX: Original had duplicate 'when 57' after 'when 50..59'; removed dead branch.
      @server.trades.handle_packet(client, packet)
    when 70..72   # Chat packets
      @server.chat.handle_packet(client, packet)
    when 80..82   # Player data
      @server.overworld.handle_packet(client, packet)
    else
      puts "[ROUTE] Unknown packet type #{packet.type} from #{client.player_name || client.id[0, 8]}"
    end
  end
end
