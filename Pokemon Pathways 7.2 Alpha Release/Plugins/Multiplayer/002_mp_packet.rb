#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Client Packet System
#  Packet encoder/decoder matching server binary format
#  Format: [type uint16][length uint16][timestamp uint32][JSON payload]
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

  NAMES = {
    0  => "HANDSHAKE",      1  => "HANDSHAKE_ACK",   2  => "HEARTBEAT",
    3  => "DISCONNECT",      4  => "ERROR",
    10 => "PLAYER_JOIN",     11 => "PLAYER_LEAVE",    12 => "PLAYER_MOVE",
    13 => "PLAYER_POS_SYNC", 14 => "PLAYER_DIR",      15 => "MAP_CHANGE",
    16 => "MAP_PLAYER_LIST", 17 => "PLAYER_SPRITE",   18 => "PLAYER_ACTION",
    30 => "BATTLE_REQUEST",  31 => "BATTLE_ACCEPT",   32 => "BATTLE_DECLINE",
    33 => "BATTLE_START",    34 => "BATTLE_COMMAND",  35 => "BATTLE_RESULT",
    36 => "BATTLE_FORFEIT",
    50 => "TRADE_REQUEST",   51 => "TRADE_ACCEPT",    52 => "TRADE_DECLINE",
    53 => "TRADE_OPEN",      54 => "TRADE_OFFER",     55 => "TRADE_CONFIRM",
    56 => "TRADE_COMPLETE",  57 => "TRADE_CANCEL",
    70 => "CHAT_MESSAGE",    71 => "CHAT_WHISPER",    72 => "CHAT_SYSTEM",
    80 => "PLAYER_DATA",     81 => "PLAYER_PARTY",    82 => "PLAYER_PROFILE"
  }
end

class MP_Packet
  HEADER_SIZE = 8

  attr_reader :type, :timestamp, :payload

  def initialize(type, payload = {})
    @type = type
    @timestamp = (Time.now.to_f * 1000).to_i
    @payload = payload
  end

  def self.decode(data)
    return nil if data.nil? || data.bytesize < HEADER_SIZE

    type = data[0, 2].unpack1('n')
    length = data[2, 2].unpack1('n')
    timestamp = data[4, 4].unpack1('N')

    return nil if data.bytesize < HEADER_SIZE + length

    payload_data = data[HEADER_SIZE, length]
    payload = JSON.parse(payload_data) rescue {}

    packet = new(type, payload)
    packet.instance_variable_set(:@timestamp, timestamp)
    packet
  rescue
    nil
  end

  def encode
    payload_json = @payload.to_json
    length = payload_json.bytesize
    [
      [@type].pack('n'),
      [length].pack('n'),
      [@timestamp].pack('N'),
      payload_json
    ].join
  end

  def type_name
    MP_PacketType::NAMES[@type] || "UNKNOWN(#{@type})"
  end

  def to_s
    "<Packet #{type_name} payload=#{@payload.inspect}>"
  end
end
