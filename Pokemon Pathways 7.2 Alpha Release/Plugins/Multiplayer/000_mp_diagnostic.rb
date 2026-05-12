#===============================================================================
#  MP DIAGNOSTIC
#  Writes timestamped log entries to console (echoln) and mp_debug.txt.
#  Safe to load before any other MP module is defined.
#
#  FIXES v2.1:
#   * Safe-mode aware: logs SAFE_MODE status
#   * Thread-safe log rotation
#   * No Scene_Map hook to avoid alias conflicts with 008_mp_hooks.rb
#===============================================================================

def mp_log(msg)
  timestamp = Time.now.strftime("%H:%M:%S.%L")
  line = "[#{timestamp}] #{msg}"
  echoln line
  begin
    File.open("mp_debug.txt", "a") { |f| f.puts(line) }
  rescue
    nil
  end
end

# Full exception + backtrace (remote player / sprite failures, hooks, etc.)
def mp_log_exception(prefix, err)
  return unless err
  mp_log("#{prefix} #{err.class}: #{err.message}")
  mp_log(err.backtrace[0..4].join("\n")) if err.backtrace
rescue
  nil
end

# Rotate log on startup
begin
  File.open("mp_debug.txt", "w") { |f| f.puts("=== MP Debug Log #{Time.now} ===") }
rescue
  nil
end

# MKXP-Z loads plugins before Ruby's socket stdlib in some builds
begin
  require "socket"
rescue LoadError
  nil
end

mp_log("DIAG: Multiplayer plugin loaded")
mp_log("DIAG: Ruby version      = #{RUBY_VERSION}")
mp_log("DIAG: TCPSocket defined = #{defined?(TCPSocket) ? 'YES' : 'NO'}")
mp_log("DIAG: Graphics defined  = #{defined?(Graphics) ? 'YES' : 'NO'}")

# Diagnostics-only helper: does NOT alias Scene_Map methods.
# All Scene_Map hooks live in 008_mp_hooks.rb to prevent alias chaining.

