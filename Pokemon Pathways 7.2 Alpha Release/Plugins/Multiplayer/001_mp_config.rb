#===============================================================================
#  MP CONFIG v1.2.0
#  TUNED VALUES (changes from v1.1.0):
#    - POSITION_SEND_INTERVAL: 3 -> 60 (was 3 frames = 50ms; now 60 frames = 1s)
#    - INTERPOLATION_DURATION: 50 -> 250 (smooths over ~15 frames at 60 FPS)
#    - VISIBLE_DISTANCE: 20 -> 12 (reduces sprite count in crowded areas)
#    - RECONNECT_MAX_ATTEMPTS: 0 -> 10 (prevents infinite reconnect loops)
#    - Added CHAT_ACTIVATION_KEY for dedicated chat toggle
#    - Added MAX_REMOTE_PLAYERS cap
#    - Added PACKET_MAX_SIZE for security
#===============================================================================

echoln "MP: config loaded"
module MP_ClientConfig
  SERVER_IP   = "127.0.0.1"
  SERVER_PORT = 9000

  RECONNECT_ENABLED            = true
  RECONNECT_BASE_INTERVAL      = 1.0
  RECONNECT_MAX_INTERVAL       = 30.0
  RECONNECT_BACKOFF_MULTIPLIER = 2.0
  RECONNECT_MAX_ATTEMPTS       = 10          # 0 = infinite; now capped

  SEND_INTERVAL                = 0.05
  POSITION_SEND_INTERVAL       = 60          # frames between periodic position sends (~1s @ 60fps)
  HEARTBEAT_INTERVAL           = 5.0         # seconds between heartbeats
  HEARTBEAT_TIMEOUT            = 15.0        # seconds before considering connection dead

  VISIBLE_DISTANCE             = 12          # tiles (was 20; reduces crowd load)
  MAX_REMOTE_PLAYERS           = 32          # cap sprites for performance

  INTERPOLATION_ENABLED        = true
  INTERPOLATION_DURATION       = 250         # ms (was 50; much smoother)

  PACKET_MAX_SIZE              = 65536       # max bytes per packet (security)
  SEND_QUEUE_LIMIT             = 500         # max queued outgoing packets
  SEND_QUEUE_BATCH_SIZE        = 50          # packets drained per tick

  DEBUG_PACKETS                = true
  DEBUG_MOVEMENT               = false

  CHAT_ACTIVATION_KEY          = :A          # Input::A = Shift key (avoids conflict with USE=C/Enter)
  CHAT_MAX_MESSAGES            = 5
  CHAT_FADE_TIME               = 8000        # ms before fade begins
end
echoln "MP: config done"
