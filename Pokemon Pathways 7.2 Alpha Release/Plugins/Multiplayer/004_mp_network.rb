#===============================================================================
#  Pokemon Pathways Multiplayer Client - Network Manager
<<<<<<< HEAD
#  REMOTE SKIN SYNC v3.1a — MKXP-Z Debug Mode Fix: removed require "json"
#
#  MKXP-Z and RPG Maker XP already have JSON available natively.
#  Calling require "json" in debug mode (PluginManager eval context)
#  causes LoadError because the gem path isn't in $LOAD_PATH.
=======
#  STABILIZED v2.1 — Dedicated heartbeat thread, session singleton bootstrap
#
#  Architecture:
#    * Background net_thread handles TCP read + handshake + heartbeat echo
#    * Dedicated heartbeat_thread sends outbound heartbeats every 5s
#    * Main-thread tick() drains outbound queue + dispatches inbound events
#    * All graphics/UI code runs on main thread via event_queue
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
#===============================================================================

begin
  require "socket"
rescue LoadError => e
  raise e unless defined?(TCPSocket) && defined?(Socket)
end
<<<<<<< HEAD
# REMOVED: require "json" — MKXP-Z has JSON built-in, require crashes debug mode
=======
require "json"
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095

module MP_NetworkManager

  STATE_DISCONNECTED = 0
  STATE_CONNECTING   = 1
  STATE_HANDSHAKING  = 2
  STATE_CONNECTED    = 3

  @socket              = nil
  @net_thread          = nil
  @heartbeat_thread    = nil
  @running             = false
  @stop_requested      = false
  @state               = STATE_DISCONNECTED
  @client_id           = nil
  @reconnect_attempts  = 0
  @reconnect_delay     = 1.0

  @receive_buffer      = "".b
  @send_queue          = []
  @event_queue         = []
  @mutex               = Mutex.new

  @packet_handlers     = {}
  @connect_handlers    = []
  @disconnect_handlers = []
  @error_handlers      = []

  @queue_overflow_count = 0
  @last_heartbeat_sent  = 0
  @last_heartbeat_rcvd  = 0

<<<<<<< HEAD
=======
  # ── Public state ────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def connected?;  @state == STATE_CONNECTED;  end
  def connecting?; @state == STATE_CONNECTING || @state == STATE_HANDSHAKING; end
  def client_id;   @client_id;   end
  def state;       @state;       end

  def state_name
    %w[DISCONNECTED CONNECTING HANDSHAKING CONNECTED][@state] || "UNKNOWN"
  end

<<<<<<< HEAD
=======
  # ── Lifecycle ───────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def start
    return if @running
    @running             = true
    @stop_requested      = false
    @state               = STATE_DISCONNECTED
    @reconnect_attempts  = 0
    @reconnect_delay     = MP_ClientConfig::RECONNECT_BASE_INTERVAL
    @send_queue.clear
    @event_queue.clear
    @receive_buffer      = "".b
    @queue_overflow_count= 0
    @last_heartbeat_sent = 0
    @last_heartbeat_rcvd = Time.now.to_f
    mp_log("NET: start — background threads launching") if defined?(mp_log)
    @net_thread = Thread.new { net_loop }
    @heartbeat_thread = Thread.new { heartbeat_loop }
  end

  def stop
    @stop_requested = true
    @running = false
    close_socket
    @net_thread&.kill
    @net_thread = nil
    @heartbeat_thread&.kill
    @heartbeat_thread = nil
    @state = STATE_DISCONNECTED
    mp_log("NET: stopped") if defined?(mp_log)
  end

<<<<<<< HEAD
=======
  # ── Game-loop side (called every frame from Scene_Map#update) ─────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def tick
    process_outgoing
    dispatch_events
  end

<<<<<<< HEAD
=======
  # Push an outbound packet (safe to call from any thread).
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def send_packet(type, payload = {})
    return unless @state == STATE_CONNECTED
    @mutex.synchronize do
      if @send_queue.length > 500
        @send_queue.shift(250)
        @queue_overflow_count += 1
        mp_log("NET: send queue overflow ##{@queue_overflow_count}") if defined?(mp_log)
      end
      @send_queue << MP_Packet.new(type, payload)
    end
  end

