#===============================================================================
#  Pokemon Pathways Multiplayer - Partner Service
#  PHASE 2 — Partnership requests, status, break, disconnect cleanup
#
#  A partnership is a named pairing of two client IDs that persists until:
#    * Either player sends PARTNER_BREAK
#    * Either player disconnects
#    * A new partnership request replaces it (server rejects if already partnered)
#
#  Partnerships are NOT persisted to disk — they are session-scoped.
#
#  Packet flow:
#    Requester --PARTNER_REQUEST--> Server --PARTNER_REQUEST--> Target
#    Target    --PARTNER_ACCEPT --> Server --PARTNER_STATUS (formed)--> Both
#    Target    --PARTNER_DECLINE-> Server --PARTNER_STATUS (declined)--> Requester
#    Either    --PARTNER_BREAK  --> Server --PARTNER_BREAK--> Other
#              (disconnect)        Server --PARTNER_BREAK--> Other
#
#  Validation enforced here:
#    * Both players must be on the same map
#    * Neither player may already have a partner
#    * The request must still be pending when ACCEPT arrives (TTL check)
#    * The acceptor must be the intended target
#===============================================================================

require_relative '../config'
require_relative '../packet'

# ─── PartnerRequest ──────────────────────────────────────────────────────────

PartnerRequest = Struct.new(:id, :requester, :target, :expires_at)

# ─── PartnerService ──────────────────────────────────────────────────────────

