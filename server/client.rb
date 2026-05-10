#===============================================================================
#  Pokemon Pathways Multiplayer - Client Connection
#
#  Represents a single connected player socket with:
#   - Binary-safe receive buffer (ASCII-8BIT)
#   - Non-blocking send with overflow queue
#   - Idempotent disconnect (safe to call multiple times)
#   - Per-tick packet rate limit (anti-flood)
#   - Heartbeat timeout detection
#
#  FIXES vs original:
#   * @receive_buffer forced to binary encoding (prevents Encoding::CompatibilityError)
#   * @disconnected flag prevents double-disconnect / double-cleanup
#   * flush_send_queue now called from send_packet when data is queued
#   * Packet rate limiting (@packets_this_tick)
#===============================================================================

require_relative 'config'
require_relative 'packet'

class MP_Client
  attr_accessor :socket, :id, :authenticated, :player_name, :map_id,
                :pos_x, :pos_y, :direction, :sprite_name, :outfit,
                :last_heartbeat, :connected_at, :party_display
  attr_reader :server

  def initialize(socket, server)
    @socket          = socket
    @server          = server
    @id              = generate_unique_id
    @authenticated   = false
    @player_name     = nil
    @map_id          = nil
    @pos_x           = 0
    @pos_y           = 0
    @direction       = 2
    @sprite_name     = ""
    @outfit          = 0
    @party_display   = nil  # { "species" => String, "level" => Integer }
    @last_heartbeat  = Time.now
    @connected_at    = Time.now

    # FIX: Force binary (ASCII-8BIT) encoding on receive buffer.
    # Socket#read_nonblock always returns ASCII-8BIT; mixing with a
    # UTF-8 String via += causes Encoding::CompatibilityError.
    @receive_buffer  = "".b

    @send_queue      = []
    @mutex           = Mutex.new
    @disconnected    = false   # FIX: idempotency guard

    # Rate limiting: reset per tick by the game loop
    @packets_this_tick = 0
  end

  # ─── Unique ID ──────────────────────────────────────────────────────────────

  def generate_unique_id
    rand(36**12).to_s(36).upcase.rjust(12, '0')
  end

  # ─── Send path ──────────────────────────────────────────────────────────────

  # Thread-safe send. Attempts non-blocking write; queues remainder on backpressure.
  def send_packet(packet)
    return if disconnected?
    begin
      data = packet.encode
      @mutex.synchronize { write_or_queue(data) }
      if MP_ServerConfig::DEBUG_PACKETS
        puts "[PACKET][OUT] #{@player_name || @id[0, 8]} <- #{packet.type_name}"
      end
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError => e
      puts "[CLIENT] Send error for #{@id[0, 8]}: #{e.message}"
      disconnect
    end
  end

  # Drain the write queue. Called at the start of each receive cycle.
  def flush_send_queue
    return if disconnected?
    return if @send_queue.empty?
    @mutex.synchronize do
      while (data = @send_queue.first)
        written = write_nonblock_safe(data)
        break if written.nil?      # would block - try again next tick
        @send_queue.shift
      end
    end
  end

  # ─── Receive path ───────────────────────────────────────────────────────────

  def receive_loop
    return if disconnected?
    flush_send_queue

    begin
      # FIX: read_nonblock returns ASCII-8BIT; concatenating to .b buffer is safe
      chunk = @socket.read_nonblock(65536)
      @receive_buffer << chunk.b
      process_buffer
    rescue IO::WaitReadable
      # Nothing available this tick - normal
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
      disconnect
    end
  end

  # ─── Packet framing ─────────────────────────────────────────────────────────

  def process_buffer
    while @receive_buffer.bytesize >= MP_Packet::HEADER_SIZE
      # Peek at the length field (bytes 2-3)
      length     = @receive_buffer[2, 2].unpack1('n')
      total_size = MP_Packet::HEADER_SIZE + length

      # Not enough data yet - wait for more
      break if @receive_buffer.bytesize < total_size

      # Extract one complete packet
      raw_packet      = @receive_buffer[0, total_size]
      @receive_buffer = @receive_buffer[total_size..] || "".b

      # FIX: Per-tick rate limit - drop abusive clients
      @packets_this_tick += 1
      if @packets_this_tick > MP_ServerConfig::MAX_PACKETS_PER_TICK
        puts "[RATELIMIT] #{@player_name || @id[0, 8]} exceeded packet limit - disconnecting"
        disconnect
        return
      end

      packet = MP_Packet.decode(raw_packet)
      next unless packet

      if MP_ServerConfig::DEBUG_PACKETS
        puts "[PACKET][IN]  #{@player_name || @id[0, 8]} -> #{packet.type_name}"
      end

      @server.clients.route_packet(self, packet)
    end
  end

  # Reset per-tick counter - called by game loop at start of each tick
  def reset_tick_counter
    @packets_this_tick = 0
  end

  # ─── Timeout / lifecycle ────────────────────────────────────────────────────

  def timed_out?
    Time.now - @last_heartbeat > MP_ServerConfig::DISCONNECT_TIMEOUT
  end

  def disconnected?
    @disconnected
  end

  # FIX: Idempotent disconnect. Safe to call from multiple code paths.
  # Notifies battle/trade services exactly once, removes from room, then closes socket.
  def disconnect
    @mutex.synchronize do
      return if @disconnected   # already handled
      @disconnected = true
    end

    # Notify gameplay services so they can resolve dangling sessions
    @server.battles.handle_disconnect(self) rescue nil
    @server.trades.handle_disconnect(self)  rescue nil

    # Remove from map room (broadcasts PLAYER_LEAVE to remaining players)
    @server.rooms.player_leave_map(self) if @map_id

    # Remove from the client registry
    @server.clients.remove_client(self)

    # Close the socket
    begin
      @socket.close unless @socket.nil? || @socket.closed?
    rescue
      nil
    end

    puts "[CLIENT] #{@player_name || @id[0, 8]} disconnected"
  end

  # ─── Private helpers ────────────────────────────────────────────────────────

  private

  # Write data to socket non-blockingly.
  # Queues any unsent portion on backpressure.
  # Returns bytes written, or nil if would block immediately.
  def write_or_queue(data)
    unless @send_queue.empty?
      @send_queue << data
      return
    end
    written = write_nonblock_safe(data)
    if written.nil?
      # Socket full - queue everything
      @send_queue << data
    elsif written < data.bytesize
      # Partial write - queue remainder
      @send_queue << data[written..]
    end
  end

  # Returns bytes written, nil if EAGAIN/WaitWritable.
  def write_nonblock_safe(data)
    @socket.write_nonblock(data)
  rescue IO::WaitWritable
    nil
  end
end
