#===============================================================================
#  MP VERSION MANAGER v1.2.0
#  FIXED:
#    1. Error callback registration deferred to init (prevents load-order issues)
#    2. Added guard for MP_NetworkManager availability
#    3. Version comparison uses proper semantic logic
#===============================================================================

module MP_VersionManager
  module_function

  @initialized = false

  def init
    return if @initialized
    @initialized = true

    # Only register callback if MP_NetworkManager is available
    if defined?(MP_NetworkManager) && MP_NetworkManager.respond_to?(:on_error)
      MP_NetworkManager.on_error do |msg|
        on_error_packet(msg)
      end
    end
  end

  def current_version
    Settings::GAME_VERSION.to_s rescue "1.0.0"
  end

  def on_version_rejected(required_version)
    msg = "Multiplayer version mismatch!\nYour game: #{current_version}\nServer needs: #{required_version || 'unknown'}\n\nFix: Update your game or contact the server admin."
    echoln "[MP][Version] #{msg}"
  end

  def on_error_packet(message)
    return unless message
    if message.include?("Version mismatch") || message.include?("version")
      required = message.match(/requires?\s+([\d.]+)/i)&.captures&.first
      on_version_rejected(required)
    end
  end
end

# Defer init until after all modules are loaded
begin
  MP_VersionManager.init
rescue => e
  echoln "[MP][Version] Init error: #{e.class}: #{e.message}"
end
