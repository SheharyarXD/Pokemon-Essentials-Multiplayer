#===============================================================================
#  Pokemon Pathways Multiplayer - Client Connection
#  REMOTE SKIN SYNC v3.0 — Added character_hue, trainer_type fields
#===============================================================================

require_relative 'config'
require_relative 'packet'

class MP_Client
  attr_accessor :socket, :id, :authenticated, :player_name, :map_id,
                :pos_x, :pos_y, :direction, :sprite_name, :character_hue, :trainer_type, :outfit,
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
    @character_hue   = 0
    @trainer_type    = ""
    @outfit          = 0
    @party_display   = nil
    @last_heartbeat  = Time.now
    @connected_at    = Time.now

    @receive_buffer  = "".b

    @send_queue      = []
    @mutex           = Mutex.new
    @disconnected    = false

    @packets_this_tick = 0
  end

  def generate_unique_id
    rand(36**12).to_s(36).upcase.rjust(12, '0')
  end

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

  def flush_send_queue
    return if disconnected?
    return if @send_queue.empty?
    @mutex.synchronize do
      while (data = @send_queue.first)
        written = write_nonblock_safe(data)
        break if written.nil?
        @send_queue.shift
      end
    end
  end

  def receive_loop
    return if disconnected?
    flush_send_queue

    begin
      chunk = @socket.read_nonblock(65536)
      @receive_buffer << chunk.b
      process_buffer
    rescue IO::WaitReadable
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
      disconnect
    end
  end

  def process_buffer
    while @receive_buffer.bytesize >= MP_Packet::HEADER_SIZE
      length     = @receive_buffer[2, 2].unpack1('n')
      total_size = MP_Packet::HEADER_SIZE + length

      break if @receive_buffer.bytesize < total_size

      raw_packet      = @receive_buffer[0, total_size]
      @receive_buffer = @receive_buffer[total_size..] || "".b

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

  def reset_tick_counter
    @packets_this_tick = 0
  end

  def timed_out?
    Time.now - @last_heartbeat > MP_ServerConfig::DISCONNECT_TIMEOUT
  end

  def disconnected?
    @disconnected
  end

  def disconnect
    @mutex.synchronize do
      return if @disconnected
      @disconnected = true
    end

    @server.battles.handle_disconnect(self) rescue nil
    @server.trades.handle_disconnect(self)  rescue nil

    @server.rooms.player_leave_map(self) if @map_id
    @server.clients.remove_client(self)

    begin
      @socket.close unless @socket.nil? || @socket.closed?
    rescue
      nil
    end

    puts "[CLIENT] #{@player_name || @id[0, 8]} disconnected"
  end

  private

  def write_or_queue(data)
    unless @send_queue.empty?
      @send_queue << data
      return
    end
    written = write_nonblock_safe(data)
    if written.nil?
      @send_queue << data
    elsif written < data.bytesize
      @send_queue << data[written..]
    end
  end

  def write_nonblock_safe(data)
    @socket.write_nonblock(data)
  rescue IO::WaitWritable
    nil
  end
end
