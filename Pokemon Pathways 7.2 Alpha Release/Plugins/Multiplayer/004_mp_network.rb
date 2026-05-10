#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Network Manager
#  FIXED:
#    1. require 'socket' added (was missing - caused NameError on TCPSocket)
#    2. send_handshake now retries until $Trainer is available (was bailing silently)
#    3. start() is now idempotent - cannot spawn duplicate threads
#    4. STATE_HANDSHAKING transition happens only after HANDSHAKE_ACK received
#===============================================================================

require 'socket'
require 'json'

module MP_NetworkManager
  module_function

  STATE_DISCONNECTED = 0
  STATE_CONNECTING   = 1
  STATE_HANDSHAKING  = 2
  STATE_CONNECTED    = 3

  @socket             = nil
  @main_thread        = nil
  @receive_thread     = nil
  @heartbeat_thread   = nil
  @running            = false
  @state              = STATE_DISCONNECTED
  @client_id          = nil
  @reconnect_attempts = 0
  @reconnect_delay    = 1.0
  @receive_buffer     = ""
  @send_queue         = []
  @mutex              = Mutex.new
  @packet_callbacks   = {}
  @connect_callbacks  = []
  @disconnect_callbacks = []
  @error_callbacks    = []
  @queue_overflow_count = 0

  # ── State helpers ──────────────────────────────────────────────────────────

  def connected?
    @state == STATE_CONNECTED
  end

  def connecting?
    @state == STATE_CONNECTING || @state == STATE_HANDSHAKING
  end

  def state_name
    %w[DISCONNECTED CONNECTING HANDSHAKING CONNECTED][@state] || "UNKNOWN"
  end

  # ── Lifecycle ──────────────────────────────────────────────────────────────

  # FIX 3: Guard against double-start
  def start
    return if @running
    @running            = true
    @state              = STATE_DISCONNECTED
    @reconnect_attempts = 0
    @reconnect_delay    = MP_ClientConfig::RECONNECT_BASE_INTERVAL
    @send_queue.clear
    @receive_buffer     = ""
    @queue_overflow_count = 0
    echoln "[MP] Network manager starting..."
    @main_thread = Thread.new { main_loop }
  end

  def stop
    @running = false
    close_socket
    @main_thread&.kill
    @main_thread = nil
    echoln "[MP] Network manager stopped."
  end

  # ── Main loop ──────────────────────────────────────────────────────────────

  def main_loop
    while @running
      case @state
      when STATE_DISCONNECTED
        MP_ClientConfig::RECONNECT_ENABLED ? attempt_reconnect : sleep(1)
      when STATE_CONNECTED
        process_outgoing
        sleep(MP_ClientConfig::SEND_INTERVAL)
      else
        sleep(0.01)
      end
    end
  rescue => e
    echoln "[MP] main_loop crashed: #{e.class}: #{e.message}"
  end

  # ── Connection ─────────────────────────────────────────────────────────────

  def attempt_reconnect
    max = MP_ClientConfig::RECONNECT_MAX_ATTEMPTS
    if max > 0 && @reconnect_attempts >= max
      echoln "[MP] Max reconnect attempts reached. Giving up."
      @running = false
      return
    end

    @reconnect_attempts += 1
    @state = STATE_CONNECTING
    echoln "[MP] Connecting to #{MP_ClientConfig::SERVER_IP}:#{MP_ClientConfig::SERVER_PORT} (attempt #{@reconnect_attempts})..."

    begin
      @socket = TCPSocket.new(MP_ClientConfig::SERVER_IP, MP_ClientConfig::SERVER_PORT)
      @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      echoln "[MP] TCP connected. Waiting for $Trainer before handshake..."

      # FIX 2: Wait up to 10s for $Trainer to be available after map load
      wait_start = Time.now
      until $Trainer || (Time.now - wait_start > 10)
        sleep(0.1)
      end

      unless $Trainer
        echoln "[MP] Handshake aborted: $Trainer still nil after 10s wait. Will retry."
        @state = STATE_DISCONNECTED
        close_socket
        sleep(@reconnect_delay)
        return
      end

      @state = STATE_HANDSHAKING
      send_handshake

      @receive_thread  = Thread.new { receive_loop }
      @heartbeat_thread = Thread.new { heartbeat_loop }

      @reconnect_delay      = MP_ClientConfig::RECONNECT_BASE_INTERVAL
      @queue_overflow_count = 0

    rescue Errno::ECONNREFUSED
      echoln "[MP] Connection refused — is the server running on #{MP_ClientConfig::SERVER_IP}:#{MP_ClientConfig::SERVER_PORT}?"
      @state = STATE_DISCONNECTED
      sleep(@reconnect_delay)
      @reconnect_delay = [@reconnect_delay * MP_ClientConfig::RECONNECT_BACKOFF_MULTIPLIER,
                          MP_ClientConfig::RECONNECT_MAX_INTERVAL].min
      close_socket
    rescue Errno::ETIMEDOUT, Errno::ENETUNREACH, SocketError => e
      echoln "[MP] Connection failed: #{e.class}: #{e.message}"
      @state = STATE_DISCONNECTED
      sleep(@reconnect_delay)
      @reconnect_delay = [@reconnect_delay * MP_ClientConfig::RECONNECT_BACKOFF_MULTIPLIER,
                          MP_ClientConfig::RECONNECT_MAX_INTERVAL].min
      close_socket
    rescue => e
      echoln "[MP] Unexpected connect error: #{e.class}: #{e.message}"
      @state = STATE_DISCONNECTED
      sleep(@reconnect_delay)
      close_socket
    end
  end

  # FIX 2: Safe handshake — only called once $Trainer is confirmed available
  def send_handshake
    sprite  = ""
    outfit  = 0
    if $game_player&.respond_to?(:charsetData) && $game_player.charsetData
      sprite = $game_player.charsetData[1].to_s rescue ""
      outfit = $game_player.charsetData[2] || 0 rescue 0
    end

    version = begin
                Settings::GAME_VERSION
              rescue NameError
                "7.4.2"
              end

    packet = MP_Packet.new(MP_PacketType::HANDSHAKE, {
      name:    $Trainer.name,
      version: version,
      sprite:  sprite,
      outfit:  outfit
    })
    echoln "[MP] Sending handshake as '#{$Trainer.name}' version #{version}"
    send_raw(packet)
  end

  # ── I/O loops ──────────────────────────────────────────────────────────────

  def receive_loop
    while @running && @state >= STATE_HANDSHAKING
      begin
        data = @socket.read_nonblock(65536)
        @receive_buffer += data
        process_buffer
      rescue IO::WaitReadable
        sleep(0.001)
      rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
        handle_disconnect("Connection lost")
        break
      rescue => e
        handle_disconnect("Receive error: #{e.class}")
        break
      end
    end
  end

  def heartbeat_loop
    while @running && @state == STATE_CONNECTED
      sleep(5)
      break unless @running && @state == STATE_CONNECTED
      send_raw(MP_Packet.new(MP_PacketType::HEARTBEAT, {}))
    end
  end

  def process_buffer
    while @receive_buffer.bytesize >= MP_Packet::HEADER_SIZE
      length     = @receive_buffer[2, 2].unpack1('n')
      total_size = MP_Packet::HEADER_SIZE + length
      return if @receive_buffer.bytesize < total_size

      packet_data     = @receive_buffer[0, total_size]
      @receive_buffer = @receive_buffer[total_size..-1] || ""

      packet = MP_Packet.decode(packet_data)
      next unless packet

      echoln "[MP][IN] #{packet.type_name}" if MP_ClientConfig::DEBUG_PACKETS
      handle_incoming_packet(packet)
    end
  end

  # ── Packet handling ────────────────────────────────────────────────────────

  def handle_incoming_packet(packet)
    case packet.type
    when MP_PacketType::HANDSHAKE_ACK
      @client_id          = packet.payload["client_id"]
      @state              = STATE_CONNECTED  # FIX 4: only transition here, not before
      @reconnect_attempts = 0
      @reconnect_delay    = MP_ClientConfig::RECONNECT_BASE_INTERVAL
      echoln "[MP] ✅ Connected! Client ID: #{@client_id}"
      @connect_callbacks.each { |cb| cb.call(packet.payload) rescue nil }
      send_player_data

    when MP_PacketType::ERROR
      msg = packet.payload["message"] || "Unknown error"
      echoln "[MP] ❌ Server error: #{msg}"
      @error_callbacks.each { |cb| cb.call(msg) rescue nil }
      if msg.include?("Version mismatch") || msg.include?("Invalid player name")
        @running = false
        close_socket
      end
    end

    callbacks = @packet_callbacks[packet.type] || []
    callbacks.each { |cb| cb.call(packet.payload) rescue nil }
  end

  # ── Send helpers ───────────────────────────────────────────────────────────

  def send_raw(packet)
    return if @socket.nil? || @socket.closed?
    begin
      @socket.write_nonblock(packet.encode)
      echoln "[MP][OUT] #{packet.type_name}" if MP_ClientConfig::DEBUG_PACKETS
    rescue IO::WaitWritable
      @mutex.synchronize { @send_queue << packet }
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError
      handle_disconnect("Send failed")
    end
  end

  def send_packet(type, payload = {})
    return unless @state == STATE_CONNECTED
    @mutex.synchronize do
      if @send_queue.length > 500
        @send_queue.shift(250)
        @queue_overflow_count += 1
        echoln "[MP] Send queue overflow ##{@queue_overflow_count}, dropped 250 packets"
      end
      @send_queue << MP_Packet.new(type, payload)
    end
  end

  def process_outgoing
    return if @socket.nil? || @socket.closed?
    to_send = []
    @mutex.synchronize { to_send = @send_queue.shift([@send_queue.length, 50].min) }
    to_send.each do |packet|
      begin
        @socket.write_nonblock(packet.encode)
      rescue IO::WaitWritable
        @mutex.synchronize { @send_queue.unshift(packet) }
        break
      rescue Errno::EPIPE, Errno::ECONNRESET, IOError
        @mutex.synchronize { @send_queue.unshift(packet) }
        handle_disconnect("Send failed")
        break
      end
    end
  end

  # ── Disconnect ─────────────────────────────────────────────────────────────

  def handle_disconnect(reason)
    return if @state == STATE_DISCONNECTED
    echoln "[MP] Disconnected: #{reason}"
    @state     = STATE_DISCONNECTED
    @client_id = nil
    close_socket
    @disconnect_callbacks.each { |cb| cb.call(reason) rescue nil }
  end

  def close_socket
    @receive_thread&.kill;  @receive_thread  = nil
    @heartbeat_thread&.kill; @heartbeat_thread = nil
    begin; @socket.close unless @socket.nil? || @socket.closed?; rescue; end
    @socket = nil
  end

  # ── Callbacks ──────────────────────────────────────────────────────────────

  def on_packet(type, &block)
    @packet_callbacks[type] ||= []
    @packet_callbacks[type] << block
  end

  def on_connect(&block);    @connect_callbacks    << block; end
  def on_disconnect(&block); @disconnect_callbacks << block; end
  def on_error(&block);      @error_callbacks      << block; end

  def remove_callbacks
    @packet_callbacks.clear
    @connect_callbacks.clear
    @disconnect_callbacks.clear
    @error_callbacks.clear
  end

  def client_id; @client_id; end
  def state;     @state;     end

  # ── Player data ────────────────────────────────────────────────────────────

  def send_player_data
    return unless $game_player && $game_map
    send_packet(MP_PacketType::PLAYER_MOVE, {
      x:         $game_player.x,
      y:         $game_player.y,
      direction: $game_player.direction
    })
    send_party_data
  end

  def send_party_data
    return unless $Trainer&.party&.first
    first = $Trainer.party[0]
    send_packet(MP_PacketType::PLAYER_PARTY, {
      party: [{
        species: first.species.to_s,
        level:   first.level,
        name:    first.name
      }]
    })
  end
end
