#===============================================================================
#  Pokemon Pathways Multiplayer Server - Version Check
#  Validates client version on handshake. Mismatched clients rejected with ERROR.
#===============================================================================

class VersionCheck
  # The game version that clients must match
  # This must match Settings::GAME_VERSION in the client game
  REQUIRED_VERSION = "7.4.2"

  def valid?(client_version)
    return false if client_version.nil? || client_version.empty?
    # Exact match for now; could support version ranges
    client_version == REQUIRED_VERSION
  end

  def required_version
    REQUIRED_VERSION
  end
end
