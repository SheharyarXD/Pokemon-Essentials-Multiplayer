# Pokemon Pathways Multiplayer System

Complete multiplayer plugin for Pokemon Pathways 7.2 Alpha, built for RPG Maker XP with MKXP-Z (Ruby 3.0.0) and Pokemon Essentials v19.1.

## Features

- **Player Synchronization**: See other players moving on the same map in real-time
- **Smooth Movement**: 50ms interpolation for fluid remote player movement
- **Distance Culling**: Only render players within 20 tiles (configurable)
- **PvP Battles**: Challenge other players to turn-based battles
- **Trading**: Exchange Pokemon with other players using the existing trade UI
- **Chat System**: Map-local chat with whispers and system messages
- **Party Display**: See other players' lead Pokemon species and level
- **Auto-Reconnect**: Exponential backoff reconnection (1s, 2s, 4s, 8s... max 30s)
- **Non-Invasive**: Works as a plugin overlay - single-player is never broken
- **Graceful Degradation**: If the server is unavailable, the game continues normally

## Architecture

```
Client (MKXP-Z/RGSS)                    Server (Ruby 3.0.0)
+------------------+                    +------------------+
| Pokemon Pathways |                    | TCPServer :9000  |
|  + Multiplayer   | <---- TCP ------>  |  + ClientManager |
|    Plugin        |     JSON Packets   |  + RoomManager   |
|  - mp_network.rb |                    |  + OverworldSvc  |
|  - mp_overworld  |                    |  + BattleSvc     |
|  - mp_battle.rb  |                    |  + TradeSvc      |
|  - mp_trade.rb   |                    |  + ChatSvc       |
|  - mp_chat.rb    |                    |  + PlayerStore   |
+------------------+                    +------------------+
```

## Quick Start

### 1. Start the Server

Requires Ruby 3.0.0 or later.

```bash
# Navigate to the server directory
cd server/

# Install dependencies (only standard library needed)
# No gems required - uses socket, json, thread, fileutils from stdlib

# Start the server
ruby main.rb
```

The server will start on port 9000 by default.

### 2. Configure the Client

Edit `Plugins/Multiplayer/001_mp_config.rb`:

```ruby
module MP_ClientConfig
  SERVER_IP = "your.server.ip"   # <-- Change this
  SERVER_PORT = 9000
end
```

Replace `your.server.ip` with:
- `"127.0.0.1"` for local testing
- Your LAN IP for local network play
- Your server's public IP for online play

### 3. Install the Plugin

Copy the entire `Plugins/Multiplayer/` folder into your game's `Plugins/` directory.

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

### 4. Run the Game

Start the game normally. The plugin will:
1. Auto-connect to the server when entering the map
2. Send your player data (position, sprite, party)
3. Show other players on the same map

## Server Configuration

Edit `server/config.rb` to customize:

```ruby
module MP_ServerConfig
  HOST = "0.0.0.0"          # Bind address
  PORT = 9000               # Server port
  MAX_CLIENTS = 100         # Maximum simultaneous connections
  TICK_RATE = 20            # Server tick rate (Hz)
  VISIBLE_DISTANCE = 20     # Player visibility radius (tiles)
  MAX_PLAYERS_PER_MAP = 32  # Max players sharing one map
end
```

## Folder Structure

```
/mnt/agents/output/
  server/
    config.rb                 # Server configuration
    packet.rb                 # Binary packet system (80+ packet types)
    client.rb                 # Connected client class
    client_manager.rb         # Connection & auth management
    room_manager.rb           # Map-based room instancing
    version_check.rb          # Client version validation
    game_server.rb            # Main TCPServer & game loop
    main.rb                   # Server entry point
    services/
      overworld_service.rb    # Position sync, delta compression
      battle_service.rb       # PvP battle rooms, turn relay
      trade_service.rb        # Trade sessions with validation
      chat_service.rb         # Map chat & whispers
    persistence/
      player_store.rb         # JSON file-based player storage
  Plugins/
    Multiplayer/
      meta.txt                # Plugin registration
      001_mp_config.rb        # Client configuration
      002_mp_packet.rb        # Client packet encoder/decoder
      003_mp_data.rb          # RemotePlayer data model
      004_mp_network.rb       # TCP socket, reconnect logic
      005_mp_remote_player.rb # Game_Character subclass
      006_mp_remote_sprite.rb # Sprite_Character subclass
      007_mp_overworld.rb     # Overworld sync & interpolation
      008_mp_hooks.rb         # Game engine hooks
      009_mp_battle.rb        # PvP battle integration
      010_mp_trade.rb         # Network trade integration
      011_mp_chat.rb          # Chat overlay
      012_mp_version.rb       # Version check client-side
  README.md                   # This file
  INSTALL.md                  # Detailed installation guide
```

## Testing Locally

1. Start the server: `ruby server/main.rb`
2. Open Pokemon Pathways with the multiplayer plugin installed
3. The client auto-connects to `127.0.0.1:9000`
4. You should see `[MP] Connected! Client ID: ...` in the game log

To test with multiple clients on one machine, you'll need to run multiple game instances (may require multiple game installations).

## Common Errors & Fixes

### "Connection refused"
- The server is not running. Start it with `ruby server/main.rb`
- Wrong `SERVER_IP` in `mp_config.rb`. Use `127.0.0.1` for local testing

### "Version mismatch"
- The client and server have different `GAME_VERSION` values
- Check `Settings::GAME_VERSION` in the game and the server's `version_check.rb`

### "Server full"
- `MAX_CLIENTS` (default 100) has been reached
- Increase in `server/config.rb` if needed

### Players not appearing
- Check that both players are on the **same map ID**
- Verify `VISIBLE_DISTANCE` (default 20 tiles) - players too far apart won't see each other
- Check server logs for packet flow

### Plugin not loading
- Verify `meta.txt` is in the `Plugins/Multiplayer/` folder
- Check that all `.rb` files are present
- Look for plugin compilation errors in the game log

### Port 9000 already in use
- Change `PORT` in both `server/config.rb` and the client's `001_mp_config.rb`
- Or kill the existing process using port 9000

### Firewall issues
- **Windows**: Allow `ruby.exe` through Windows Firewall
- **Linux**: `sudo ufw allow 9000/tcp`
- **Router**: Forward port 9000 to your server's local IP for online play

## Network Protocol

Packets use a binary header + JSON payload format:
- **Header (8 bytes)**: `[type: uint16][length: uint16][timestamp: uint32]`
- **Payload**: JSON-encoded data

See `002_mp_packet.rb` / `server/packet.rb` for the full packet type definitions (80+ types).

## Technical Details

- **Server tick rate**: 20 Hz (50ms per tick)
- **Position broadcast**: Every 3 ticks (150ms)
- **Heartbeat interval**: 5 seconds
- **Disconnect timeout**: 15 seconds
- **Interpolation**: 50ms lerp for smooth movement
- **Reconnection**: Exponential backoff, max 30 seconds
- **Trade timeout**: 120 seconds
- **Battle turn timeout**: 60 seconds

## Credits

- Pokemon Pathways Development Team
- Pokemon Essentials by Maruno
- MKXP-Z by the MKXP team
