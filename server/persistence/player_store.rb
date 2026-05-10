#===============================================================================
#  Pokemon Pathways Multiplayer - Player Data Store
#  JSON file-based player data storage with periodic backup
#===============================================================================

require 'json'
require 'fileutils'
require_relative '../config'

class PlayerStore
  def initialize
    ensure_data_dir
  end

  def ensure_data_dir
    FileUtils.mkdir_p(MP_ServerConfig::DATA_DIR)
    FileUtils.mkdir_p(MP_ServerConfig::BACKUP_DIR)
  end

  def player_file_path(client_id)
    "#{MP_ServerConfig::DATA_DIR}/#{client_id}.json"
  end

  def backup_file_path(client_id)
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    "#{MP_ServerConfig::BACKUP_DIR}/#{client_id}_#{timestamp}.json"
  end

  def save_player(client)
    return unless client.authenticated
    data = {
      id: client.id,
      name: client.player_name,
      sprite_name: client.sprite_name,
      outfit: client.outfit,
      last_map_id: client.map_id,
      last_x: client.pos_x,
      last_y: client.pos_y,
      last_direction: client.direction,
      party_display: client.party_display,
      saved_at: Time.now.to_i
    }

    filepath = player_file_path(client.id)
    temp_path = "#{filepath}.tmp"

    begin
      File.write(temp_path, JSON.pretty_generate(data))
      File.rename(temp_path, filepath)
    rescue => e
      puts "[STORE] Failed to save player #{client.id}: #{e.message}"
    end

    # Periodic backup (every 5 minutes per player)
    backup_player(client.id, data)
  end

  def load_player(client)
    filepath = player_file_path(client.id)
    return unless File.exist?(filepath)

    begin
      data = JSON.parse(File.read(filepath), symbolize_names: true)
      client.sprite_name = data[:sprite_name] || client.sprite_name
      client.outfit = data[:outfit] || 0
      client.party_display = data[:party_display]
      puts "[STORE] Loaded player data for #{client.player_name}"
    rescue => e
      puts "[STORE] Failed to load player #{client.id}: #{e.message}"
    end
  end

  def backup_player(client_id, data = nil)
    return unless data || File.exist?(player_file_path(client_id))
    data ||= JSON.parse(File.read(player_file_path(client_id)), symbolize_names: true)

    # Only backup if last backup is older than 5 minutes
    recent_backups = Dir.glob("#{MP_ServerConfig::BACKUP_DIR}/#{client_id}_*.json")
    if !recent_backups.empty?
      last_backup_time = File.mtime(recent_backups.sort.last)
      return if Time.now - last_backup_time < MP_ServerConfig::BACKUP_INTERVAL
    end

    begin
      File.write(backup_file_path(client_id), JSON.pretty_generate(data))
    rescue => e
      puts "[STORE] Failed to backup player #{client_id}: #{e.message}"
    end
  end

  def final_backup
    puts "[STORE] Performing final backup..."
    ensure_data_dir
  end
end
