#===============================================================================
#  Pokemon Pathways Multiplayer - Main Game Server
#  PHASE 2 v4.0 — Wire in RankService, PartnerService; read rank from handshake
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
require_relative 'services/rank_service'       # Phase 2
require_relative 'services/partner_service'    # Phase 2
require_relative 'persistence/player_store'
require_relative 'version_check'

class GameServer
  attr_reader :clients, :rooms, :overworld, :battles, :trades, :chat,
              :rank_svc, :partners,                                      # Phase 2
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
    @rank_svc     = RankService.new(self)      # Phase 2
    @partners     = PartnerService.new(self)   # Phase 2
    @player_store = PlayerStore.new
    @version_check= VersionCheck.new
    @tick_count   = 0
    @last_backup  = Time.now
  end

  def start
    @server = TCPServer.new(MP_ServerConfig::HOST, MP_ServerConfig::PORT)
    @server.listen(MP_ServerConfig::MAX_CLIENTS)
    @running = true

    puts "=" * 60
    puts "  Pokemon Pathways Multiplayer Server  [Phase 2]"
    puts "  Listening on #{MP_ServerConfig::HOST}:#{MP_ServerConfig::PORT}"
    puts "  Tick rate    : #{MP_ServerConfig::TICK_RATE} Hz"
    puts "  Max clients  : #{MP_ServerConfig::MAX_CLIENTS}"
    puts "  2v2 maps     : #{MP_ServerConfig::BATTLE_2V2_ALLOWED_MAPS.join(', ')}"
    puts "  Debug packets: #{MP_ServerConfig::DEBUG_PACKETS}"
    puts "=" * 60

    Thread.new { accept_loop }
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
        puts "[ERROR] Unexpected accept error: #{e.class}: #{e.message}"
        sleep(0.1)
      end
    end
  end

  def game_loop
    tick_duration = MP_ServerConfig::TICK_DURATION
    while @running
      if defined?($mp_server_shutdown_requested) && $mp_server_shutdown_requested
        puts "\n[SERVER] Shutdown flag set — stopping cleanly..."
        stop
        break
      end

      tick_start = Time.now
      @tick_count += 1
      update

      elapsed    = Time.now - tick_start
      sleep_time = tick_duration - elapsed
      sleep(sleep_time) if sleep_time > 0.0
    end
  end

  def update
    @clients.each(&:reset_tick_counter)
    @clients.each(&:receive_loop)
    @overworld.update(@tick_count)
    @battles.update(@tick_count)
    @trades.update(@tick_count)
    @partners.update(@tick_count)    # Phase 2 — expire stale partner requests
    @clients.check_timeouts

    if Time.now - @last_backup >= MP_ServerConfig::BACKUP_INTERVAL
      @clients.save_all
      @last_backup = Time.now
    end
  end

  # ─── Handshake ───────────────────────────────────────────────────────────────

  def handle_handshake(client, packet)
    name    = packet.payload["name"]
    version = packet.payload["version"]
    sprite  = packet.payload["sprite"]         || ""
    hue     = packet.payload["character_hue"]  || 0
    ttype   = packet.payload["trainer_type"]   || ""
    outfit  = packet.payload["outfit"]         || 0
    # Phase 2 — read rank from handshake payload
    raw_rank= packet.payload["rank"]           || "D"

    unless @version_check.valid?(version)
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        "message" => "Version mismatch. Server requires v#{@version_check.required_version}."
      }))
      client.disconnect
      return
    end

    if name.nil? || name.strip.empty? || name.length > MP_ServerConfig::MAX_PLAYER_NAME_LEN
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        "message" => "Invalid player name (1-#{MP_ServerConfig::MAX_PLAYER_NAME_LEN} characters)"
      }))
      client.disconnect
      return
    end

    existing = @clients.find_by_name(name.strip)
    if existing && existing.id != client.id
      client.send_packet(MP_Packet.new(MP_PacketType::ERROR, {
        "message" => "A player named '#{name}' is already logged in."
      }))
      client.disconnect
      return
    end

    client.player_name   = name.strip
    client.sprite_name   = sprite
    client.character_hue = hue.to_i
    client.trainer_type  = ttype.to_s
    client.outfit        = outfit.to_i
    # Phase 2 — sanitize rank before storing
    client.rank          = @rank_svc.sanitize_rank(raw_rank)
    client.rank_tier     = @rank_svc.tier_for(client.rank)
    client.authenticated = true

    client.send_packet(MP_Packet.new(MP_PacketType::HANDSHAKE_ACK, {
      "client_id"   => client.id,
      "server_name" => "Pokemon Pathways Server",
      "max_players" => MP_ServerConfig::MAX_CLIENTS,
      "tick_rate"   => MP_ServerConfig::TICK_RATE
    }))

    @player_store.load_player(client)

    puts "[CLIENT] #{client.player_name} (#{client.id[0, 8]}) authenticated " \
         "(v#{version}, rank: #{client.rank})"
  end

  # ─── Broadcast helpers ───────────────────────────────────────────────────────

  def broadcast_to_map(map_id, packet, exclude_client = nil)
    @rooms.clients_on_map(map_id).each do |client|
      next if exclude_client && client.id == exclude_client.id
      client.send_packet(packet)
    end
  end

  def broadcast(packet)
    @clients.each { |c| c.send_packet(packet) }
  end

  def send_to_client(client_id, packet)
    client = @clients.find(client_id)
    client&.send_packet(packet)
  end

  def broadcast_system_message(message)
    broadcast(MP_Packet.new(MP_PacketType::CHAT_SYSTEM, { "message" => message }))
  end
end
