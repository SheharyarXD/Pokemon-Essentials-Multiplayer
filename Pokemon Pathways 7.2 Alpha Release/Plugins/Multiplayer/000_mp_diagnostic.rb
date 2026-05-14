#===============================================================================
#  MP DIAGNOSTIC
#  Writes timestamped log entries to console (echoln) and mp_debug.txt.
#  Safe to load before any other MP module is defined.
#  STABILIZED v2.1 — Removed Scene_Map#main alias conflict
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

# Rotate log on startup
begin
  File.open("mp_debug.txt", "w") { |f| f.puts("=== MP Debug Log #{Time.now} ===") }
rescue
  nil
end

mp_log("DIAG: Multiplayer plugin loaded")
mp_log("DIAG: Ruby version      = #{RUBY_VERSION}")
mp_log("DIAG: TCPSocket defined = #{defined?(TCPSocket) ? 'YES' : 'NO'}")

# NOTE: We intentionally do NOT hook Scene_Map#main here.
# The 008_mp_hooks.rb file handles all Scene_Map hooks.
# Hooking main in multiple files creates double-alias chains that crash.

mp_log("DIAG: Diagnostic module loaded — Scene_Map hooks delegated to 008_mp_hooks.rb")
