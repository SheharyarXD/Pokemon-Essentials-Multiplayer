#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Client Configuration
#  Client-side settings: server IP, port, reconnect behavior
#===============================================================================

module MP_ClientConfig
  # Server connection settings
  # Change SERVER_IP to the IP address of your multiplayer server
  SERVER_IP = "127.0.0.1"
  SERVER_PORT = 9000

  # Reconnection settings
  RECONNECT_ENABLED = true
  RECONNECT_BASE_INTERVAL = 1.0    # Starting reconnect delay in seconds
  RECONNECT_MAX_INTERVAL = 30.0    # Maximum reconnect delay
  RECONNECT_BACKOFF_MULTIPLIER = 2.0
  RECONNECT_MAX_ATTEMPTS = 0       # 0 = infinite attempts

  # Timing settings
  SEND_INTERVAL = 0.05             # Send queued packets every 50ms
  POSITION_SEND_INTERVAL = 3       # Send position every N frames

  # Game settings
  VISIBLE_DISTANCE = 20            # Tiles to show other players
  INTERPOLATION_ENABLED = true
  INTERPOLATION_DURATION = 50      # ms to interpolate between positions

  # Debug
  DEBUG_PACKETS = false
  DEBUG_MOVEMENT = false
end
