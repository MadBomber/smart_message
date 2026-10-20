#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# File Watching Demo
# 
# This example demonstrates SmartMessage's FileTransport file watching capabilities.
# It shows how to monitor files for changes and automatically process new content.

require_relative '../../lib/smart_message'
require 'tempfile'
require 'fileutils'

# Define message classes
Dir.mkdir('messages') unless Dir.exist?('messages')

class LogEntry < SmartMessage::Base
  property :timestamp, required: true
  property :level, required: true
  property :message, required: true
  property :source_file, required: true
  
  from 'file_watching_demo'
end

class ConfigChange < SmartMessage::Base
  property :setting, required: true
  property :old_value
  property :new_value, required: true
  property :changed_at, default: -> { Time.now.iso8601 }
  
  from 'file_watching_demo'
end

puts "=== SmartMessage File Watching Demo ==="
puts

demo_dir = Dir.mktmpdir('file_watching_demo')
puts "Demo directory: #{demo_dir}"

begin
  # Example 1: Basic File Watching
  puts "\n1. Basic File Watching"
  puts "=" * 30
  
  watch_file = File.join(demo_dir, 'application.log')
  File.write(watch_file, "")  # Create empty file
  
  # Configure file watching transport
  watching_transport = SmartMessage::Transport::FileTransport.new(
    file_path: watch_file,
    enable_subscriptions: true,
    subscription_mode: :poll_changes,
    poll_interval: 0.5,  # Check every 500ms
    read_from: :end      # Only read new content
  )
  
  received_entries = []
  
  # Subscribe to file changes
  watching_transport.subscribe('LogEntry', ->(entry) {
    received_entries << entry
    puts "[Watcher] New log entry: #{entry.message}"
  }, {})
  
  puts "✓ Started watching: #{watch_file}"
  puts "✓ Polling interval: 500ms"
  
  # Simulate log entries being written to the file
  Thread.new do
    sleep 1  # Let watcher start
    
    log_entries = [
      "2024-01-15T10:00:00Z INFO Application started",
      "2024-01-15T10:00:01Z DEBUG Loading configuration",
      "2024-01-15T10:00:02Z INFO Database connected",
      "2024-01-15T10:00:03Z WARN Deprecated API used",
      "2024-01-15T10:00:04Z ERROR Connection timeout"
    ]
    
    log_entries.each do |entry|
      File.open(watch_file, 'a') do |f|
        f.puts entry
        f.flush
      end
      puts "[Writer] Added: #{entry}"
      sleep 0.8  # Slower than poll interval
    end
  end
  
  # Let the watcher run for a few seconds
  sleep 6
  watching_transport.disconnect
  
  puts "✓ Watched file changes, received #{received_entries.length} entries"

  # Example 2: Configuration File Monitoring
  puts "\n2. Configuration File Monitoring"
  puts "=" * 40
  
  config_file = File.join(demo_dir, 'app_config.ini')
  
  # Initial configuration
  initial_config = <<~CONFIG
    [database]
    host=localhost
    port=5432
    pool_size=10
    
    [logging]
    level=INFO
    format=json
  CONFIG
  
  File.write(config_file, initial_config)
  
  config_transport = SmartMessage::Transport::FileTransport.new(
    file_path: config_file,
    enable_subscriptions: true,
    subscription_mode: :poll_changes,
    poll_interval: 0.3,
    read_from: :beginning  # Re-read entire file on changes
  )
  
  current_config = {}
  
  # Monitor configuration changes
  config_transport.subscribe('ConfigChange', ->(change) {
    puts "[Config Monitor] Setting '#{change.setting}' changed: #{change.old_value} → #{change.new_value}"
    current_config[change.setting] = change.new_value
  }, {})
  
  puts "✓ Started monitoring config file: #{config_file}"
  
  # Simulate configuration changes
  Thread.new do
    sleep 1
    
    changes = [
      { file: config_file, content: initial_config.gsub('pool_size=10', 'pool_size=20') },
      { file: config_file, content: initial_config.gsub('pool_size=10', 'pool_size=20').gsub('level=INFO', 'level=DEBUG') },
      { file: config_file, content: initial_config.gsub('pool_size=10', 'pool_size=15').gsub('level=INFO', 'level=WARN').gsub('format=json', 'format=text') }
    ]
    
    changes.each_with_index do |change, i|
      File.write(change[:file], change[:content])
      puts "[Config Writer] Applied configuration change #{i + 1}"
      sleep 1.2
    end
  end
  
  sleep 5
  config_transport.disconnect
  
  puts "✓ Configuration monitoring completed"

  # Example 3: Log Rotation Handling
  puts "\n3. Log Rotation Handling"
  puts "=" * 30
  
  rotating_log = File.join(demo_dir, 'rotating.log')
  File.write(rotating_log, "")
  
  rotation_transport = SmartMessage::Transport::FileTransport.new(
    file_path: rotating_log,
    enable_subscriptions: true,
    subscription_mode: :poll_changes,
    poll_interval: 0.4,
    read_from: :end,
    handle_rotation: true  # Handle file rotation
  )
  
  rotation_messages = []
  
  rotation_transport.subscribe('LogEntry', ->(entry) {
    rotation_messages << entry
    puts "[Rotation Watcher] #{entry.message}"
  }, {})
  
  puts "✓ Started rotation-aware watching: #{rotating_log}"
  
  # Simulate log rotation
  Thread.new do
    sleep 1
    
    # Write some initial entries
    3.times do |i|
      File.open(rotating_log, 'a') { |f| f.puts "Entry #{i + 1} before rotation" }
      sleep 0.5
    end
    
    # Simulate rotation
    puts "[Rotator] Rotating log file..."
    FileUtils.mv(rotating_log, "#{rotating_log}.1")
    File.write(rotating_log, "")  # New file
    
    # Write entries to new file
    3.times do |i|
      File.open(rotating_log, 'a') { |f| f.puts "Entry #{i + 1} after rotation" }
      sleep 0.5
    end
  end
  
  sleep 5
  rotation_transport.disconnect
  
  puts "✓ Log rotation handling completed, processed #{rotation_messages.length} messages"

  # Example 4: Multiple File Watching
  puts "\n4. Multiple File Watching"
  puts "=" * 30
  
  files_to_watch = %w[app1.log app2.log app3.log].map { |name| File.join(demo_dir, name) }
  
  # Create empty files
  files_to_watch.each { |file| File.write(file, "") }
  
  watchers = []
  all_messages = []
  
  files_to_watch.each_with_index do |file, index|
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: file,
      enable_subscriptions: true,
      subscription_mode: :poll_changes,
      poll_interval: 0.3,
      read_from: :end
    )
    
    transport.subscribe('LogEntry', ->(entry) {
      all_messages << entry
      puts "[Multi-Watcher] #{File.basename(entry.source_file)}: #{entry.message}"
    }, {})
    
    watchers << transport
  end
  
  puts "✓ Started watching #{files_to_watch.length} files"
  
  # Simulate activity on multiple files
  Thread.new do
    sleep 1
    
    10.times do |i|
      # Randomly pick a file to write to
      file = files_to_watch.sample
      message = "Message #{i + 1} from #{File.basename(file)}"
      
      File.open(file, 'a') { |f| f.puts message }
      puts "[Multi-Writer] → #{File.basename(file)}: #{message}"
      
      sleep rand(0.2..0.6)
    end
  end
  
  sleep 8
  watchers.each(&:disconnect)
  
  puts "✓ Multiple file watching completed, total messages: #{all_messages.length}"

  # Example 5: File Content Processing
  puts "\n5. File Content Processing with Patterns"
  puts "=" * 45
  
  pattern_file = File.join(demo_dir, 'structured.log')
  File.write(pattern_file, "")
  
  # Custom processor that parses log lines
  pattern_transport = SmartMessage::Transport::FileTransport.new(
    file_path: pattern_file,
    enable_subscriptions: true,
    subscription_mode: :poll_changes,
    poll_interval: 0.4,
    read_from: :end,
    line_processor: ->(line) {
      # Parse structured log lines: "TIMESTAMP LEVEL MESSAGE"
      if match = line.match(/^(\S+)\s+(\S+)\s+(.+)$/)
        {
          timestamp: match[1],
          level: match[2],
          message: match[3],
          source_file: pattern_file
        }
      else
        nil  # Skip malformed lines
      end
    }
  )
  
  processed_logs = []
  
  pattern_transport.subscribe('LogEntry', ->(entry) {
    processed_logs << entry
    puts "[Pattern Processor] [#{entry.level}] #{entry.message}"
  }, {})
  
  puts "✓ Started pattern-based processing: #{pattern_file}"
  
  # Write structured log entries
  Thread.new do
    sleep 1
    
    entries = [
      "2024-01-15T10:00:00Z INFO Application started successfully",
      "2024-01-15T10:00:01Z DEBUG Loading user preferences",
      "invalid log line that will be skipped",
      "2024-01-15T10:00:02Z WARN Database connection slow",
      "2024-01-15T10:00:03Z ERROR Failed to process request",
      "another invalid line",
      "2024-01-15T10:00:04Z INFO Request processed successfully"
    ]
    
    entries.each do |entry|
      File.open(pattern_file, 'a') { |f| f.puts entry }
      sleep 0.6
    end
  end
  
  sleep 5
  pattern_transport.disconnect
  
  puts "✓ Pattern processing completed, valid entries: #{processed_logs.length}"

rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(3)
ensure
  # Cleanup
  FileUtils.rm_rf(demo_dir) if Dir.exist?(demo_dir)
  FileUtils.rm_rf('messages') if Dir.exist?('messages')
  puts "\n✓ File watching demo completed and cleaned up"
end