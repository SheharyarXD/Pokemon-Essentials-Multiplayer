#===============================================================================
#  Pokemon Pathways Multiplayer - Main Game Server
#  TCPServer accept loop, game tick loop at 20Hz, position broadcasts
#===============================================================================

require 'socket'
require_relative 'config'
require_relative 'packet'
require_relative 'client'
require_relative 'client_manager'
require_relative 'room_manager'
require_relative 'services/overworld_service'
require_relative 'services/battle_service'
require_relative 'services/trade_service'
require_relative 'services/chat_service'
require_relative 'persistence/player_store'
require_relative 'version_check'

class GameServer
  attr_reader :clients, :rooms, :overworld, :battles, :trades, :chat, :player_store, :running

  def initialize
    @server = nil
    @running = false
    @clients = ClientManager.new(self)
    @rooms = RoomManager.new(self)
    @overworld = OverworldService.new(self)
    @battles = BattleService.new(self)
    @trades = TradeService.new(self)
    @chat = ChatService.new(self)
    @player_store = PlayerStore.new
    @version_check = VersionCheck.new
    @tick_count = 0
    @last_backup = Time.now
  end

  def start
    @server = TCPServer.new(MP_ServerConfig::HOST, MP_ServerConfig::PORT)
    @server.listen(MP_ServerConfig::MAX_CLIENTS)
    @running = true
    puts "=" * 60
    puts "  Pokemon Pathways Multiplayer Server"
    puts "  Listening on #{MP_ServerConfig::HOST}:#{MP_ServerConfig::PORT}"
    puts "  Tick rate: #{MP_ServerConfig::TICK_RATE} Hz"
    puts "  Max clients: #{MP_ServerConfig::MAX_CLIENTS}"
    puts "=" * 60

    # Start network accept thread
    Thread.new { accept_loop }

    # Start main game loop (blocks)
    game_loop
  rescue Errno::EADDRINUSE
    puts "[FATAL] Port #{MP_ServerConfig::PORT} is already in use!"
    exit 1
  rescue => e
    puts "[FATAL] Server error: #{e.class}: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end

  def stop
    @running = false
    @clients.disconnect_all
    @server.close if @server && !@server.closed?
    @player_store.final_backup
    puts "[SERVER] Server stopped"
  end

  def accept_loop
    while @running
      begin
        socket = @server.accept_nonblock
        @clients.handle_new_connection(socket)
      rescue IO::WaitReadable, Errno::EINTR
        sleep(0.001)
      rescue IOError => e
        break unless @running
        puts "[ERROR] Accept error: #{e.message}"
        sleep(0.1)
      rescue => e
        puts "[ERROR] Accept unexpected error: #{e.class}: #{e.message}"
        sleep(0.1)
      end
    end
  end

  def game_loop
    tick_duration = MP_ServerConfig::TICK_DURATION
    while @running
      start_time = Time.now

      @tick_count += 1
      update

      elapsed = Time.now - start_time
      sleep_time = tick_duration - elapsed
      sleep(sleep_time) if sleep_time > 0
    end
  end

  def update
    # Process incoming data from all clients
    @clients.each(&:receive_loop)

    # Update services
    @overworld.update(@tick_count)
    @battles.update(@tick_count)
    @trades.update(@tick_count)

    # Check for timed out clients
    @clients.check_timeouts

    # Periodic backup
    if Time.now - @last_backup >= MP_ServerConfig::BACKUP_INTERVAL
      @clients.save_all
      @last_backup = Time.now
    end
  end

  def handle_handshake(client, packet)
    name = packet.payload["name"]
    version = packet.payload["version"]
    sprite = packet.payload["sprite"] || ""
    outfit = packet.payload["outfit"] || 0

    # Validate version
    unless @version_check.valid?(version)
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "Version mismatch. Server requires #{@version_check.required_version}"
      }))
      client.disconnect
      return
    end

    # Validate name
    if name.nil? || name.empty? || name.length > 20
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        message: "Invalid player name"
      }))
      client.disconnect
      return
    end

    client.player_name = name
    client.sprite_name = sprite
    client.outfit = outfit
    client.authenticated = true

    # Send handshake ack
    client.send_packet(MP_Packet.new(MP_PacketType::HANDSHAKE_ACK, {
      client_id: client.id,
      server_name: "Pokemon Pathways Server",
      max_players: MP_ServerConfig::MAX_CLIENTS,
      tick_rate: MP_ServerConfig::TICK_RATE
    }))

    # Load saved player data if exists
    @player_store.load_player(client)

    puts "[CLIENT] #{client.player_name} (#{client.id}) authenticated (version: #{version})"
  end

  def broadcast_to_map(map_id, packet, exclude_client = nil)
    @rooms.clients_on_map(map_id).each do |client|
      next if client == exclude_client
      client.send_packet(packet)
    end
  end

  def broadcast(packet)
    @clients.each do |client|
      client.send_packet(packet)
    end
  end

  def send_to_client(client_id, packet)
    client = @clients.find(client_id)
    client.send_packet(packet) if client
  end

  def broadcast_system_message(message)
    broadcast(MP_Packet.new(MP_PacketType::CHAT_SYSTEM, {
      message: message
    }))
  end
end