class PartnerService
  def initialize(server)
    @server   = server
    @requests = {}    # request_id => PartnerRequest
    @partners = {}    # client_id  => partner_client_id  (both directions stored)
    @mutex    = Mutex.new
  end

  # ─── Tick (expire stale requests) ────────────────────────────────────────────

  def update(_tick_count)
    expired = @mutex.synchronize do
      @requests.select { |_, r| Time.now > r.expires_at }.values
    end
    expired.each { |r| expire_request(r) }
  end

  # ─── Packet dispatch ─────────────────────────────────────────────────────────

  def handle_packet(client, packet)
    case packet.type
    when MP_PacketType::PARTNER_REQUEST then handle_partner_request(client, packet)
    when MP_PacketType::PARTNER_ACCEPT  then handle_partner_accept(client, packet)
    when MP_PacketType::PARTNER_DECLINE then handle_partner_decline(client, packet)
    when MP_PacketType::PARTNER_BREAK   then handle_partner_break(client, packet)
    end
  end

  # ─── Disconnect cleanup (called from MP_Client#disconnect) ───────────────────

  def handle_disconnect(client)
    # Cancel any pending outbound request from this client
    cancel_pending_requests_for(client)
    # Dissolve active partnership
    dissolve_partnership(client, notify_other: true, reason: "disconnect")
  end

  # ─── Public accessors ────────────────────────────────────────────────────────

  def partner_of(client_id)
    partner_id = @mutex.synchronize { @partners[client_id] }
    return nil unless partner_id
    @server.clients.find(partner_id)
  end

  def partners?(client_id_a, client_id_b)
    @mutex.synchronize { @partners[client_id_a] == client_id_b }
  end

  private

  # ─── PARTNER_REQUEST ─────────────────────────────────────────────────────────

  def handle_partner_request(client, packet)
    target_id = packet.payload["target_id"]
    return unless target_id

    target = @server.clients.find(target_id)
    unless target
      return client.send_packet(error("Player not found"))
    end

    return client.send_packet(error("Cannot partner with yourself")) if target.id == client.id

    # Same-map check
    unless client.map_id && client.map_id == target.map_id
      return client.send_packet(error("#{target.player_name} is not on the same map"))
    end

    # Distance check
    dx = client.pos_x - target.pos_x
    dy = client.pos_y - target.pos_y
    max = MP_ServerConfig::PARTNER_MAX_DISTANCE
    if (dx * dx + dy * dy) > (max * max)
      return client.send_packet(error("#{target.player_name} is too far away"))
    end

    # Already partnered?
    already_partnered = @mutex.synchronize do
      @partners.key?(client.id) || @partners.key?(target.id)
    end
    if already_partnered
      return client.send_packet(error("One or both players already have a partner"))
    end

    request = @mutex.synchronize do
      req = PartnerRequest.new(
        generate_id,
        client,
        target,
        Time.now + MP_ServerConfig::PARTNER_REQUEST_TTL
      )
      @requests[req.id] = req
      req
    end

    target.send_packet(MP_Packet.new(MP_PacketType::PARTNER_REQUEST, {
      "request_id" => request.id,
      "from_id"    => client.id,
      "from_name"  => client.player_name
    }))

    puts "[PARTNER] #{client.player_name} requested partnership with #{target.player_name}"
  end

  # ─── PARTNER_ACCEPT ──────────────────────────────────────────────────────────

  def handle_partner_accept(client, packet)
    request_id = packet.payload["request_id"]
    request    = @mutex.synchronize { @requests[request_id] }

    unless request
      return client.send_packet(error("Partner request not found or expired"))
    end

    # Security: only the intended target may accept
    unless request.target.id == client.id
      return client.send_packet(error("This request was not addressed to you"))
    end

    requester = request.requester

    # Re-validate: both still online and on the same map
    unless requester && !requester.disconnected?
      @mutex.synchronize { @requests.delete(request_id) }
      return client.send_packet(error("The requester is no longer online"))
    end

    unless client.map_id && client.map_id == requester.map_id
      @mutex.synchronize { @requests.delete(request_id) }
      return client.send_packet(error("You are no longer on the same map"))
    end

    # Neither may already have a partner (could have changed since request)
    already = @mutex.synchronize { @partners.key?(client.id) || @partners.key?(requester.id) }
    if already
      @mutex.synchronize { @requests.delete(request_id) }
      return client.send_packet(error("One or both players already have a partner"))
    end

    # Form the partnership
    @mutex.synchronize do
      @requests.delete(request_id)
      @partners[client.id]     = requester.id
      @partners[requester.id]  = client.id
      requester.partner_id     = client.id
      client.partner_id        = requester.id
    end

    notify_partnership_formed(requester, client)
    puts "[PARTNER] Partnership formed: #{requester.player_name} <-> #{client.player_name}"
  end

  # ─── PARTNER_DECLINE ─────────────────────────────────────────────────────────

  def handle_partner_decline(client, packet)
    request_id = packet.payload["request_id"]
    request    = @mutex.synchronize { @requests.delete(request_id) }
    return unless request

    request.requester.send_packet(MP_Packet.new(MP_PacketType::PARTNER_STATUS, {
      "declined"    => true,
      "from_name"   => client.player_name
    }))

    puts "[PARTNER] #{client.player_name} declined partnership from #{request.requester.player_name}"
  end

  # ─── PARTNER_BREAK ───────────────────────────────────────────────────────────

  def handle_partner_break(client, _packet)
    dissolve_partnership(client, notify_other: true, reason: "break")
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def notify_partnership_formed(player_a, player_b)
    # Each player receives their own PARTNER_STATUS with the other's details
    [
      [player_a, player_b],
      [player_b, player_a]
    ].each do |receiver, partner|
      party_data = build_party_summary(partner)
      receiver.send_packet(MP_Packet.new(MP_PacketType::PARTNER_STATUS, {
        "formed"        => true,
        "partner_id"    => partner.id,
        "partner_name"  => partner.player_name,
        "partner_party" => party_data
      }))
    end
  end

  # Sends a lightweight party summary (species/level/name only) from
  # the client's party_display field. A full party sync would require
  # PLAYER_PARTY data stored on the client — party_display holds the
  # lead Pokémon already; for 2v2 we need all three active slots.
  # The server stores whatever the client last sent via PLAYER_PARTY.
  def build_party_summary(client)
    return [] unless client.party_display
    # party_display is the LEAD pokemon only from PLAYER_PARTY handler.
    # Return it wrapped in an array so the client gets at least one entry.
    [client.party_display]
  end

  def dissolve_partnership(client, notify_other:, reason:)
    partner_id = @mutex.synchronize do
      pid = @partners.delete(client.id)
      @partners.delete(pid) if pid
      client.partner_id = nil
      pid
    end

    return unless partner_id

    partner = @server.clients.find(partner_id)
    if partner
      partner.partner_id = nil
      if notify_other
        partner.send_packet(MP_Packet.new(MP_PacketType::PARTNER_BREAK, {
          "reason"       => reason,
          "former_partner" => client.player_name
        }))
      end
    end

    puts "[PARTNER] Partnership dissolved (#{reason}): #{client.player_name} / #{partner&.player_name || partner_id}"
  end

  def cancel_pending_requests_for(client)
    to_remove = @mutex.synchronize do
      @requests.select { |_, r| r.requester.id == client.id || r.target.id == client.id }
    end
    to_remove.each { |_, r| expire_request(r) }
  end

  def expire_request(request)
    @mutex.synchronize { @requests.delete(request.id) }
    # Notify target if they haven't responded yet
    if !request.target.disconnected?
      request.target.send_packet(MP_Packet.new(MP_PacketType::CHAT_SYSTEM, {
        "message" => "Partner request from #{request.requester.player_name} expired."
      })) rescue nil
    end
  end

  def generate_id
    rand(36**8).to_s(36).upcase
  end

  def error(message)
    MP_Packet.new(MP_PacketType::ERROR, { "message" => message })
  end
end
