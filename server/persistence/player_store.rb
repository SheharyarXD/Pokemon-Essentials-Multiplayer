#===============================================================================
#  Pokemon Pathways Multiplayer - Player Data Store
#  REMOTE SKIN SYNC v3.0 — Persist character_hue, trainer_type
#===============================================================================

require 'json'
require 'fileutils'
require_relative '../config'

class PlayerStore
  def initialize
    ensure_data_dirs
  end

  def player_file_path(player_name)
    safe = sanitize_filename(player_name)
    "#{MP_ServerConfig::PLAYERS_DIR}/#{safe}.json"
  end

  def backup_file_path(player_name)
    safe      = sanitize_filename(player_name)
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    "#{MP_ServerConfig::BACKUP_DIR}/#{safe}_#{timestamp}.json"
  end

  def save_player(client)
    return unless client.authenticated && client.player_name

    data = {
      "name"           => client.player_name,
      "sprite_name"    => client.sprite_name,
      "character_hue"  => client.character_hue,
      "trainer_type"   => client.trainer_type,
      "outfit"         => client.outfit,
      "last_map_id"    => client.map_id,
      "last_x"         => client.pos_x,
      "last_y"         => client.pos_y,
      "last_direction" => client.direction,
      "party_display"  => client.party_display,
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

  def load_player(client)
    return unless client.player_name
    filepath = player_file_path(client.player_name)
    return unless File.exist?(filepath)

    begin
      data = JSON.parse(File.read(filepath))
      client.sprite_name   = data["sprite_name"]    if data["sprite_name"]
      client.character_hue = data["character_hue"].to_i if data["character_hue"]
      client.trainer_type  = data["trainer_type"].to_s if data["trainer_type"]
      client.outfit        = data["outfit"]          unless data["outfit"].nil?
      client.party_display = data["party_display"]
      puts "[STORE] Loaded saved data for #{client.player_name}"
    rescue => e
      puts "[STORE] Failed to load player #{client.player_name}: #{e.message}"
    end
  end

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

    existing = Dir.glob("#{MP_ServerConfig::BACKUP_DIR}/#{safe}_*.json").sort
    to_delete = existing[0...(existing.size - MP_ServerConfig::MAX_BACKUPS_PER_PLAYER)]
    to_delete.each { |f| File.delete(f) rescue nil }
  end

  def sanitize_filename(name)
    name.gsub(/[^a-zA-Z0-9_\-]/, '_')[0, 64]
  end
end
