#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Version Check
#  Sends version in handshake, handles rejection gracefully with user message
#===============================================================================

module MP_VersionManager
  module_function

  def current_version
    Settings::GAME_VERSION rescue "7.4.2"
  end

  def on_version_rejected(server_version)
    message = _INTL("Server version mismatch!\\nYour version: {1}\\nRequired: {2}\\n\\nPlease update your game.", current_version, server_version || "unknown")
    echoln "[MP][Version] #{message}"

    # Show error to user
    Thread.new {
      sleep(0.5)
      pbMessage(message)
    }
  end

  def on_error_packet(payload)
    message = payload["message"] || "Unknown error"
    if message.include?("version") || message.include?("Version")
      # Extract required version from message if possible
      required = message.match(/requires?\s+([\d.]+)/i)
      on_version_rejected(required ? required[1] : nil)
    end
  end
end

# Register error handler for version rejection
MP_NetworkManager.on_error do |msg|
  MP_VersionManager.on_error_packet({ "message" => msg })
end
