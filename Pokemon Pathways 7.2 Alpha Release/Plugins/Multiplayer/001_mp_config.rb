# MP Config
echoln "MP: config loaded"
module MP_ClientConfig
  SERVER_IP   = "127.0.0.1"
  SERVER_PORT = 9000
  RECONNECT_ENABLED            = true
  RECONNECT_BASE_INTERVAL      = 1.0
  RECONNECT_MAX_INTERVAL       = 30.0
  RECONNECT_BACKOFF_MULTIPLIER = 2.0
  RECONNECT_MAX_ATTEMPTS       = 0
  SEND_INTERVAL                = 0.05
  POSITION_SEND_INTERVAL       = 3
  VISIBLE_DISTANCE             = 20
  INTERPOLATION_ENABLED        = true
  INTERPOLATION_DURATION       = 50
  DEBUG_PACKETS                = true
  DEBUG_MOVEMENT               = false
end
echoln "MP: config done"
