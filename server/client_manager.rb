#===============================================================================
#  Pokemon Pathways Multiplayer - Client Manager
#  PHASE 2 v4.0 — Route new packet ranges: 37-39 (2v2), 83 (rank), 90-94 (partner)
#===============================================================================

require_relative 'config'
require_relative 'packet'

class ClientManager
  include Enumerable

  def initialize(server)
    @server  = server
    @clients = {}
    @mutex   = Mutex.new
  end

  # ─── Enumerable / lookup ─────────────────────────────────────────────────────

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
      client.send_packet(MP_Packet.new(MP_PacketType::HEARTBEAT, {
        "ts" => packet.payload["ts"]
      }))

    when MP_PacketType::DISCONNECT
      client.disconnect

    else
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

  private

  def snapshot
    @mutex.synchronize { @clients.values.dup }
  end

  def route_to_service(client, packet)
    case packet.type
    when 10..18
      # Overworld: PLAYER_JOIN..PLAYER_ACTION, MAP_CHANGE, PLAYER_PARTY etc.
      @server.overworld.handle_packet(client, packet)

    when 30..36
      # Battle 1v1: REQUEST..FORFEIT
      @server.battles.handle_packet(client, packet)

    when 37..39
      # Battle 2v2: REQUEST, ACCEPT, DECLINE  (Phase 2)
      @server.battles.handle_packet(client, packet)

    when 50..57
      # Trade
      @server.trades.handle_packet(client, packet)

    when 70..72
      # Chat
      @server.chat.handle_packet(client, packet)

    when 80..82
      # Player data (overworld handles PLAYER_PARTY/PROFILE)
      @server.overworld.handle_packet(client, packet)

    when 83
      # Rank sync  (Phase 2)
      @server.rank_svc.handle_packet(client, packet)

    when 90..94
      # Partner system  (Phase 2)
      @server.partners.handle_packet(client, packet)

    else
      puts "[ROUTE] Unknown packet type #{packet.type} from #{client.player_name || client.id[0, 8]}"
    end
  end
end
