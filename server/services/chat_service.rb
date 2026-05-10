#===============================================================================
#  Pokemon Pathways Multiplayer - Chat Service
#  Handles CHAT_MESSAGE (map broadcast), CHAT_WHISPER (private), CHAT_SYSTEM
#===============================================================================

require_relative '../config'
require_relative '../packet'

class ChatService
  def initialize(server)
    @server = server
  end

  def handle_packet(client, packet)
    return unless client.authenticated

    case packet.type
    when MP_PacketType::CHAT_MESSAGE
      handle_chat_message(client, packet)
    when MP_PacketType::CHAT_WHISPER
      handle_whisper(client, packet)
    end
  end

  def handle_chat_message(client, packet)
    message = packet.payload["message"]
    return unless message
    return if message.strip.empty?
    return if message.length > 200

    # Sanitize message
    sanitized = sanitize_message(message)

    broadcast_packet = MP_Packet.new(MP_PacketType::CHAT_MESSAGE, {
      sender: client.player_name,
      sender_id: client.id,
      message: sanitized,
      map_id: client.map_id,
      timestamp: Time.now.to_i
    })

    # Broadcast to all players on the same map
    @server.broadcast_to_map(client.map_id, broadcast_packet)

    puts "[CHAT] [#{client.map_id}] #{client.player_name}: #{sanitized}"
  end

  def handle_whisper(client, packet)
    message = packet.payload["message"]
    target_name = packet.payload["target"]
    return unless message && target_name
    return if message.strip.empty?
    return if message.length > 500

    target = @server.clients.find_by_name(target_name)
    unless target
      client.send_packet(MP_Packet.new(MP_PacketType::CHAT_SYSTEM, {
        message: "Player '#{target_name}' is not online."
      }))
      return
    end

    sanitized = sanitize_message(message)

    # Send to target
    whisper_packet = MP_Packet.new(MP_PacketType::CHAT_WHISPER, {
      sender: client.player_name,
      sender_id: client.id,
      message: sanitized,
      timestamp: Time.now.to_i
    })
    target.send_packet(whisper_packet)

    # Echo back to sender
    client.send_packet(MP_Packet.new(MP_PacketType::CHAT_WHISPER, {
      sender: client.player_name,
      sender_id: client.id,
      message: sanitized,
      timestamp: Time.now.to_i,
      echo: true
    }))

    puts "[WHISPER] #{client.player_name} -> #{target_name}: #{sanitized}"
  end

  def send_system_message(client, message)
    client.send_packet(MP_Packet.new(MP_PacketType::CHAT_SYSTEM, {
      message: message
    }))
  end

  private

  def sanitize_message(message)
    # Remove control characters
    message.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, '')
      .gsub(/</, '&lt;')
      .gsub(/>/, '&gt;')
      .strip[0, 200]
  end
end
