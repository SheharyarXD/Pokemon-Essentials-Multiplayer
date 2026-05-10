#===============================================================================
#  Pokemon Pathways Multiplayer - Client Manager
#  Manages all connected clients: auth, disconnect, timeout handling
#===============================================================================

require_relative 'config'
require_relative 'packet'

class ClientManager
  include Enumerable

  def initialize(server)
    @server = server
    @clients = {}
    @mutex = Mutex.new
  end

  def each(&block)
    @mutex.synchronize { @clients.values.each(&block) }
  end

  def handle_new_connection(socket)
    if count >= MP_ServerConfig::MAX_CLIENTS
      begin
        socket.close
      rescue
        nil
      end
      puts "[SERVER] Connection rejected: server full (#{MP_ServerConfig::MAX_CLIENTS})"
      return
    end

    client = MP_Client.new(socket, @server)
    @mutex.synchronize { @clients[client.id] = client }
    puts "[SERVER] New connection from #{socket.peeraddr[2]}:#{socket.peeraddr[1]} (ID: #{client.id})"
  end

  def find(client_id)
    @mutex.synchronize { @clients[client_id] }
  end

  def find_by_name(name)
    @mutex.synchronize { @clients.values.find { |c| c.player_name == name } }
  end

  def remove_client(client)
    @mutex.synchronize { @clients.delete(client.id) }
  end

  def route_packet(client, packet)
    case packet.type
    when MP_PacketType::HANDSHAKE
      client.handle_handshake(packet) if client.respond_to?(:handle_handshake)
      @server.handle_handshake(client, packet)
    when MP_PacketType::HEARTBEAT
      client.last_heartbeat = Time.now
      client.send_packet(MP_Packet.new(MP_PacketType::HEARTBEAT, {}))
    when MP_PacketType::DISCONNECT
      client.disconnect
    else
      if !client.authenticated && packet.type != MP_PacketType::HANDSHAKE
        client.send_packet(MP_Packet.new(MP_PacketType::ERROR, { message: "Not authenticated" }))
        return
      end
      route_to_service(client, packet)
    end
  end

  def route_to_service(client, packet)
    case packet.type
    when 10..19
      @server.overworld.handle_packet(client, packet)
    when 30..39
      @server.battles.handle_packet(client, packet) if @server.respond_to?(:battles)
    when 50..59
      @server.trades.handle_packet(client, packet) if @server.respond_to?(:trades)
    when 57  # TRADE_CANCEL handled by trade service too
      @server.trades.handle_packet(client, packet) if @server.respond_to?(:trades)
    when 70..79
      @server.chat.handle_packet(client, packet) if @server.respond_to?(:chat)
    when 80..89
      @server.overworld.handle_packet(client, packet)
    end
  end

  def check_timeouts
    timed_out = []
    @mutex.synchronize do
      @clients.each do |_id, client|
        timed_out << client if client.timed_out?
      end
    end
    timed_out.each do |client|
      puts "[TIMEOUT] #{client.player_name || client.id[0,8]} timed out"
      # Notify battle/trade services of disconnect before removing client
      @server.battles.handle_disconnect(client) if @server.respond_to?(:battles)
      @server.trades.handle_disconnect(client) if @server.respond_to?(:trades)
      client.disconnect
    end
  end

  def disconnect_all
    @mutex.synchronize do
      @clients.values.each(&:disconnect)
      @clients.clear
    end
  end

  def count
    @mutex.synchronize { @clients.length }
  end

  def authenticated_count
    @mutex.synchronize { @clients.values.count(&:authenticated) }
  end

  def save_all
    @mutex.synchronize do
      @clients.values.each do |client|
        next unless client.authenticated
        @server.player_store.save_player(client) if @server.respond_to?(:player_store)
      end
    end
  end
end
