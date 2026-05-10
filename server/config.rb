#===============================================================================
#  Pokemon Pathways Multiplayer Server - Configuration
#  Server-side configuration constants
#===============================================================================

module MP_ServerConfig
  # Network settings
  HOST = "127.0.0.1"
  PORT = 9000
  MAX_CLIENTS = 100

  # Timing settings
  TICK_RATE = 20                    # Game ticks per second (20Hz = 50ms/tick)
  TICK_DURATION = 1.0 / TICK_RATE
  HEARTBEAT_INTERVAL = 5            # Seconds between expected heartbeats
  DISCONNECT_TIMEOUT = 15           # Seconds without heartbeat before disconnect
  POSITION_SYNC_INTERVAL = 3        # Broadcast positions every N ticks
  BACKUP_INTERVAL = 300             # Save player data every 5 minutes (in seconds)

  # Game settings
  MAX_PLAYERS_PER_MAP = 32
  VISIBLE_DISTANCE = 20             # Tiles - visibility radius for player culling
  MAP_INSTANCING = false            # Shared world (not instances)

  # Persistence settings
  DATA_DIR = "./server_data"
  PLAYERS_FILE = "#{DATA_DIR}/players.json"
  BACKUP_DIR = "#{DATA_DIR}/backups"

  # Debugging
  DEBUG_PACKETS = true
  DEBUG_MOVEMENT = false
end