<<<<<<< HEAD
=======
  # ── Callback registration ─────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def on_packet(type, &block)
    @packet_handlers[type] ||= []
    @packet_handlers[type] << block
  end

  def on_connect(&block);    @connect_handlers    << block; end
  def on_disconnect(&block); @disconnect_handlers << block; end
  def on_error(&block);      @error_handlers      << block; end

  def remove_callbacks
    @packet_handlers.clear
    @connect_handlers.clear
    @disconnect_handlers.clear
    @error_handlers.clear
  end

<<<<<<< HEAD
=======
  # ── Party helper ────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def send_party_data
    return unless $Trainer&.party&.first
    first = $Trainer.party[0]
    send_packet(MP_PacketType::PLAYER_PARTY, {
      "party" => [{ "species" => first.species.to_s, "level" => first.level, "name" => first.name }]
    })
  end

<<<<<<< HEAD
  def send_sprite_update
    return unless $game_player && MP_NetworkManager.connected?
    sprite = $game_player.character_name.to_s rescue ""
    hue = $game_player.character_hue.to_i rescue 0
    outfit = (defined?($Trainer) && $Trainer) ? ($Trainer.outfit.to_i rescue 0) : 0
    trainer_type = (defined?($Trainer) && $Trainer) ? ($Trainer.trainer_type.to_s rescue "") : ""

    mp_log("SYNC: sending sprite '#{sprite}' (hue:#{hue}, outfit:#{outfit}, type:#{trainer_type})") if defined?(mp_log)

    send_packet(MP_PacketType::PLAYER_SPRITE, {
      "sprite"        => sprite,
      "character_hue" => hue,
      "trainer_type"  => trainer_type,
      "outfit"        => outfit
    })
  end
=======
  # ── Private: background network thread ─────────────────────────────────────
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095

  private

  def heartbeat_loop
    mp_log("NET: heartbeat thread started") if defined?(mp_log)
    loop do
      break if @stop_requested
      begin
        if @state == STATE_CONNECTED && @socket && !@socket.closed?
          now = Time.now.to_f
          if now - @last_heartbeat_sent >= MP_ClientConfig::HEARTBEAT_INTERVAL
            send_raw(MP_Packet.new(MP_PacketType::HEARTBEAT, { "ts" => now.to_i }))
            @last_heartbeat_sent = now
            mp_log("NET: heartbeat sent ts=#{now.to_i}") if MP_ClientConfig::DEBUG_PACKETS && defined?(mp_log)
          end
<<<<<<< HEAD
=======
          # Detect dead connection if no heartbeat received in timeout
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
          if now - @last_heartbeat_rcvd > MP_ClientConfig::HEARTBEAT_TIMEOUT
            mp_log("NET: heartbeat timeout — connection dead") if defined?(mp_log)
            on_disconnected("Heartbeat timeout")
          end
        end
      rescue => e
        mp_log("NET: heartbeat_loop error #{e.class}: #{e.message}") if defined?(mp_log)
      end
      sleep 1.0
    end
    mp_log("NET: heartbeat thread exiting") if defined?(mp_log)
  end

  def net_loop
    mp_log("NET: net_loop thread started") if defined?(mp_log)
    while @running
      begin
        case @state
        when STATE_DISCONNECTED
          if MP_ClientConfig::RECONNECT_ENABLED
            attempt_connect
          else
            sleep(1)
          end
        when STATE_HANDSHAKING, STATE_CONNECTED
          receive_data
          sleep(0.001)
        when STATE_CONNECTING
          sleep(0.01)
        end
      rescue => e
        mp_log("NET: net_loop error #{e.class}: #{e.message}") if defined?(mp_log)
        sleep(1)
      end
    end
    mp_log("NET: net_loop thread exiting") if defined?(mp_log)
  end

<<<<<<< HEAD
=======
  # ── Connect / handshake ────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def attempt_connect
    max = MP_ClientConfig::RECONNECT_MAX_ATTEMPTS
    if max > 0 && @reconnect_attempts >= max
      mp_log("NET: max reconnect attempts reached") if defined?(mp_log)
      @running = false
      return
    end

    @reconnect_attempts += 1
    @state = STATE_CONNECTING
    @receive_buffer = "".b
    @send_queue.clear
    @event_queue.clear
    mp_log("NET: connecting (attempt #{@reconnect_attempts})") if defined?(mp_log)

    begin
      @socket = TCPSocket.new(MP_ClientConfig::SERVER_IP, MP_ClientConfig::SERVER_PORT)
      @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      deadline = Time.now + 10
      sleep(0.1) until $Trainer || Time.now > deadline

      unless $Trainer
        mp_log("NET: $Trainer nil after 10s; aborting handshake") if defined?(mp_log)
        close_socket
        @state = STATE_DISCONNECTED
        sleep(@reconnect_delay)
        return
      end

      @state = STATE_HANDSHAKING
      send_raw(build_handshake_packet)

    rescue Errno::ECONNREFUSED
      mp_log("NET: connection refused") if defined?(mp_log)
      push_error("Cannot reach the server. Is it running?")
      backoff_and_reset

    rescue Errno::ETIMEDOUT, Errno::ENETUNREACH, SocketError => e
      mp_log("NET: connect failed #{e.class}") if defined?(mp_log)
      push_error("Connection failed: #{e.message}")
      backoff_and_reset

    rescue => e
      mp_log("NET: unexpected connect error #{e.class}: #{e.message}") if defined?(mp_log)
      push_error("Unexpected error: #{e.class}")
      backoff_and_reset
    end
  end

  def build_handshake_packet
    sprite = ""
    outfit = 0
