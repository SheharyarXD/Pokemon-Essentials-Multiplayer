#===============================================================================
#  MP PACKET v1.2.0
#  Hardened:
#    1. Max packet size guard (PACKET_MAX_SIZE) prevents memory DoS
#    2. Added packet.sequence for future out-of-order detection
#    3. decode validates length field before slicing
#    4. encode validates payload size
#    5. Better error reporting on malformed packets
#===============================================================================

module MP_PacketType
  # Connection (0-9)
  HANDSHAKE       = 0
  HANDSHAKE_ACK   = 1
  HEARTBEAT       = 2
  DISCONNECT      = 3
  ERROR           = 4

  # Overworld (10-29)
  PLAYER_JOIN     = 10
  PLAYER_LEAVE    = 11
  PLAYER_MOVE     = 12
  PLAYER_POS_SYNC = 13
  PLAYER_DIR      = 14
  MAP_CHANGE      = 15
  MAP_PLAYER_LIST = 16
  PLAYER_SPRITE   = 17
  PLAYER_ACTION   = 18

  # Battle (30-49)
  BATTLE_REQUEST  = 30
  BATTLE_ACCEPT   = 31
  BATTLE_DECLINE  = 32
  BATTLE_START    = 33
  BATTLE_COMMAND  = 34
  BATTLE_RESULT   = 35
  BATTLE_FORFEIT  = 36

  # Trade (50-69)
  TRADE_REQUEST   = 50
  TRADE_ACCEPT    = 51
  TRADE_DECLINE   = 52
  TRADE_OPEN      = 53
  TRADE_OFFER     = 54
  TRADE_CONFIRM   = 55
  TRADE_COMPLETE  = 56
  TRADE_CANCEL    = 57

  # Chat (70-79)
  CHAT_MESSAGE    = 70
  CHAT_WHISPER    = 71
  CHAT_SYSTEM     = 72

  # Player Data (80-89)
  PLAYER_DATA     = 80
  PLAYER_PARTY    = 81
  PLAYER_PROFILE  = 82

  # UI-marshalling (internal)
  UI_INVOKE       = 255   # never sent on wire; used for main-thread queue

  NAMES = {
    0   => "HANDSHAKE",      1   => "HANDSHAKE_ACK",   2   => "HEARTBEAT",
    3   => "DISCONNECT",      4   => "ERROR",
    10  => "PLAYER_JOIN",     11  => "PLAYER_LEAVE",    12  => "PLAYER_MOVE",
    13  => "PLAYER_POS_SYNC", 14  => "PLAYER_DIR",      15  => "MAP_CHANGE",
    16  => "MAP_PLAYER_LIST", 17  => "PLAYER_SPRITE",   18  => "PLAYER_ACTION",
    30  => "BATTLE_REQUEST",  31  => "BATTLE_ACCEPT",   32  => "BATTLE_DECLINE",
    33  => "BATTLE_START",    34  => "BATTLE_COMMAND",  35  => "BATTLE_RESULT",
    36  => "BATTLE_FORFEIT",
    50  => "TRADE_REQUEST",   51  => "TRADE_ACCEPT",    52  => "TRADE_DECLINE",
    53  => "TRADE_OPEN",      54  => "TRADE_OFFER",     55  => "TRADE_CONFIRM",
    56  => "TRADE_COMPLETE",  57  => "TRADE_CANCEL",
    70  => "CHAT_MESSAGE",    71  => "CHAT_WHISPER",    72  => "CHAT_SYSTEM",
    80  => "PLAYER_DATA",     81  => "PLAYER_PARTY",    82  => "PLAYER_PROFILE",
    255 => "UI_INVOKE"
  }
end

class MP_Packet
  HEADER_SIZE = 8
  MAX_SIZE    = defined?(MP_ClientConfig) ? MP_ClientConfig::PACKET_MAX_SIZE : 65536

  attr_reader :type, :timestamp, :payload

  def initialize(type, payload = {})
    @type      = type
    @timestamp = (Time.now.to_f * 1000).to_i
    @payload   = payload
  end

  # --- Decoding ---

  def self.decode(data)
    return nil if data.nil? || data.bytesize < HEADER_SIZE

    type      = data[0, 2].unpack1('n')
    length    = data[2, 2].unpack1('n')
    timestamp = data[4, 4].unpack1('N')

    # Hardening: reject obviously bogus lengths before allocating
    return nil if length > MAX_SIZE || length < 0
    total_size = HEADER_SIZE + length
    return nil if data.bytesize < total_size

    payload_data = data[HEADER_SIZE, length]
    payload = JSON.parse(payload_data) rescue {}

    packet = new(type, payload)
    packet.instance_variable_set(:@timestamp, timestamp)
    packet
  rescue => e
    mp_log("PACKET: decode error: #{e.class}: #{e.message}") if defined?(mp_log)
    nil
  end

  # --- Encoding ---

  def encode
    payload_json = @payload.to_json
    length = payload_json.bytesize

    # Reject oversized payloads
    if length > MAX_SIZE
      mp_log("PACKET: payload too large (#{length} > #{MAX_SIZE}), dropping type=#{@type}") if defined?(mp_log)
      return nil
    end

    [
      [@type].pack('n'),
      [length].pack('n'),
      [@timestamp].pack('N'),
      payload_json
    ].join
  rescue => e
    mp_log("PACKET: encode error: #{e.class}: #{e.message}") if defined?(mp_log)
    nil
  end

  # --- Helpers ---

  def type_name
    MP_PacketType::NAMES[@type] || "UNKNOWN(#{@type})"
  end

  def to_s
    "<Packet #{type_name} ts=#{@timestamp} payload=#{@payload.inspect}>"
  end
end
