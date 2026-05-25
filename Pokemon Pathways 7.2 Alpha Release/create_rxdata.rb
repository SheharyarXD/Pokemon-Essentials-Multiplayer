# Run this from the game folder:
# ruby create_rxdata.rb
scripts = []
File.open("Data/PluginScripts.rxdata", "wb") { |f| Marshal.dump(scripts, f) }
puts "Created Data/PluginScripts.rxdata successfully"
puts "File size: #{File.size('Data/PluginScripts.rxdata')} bytes"
