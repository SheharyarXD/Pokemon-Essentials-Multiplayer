#===============================================================================
#  Pokemon Pathways Multiplayer Server - Configuration
#  Server-side configuration constants
#===============================================================================

module MP_ServerConfig
  # Network settings
  HOST           = "0.0.0.0"          # Listen on all interfaces (was 127.0.0.1 = localhost only)
  PORT           = 9000
  MAX_CLIENTS    = 100

  # Timing settings
  TICK_RATE              = 20          # Game ticks per second (20 Hz => 50 ms/tick)
  TICK_DURATION          = 1.0 / TICK_RATE
  HEARTBEAT_INTERVAL     = 5          # Seconds between expected client heartbeats
  DISCONNECT_TIMEOUT     = 15         # Seconds without heartbeat before forced disconnect
  POSITION_SYNC_INTERVAL = 3          # Broadcast pending moves every N ticks (~150 ms)
  BACKUP_INTERVAL        = 300        # Periodic player save every 5 minutes (seconds)

  # Anti-abuse / rate limiting
  MAX_PACKETS_PER_TICK   = 30         # Drop connection if client sends more than this per tick
  MAX_CHAT_LENGTH        = 200        # Hard cap on chat message length (characters)
  MAX_WHISPER_LENGTH     = 500
  MAX_PLAYER_NAME_LEN    = 20
  MAX_TRADE_DISTANCE     = 3          # Tiles - must be within this range to initiate trade

  # Game / world settings
  MAX_PLAYERS_PER_MAP    = 32
  VISIBLE_DISTANCE       = 20         # Tiles - radius beyond which player updates are not sent
  MAP_INSTANCING         = false      # Shared world (false = no per-player map instances)

  # Persistence
  DATA_DIR     = "./server_data"
  PLAYERS_DIR  = "#{DATA_DIR}/players"
  BACKUP_DIR   = "#{DATA_DIR}/backups"
  MAX_BACKUPS_PER_PLAYER = 5          # Keep only the N most recent backup files

  # Debugging (disable for production)
  DEBUG_PACKETS  = false
  DEBUG_MOVEMENT = false
end
