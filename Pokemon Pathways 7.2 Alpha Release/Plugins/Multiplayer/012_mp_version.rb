#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Version Manager
#  Sends game version in handshake; handles rejection with a user message.
#  NOTE: If version mismatch, update REQUIRED_VERSION in server/version_check.rb
#        to match whatever Settings::GAME_VERSION returns in your game.
#===============================================================================

module MP_VersionManager
  module_function

  def current_version
    Settings::GAME_VERSION.to_s rescue "7.4.2"
  end

  def on_version_rejected(required_version)
    msg = "Multiplayer version mismatch!\nYour game: #{current_version}\nServer needs: #{required_version || 'unknown'}\n\nFix: open server/version_check.rb and set REQUIRED_VERSION = \"#{current_version}\""
    echoln "[MP][Version] #{msg}"
  end

  def on_error_packet(message)
    if message.include?("Version mismatch") || message.include?("version")
      required = message.match(/requires?\s+([\d.]+)/i)&.captures&.first
      on_version_rejected(required)
    end
  end
end

MP_NetworkManager.on_error do |msg|
  MP_VersionManager.on_error_packet(msg)
end
