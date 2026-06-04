#===============================================================================
#  Pokemon Pathways Multiplayer - Rank Service
#  PHASE 2 — Validates and broadcasts PLAYER_RANK packets
#
#  The client sends PLAYER_RANK whenever its local switch state changes.
#  The server:
#    1. Validates the rank name against the whitelist
#    2. Stores rank + tier on the MP_Client object
#    3. Broadcasts the change to all players on the same map
#    4. Includes rank in every PLAYER_JOIN and MAP_PLAYER_LIST payload
#       (that responsibility lives in room_manager.rb)
#
#  Security note:
#    Ranks are client-reported — we validate the string but cannot verify
#    that the game switches are genuinely set. Anomaly detection (e.g. a
#    player claiming Monarch tier immediately on connect) is noted as a
#    future enhancement; for now, whitelist enforcement prevents garbage data.
#===============================================================================

require_relative '../config'
require_relative '../packet'

class RankService
  # Numeric tier map — higher = stronger. Mirrors client MP_RankSystem::RANK_TIER.
  TIER_MAP = {
    "D"       => 0,
    "C"       => 1,
    "B"       => 2,
    "A"       => 3,
    "S"       => 4,
    "SS"      => 5,
    "Monarch" => 6
  }.freeze

  def initialize(server)
    @server = server
  end

  # ─── Packet dispatch ──────────────────────────────────────────────────────────

  def handle_packet(client, packet)
    case packet.type
    when MP_PacketType::PLAYER_RANK
      handle_rank_update(client, packet)
    end
  end

  # ─── Public helpers ───────────────────────────────────────────────────────────

  # Returns the canonical tier integer for a rank string (0 if unknown).
  def tier_for(rank_name)
    TIER_MAP[rank_name.to_s] || 0
  end

  # Validates and normalises a rank string from untrusted input.
  def sanitize_rank(rank_name)
    r = rank_name.to_s.strip
    MP_ServerConfig::VALID_RANKS.include?(r) ? r : "D"
  end

  private

  def handle_rank_update(client, packet)
    raw_rank = packet.payload["rank"]
    rank     = sanitize_rank(raw_rank)
    tier     = tier_for(rank)

    # Reject obviously impossible claims (e.g. tier mismatches).
    # Client sends tier too — we recalculate from our own map so it can't be spoofed.
    if rank != raw_rank
      puts "[RANK] #{client.player_name} sent invalid rank '#{raw_rank}' — clamped to '#{rank}'"
    end

    return if client.rank == rank && client.rank_tier == tier   # no-op

    client.rank      = rank
    client.rank_tier = tier

    # Broadcast to everyone on the same map (including the sender, so their
    # own badge on other clients updates consistently)
    return unless client.map_id

    @server.broadcast_to_map(client.map_id,
      MP_Packet.new(MP_PacketType::PLAYER_RANK, {
        "client_id" => client.id,
        "rank"      => rank,
        "tier"      => tier
      })
    )

    puts "[RANK] #{client.player_name} => #{rank} (tier #{tier})"
  end
end
