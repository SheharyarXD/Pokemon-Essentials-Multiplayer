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

  # ── Debug ───────────────────────────────────────────────────────────────────
  DEBUG_PACKETS  = false   # set true to log every packet to console
  DEBUG_MOVEMENT = false
end