<<<<<<< HEAD
    hue = 0
    trainer_type = ""

    if $game_player
      sprite = $game_player.character_name.to_s rescue ""
      hue = $game_player.character_hue.to_i rescue 0
    end

    if defined?($Trainer) && $Trainer
      outfit = $Trainer.outfit.to_i rescue 0
      trainer_type = $Trainer.trainer_type.to_s rescue ""
    end

    if sprite.empty? && !trainer_type.empty?
      sprite = resolve_charset_from_trainer_type(trainer_type)
    end

    version = (Settings::GAME_VERSION rescue "7.4.2")

    mp_log("SYNC: handshake sprite='#{sprite}' hue=#{hue} outfit=#{outfit} type=#{trainer_type}") if defined?(mp_log)

    MP_Packet.new(MP_PacketType::HANDSHAKE, {
      "name"          => $Trainer.name,
      "version"       => version,
      "sprite"        => sprite,
      "character_hue" => hue,
      "trainer_type"  => trainer_type,
      "outfit"        => outfit
    })
  end

  def resolve_charset_from_trainer_type(trainer_type)
    return "" if trainer_type.nil? || trainer_type.empty?
    candidates = [
      "trainer_#{trainer_type}",
      "trchar_#{trainer_type}",
      trainer_type.to_s
    ]
    candidates.each do |c|
      return c if charset_file_exists?(c)
    end
    ""
  end

  def charset_file_exists?(name)
    return false if name.nil? || name.empty?
    paths = [
      "Graphics/Characters/#{name}.png",
      "Graphics/Characters/#{name}.jpg",
      "Graphics/Characters/#{name}.bmp",
      "Graphics/Characters/#{name}.gif",
      "Graphics/Characters/#{name}"
    ]
    paths.any? { |p| FileTest.exist?(p) }
  rescue => e
    false
  end

=======
    if $game_player&.respond_to?(:charsetData) && $game_player.charsetData
      sprite = ($game_player.charsetData[1] || "").to_s rescue ""
      outfit = ($game_player.charsetData[2] || 0).to_i  rescue 0
    end
    version = (Settings::GAME_VERSION rescue "7.4.2")

    MP_Packet.new(MP_PacketType::HANDSHAKE, {
      "name"    => $Trainer.name,
      "version" => version,
      "sprite"  => sprite,
      "outfit"  => outfit
    })
  end

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def backoff_and_reset
    sleep(@reconnect_delay)
    @reconnect_delay = [@reconnect_delay * MP_ClientConfig::RECONNECT_BACKOFF_MULTIPLIER,
                        MP_ClientConfig::RECONNECT_MAX_INTERVAL].min
    @state = STATE_DISCONNECTED
    close_socket
  end

<<<<<<< HEAD
=======
  # ── Receive ────────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def receive_data
    return unless @socket && !@socket.closed?
    begin
      chunk = @socket.read_nonblock(65536)
      @receive_buffer << chunk.b
      process_buffer
    rescue IO::WaitReadable
