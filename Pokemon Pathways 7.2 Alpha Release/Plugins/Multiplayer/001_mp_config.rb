#===============================================================================
#  Pokemon Pathways Multiplayer Client - Configuration
#  STABILIZED v2.1 — Production-ready client architecture
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
  VISIBLE_DISTANCE             = 20    # tiles - culling radius

  # ── Interpolation ─────────────────────────────────────────────────────────
  INTERPOLATION_ENABLED        = true
  INTERPOLATION_DURATION       = 150   # ms

  # ── Heartbeat ───────────────────────────────────────────────────────────────
  HEARTBEAT_INTERVAL           = 5.0   # seconds between heartbeats
  HEARTBEAT_TIMEOUT            = 15.0  # seconds before considering dead

  # ── Debug ───────────────────────────────────────────────────────────────────
  DEBUG_PACKETS  = false
  DEBUG_MOVEMENT = false
  DEBUG_LIFECYCLE = true   # NEW: log bootstrap, scene transitions, dispose
  DEBUG_SPRITES  = true   # NEW: log sprite creation, disposal, viewport
end
