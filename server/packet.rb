#===============================================================================
#  Pokemon Pathways Multiplayer - Packet System
<<<<<<< HEAD
#  PHASE 2 v4.0 — Added rank, partner, 2v2 battle packet types
=======
#
#  Binary packet format:
#    [type     : uint16 BE  ] 2 bytes  - packet type constant
#    [length   : uint16 BE  ] 2 bytes  - byte length of JSON payload
#    [timestamp: uint32 BE  ] 4 bytes  - seconds since Unix epoch (NOT milliseconds)
#    [payload  : UTF-8 JSON ] N bytes  - packet body
#
#  FIX: Timestamp was (Time.now.to_f * 1000).to_i (milliseconds), which overflows
#       uint32 (~49 days from epoch). Changed to seconds; client must be updated
#       to match. uint32 seconds is valid until 2106.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
#===============================================================================

require 'json'

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

<<<<<<< HEAD
  # Battle 1v1 (30-36)
=======
  # Battle (30-49)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  BATTLE_REQUEST  = 30
  BATTLE_ACCEPT   = 31
  BATTLE_DECLINE  = 32
  BATTLE_START    = 33
  BATTLE_COMMAND  = 34
  BATTLE_RESULT   = 35
  BATTLE_FORFEIT  = 36

<<<<<<< HEAD
  # Battle 2v2 (37-39)
  BATTLE_2V2_REQUEST = 37
  BATTLE_2V2_ACCEPT  = 38
  BATTLE_2V2_DECLINE = 39

  # Trade (50-57)
=======
  # Trade (50-69)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  TRADE_REQUEST   = 50
  TRADE_ACCEPT    = 51
  TRADE_DECLINE   = 52
  TRADE_OPEN      = 53
  TRADE_OFFER     = 54
  TRADE_CONFIRM   = 55
  TRADE_COMPLETE  = 56
  TRADE_CANCEL    = 57

<<<<<<< HEAD
  # Chat (70-72)
=======
  # Chat (70-79)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  CHAT_MESSAGE    = 70
  CHAT_WHISPER    = 71
  CHAT_SYSTEM     = 72

<<<<<<< HEAD
  # Player Data (80-82)
=======
  # Player Data (80-89)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  PLAYER_DATA     = 80
  PLAYER_PARTY    = 81
  PLAYER_PROFILE  = 82

