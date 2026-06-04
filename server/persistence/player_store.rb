#===============================================================================
#  Pokemon Pathways Multiplayer - Player Data Store
<<<<<<< HEAD
#  PHASE 2 v4.0 — Persist rank and rank_tier
=======
#
#  Persists player appearance and last-known position between sessions.
#  Uses atomic write (write to .tmp then rename) for crash safety.
#
#  FIXES vs original:
#   * CRITICAL: Player data was saved under the client's random session ID,
#     which changes on every connection. Reconnecting players never recovered
#     their saved data. Data is now keyed by sanitized player name.
#   * DISK GROWTH: backup_player created a new timestamped file every 5 minutes
#     with no cleanup. Old backups are now pruned to MAX_BACKUPS_PER_PLAYER.
#   * SAFETY: load_player now matches by name, so the file must exist
#     and belong to this player name.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
#===============================================================================

require 'json'
require 'fileutils'
require_relative '../config'

class PlayerStore
  def initialize
    ensure_data_dirs
  end

<<<<<<< HEAD
=======
  # ─── Path helpers ────────────────────────────────────────────────────────────

  # Player data files are named after the sanitized player name, not the session ID.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def player_file_path(player_name)
    safe = sanitize_filename(player_name)
    "#{MP_ServerConfig::PLAYERS_DIR}/#{safe}.json"
  end

  def backup_file_path(player_name)
    safe      = sanitize_filename(player_name)
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    "#{MP_ServerConfig::BACKUP_DIR}/#{safe}_#{timestamp}.json"
  end

<<<<<<< HEAD
=======
  # ─── Save ────────────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def save_player(client)
    return unless client.authenticated && client.player_name

    data = {
      "name"           => client.player_name,
      "sprite_name"    => client.sprite_name,
<<<<<<< HEAD
      "character_hue"  => client.character_hue,
      "trainer_type"   => client.trainer_type,
=======
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
      "outfit"         => client.outfit,
      "last_map_id"    => client.map_id,
      "last_x"         => client.pos_x,
      "last_y"         => client.pos_y,
      "last_direction" => client.direction,
      "party_display"  => client.party_display,
<<<<<<< HEAD
      # Phase 2
      "rank"           => client.rank,
      "rank_tier"      => client.rank_tier,
=======
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
      "saved_at"       => Time.now.to_i
    }

    filepath  = player_file_path(client.player_name)
    temp_path = "#{filepath}.tmp"

    begin
      File.write(temp_path, JSON.pretty_generate(data))
      File.rename(temp_path, filepath)
    rescue => e
      puts "[STORE] Failed to save player #{client.player_name}: #{e.message}"
      File.delete(temp_path) rescue nil
      return
    end

    maybe_backup(client.player_name, data)
  end

<<<<<<< HEAD
=======
  # ─── Load ────────────────────────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def load_player(client)
    return unless client.player_name
    filepath = player_file_path(client.player_name)
    return unless File.exist?(filepath)

    begin
      data = JSON.parse(File.read(filepath))
<<<<<<< HEAD
      client.sprite_name   = data["sprite_name"]        if data["sprite_name"]
      client.character_hue = data["character_hue"].to_i if data["character_hue"]
      client.trainer_type  = data["trainer_type"].to_s  if data["trainer_type"]
      client.outfit        = data["outfit"]              unless data["outfit"].nil?
      client.party_display = data["party_display"]
      # Phase 2 — validate loaded rank against whitelist
      if data["rank"]
        loaded_rank     = data["rank"].to_s
        client.rank     = MP_ServerConfig::VALID_RANKS.include?(loaded_rank) ? loaded_rank : "D"
        client.rank_tier= data["rank_tier"].to_i
      end
      puts "[STORE] Loaded saved data for #{client.player_name} (rank: #{client.rank})"
=======
      client.sprite_name   = data["sprite_name"]    if data["sprite_name"]
      client.outfit        = data["outfit"]          unless data["outfit"].nil?
      client.party_display = data["party_display"]
      puts "[STORE] Loaded saved data for #{client.player_name}"
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    rescue => e
      puts "[STORE] Failed to load player #{client.player_name}: #{e.message}"
    end
  end

<<<<<<< HEAD
=======
  # ─── Final backup on shutdown ────────────────────────────────────────────────

>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def final_backup
    puts "[STORE] Performing final backup of all player files..."
    ensure_data_dirs
    Dir.glob("#{MP_ServerConfig::PLAYERS_DIR}/*.json").each do |f|
      begin
        data = JSON.parse(File.read(f))
        name = data["name"]
        next unless name
        File.write(backup_file_path(name), File.read(f))
      rescue => e
        puts "[STORE] Final backup failed for #{f}: #{e.message}"
      end
    end
  end

  private

  def ensure_data_dirs
    FileUtils.mkdir_p(MP_ServerConfig::PLAYERS_DIR)
    FileUtils.mkdir_p(MP_ServerConfig::BACKUP_DIR)
  end

<<<<<<< HEAD
=======
  # Write a backup only if the last backup is older than BACKUP_INTERVAL,
  # then prune old backups beyond MAX_BACKUPS_PER_PLAYER.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def maybe_backup(player_name, data)
    safe     = sanitize_filename(player_name)
    existing = Dir.glob("#{MP_ServerConfig::BACKUP_DIR}/#{safe}_*.json").sort

    if existing.any?
      last_time = File.mtime(existing.last)
      return if Time.now - last_time < MP_ServerConfig::BACKUP_INTERVAL
    end

    begin
      File.write(backup_file_path(player_name), JSON.pretty_generate(data))
    rescue => e
      puts "[STORE] Failed to write backup for #{player_name}: #{e.message}"
      return
    end

<<<<<<< HEAD
=======
    # FIX: Prune old backups so disk doesn't grow unboundedly
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    existing = Dir.glob("#{MP_ServerConfig::BACKUP_DIR}/#{safe}_*.json").sort
    to_delete = existing[0...(existing.size - MP_ServerConfig::MAX_BACKUPS_PER_PLAYER)]
    to_delete.each { |f| File.delete(f) rescue nil }
  end

<<<<<<< HEAD
=======
  # Strip characters unsafe for filenames
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def sanitize_filename(name)
    name.gsub(/[^a-zA-Z0-9_\-]/, '_')[0, 64]
  end
end
