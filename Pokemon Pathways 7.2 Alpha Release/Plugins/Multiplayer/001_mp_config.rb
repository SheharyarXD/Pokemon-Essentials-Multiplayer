#===============================================================================
#  Pokemon Pathways Multiplayer Client - Configuration
#===============================================================================

module MP_ClientConfig
  # ── Server connection ───────────────────────────────────────────────────────
  SERVER_IP   = "127.0.0.1"
  SERVER_PORT = 9000

  # ── Reconnect settings ──────────────────────────────────────────────────────
  RECONNECT_ENABLED            = true
  RECONNECT_BASE_INTERVAL      = 1.0   # seconds before first retry
  RECONNECT_MAX_INTERVAL       = 30.0  # cap on exponential backoff
  RECONNECT_BACKOFF_MULTIPLIER = 2.0
  RECONNECT_MAX_ATTEMPTS       = 0     # 0 = unlimited

  # ── Network timing ──────────────────────────────────────────────────────────
  # How often (in frames, at ~60fps) the local position is re-sent even if
  # nothing has changed. Keeps the server aware the player is alive.
  # Server broadcasts every 3 ticks (~150ms); don't spam more than needed.
  POSITION_RESEND_INTERVAL     = 120   # ~2 seconds at 60fps (was POSITION_SEND_INTERVAL=3 -> 20/sec!)

  # ── Rendering ───────────────────────────────────────────────────────────────
  VISIBLE_DISTANCE             = 20    # tiles - culling radius

  # Interpolation smooths remote player movement between sync packets.
  # Duration in milliseconds; roughly one server tick (server broadcasts ~150ms).
  INTERPOLATION_ENABLED        = true
  INTERPOLATION_DURATION       = 150   # ms (was 50ms - too fast, leaves gaps)

  # ── Heartbeat (must stay under server DISCONNECT_TIMEOUT; server is 15s) ───
  CLIENT_HEARTBEAT_INTERVAL      = 3.0   # seconds between client-initiated pings
  HEARTBEAT_WARN_AFTER           = 10.0  # diagnostic: warn if no server echo this long
  SERVER_DISCONNECT_TIMEOUT_HINT = 15  # for log messages only (matches server default)

  # ── Debug / diagnostics ───────────────────────────────────────────────────
  DEBUG_PACKETS  = false   # set true to log every packet to console
  DEBUG_MOVEMENT = false
  # Thread state, queues, heartbeat age, map id — set false to silence mp_debug.txt
  NETWORK_DIAGNOSTICS         = true
  NETWORK_DIAG_TICK_INTERVAL  = 60     # frames between NET TICK lines (~1s at 60fps)
  # If true, press F9 on the map once to log MP_NetworkManager.diagnostics_text
  NETWORK_DIAG_F9_DUMP        = false
  # PLAYER_MOVE lines while NETWORK_DIAGNOSTICS (still throttled inside network code)
  NETWORK_DIAG_MOVEMENT_THROTTLE = 0.5  # seconds between PLAYER_MOVE SENT logs
end
