#===============================================================================
#  Pokemon Pathways Multiplayer - Main Game Server
#
#  Single-process TCP server with:
#    accept_loop thread  - accepts new connections non-blockingly
#    game_loop   thread  - main tick loop at TICK_RATE Hz (blocks)
#
#  FIXES vs original:
#   * HOST changed to 0.0.0.0 in config (was 127.0.0.1 - localhost only).
#   * update() now calls client.reset_tick_counter at start of each tick so
#     per-tick rate limiting in MP_Client works correctly.
#   * handle_handshake guard: if a name is already logged in, the new
#     connection is rejected to prevent session hijacking.
#   * Removed respond_to? guards on sub-services - they are always present.
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
  attr_reader :clients, :rooms, :overworld, :battles, :trades, :chat,
              :player_store, :running

  def initialize
    @server       = nil
    @running      = false
    @clients      = ClientManager.new(self)
    @rooms        = RoomManager.new(self)
    @overworld    = OverworldService.new(self)
    @battles      = BattleService.new(self)
    @trades       = TradeService.new(self)
    @chat         = ChatService.new(self)
    @player_store = PlayerStore.new
    @version_check= VersionCheck.new
    @tick_count   = 0
    @last_backup  = Time.now
  end

  # ─── Startup / shutdown ──────────────────────────────────────────────────────

  def start
    @server = TCPServer.new(MP_ServerConfig::HOST, MP_ServerConfig::PORT)
    @server.listen(MP_ServerConfig::MAX_CLIENTS)
    @running = true

    puts "=" * 60
    puts "  Pokemon Pathways Multiplayer Server"
    puts "  Listening on #{MP_ServerConfig::HOST}:#{MP_ServerConfig::PORT}"
    puts "  Tick rate    : #{MP_ServerConfig::TICK_RATE} Hz"
    puts "  Max clients  : #{MP_ServerConfig::MAX_CLIENTS}"
    puts "  Debug packets: #{MP_ServerConfig::DEBUG_PACKETS}"
    puts "=" * 60

    Thread.new { accept_loop }
    game_loop   # blocks until @running = false

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

  # ─── Accept loop (runs in dedicated thread) ──────────────────────────────────

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
        puts "[ERROR] Unexpected accept error: #{e.class}: #{e.message}"
        sleep(0.1)
      end
    end
  end

  # ─── Game loop (main thread) ─────────────────────────────────────────────────

  def game_loop
    tick_duration = MP_ServerConfig::TICK_DURATION
    while @running
      tick_start = Time.now

      @tick_count += 1
      update

      elapsed    = Time.now - tick_start
      sleep_time = tick_duration - elapsed
      sleep(sleep_time) if sleep_time > 0.0
    end
  end

  def update
    # Reset per-tick packet counters before processing incoming data
    @clients.each(&:reset_tick_counter)

    # Drain incoming socket data and dispatch packets
    @clients.each(&:receive_loop)

    # Service updates (position broadcasts, battle timeouts, trade timeouts)
    @overworld.update(@tick_count)
    @battles.update(@tick_count)
    @trades.update(@tick_count)

    # Timeout check: disconnect clients that stopped heartbeating
    @clients.check_timeouts

    # Periodic persistence
    if Time.now - @last_backup >= MP_ServerConfig::BACKUP_INTERVAL
      @clients.save_all
      @last_backup = Time.now
    end
  end

  # ─── Handshake handler ───────────────────────────────────────────────────────

  def handle_handshake(client, packet)
    name    = packet.payload["name"]
    version = packet.payload["version"]
    sprite  = packet.payload["sprite"]  || ""
    outfit  = packet.payload["outfit"]  || 0

    # Version check
    unless @version_check.valid?(version)
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        "message" => "Version mismatch. Server requires v#{@version_check.required_version}."
      }))
      client.disconnect
      return
    end

    # Name validation
    if name.nil? || name.strip.empty? || name.length > MP_ServerConfig::MAX_PLAYER_NAME_LEN
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        "message" => "Invalid player name (1-#{MP_ServerConfig::MAX_PLAYER_NAME_LEN} characters)"
      }))
      client.disconnect
      return
    end

    # Prevent duplicate logins (name already online)
    existing = @clients.find_by_name(name.strip)
    if existing && existing.id != client.id
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        "message" => "A player named '#{name}' is already logged in."
      }))
      client.disconnect
      return
    end

    client.player_name  = name.strip
    client.sprite_name  = sprite
    client.outfit       = outfit
    client.authenticated= true

    client.send_packet(MP_Packet.new(MP_PacketType::HANDSHAKE_ACK, {
      "client_id"   => client.id,
      "server_name" => "Pokemon Pathways Server",
      "max_players" => MP_ServerConfig::MAX_CLIENTS,
      "tick_rate"   => MP_ServerConfig::TICK_RATE
    }))

    # Restore saved appearance / position hint
    @player_store.load_player(client)

    puts "[CLIENT] #{client.player_name} (#{client.id[0, 8]}) authenticated (v#{version})"
  end

  # ─── Broadcast helpers ───────────────────────────────────────────────────────

  # Send to all clients on a specific map, optionally skipping one sender.
  def broadcast_to_map(map_id, packet, exclude_client = nil)
    @rooms.clients_on_map(map_id).each do |client|
      next if exclude_client && client.id == exclude_client.id
      client.send_packet(packet)
    end
  end

  # Global broadcast to all connected (authenticated) clients.
  def broadcast(packet)
    @clients.each { |c| c.send_packet(packet) }
  end

  # Direct send by client ID.
  def send_to_client(client_id, packet)
    client = @clients.find(client_id)
    client&.send_packet(packet)
  end

  def broadcast_system_message(message)
    broadcast(MP_Packet.new(MP_PacketType::CHAT_SYSTEM, { "message" => message }))
  end
end
