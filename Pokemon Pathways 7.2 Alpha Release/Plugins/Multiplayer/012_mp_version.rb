#===============================================================================
#  Pokemon Pathways Multiplayer Client - Version Manager (STABLE v2.1)
#
#  No critical changes needed — already safe.
#===============================================================================

module MP_VersionManager
  module_function

  def current_version
    Settings::GAME_VERSION.to_s rescue "7.4.2"
  end

  def handle_error(message)
    msg = message.to_s
    return unless msg.include?("Version mismatch") || msg.include?("version")
    required = msg.match(/requires?\s+v?([\d.]+)/i)&.captures&.first || "unknown"
    user_msg = [
      "Multiplayer version mismatch!",
      "Your game : #{current_version}",
      "Server    : #{required}",
      "",
      "Ask the server admin to update server/version_check.rb,",
      "or update your game client."
    ].join("\n")
    mp_log("VERSION: #{user_msg}") if defined?(mp_log)
    pbMessage(user_msg) rescue nil
  rescue => e
    mp_log_exception("VERSION: handle_error", e) if defined?(mp_log_exception)
  end
end

begin
  MP_NetworkManager.on_error do |msg|
    MP_VersionManager.handle_error(msg)
  end
rescue => e
  mp_log_exception("VERSION: register error handler", e) if defined?(mp_log_exception)
end

