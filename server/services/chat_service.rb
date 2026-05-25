#===============================================================================
#  Pokemon Pathways Multiplayer - Chat Service
#
#  Handles:
#   CHAT_MESSAGE  -> broadcast to all players on the same map
#   CHAT_WHISPER  -> private message between two players (with sender echo)
#   CHAT_SYSTEM   -> server-initiated system messages (no inbound handler)
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
    when MP_PacketType::CHAT_MESSAGE then handle_chat_message(client, packet)
    when MP_PacketType::CHAT_WHISPER then handle_whisper(client, packet)
    end
  end

  # ─── Map broadcast ────────────────────────────────────────────────────────────

  def handle_chat_message(client, packet)
    return unless client.map_id   # must be on a map to chat

    message = packet.payload["message"]
    return unless message.is_a?(String)
    return if message.strip.empty?

    sanitized = sanitize_message(message, MP_ServerConfig::MAX_CHAT_LENGTH)

    @server.broadcast_to_map(client.map_id,
      MP_Packet.new(MP_PacketType::CHAT_MESSAGE, {
        "sender"    => client.player_name,
        "sender_id" => client.id,
        "message"   => sanitized,
        "map_id"    => client.map_id,
        "timestamp" => Time.now.to_i
      })
    )

    puts "[CHAT] [map:#{client.map_id}] #{client.player_name}: #{sanitized}"
  end

  # ─── Whisper ─────────────────────────────────────────────────────────────────

  def handle_whisper(client, packet)
    message     = packet.payload["message"]
    target_name = packet.payload["target"]
    return unless message.is_a?(String) && target_name.is_a?(String)
    return if message.strip.empty?

    target = @server.clients.find_by_name(target_name)
    unless target
      client.send_packet(MP_Packet.new(MP_PacketType::CHAT_SYSTEM, {
        "message" => "Player '#{target_name}' is not online."
      }))
      return
    end

    sanitized = sanitize_message(message, MP_ServerConfig::MAX_WHISPER_LENGTH)
    ts        = Time.now.to_i

    whisper_pkt = MP_Packet.new(MP_PacketType::CHAT_WHISPER, {
      "sender"    => client.player_name,
      "sender_id" => client.id,
      "message"   => sanitized,
      "timestamp" => ts
    })

    target.send_packet(whisper_pkt)

    # Echo back to sender with a flag so the client can render it differently
    client.send_packet(MP_Packet.new(MP_PacketType::CHAT_WHISPER, {
      "sender"    => client.player_name,
      "sender_id" => client.id,
      "to"        => target_name,
      "message"   => sanitized,
      "timestamp" => ts,
      "echo"      => true
    }))

    puts "[WHISPER] #{client.player_name} -> #{target_name}: #{sanitized}"
  end

  # ─── Server-initiated system message ─────────────────────────────────────────

  def send_system_message(client, message)
    client.send_packet(MP_Packet.new(MP_PacketType::CHAT_SYSTEM, {
      "message" => message
    }))
  end

  private

  def sanitize_message(message, max_len)
    message
      .gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, '')  # strip control characters
      .gsub('<', '&lt;')
      .gsub('>', '&gt;')
      .strip
      .slice(0, max_len)
  end
end
