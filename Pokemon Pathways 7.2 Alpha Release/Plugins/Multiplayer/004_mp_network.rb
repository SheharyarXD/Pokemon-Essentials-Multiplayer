#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Network Manager
#  TCP socket with non-blocking I/O via Ruby Thread
#  Exponential backoff reconnect, packet queue overflow protection
#  Connection state machine: disconnected -> connecting -> handshaking -> connected
#===============================================================================

module MP_NetworkManager
  module_function

  STATE_DISCONNECTED = 0
  STATE_CONNECTING = 1
  STATE_HANDSHAKING = 2
  STATE_CONNECTED = 3

  @socket = nil
  @receive_thread = nil
  @send_thread = nil
  @heartbeat_thread = nil
  @running = false
  @state = STATE_DISCONNECTED
  @client_id = nil
  @reconnect_attempts = 0
  @reconnect_delay = MP_ClientConfig::RECONNECT_BASE_INTERVAL
  @receive_buffer = ""
  @send_queue = []
  @mutex = Mutex.new
  @packet_callbacks = {}
  @connect_callbacks = []
  @disconnect_callbacks = []
  @error_callbacks = []
  @queue_overflow_count = 0

  def state_name
    case @state
    when STATE_DISCONNECTED then "DISCONNECTED"
    when STATE_CONNECTING then "CONNECTING"
    when STATE_HANDSHAKING then "HANDSHAKING"
    when STATE_CONNECTED then "CONNECTED"
    else "UNKNOWN"
    end
  end

  def connected?
    @state == STATE_CONNECTED
  end

  def connecting?
    @state == STATE_CONNECTING || @state == STATE_HANDSHAKING
  end

  def start
    return if @running
    @running = true
    @state = STATE_DISCONNECTED
    @reconnect_attempts = 0
    @reconnect_delay = MP_ClientConfig::RECONNECT_BASE_INTERVAL
    @send_queue.clear
    @receive_buffer = ""
    @queue_overflow_count = 0

    @main_thread = Thread.new { main_loop }
  end

  def stop
    @running = false
    close_socket
    @main_thread&.kill
    @main_thread = nil
  end

  def main_loop
    while @running
      case @state
      when STATE_DISCONNECTED
        if MP_ClientConfig::RECONNECT_ENABLED
          attempt_reconnect
        else
          sleep(1)
        end
      when STATE_CONNECTED
        process_outgoing
        sleep(MP_ClientConfig::SEND_INTERVAL)
      else
        sleep(0.01)
      end
    end
  end

  def attempt_reconnect
    max_attempts = MP_ClientConfig::RECONNECT_MAX_ATTEMPTS
    if max_attempts > 0 && @reconnect_attempts >= max_attempts
      echoln "[MP] Max reconnect attempts (#{max_attempts}) reached. Giving up."
      @running = false
      return
    end

    @reconnect_attempts += 1
    @state = STATE_CONNECTING

    echoln "[MP] Connecting to #{MP_ClientConfig::SERVER_IP}:#{MP_ClientConfig::SERVER_PORT} (attempt #{@reconnect_attempts})..."

    begin
      @socket = TCPSocket.new(MP_ClientConfig::SERVER_IP, MP_ClientConfig::SERVER_PORT)
      @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      @state = STATE_HANDSHAKING
      echoln "[MP] TCP connection established, sending handshake..."

      # Send handshake
      send_handshake

      # Start receive thread
      @receive_thread = Thread.new { receive_loop }

      # Start heartbeat thread
      @heartbeat_thread = Thread.new { heartbeat_loop }

      # Reset reconnect params on successful connect
      @reconnect_delay = MP_ClientConfig::RECONNECT_BASE_INTERVAL
      @queue_overflow_count = 0

    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::ENETUNREACH, SocketError => e
      echoln "[MP] Connection failed: #{e.class}"
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

  def send_handshake
    return unless $Trainer
    sprite = ""
    outfit = 0
    if $game_player && $game_player.respond_to?(:charsetData) && $game_player.charsetData
      sprite = $game_player.charsetData[1].to_s if $game_player.charsetData[1]
      outfit = $game_player.charsetData[2] || 0
    end

    version = Settings::GAME_VERSION rescue "7.4.2"

    packet = MP_Packet.new(MP_PacketType::HANDSHAKE, {
      name: $Trainer.name,
      version: version,
      sprite: sprite,
      outfit: outfit
    })
    send_raw(packet)
  end

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
      sleep(5) # 5 second heartbeat interval
      break unless @running && @state == STATE_CONNECTED
      send_raw(MP_Packet.new(MP_PacketType::HEARTBEAT, {}))
    end
  end

  def process_buffer
    while @receive_buffer.bytesize >= MP_Packet::HEADER_SIZE
      length = @receive_buffer[2, 2].unpack1('n')
      total_size = MP_Packet::HEADER_SIZE + length
      return if @receive_buffer.bytesize < total_size

      packet_data = @receive_buffer[0, total_size]
      @receive_buffer = @receive_buffer[total_size..-1] || ""

      packet = MP_Packet.decode(packet_data)
      next unless packet

      echoln "[MP][IN] #{packet.type_name}" if MP_ClientConfig::DEBUG_PACKETS
      handle_incoming_packet(packet)
    end
  end

  def handle_incoming_packet(packet)
    case packet.type
    when MP_PacketType::HANDSHAKE_ACK
      @client_id = packet.payload["client_id"]
      @state = STATE_CONNECTED
      @reconnect_attempts = 0
      @reconnect_delay = MP_ClientConfig::RECONNECT_BASE_INTERVAL
      echoln "[MP] Connected! Client ID: #{@client_id}"
      @connect_callbacks.each { |cb| cb.call(packet.payload) }
      # Send initial position
      send_player_data
    when MP_PacketType::ERROR
      msg = packet.payload["message"] || "Unknown error"
      echoln "[MP] Server error: #{msg}"
      @error_callbacks.each { |cb| cb.call(msg) }
      if msg.include?("Version mismatch")
        @running = false
      end
    end

    # Notify registered callbacks
    callbacks = @packet_callbacks[packet.type] || []
    callbacks.each { |cb| cb.call(packet.payload) }
  end

  def send_raw(packet)
    return if @socket.nil? || @socket.closed?
    begin
      data = packet.encode
      @socket.write_nonblock(data)
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
      # Overflow protection: drop oldest packets if queue too large
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
    packets_to_send = []
    @mutex.synchronize do
      packets_to_send = @send_queue.shift([@send_queue.length, 50].min)
    end
    packets_to_send.each do |packet|
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

  def handle_disconnect(reason)
    return if @state == STATE_DISCONNECTED
    echoln "[MP] Disconnected: #{reason}"
    @state = STATE_DISCONNECTED
    @client_id = nil
    close_socket
    @disconnect_callbacks.each { |cb| cb.call(reason) }
  end

  def close_socket
    @receive_thread&.kill
    @receive_thread = nil
    @heartbeat_thread&.kill
    @heartbeat_thread = nil
    begin
      @socket.close unless @socket.nil? || @socket.closed?
    rescue
      nil
    end
    @socket = nil
  end

  def on_packet(type, &block)
    @packet_callbacks[type] ||= []
    @packet_callbacks[type] << block
  end

  def on_connect(&block)
    @connect_callbacks << block
  end

  def on_disconnect(&block)
    @disconnect_callbacks << block
  end

  def on_error(&block)
    @error_callbacks << block
  end

  def remove_callbacks
    @packet_callbacks.clear
    @connect_callbacks.clear
    @disconnect_callbacks.clear
    @error_callbacks.clear
  end

  def client_id
    @client_id
  end

  def state
    @state
  end

  def send_player_data
    return unless $game_player && $game_map
    send_packet(MP_PacketType::PLAYER_MOVE, {
      x: $game_player.x,
      y: $game_player.y,
      direction: $game_player.direction
    })
    send_party_data
  end

  def send_party_data
    return unless $Trainer && $Trainer.party && !$Trainer.party.empty?
    first = $Trainer.party[0]
    return unless first
    send_packet(MP_PacketType::PLAYER_PARTY, {
      party: [{
        species: first.species.to_s,
        level: first.level,
        name: first.name
      }]
    })
  end
end
