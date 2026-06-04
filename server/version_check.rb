#===============================================================================
#  Pokemon Pathways Multiplayer Server - Version Check
#  Validates client version on handshake; mismatched clients are rejected.
#  REQUIRED_VERSION must match Settings::GAME_VERSION in the client game.
#===============================================================================

class VersionCheck
<<<<<<< HEAD
  REQUIRED_VERSION = "9.1.3"
=======
  REQUIRED_VERSION = "7.4.2"
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095

  def valid?(client_version)
    return false if client_version.nil? || client_version.to_s.strip.empty?
    client_version.strip == REQUIRED_VERSION
  end

  def required_version
    REQUIRED_VERSION
  end
end
