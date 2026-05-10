#===============================================================================
#  Pokemon Pathways Multiplayer Client - Network Manager
#
#  Manages the TCP connection to the game server on a dedicated background
#  thread. The main game loop interacts with the manager via two thread-safe
#  queues:
#
#    @send_queue    — game loop pushes outbound packets; network thread drains
#    @event_queue   — network thread pushes incoming events; game loop processes
#
#  WHY TWO QUEUES?
#  All MKXP-Z/RPG Maker graphics objects (Sprite, Bitmap, Viewport) must be
#  created and disposed on the main thread. By deferring incoming packet
#  handling to the game loop (via @event_queue), we guarantee that packet
#  handlers that touch game state or UI always run on the correct thread.
#
#  FIXES vs original:
#   * ENCODING: @receive_buffer forced to ASCII-8BIT (.b). Original was UTF-8;
#     Socket#read_nonblock returns ASCII-8BIT; += raised Encoding::CompatibilityError.
#   * THREAD SAFETY: Callbacks NO LONGER fire on the receive thread.
#     Incoming events are enqueued and dispatched on the game loop thread by
#     MP_NetworkManager.dispatch_events (called from Scene_Map#update).
#   * HEARTBEAT: now includes a "ts" field so the server can echo it back for RTT.
#   * SYMBOL KEYS: All outbound payload hashes use string keys consistently.
#   * DUPLICATE MAP_CHANGE: send_map_change flag prevents double-sending.
#   * DISCONNECT CLEANUP: on_disconnect triggers MP_OverworldManager.on_disconnect.
#   * CLIENT HEARTBEAT: server only refreshes last_heartbeat when it *receives*
#     HEARTBEAT from the client. This client now sends periodic pings on the net
#     thread so menus / missed map ticks cannot cause server-side timeout.
#   * NO HEARTBEAT ECHO: echoing every inbound HEARTBEAT caused infinite
#     client↔server ping-pong; inbound packets only update LAST_SEEN diagnostics.
#===============================================================================

begin
  require "socket"
rescue LoadError => e
  raise e unless defined?(TCPSocket) && defined?(Socket)
end
require "json"

