#===============================================================================
#  Pokemon Pathways Multiplayer - Client Connection
#  Represents a single connected client with socket I/O
#===============================================================================

require_relative 'config'
require_relative 'packet'

class MP_Client
  attr_accessor :socket, :id, :authenticated, :player_name, :map_id,
                :pos_x, :pos_y, :direction, :sprite_name, :outfit,
                :last_heartbeat, :connected_at, :party_display
  attr_reader :server

  def initialize(socket, server)
    @socket = socket
    @server = server
    @id = generate_unique_id
    @authenticated = false
    @player_name = nil
    @map_id = nil
    @pos_x = 0
    @pos_y = 0
    @direction = 2
    @sprite_name = ""
    @outfit = 0
    @party_display = nil  # { species: string, level: int }
    @last_heartbeat = Time.now
    @connected_at = Time.now
    @receive_buffer = ""
    @send_queue = []
    @mutex = Mutex.new
  end

  def generate_unique_id
    rand(36**12).to_s(36).upcase.rjust(12, '0')
  end

  def send_packet(packet)
    return if @socket.nil? || @socket.closed?
    begin
      data = packet.encode
      @mutex.synchronize do
        @socket.write_nonblock(data)
      end
      puts "[PACKET][OUT] #{@player_name || @id[0,8]} <- #{packet.type_name}" if MP_ServerConfig::DEBUG_PACKETS
    rescue IO::WaitWritable
      @mutex.synchronize { @send_queue << packet }
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError => e
      puts "[ERROR] Send to #{@id[0,8]} failed: #{e.message}"
      disconnect
    end
  end

  def flush_send_queue
    return if @socket.nil? || @socket.closed? || @send_queue.empty?
    @mutex.synchronize do
      while !@send_queue.empty?
        packet = @send_queue.shift
        begin
          @socket.write_nonblock(packet.encode)
        rescue IO::WaitWritable
          @send_queue.unshift(packet)
          break
        rescue Errno::EPIPE, Errno::ECONNRESET, IOError
          break
        end
      end
    end
  end

  def receive_loop
    return if @socket.nil? || @socket.closed?
    begin
      data = @socket.read_nonblock(65536)
      @receive_buffer += data
      process_buffer
    rescue IO::WaitReadable
      # No data available
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
      disconnect
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

      puts "[PACKET][IN]  #{@player_name || @id[0,8]} -> #{packet.type_name}" if MP_ServerConfig::DEBUG_PACKETS
      @server.clients.route_packet(self, packet)
    end
  end

  def timed_out?
    Time.now - @last_heartbeat > MP_ServerConfig::DISCONNECT_TIMEOUT
  end

  def disconnect
    return if @socket.nil? || @socket.closed?
    # Notify gameplay services of disconnect for auto-forfeit/cancel
    @server.battles.handle_disconnect(self) if @server.respond_to?(:battles)
    @server.trades.handle_disconnect(self) if @server.respond_to?(:trades)
    begin
      @socket.close
    rescue
      nil
    end
    @server.rooms.player_leave_map(self) if @map_id
    @server.clients.remove_client(self)
    puts "[CLIENT] #{@player_name || @id[0,8]} disconnected"
  end
end
