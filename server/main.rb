#!/usr/bin/env ruby
#===============================================================================
#  Pokemon Pathways Multiplayer Server - Entry Point
#  Loads all components, starts the server, handles SIGINT/SIGTERM gracefully.
#===============================================================================

require 'socket'
require 'json'
require 'thread'
require 'fileutils'

SERVER_ROOT = File.expand_path(File.dirname(__FILE__))

require_relative 'config'
require_relative 'packet'
require_relative 'client'
require_relative 'client_manager'
require_relative 'room_manager'
require_relative 'game_server'

# Ensure data directories exist before the store initialises
FileUtils.mkdir_p(MP_ServerConfig::PLAYERS_DIR)
FileUtils.mkdir_p(MP_ServerConfig::BACKUP_DIR)

puts "[SERVER] Starting Pokemon Pathways Multiplayer Server..."
puts "[SERVER] Ruby version : #{RUBY_VERSION}"
puts "[SERVER] Server root  : #{SERVER_ROOT}"

$game_server = GameServer.new

trap("SIGINT") do
  puts "\n[SERVER] SIGINT received - shutting down..."
  $game_server.stop
  exit 0
end

trap("SIGTERM") do
  puts "\n[SERVER] SIGTERM received - shutting down..."
  $game_server.stop
  exit 0
end

begin
  $game_server.start
rescue Interrupt
  puts "\n[SERVER] Interrupted by user"
  $game_server.stop
rescue => e
  puts "[FATAL] Uncaught error: #{e.class}: #{e.message}"
  puts e.backtrace.first(10).join("\n")
  $game_server.stop
  exit 1
end