module MP_NetworkManager
  module_function

  STATE_DISCONNECTED = 0
  STATE_CONNECTING   = 1
  STATE_HANDSHAKING  = 2
  STATE_CONNECTED    = 3

  @socket              = nil
  @net_thread          = nil          # single background thread
  @running             = false
  @state               = STATE_DISCONNECTED
  @client_id           = nil
  @reconnect_attempts  = 0
  @reconnect_delay     = 1.0

  # FIX: ASCII-8BIT receive buffer (socket always returns ASCII-8BIT)
  @receive_buffer      = "".b

  # Thread-safe queues (Array used as queue; protected by @mutex)
  @send_queue          = []
  @event_queue         = []           # populated by net thread, drained by game loop
  @mutex               = Mutex.new

  # Registered handlers: type => [Proc, ...]
  @packet_handlers     = {}
  @connect_handlers    = []
  @disconnect_handlers = []
  @error_handlers      = []

  @queue_overflow_count = 0

  # Heartbeat / diagnostics (updated on net thread + main thread)
  @last_heartbeat_sent = nil
  @last_heartbeat_recv = nil
  @diag_frame          = 0
  @last_move_log_at    = nil

  # ── Public state ────────────────────────────────────────────────────────────

  def connected?;  @state == STATE_CONNECTED;  end
  def connecting?; @state == STATE_CONNECTING || @state == STATE_HANDSHAKING; end
  def client_id;   @client_id;   end
  def state;       @state;       end

  def state_name
    %w[DISCONNECTED CONNECTING HANDSHAKING CONNECTED][@state] || "UNKNOWN"
  end

  def diagnostics_text
    eq, sq = @mutex.synchronize { [@event_queue.length, @send_queue.length] }
    sock = @socket && !@socket.closed?
    thr  = @net_thread&.alive?
    hb_s = @last_heartbeat_sent ? format("%.2fs ago", Time.now - @last_heartbeat_sent) : "never"
    hb_r = @last_heartbeat_recv ? format("%.2fs ago", Time.now - @last_heartbeat_recv) : "never"
    map  = ($game_map.map_id rescue "n/a")
    [
      "state=#{@state} (#{state_name}) running=#{@running}",
      "thread_alive=#{thr} socket_open=#{sock}",
      "send_q=#{sq} event_q=#{eq}",
      "heartbeat_sent=#{hb_s} heartbeat_recv=#{hb_r}",
      "map_id=#{map} client_id=#{@client_id.inspect}"
    ].join(" | ")
  end

  # ── Lifecycle ───────────────────────────────────────────────────────────────

  def start
    if @running && @net_thread&.alive?
      mp_log("NET: start skipped (singleton already running)") if defined?(mp_log) && mp_diag_network?
      return
    end
    # Stale thread from a crash or partial stop
    if @net_thread&.alive?
      mp_log("NET: start — stopping stale net thread before restart") if defined?(mp_log) && mp_diag_network?
      stop
    end
    @running             = true
    @state               = STATE_DISCONNECTED
    @reconnect_attempts  = 0
    @reconnect_delay     = MP_ClientConfig::RECONNECT_BASE_INTERVAL
    @send_queue.clear
    @event_queue.clear
    @receive_buffer      = "".b
    @queue_overflow_count= 0
    @last_heartbeat_sent = nil
    @last_heartbeat_recv = nil
    @last_move_log_at    = nil
    @diag_frame          = 0
    mp_log("NET: start") if defined?(mp_log)
    @net_thread = Thread.new { net_loop }
  end

  def stop
    @running = false
    close_socket
    t = @net_thread
    @net_thread = nil
    if t&.alive?
      t.kill
      t.join(1.0) rescue nil
    end
    @state = STATE_DISCONNECTED
    @client_id = nil
    @last_heartbeat_sent = nil
    @last_heartbeat_recv = nil
    mp_log("NET: stopped") if defined?(mp_log)
  end

  # ── Game-loop side ──────────────────────────────────────────────────────────

  # Called every frame from Scene_Map#update (main thread).
  # Dispatches inbound events first so handlers can enqueue replies, then drains
  # send queue (twice so :connect → MAP_CHANGE flushes same frame).
  def tick
    ev_n = dispatch_events
    out_n = process_outgoing + process_outgoing
    net_diag_tick(ev_n, out_n)
  end

  # Push an outbound packet (safe to call from any thread).
  def send_packet(type, payload = {})
    return unless @state == STATE_CONNECTED
    log_outbound_packet(type, payload)
    @mutex.synchronize do
      if @send_queue.length > 500
        @send_queue.shift(250)
        @queue_overflow_count += 1
        mp_log("NET: send queue overflow ##{@queue_overflow_count}") if defined?(mp_log)
      end
      @send_queue << MP_Packet.new(type, payload)
    end
  end

  # ── Callback registration ───────────────────────────────────────────────────

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

  def mp_diag_network?
    MP_ClientConfig::NETWORK_DIAGNOSTICS
  rescue NameError
    false
  end

  # ── Party helper ────────────────────────────────────────────────────────────

  def send_party_data
    return unless $Trainer&.party&.first
    first = $Trainer.party[0]
    send_packet(MP_PacketType::PLAYER_PARTY, {
      "party" => [{ "species" => first.species.to_s, "level" => first.level, "name" => first.name }]
    })
  end

  # ── Private: background network thread ─────────────────────────────────────

  private

  def net_loop
    while @running
      case @state
      when STATE_DISCONNECTED
        if MP_ClientConfig::RECONNECT_ENABLED
          attempt_connect
        else
          sleep(1)
        end
      when STATE_HANDSHAKING, STATE_CONNECTED
        maybe_send_client_heartbeat if @state == STATE_CONNECTED
        receive_data
        sleep(0.001)   # yield; outbound is handled by game-loop tick
      when STATE_CONNECTING
        sleep(0.01)
      end
    end
  rescue => e
    mp_log("NET: net_loop crashed: #{e.class}: #{e.message}") if defined?(mp_log)
    @running = false
  end

  # ── Connect / handshake ────────────────────────────────────────────────────

  def attempt_connect
    max = MP_ClientConfig::RECONNECT_MAX_ATTEMPTS
    if max > 0 && @reconnect_attempts >= max
      mp_log("NET: max reconnect attempts reached") if defined?(mp_log)
      @running = false
      return
    end

    close_socket
    @reconnect_attempts += 1
    @state = STATE_CONNECTING
    mp_log("NET: connecting (attempt #{@reconnect_attempts})") if defined?(mp_log)

    begin
      @socket = TCPSocket.new(MP_ClientConfig::SERVER_IP, MP_ClientConfig::SERVER_PORT)
      @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # Wait for $Trainer (loaded save / new game may not have it immediately)
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

  def backoff_and_reset
    mp_log("NET: reconnect backoff #{@reconnect_delay}s before next attempt") if defined?(mp_log)
    sleep(@reconnect_delay)
    @reconnect_delay = [@reconnect_delay * MP_ClientConfig::RECONNECT_BACKOFF_MULTIPLIER,
                        MP_ClientConfig::RECONNECT_MAX_INTERVAL].min
    @state = STATE_DISCONNECTED
    close_socket
  end

  # ── Receive ────────────────────────────────────────────────────────────────

  def receive_data
    return unless @socket && !@socket.closed?
    begin
      chunk = @socket.read_nonblock(65536)
      # FIX: socket returns ASCII-8BIT; << on a .b buffer keeps encoding consistent
      @receive_buffer << chunk.b
      process_buffer
    rescue IO::WaitReadable
      # nothing to read yet
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
      on_disconnected("Connection lost")
    rescue => e
      on_disconnected("Receive error: #{e.class}: #{e.message}")
    end
  end

  def process_buffer
    while @receive_buffer.bytesize >= MP_Packet::HEADER_SIZE
      length     = @receive_buffer[2, 2].unpack1("n")
      total_size = MP_Packet::HEADER_SIZE + length
      break if @receive_buffer.bytesize < total_size

      raw    = @receive_buffer[0, total_size]
      # FIX: use slice assignment to preserve binary encoding on buffer
      @receive_buffer = @receive_buffer.byteslice(total_size, @receive_buffer.bytesize - total_size) || "".b

      packet = MP_Packet.decode(raw)
      next unless packet

      if MP_ClientConfig::DEBUG_PACKETS
        mp_log("IN  #{packet.type_name}") if defined?(mp_log)
      end

      # Handle handshake/error on this thread immediately (no game-state changes needed)
      case packet.type
      when MP_PacketType::HANDSHAKE_ACK
        @client_id         = packet.payload["client_id"]
        @state             = STATE_CONNECTED
        @reconnect_attempts= 0
        @reconnect_delay   = MP_ClientConfig::RECONNECT_BASE_INTERVAL
        mp_log("NET: HANDSHAKE_ACK, client_id=#{@client_id}") if defined?(mp_log)
        push_event(:connect, packet.payload)

      when MP_PacketType::ERROR
        msg = packet.payload["message"] || "Unknown server error"
        mp_log("NET: ERROR from server: #{msg}") if defined?(mp_log)
        push_event(:error, msg)
        # Fatal errors — stop reconnecting
        if msg.include?("Version mismatch") || msg.include?("Invalid player name") ||
           msg.include?("already logged in")
          @running = false
          close_socket
        end

      when MP_PacketType::HEARTBEAT
        # Server echoes our periodic ping — do NOT send_raw again (infinite ping-pong).
        @last_heartbeat_recv = Time.now
        if mp_diag_network?
          mp_log("NET: HEARTBEAT RECEIVED ts=#{packet.payload['ts'].inspect}") if defined?(mp_log)
          mp_log("NET: LAST_SEEN UPDATED (server echo) at #{@last_heartbeat_recv.strftime('%H:%M:%S.%L')}") if defined?(mp_log)
        end

      else
        # All other packets are deferred to the game loop thread
        push_event(:packet, packet)
      end
    end
  end

  # ── Send ──────────────────────────────────────────────────────────────────

  # Drain the outbound queue. Called from main-thread tick().
  # Returns number of packets written this call.
  def process_outgoing
    return 0 unless @socket && !@socket.closed?
    to_send = @mutex.synchronize { @send_queue.shift([@send_queue.length, 50].min) }
    to_send.each do |packet|
      if MP_ClientConfig::DEBUG_PACKETS
        mp_log("OUT #{packet.type_name}") if defined?(mp_log)
      end
      send_raw(packet)
    end
    to_send.length
  end

  # Write directly to socket (called from net_thread for handshake/heartbeat,
  # and from process_outgoing on main thread).
  def send_raw(packet)
    return unless @socket && !@socket.closed?
    begin
      data = packet.encode  # returns ASCII-8BIT .b string
      @socket.write(data)   # use blocking write; non-blocking was causing silent data loss
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError => e
      on_disconnected("Send error: #{e.class}")
    end
  end

  # ── Event queue (net→game) ─────────────────────────────────────────────────

  def push_event(kind, data)
    @mutex.synchronize { @event_queue << [kind, data] }
  end

  def push_error(msg)
    @mutex.synchronize { @event_queue << [:error, msg] }
  end

  # Dispatches all pending events to registered handlers.
  # Always called from the main (game loop) thread.
  # Returns number of events processed (for diagnostics).
  def dispatch_events
    events = @mutex.synchronize { @event_queue.shift(@event_queue.length) }
    events.each do |kind, data|
      case kind
      when :connect
        @connect_handlers.each { |cb| cb.call(data) rescue nil }
        # After connection confirmed, send initial position + party
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
    events.length
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

  private

  # Periodic client→server ping on the net thread (survives Scene_Map not ticking).
  def maybe_send_client_heartbeat
    return unless @socket && !@socket.closed?
    interval = MP_ClientConfig::CLIENT_HEARTBEAT_INTERVAL
    now = Time.now
    if @last_heartbeat_sent.nil? || (now - @last_heartbeat_sent) >= interval
      @last_heartbeat_sent = now
      ts = (now.to_f * 1000).to_i
      send_raw(MP_Packet.new(MP_PacketType::HEARTBEAT, { "ts" => ts }))
      mp_log("NET: HEARTBEAT SENT ts=#{ts}") if defined?(mp_log) && mp_diag_network?
    end
  end

  def net_diag_tick(events_processed, packets_sent)
    return unless mp_diag_network?
    intv = MP_ClientConfig::NETWORK_DIAG_TICK_INTERVAL
    @diag_frame += 1
    return unless @diag_frame % intv == 0
    eq, sq = @mutex.synchronize { [@event_queue.length, @send_queue.length] }
    thr = @net_thread&.alive?
    sock = @socket && !@socket.closed?
    hb_r = @last_heartbeat_recv ? format("%.2f", Time.now - @last_heartbeat_recv) : "—"
    mp_log("NET: DIAG TICK events_dispatched=#{events_processed} send_writes=#{packets_sent} event_q=#{eq} send_q=#{sq} state=#{state_name} thread=#{thr} sock=#{sock} hb_recv_ago=#{hb_r}s") if defined?(mp_log)
    warn_after = MP_ClientConfig::HEARTBEAT_WARN_AFTER
    hint = MP_ClientConfig::SERVER_DISCONNECT_TIMEOUT_HINT
    if @last_heartbeat_recv && (Time.now - @last_heartbeat_recv) > warn_after
      mp_log("NET: TIMEOUT CHECK — no HEARTBEAT echo for #{(Time.now - @last_heartbeat_recv).round(1)}s (server drops ~#{hint}s)") if defined?(mp_log)
    end
  end

  def log_outbound_packet(type, payload)
    return unless mp_diag_network?
    case type
    when MP_PacketType::MAP_CHANGE
      mp_log("NET: MAP_CHANGE SENT map_id=#{payload['map_id']} x=#{payload['x']} y=#{payload['y']}") if defined?(mp_log)
    when MP_PacketType::PLAYER_MOVE
      throttle = MP_ClientConfig::NETWORK_DIAG_MOVEMENT_THROTTLE
      t = Time.now
      if @last_move_log_at.nil? || (t - @last_move_log_at) >= throttle
        @last_move_log_at = t
        mp_log("NET: PLAYER_MOVE SENT x=#{payload['x']} y=#{payload['y']} dir=#{payload['direction']}") if defined?(mp_log)
      end
    end
  end

  public

  # ── Disconnect ────────────────────────────────────────────────────────────

  def on_disconnected(reason)
    return if @state == STATE_DISCONNECTED
    mp_log("NET: disconnected (#{reason})") if defined?(mp_log)
    old_state = @state
    @state     = STATE_DISCONNECTED
    @client_id = nil
    @last_heartbeat_sent = nil
    @last_heartbeat_recv = nil
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
end
