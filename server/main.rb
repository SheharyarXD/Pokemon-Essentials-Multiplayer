#!/usr/bin/env ruby
#===============================================================================
#  Pokemon Pathways Multiplayer Server - Entry Point
#  Loads all server modules, starts the game server, handles SIGINT gracefully
#===============================================================================

require 'socket'
require 'json'
require 'thread'
require 'fileutils'

# Determine server root directory
SERVER_ROOT = File.expand_path(File.dirname(__FILE__))

# Load all server components
require_relative 'config'
require_relative 'packet'
require_relative 'client'
require_relative 'client_manager'
require_relative 'room_manager'
require_relative 'game_server'

# Create data directories
FileUtils.mkdir_p(MP_ServerConfig::DATA_DIR)
FileUtils.mkdir_p(MP_ServerConfig::BACKUP_DIR)

puts "[SERVER] Starting Pokemon Pathways Multiplayer Server..."
puts "[SERVER] Ruby version: #{RUBY_VERSION}"
puts "[SERVER] Server root: #{SERVER_ROOT}"

# Create and start the game server
$game_server = GameServer.new

# Handle graceful shutdown
trap("SIGINT") do
  puts "\n[SERVER] Received SIGINT, shutting down..."
  $game_server.stop if $game_server
  exit 0
end

trap("SIGTERM") do
  puts "\n[SERVER] Received SIGTERM, shutting down..."
  $game_server.stop if $game_server
  exit 0
end

# Start the server (blocks)
begin
  $game_server.start
rescue Interrupt
  puts "\n[SERVER] Interrupted by user"
  $game_server.stop if $game_server
rescue => e
  puts "[FATAL] Uncaught error: #{e.class}: #{e.message}"
  puts e.backtrace.first(10).join("\n")
  $game_server.stop if $game_server
  exit 1
end
