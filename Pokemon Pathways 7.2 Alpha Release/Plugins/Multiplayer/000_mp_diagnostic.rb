#===============================================================================
#  MP DIAGNOSTIC v1.2.0
#  - Safe logging utility used by all other MP modules
#  - Removed Scene_Map#main hook (was conflicting with 008_mp_hooks.rb)
#  - Now purely a utility module with no side effects
#===============================================================================

def mp_log(msg)
  return unless $DEBUG || (defined?(MP_ClientConfig) && MP_ClientConfig::DEBUG_PACKETS)
  timestamp = Time.now.strftime("%H:%M:%S.%L")
  line = "[#{timestamp}] #{msg}"
  echoln line rescue nil
  begin
    File.open("mp_debug.txt", "a") { |f| f.puts(line) }
  rescue
    nil
  end
end

# Only create fresh log file on initial load, not on reload
unless defined?($mp_diagnostic_loaded)
  $mp_diagnostic_loaded = true
  begin
    File.open("mp_debug.txt", "w") { |f| f.puts("=== MP Debug Log #{Time.now} ===") }
  rescue
    nil
  end
  mp_log("DIAG: Multiplayer plugin loaded")
  mp_log("DIAG: Ruby version = #{RUBY_VERSION}")
  mp_log("DIAG: TCPSocket defined? #{defined?(TCPSocket) ? 'YES' : 'NO'}")
end
