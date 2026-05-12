#===============================================================================
#  Pokemon Pathways Multiplayer Client - Configuration
#
#  FIXES v2.1:
#   * Added SAFE_MODE — when true, disables ALL remote sprite creation for
#     Phase 1 diagnostics. Networking continues normally.
#   * Added REMOTE_RENDERING_ENABLED — master switch for remote player display.
#   * Added PLACEHOLDER_ON_MISSING_CHARSET — when true, uses colored placeholder
#     instead of trying to load potentially missing charset files.
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
  POSITION_RESEND_INTERVAL     = 120   # ~2 seconds at 60fps

  # ── Rendering ───────────────────────────────────────────────────────────────
  # PHASE 1 DIAGNOSTIC: Set SAFE_MODE = true to disable ALL remote rendering.
  # Only networking runs. Use this to verify connection stability without
  # any sprite creation.
  SAFE_MODE                      = false

  # Master switch for remote player rendering. Set false to keep networking
  # but never show remote players.
  REMOTE_RENDERING_ENABLED       = true

  # When true and a charset file cannot be found, renders a colored placeholder
  # rectangle instead of crashing. When false, attempts normal PE charset load.
  PLACEHOLDER_ON_MISSING_CHARSET = true

  VISIBLE_DISTANCE             = 20    # tiles - culling radius

  # Interpolation smooths remote player movement between sync packets.
  INTERPOLATION_ENABLED        = true
  INTERPOLATION_DURATION       = 150   # ms

  # ── Heartbeat (must stay under server DISCONNECT_TIMEOUT; server is 15s) ───
  CLIENT_HEARTBEAT_INTERVAL      = 3.0
  HEARTBEAT_WARN_AFTER           = 10.0
  SERVER_DISCONNECT_TIMEOUT_HINT = 15

  # ── Debug / diagnostics ───────────────────────────────────────────────────
  DEBUG_PACKETS  = false
  DEBUG_MOVEMENT = false
  NETWORK_DIAGNOSTICS         = true
  NETWORK_DIAG_TICK_INTERVAL  = 60
  NETWORK_DIAG_F9_DUMP        = false
  NETWORK_DIAG_MOVEMENT_THROTTLE = 0.5
end

