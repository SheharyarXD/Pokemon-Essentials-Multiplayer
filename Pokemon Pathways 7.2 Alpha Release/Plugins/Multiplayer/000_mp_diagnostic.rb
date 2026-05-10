#===============================================================================
#  MP DIAGNOSTIC
#  - Writes to console (echoln) and mp_debug.txt
#  - Safe to load even before all MP modules are defined
#===============================================================================

def mp_log(msg)
  timestamp = Time.now.strftime("%H:%M:%S")
  line = "[#{timestamp}] #{msg}"
  echoln line
  begin
    File.open("mp_debug.txt", "a") { |f| f.puts(line) }
  rescue
    nil
  end
end

begin
  File.open("mp_debug.txt", "w") { |f| f.puts("=== MP Debug Log #{Time.now} ===") }
rescue
  nil
end

mp_log("DIAG: Multiplayer plugin loaded")
mp_log("DIAG: Ruby version = #{RUBY_VERSION}")
mp_log("DIAG: TCPSocket defined? #{defined?(TCPSocket) ? 'YES' : 'NO'}")
mp_log("DIAG: MP_ClientConfig defined? #{defined?(MP_ClientConfig) ? 'YES' : 'NO'}")
mp_log("DIAG: MP_NetworkManager defined? #{defined?(MP_NetworkManager) ? 'YES' : 'NO'}")

class Scene_Map
  unless method_defined?(:mp_diag_main)
    alias_method :mp_diag_main, :main
  end

  def main
    mp_log("DIAG: Scene_Map#main entered")
    mp_log("DIAG: $Trainer = #{$Trainer ? $Trainer.name : 'NIL'}")
    mp_log("DIAG: $game_map = #{$game_map ? $game_map.map_id : 'NIL'}")
    mp_log("DIAG: $game_player = #{$game_player ? 'SET' : 'NIL'}")
    mp_log("DIAG: $mp_network_started = #{$mp_network_started.inspect}") if defined?($mp_network_started)
    mp_diag_main
  ensure
    mp_log("DIAG: Scene_Map#main exited")
  end
end

mp_log("DIAG: Scene_Map diagnostic hook installed")
