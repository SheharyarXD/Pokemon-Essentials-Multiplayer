#===============================================================================
#  Pokemon Pathways Multiplayer Server - Configuration
<<<<<<< HEAD
#  PHASE 2 v4.0 — Added 2v2 map whitelist, partner timeout, rank validation
#===============================================================================

module MP_ServerConfig
  # ── Network ──────────────────────────────────────────────────────────────────
  HOST        = "127.0.0.1"
  PORT        = 9000
  MAX_CLIENTS = 100

  # ── Timing ───────────────────────────────────────────────────────────────────
  TICK_RATE              = 20
  TICK_DURATION          = 1.0 / TICK_RATE
  HEARTBEAT_INTERVAL     = 5
  DISCONNECT_TIMEOUT     = 15
  POSITION_SYNC_INTERVAL = 3
  BACKUP_INTERVAL        = 300

  # ── Anti-abuse / rate limiting ───────────────────────────────────────────────
  MAX_PACKETS_PER_TICK   = 30
  MAX_CHAT_LENGTH        = 200
  MAX_WHISPER_LENGTH     = 500
  MAX_PLAYER_NAME_LEN    = 20
  MAX_TRADE_DISTANCE     = 3

  # ── World ────────────────────────────────────────────────────────────────────
  MAX_PLAYERS_PER_MAP    = 32
  VISIBLE_DISTANCE       = 20
  MAP_INSTANCING         = false

  # ── Persistence ──────────────────────────────────────────────────────────────
  DATA_DIR               = "./server_data"
  PLAYERS_DIR            = "#{DATA_DIR}/players"
  BACKUP_DIR             = "#{DATA_DIR}/backups"
  MAX_BACKUPS_PER_PLAYER = 5

  # ── Phase 2: 2v2 battle map whitelist ────────────────────────────────────────
  # Only these map IDs may host 2v2 battles. Must match 013_mp_2v2_config.rb.
  BATTLE_2V2_ALLOWED_MAPS = [32, 45, 71].freeze

  # ── Phase 2: Partner system ───────────────────────────────────────────────────
  PARTNER_REQUEST_TTL    = 60    # Seconds before an unanswered partner request expires
  PARTNER_MAX_DISTANCE   = 5     # Tiles — must be within this range to form a partnership

  # ── Phase 2: Rank ────────────────────────────────────────────────────────────
  # Valid rank names the client may submit. Any other value is clamped to "D".
  VALID_RANKS = %w[D C B A S SS Monarch].freeze

  # ── Debug ────────────────────────────────────────────────────────────────────
=======
#  Server-side configuration constants
#===============================================================================

module MP_ServerConfig
  # Network settings
  HOST           = "127.0.0.1"          # Listen on all interfaces (was 127.0.0.1 = localhost only)
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
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  DEBUG_PACKETS  = false
  DEBUG_MOVEMENT = false
end
