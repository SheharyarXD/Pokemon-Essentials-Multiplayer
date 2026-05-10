# Installation Guide - Pokemon Pathways Multiplayer

## Step 1: Install Ruby 3.0.0

### Windows
1. Download Ruby 3.0.0+ from https://rubyinstaller.org/
2. Run the installer with default options
3. Verify: `ruby --version` should show 3.0.0 or higher

### Linux (Ubuntu/Debian)
```bash
sudo apt-get update
sudo apt-get install ruby ruby-dev
ruby --version
```

### macOS
```bash
brew install ruby
ruby --version
```

## Step 2: Place the Plugin in Your Game

Copy the `Plugins/Multiplayer/` folder into your game's `Plugins/` directory:

```
Your Game/
  Plugins/
    Multiplayer/
      meta.txt
      001_mp_config.rb
      002_mp_packet.rb
      003_mp_data.rb
      004_mp_network.rb
      005_mp_remote_player.rb
      006_mp_remote_sprite.rb
      007_mp_overworld.rb
      008_mp_hooks.rb
      009_mp_battle.rb
      010_mp_trade.rb
      011_mp_chat.rb
      012_mp_version.rb
```

## Step 3: Configure the Server IP

Edit `Plugins/Multiplayer/001_mp_config.rb`:

```ruby
module MP_ClientConfig
  SERVER_IP = "127.0.0.1"   # <-- Change this
  SERVER_PORT = 9000
  ...
end
```

**Configuration options:**
- `"127.0.0.1"` - Local testing (server on same machine)
- `"192.168.x.x"` - LAN play (server on another computer on your network)
- `"your.public.ip"` - Online play (server with public IP)

## Step 4: Start the Server

```bash
cd server/
ruby main.rb
```

You should see:
```
============================================================
  Pokemon Pathways Multiplayer Server
  Listening on 0.0.0.0:9000
  Tick rate: 20 Hz
  Max clients: 100
============================================================
```

## Step 5: Configure Firewall / Port Forwarding

### Local Testing
No configuration needed. Use `127.0.0.1`.

### LAN Play
Allow port 9000 through your firewall:

**Windows Firewall:**
1. Open Windows Defender Firewall
2. Click "Advanced Settings"
3. Inbound Rules > New Rule
4. Port > TCP > 9000 > Allow
5. Name it "Pokemon Pathways Multiplayer"

**Linux (UFW):**
```bash
sudo ufw allow 9000/tcp
```

### Online Play (Port Forwarding)

If your server is behind a router, forward port 9000:

1. Access your router admin panel (usually `192.168.1.1`)
2. Find "Port Forwarding" or "Virtual Servers"
3. Add a rule:
   - External Port: 9000
   - Internal Port: 9000
   - Internal IP: Your server's local IP (e.g., `192.168.1.100`)
   - Protocol: TCP
4. Save and apply

Find your local IP:
- Windows: `ipconfig` - look for "IPv4 Address"
- Linux: `ip addr` or `ifconfig`
- macOS: `ifconfig` or System Preferences > Network

## Step 6: Launch the Game

1. Start Pokemon Pathways normally
2. Enter a save file and load into the overworld
3. The plugin auto-connects to the server
4. Check the log (or console in debug mode) for connection messages

You should see:
```
[MP] Connecting to 127.0.0.1:9000 (attempt 1)...
[MP] TCP connection established, sending handshake...
[MP] Connected! Client ID: XXXXXXXXXXXX
```

## Troubleshooting

### "Cannot load such file -- socket"
Your Ruby installation is missing the socket standard library. Reinstall Ruby.

### Plugin doesn't appear in plugin list
- Ensure `meta.txt` exists in `Plugins/Multiplayer/`
- Check that the file encoding is UTF-8
- Look for compilation errors in the game log

### "Plugin Error" on startup
- Verify all 12 `.rb` files are present
- Check that `001_mp_config.rb` has valid Ruby syntax
- Ensure no files were corrupted during copy

### Server starts but clients can't connect
- Verify the server IP in `001_mp_config.rb`
- Check firewall rules (both server and client machines)
- Test with `telnet SERVER_IP 9000` from the client machine
- For online play, verify port forwarding is active

### High latency or choppy movement
- Lower `TICK_RATE` in `server/config.rb` (try 30 or 40)
- Reduce `INTERPOLATION_DURATION` in client config
- Check network connection quality between client and server

## Uninstalling

To remove the multiplayer system:
1. Delete the `Plugins/Multiplayer/` folder
2. Delete `Data/PluginScripts.rxdata` (forces recompilation)
3. The game will return to pure single-player mode

## Updating

To update the multiplayer system:
1. Stop the server if running
2. Replace all files in `Plugins/Multiplayer/` with new versions
3. Replace all files in `server/` with new versions
4. Delete `Data/PluginScripts.rxdata`
5. Restart the server
6. Launch the game
