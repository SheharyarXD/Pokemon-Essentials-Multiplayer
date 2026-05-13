#===============================================================================
#  Pokemon Pathways Multiplayer Client - Version Manager
#
#  Reads game version from Settings::GAME_VERSION and handles version-mismatch
#  ERROR packets from the server with a clear user-facing message.
#
#  NOTE: If rejected, update REQUIRED_VERSION in server/version_check.rb to
#  match whatever Settings::GAME_VERSION returns in your game build.
#===============================================================================

module MP_VersionManager
  def current_version
    Settings::GAME_VERSION.to_s rescue "7.4.2"
  end

  def handle_error(message)
    return unless message.include?("Version mismatch") || message.include?("version")
    required = message.match(/requires?\s+v?([\d.]+)/i)&.captures&.first || "unknown"
    user_msg = [
      "Multiplayer version mismatch!",
      "Your game : #{current_version}",
      "Server    : #{required}",
      "",
      "Ask the server admin to update server/version_check.rb,",
      "or update your game client."
    ].join("\n")
    mp_log("VERSION: #{user_msg}") if defined?(mp_log)
    # pbMessage is deferred — this runs on main thread via error handler
    pbMessage(user_msg) rescue nil
  end

  extend self
end

# Register after MP_NetworkManager is defined (happens at load time before hooks run)
MP_NetworkManager.on_error do |msg|
  MP_VersionManager.handle_error(msg)
end
