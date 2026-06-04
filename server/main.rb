#!/usr/bin/env ruby
#===============================================================================
#  Pokemon Pathways Multiplayer Server - Entry Point
#  PHASE 2 v4.0 — Requires rank_service and partner_service
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

puts "[SERVER] Starting Pokemon Pathways Multiplayer Server (Phase 2)..."
puts "[SERVER] Ruby version : #{RUBY_VERSION}"
puts "[SERVER] Server root  : #{SERVER_ROOT}"

$game_server = GameServer.new
$mp_server_shutdown_requested = false

["INT", "TERM"].each do |sig|
  begin
    trap(sig) do
      $mp_server_shutdown_requested = true
      STDERR.puts "\n[SERVER] #{sig} received — shutdown scheduled (finishing this tick)..."
    end
  rescue ArgumentError
    # Unsupported signal on this OS
  end
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