<<<<<<< HEAD
=======
      # nothing to read yet
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
      on_disconnected("Connection lost")
    rescue => e
      on_disconnected("Receive error: #{e.class}: #{e.message}")
    end
  end

  def process_buffer
    while @receive_buffer.bytesize >= MP_Packet::HEADER_SIZE
      begin
        length     = @receive_buffer[2, 2].unpack1("n")
        total_size = MP_Packet::HEADER_SIZE + length
        break if @receive_buffer.bytesize < total_size

        if length > 100_000
          mp_log("NET: packet length #{length} looks bogus, dropping 1 byte to resync") if defined?(mp_log)
          @receive_buffer = @receive_buffer.byteslice(1, @receive_buffer.bytesize - 1) || "".b
          next
        end

        raw    = @receive_buffer[0, total_size]
        @receive_buffer = @receive_buffer.byteslice(total_size, @receive_buffer.bytesize - total_size) || "".b

        packet = MP_Packet.decode(raw)
        next unless packet

        if MP_ClientConfig::DEBUG_PACKETS
          mp_log("IN  #{packet.type_name}") if defined?(mp_log)
        end

        case packet.type
        when MP_PacketType::HANDSHAKE_ACK
          @client_id         = packet.payload["client_id"]
          @state             = STATE_CONNECTED
          @reconnect_attempts= 0
          @reconnect_delay   = MP_ClientConfig::RECONNECT_BASE_INTERVAL
          @last_heartbeat_rcvd = Time.now.to_f
          mp_log("NET: HANDSHAKE_ACK, client_id=#{@client_id}") if defined?(mp_log)
          push_event(:connect, packet.payload)

        when MP_PacketType::ERROR
          msg = packet.payload["message"] || "Unknown server error"
          mp_log("NET: ERROR from server: #{msg}") if defined?(mp_log)
          push_event(:error, msg)
          if msg.include?("Version mismatch") || msg.include?("Invalid player name") ||
             msg.include?("already logged in")
            @running = false
            close_socket
          end

        when MP_PacketType::HEARTBEAT
          @last_heartbeat_rcvd = Time.now.to_f
<<<<<<< HEAD
=======
          # Echo back ts for RTT
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
          send_raw(MP_Packet.new(MP_PacketType::HEARTBEAT, { "ts" => packet.payload["ts"] }))

        else
          push_event(:packet, packet)
        end
      rescue => e
        mp_log("NET: process_buffer error #{e.class}: #{e.message}") if defined?(mp_log)
        @receive_buffer = @receive_buffer.byteslice(1, @receive_buffer.bytesize - 1) || "".b
      end
    end
  end

<<<<<<< HEAD
=======
  # ── Send ──────────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def process_outgoing
    return unless @socket && !@socket.closed?
    to_send = @mutex.synchronize { @send_queue.shift([@send_queue.length, 50].min) }
    to_send.each do |packet|
      if MP_ClientConfig::DEBUG_PACKETS
        mp_log("OUT #{packet.type_name}") if defined?(mp_log)
      end
      send_raw(packet)
    end
  end

  def send_raw(packet)
    return unless @socket && !@socket.closed?
    begin
      data = packet.encode
      @socket.write(data)
    rescue => e
      on_disconnected("Send error: #{e.class}: #{e.message}")
    end
  end

<<<<<<< HEAD
=======
  # ── Event queue (net→game) ─────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def push_event(kind, data)
    @mutex.synchronize { @event_queue << [kind, data] }
  end

  def push_error(msg)
    @mutex.synchronize { @event_queue << [:error, msg] }
  end

  def dispatch_events
    events = @mutex.synchronize { @event_queue.shift(@event_queue.length) }
    events.each do |kind, data|
      case kind
      when :connect
        @connect_handlers.each { |cb| cb.call(data) rescue nil }
        initial_player_data
      when :disconnect
        @disconnect_handlers.each { |cb| cb.call(data) rescue nil }
      when :error
        @error_handlers.each { |cb| cb.call(data) rescue nil }
      when :packet
        handlers = @packet_handlers[data.type] || []
        handlers.each { |cb| cb.call(data.payload) rescue nil }
      end
    end
  end

  def initial_player_data
    return unless $game_player && $game_map
    send_packet(MP_PacketType::MAP_CHANGE, {
      "map_id"    => $game_map.map_id,
      "x"         => $game_player.x,
      "y"         => $game_player.y,
      "direction" => $game_player.direction
    })
    send_party_data
  end

<<<<<<< HEAD
=======
  # ── Disconnect ────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def on_disconnected(reason)
    return if @state == STATE_DISCONNECTED
    mp_log("NET: disconnected (#{reason})") if defined?(mp_log)
    old_state = @state
    @state     = STATE_DISCONNECTED
    @client_id = nil
    close_socket
    push_event(:disconnect, reason) if old_state == STATE_CONNECTED
  end

  def close_socket
    begin
      @socket.close unless @socket.nil? || @socket.closed?
    rescue
      nil
    end
    @socket = nil
  end
  extend self
end
