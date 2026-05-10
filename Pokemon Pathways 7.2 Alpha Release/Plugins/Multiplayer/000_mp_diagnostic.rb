#===============================================================================
#  MP DIAGNOSTIC
#  Writes timestamped log entries to console (echoln) and mp_debug.txt.
#  Safe to load before any other MP module is defined.
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
  mp_log(err.backtrace.join("\n")) if err.backtrace
rescue
  nil
end

# Rotate log on startup
begin
  File.open("mp_debug.txt", "w") { |f| f.puts("=== MP Debug Log #{Time.now} ===") }
rescue
  nil
end

# MKXP-Z loads plugins before Ruby's socket stdlib in some builds — load early so
# diagnostics and later scripts see TCPSocket.
begin
  require "socket"
rescue LoadError
  nil
end

mp_log("DIAG: Multiplayer plugin loaded")
mp_log("DIAG: Ruby version      = #{RUBY_VERSION}")
mp_log("DIAG: TCPSocket defined = #{defined?(TCPSocket) ? 'YES' : 'NO'}")

class Scene_Map
  unless method_defined?(:mp_diag_main)
    alias_method :mp_diag_main, :main
  end

  def main
    mp_log("DIAG: Scene_Map#main entered")
    mp_log("DIAG: $Trainer   = #{$Trainer ? $Trainer.name : 'NIL'}")
    mp_log("DIAG: $game_map  = #{$game_map ? $game_map.map_id : 'NIL'}")
    mp_log("DIAG: $game_player = #{$game_player ? 'SET' : 'NIL'}")
    mp_diag_main
  ensure
    mp_log("DIAG: Scene_Map#main exited")
  end
end

mp_log("DIAG: Scene_Map diagnostic hook installed")