<<<<<<< HEAD
  # Rank (Phase 2)
  PLAYER_RANK     = 83

  # Partner (Phase 2)
  PARTNER_REQUEST = 90
  PARTNER_ACCEPT  = 91
  PARTNER_DECLINE = 92
  PARTNER_BREAK   = 93
  PARTNER_STATUS  = 94

  NAMES = {
    0  => "HANDSHAKE",           1  => "HANDSHAKE_ACK",      2  => "HEARTBEAT",
    3  => "DISCONNECT",           4  => "ERROR",
    10 => "PLAYER_JOIN",          11 => "PLAYER_LEAVE",       12 => "PLAYER_MOVE",
    13 => "PLAYER_POS_SYNC",      14 => "PLAYER_DIR",         15 => "MAP_CHANGE",
    16 => "MAP_PLAYER_LIST",      17 => "PLAYER_SPRITE",      18 => "PLAYER_ACTION",
    30 => "BATTLE_REQUEST",       31 => "BATTLE_ACCEPT",      32 => "BATTLE_DECLINE",
    33 => "BATTLE_START",         34 => "BATTLE_COMMAND",     35 => "BATTLE_RESULT",
    36 => "BATTLE_FORFEIT",       37 => "BATTLE_2V2_REQUEST", 38 => "BATTLE_2V2_ACCEPT",
    39 => "BATTLE_2V2_DECLINE",
    50 => "TRADE_REQUEST",        51 => "TRADE_ACCEPT",       52 => "TRADE_DECLINE",
    53 => "TRADE_OPEN",           54 => "TRADE_OFFER",        55 => "TRADE_CONFIRM",
    56 => "TRADE_COMPLETE",       57 => "TRADE_CANCEL",
    70 => "CHAT_MESSAGE",         71 => "CHAT_WHISPER",       72 => "CHAT_SYSTEM",
    80 => "PLAYER_DATA",          81 => "PLAYER_PARTY",       82 => "PLAYER_PROFILE",
    83 => "PLAYER_RANK",
    90 => "PARTNER_REQUEST",      91 => "PARTNER_ACCEPT",     92 => "PARTNER_DECLINE",
    93 => "PARTNER_BREAK",        94 => "PARTNER_STATUS"
=======
  # Debug lookup map
  NAMES = {
    0  => "HANDSHAKE",       1  => "HANDSHAKE_ACK",    2  => "HEARTBEAT",
    3  => "DISCONNECT",       4  => "ERROR",
    10 => "PLAYER_JOIN",      11 => "PLAYER_LEAVE",     12 => "PLAYER_MOVE",
    13 => "PLAYER_POS_SYNC",  14 => "PLAYER_DIR",       15 => "MAP_CHANGE",
    16 => "MAP_PLAYER_LIST",  17 => "PLAYER_SPRITE",    18 => "PLAYER_ACTION",
    30 => "BATTLE_REQUEST",   31 => "BATTLE_ACCEPT",    32 => "BATTLE_DECLINE",
    33 => "BATTLE_START",     34 => "BATTLE_COMMAND",   35 => "BATTLE_RESULT",
    36 => "BATTLE_FORFEIT",
    50 => "TRADE_REQUEST",    51 => "TRADE_ACCEPT",     52 => "TRADE_DECLINE",
    53 => "TRADE_OPEN",       54 => "TRADE_OFFER",      55 => "TRADE_CONFIRM",
    56 => "TRADE_COMPLETE",   57 => "TRADE_CANCEL",
    70 => "CHAT_MESSAGE",     71 => "CHAT_WHISPER",     72 => "CHAT_SYSTEM",
    80 => "PLAYER_DATA",      81 => "PLAYER_PARTY",     82 => "PLAYER_PROFILE"
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  }.freeze
end

class MP_Packet
<<<<<<< HEAD
  HEADER_SIZE = 8
=======
  HEADER_SIZE = 8   # type(2) + length(2) + timestamp(4)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  MAX_PAYLOAD = 65535

  attr_reader :type, :timestamp, :payload

  def initialize(type, payload = {})
    @type      = type
<<<<<<< HEAD
    @timestamp = Time.now.to_i
    @payload   = payload
  end

  def self.decode(data)
    return nil if data.nil? || data.bytesize < HEADER_SIZE

    raw = data.b
=======
    @timestamp = Time.now.to_i   # FIX: seconds, not milliseconds - avoids uint32 overflow
    @payload   = payload
  end

  # Decode raw binary data into a packet object.
  # Returns nil on any parse error (never raises).
  def self.decode(data)
    return nil if data.nil? || data.bytesize < HEADER_SIZE

    # FIX: force binary encoding so slice operations work on raw bytes, not characters
    raw = data.b

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    type      = raw[0, 2].unpack1('n')
    length    = raw[2, 2].unpack1('n')
    timestamp = raw[4, 4].unpack1('N')

    return nil if raw.bytesize < HEADER_SIZE + length

<<<<<<< HEAD
    payload_str = raw[HEADER_SIZE, length].force_encoding('UTF-8')
    payload     = JSON.parse(payload_str)
=======
    payload_bytes = raw[HEADER_SIZE, length]
    # Re-encode payload to UTF-8 for JSON parsing
    payload_str   = payload_bytes.force_encoding('UTF-8')
    payload       = JSON.parse(payload_str)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095

    pkt = new(type, payload)
    pkt.instance_variable_set(:@timestamp, timestamp)
    pkt
  rescue JSON::ParserError, Encoding::UndefinedConversionError
    nil
  rescue => e
    $stderr.puts "[PACKET] Unexpected decode error: #{e.class}: #{e.message}"
    nil
  end

<<<<<<< HEAD
  def encode
    payload_json = @payload.to_json
    length = payload_json.bytesize
    if length > MAX_PAYLOAD
      $stderr.puts "[PACKET] WARNING: payload for type #{@type} exceeds #{MAX_PAYLOAD} bytes, truncating"
      payload_json = { error: "payload_too_large" }.to_json
      length = payload_json.bytesize
    end
    [[@type, length].pack('nn'), [@timestamp].pack('N'), payload_json].join.b
=======
  # Encode packet to wire format (always returns a binary String).
  def encode
    payload_json = @payload.to_json
    length = payload_json.bytesize
    # Clamp oversized payloads rather than letting pack raise
    if length > MAX_PAYLOAD
      $stderr.puts "[PACKET] WARNING: payload for type #{@type} exceeds #{MAX_PAYLOAD} bytes, truncating"
      payload_json = {error: "payload_too_large"}.to_json
      length = payload_json.bytesize
    end

    [
      [@type, length].pack('nn'),
      [@timestamp].pack('N'),
      payload_json
    ].join.b   # binary encoding on output
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  end

  def type_name
    MP_PacketType::NAMES[@type] || "UNKNOWN(#{@type})"
  end

  def to_s
    "<Packet #{type_name} ts=#{@timestamp} payload=#{@payload.inspect}>"
  end
end
