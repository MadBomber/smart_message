#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Basic File Transport Demo
#
# This example demonstrates the core functionality of SmartMessage's FileTransport.
# It shows how to publish messages to files and read them back.

require_relative '../../lib/smart_message'
require 'tempfile'
require 'fileutils'

# Define message classes that will be saved in the messages directory
Dir.mkdir('messages') unless Dir.exist?('messages')

class LogMessage < SmartMessage::Base
  property :level, required: true, valid: %w[DEBUG INFO WARN ERROR FATAL]
  property :message, required: true
  property :timestamp, default: -> { Time.now.iso8601 }
  property :component, default: 'system'

  from 'file_transport_demo'

  # Transport will be set dynamically in examples
end

class UserAction < SmartMessage::Base
  property :user_id, required: true
  property :action, required: true
  property :details, default: {}
  property :timestamp, default: -> { Time.now.iso8601 }

  from 'file_transport_demo'

  # Transport will be set dynamically in examples
end

puts "=== SmartMessage FileTransport Basic Demo ==="
puts

# Create a temporary directory for our demo
demo_dir = Dir.mktmpdir('file_transport_demo')
puts "Demo directory: #{demo_dir}"

begin
  # Example 1: Basic file writing
  puts "\n1. Basic File Writing"
  puts "=" * 30

  log_file = File.join(demo_dir, 'application.log')

  # Configure a simple file transport
  file_transport = SmartMessage::Transport::FileTransport.new(
    file_path: log_file,
    format: :json
  )

  # Configure LogMessage to use the file transport
  LogMessage.class_eval do
    transport file_transport
  end

  # Publish some log messages
  LogMessage.new(level: 'INFO', message: 'Application started', component: 'main').publish
  LogMessage.new(level: 'DEBUG', message: 'Loading configuration', component: 'config').publish
  LogMessage.new(level: 'WARN', message: 'Deprecated feature used', component: 'legacy').publish
  LogMessage.new(level: 'ERROR', message: 'Database connection failed', component: 'db').publish

  puts "✓ Messages written to: #{log_file}"
  puts "File contents:"
  puts File.read(log_file)

  # Example 2: Different output formats
  puts "\n2. Different Output Formats"
  puts "=" * 30

  formats = [:json, :yaml, :raw]

  formats.each do |format|
    format_file = File.join(demo_dir, "messages_#{format}.log")

    format_transport = SmartMessage::Transport::FileTransport.new(
      file_path: format_file,
      format: format
    )

    # Create a temporary message class for this format
    temp_message = Class.new(SmartMessage::Base) do
      property :content, required: true
      property :format_type, required: true
      from 'file_transport_demo'
    end

    temp_message.class_eval do
      transport format_transport
    end

    temp_message.new(
      content: "This message is in #{format} format",
      format_type: format.to_s
    ).publish

    puts "\n#{format.upcase} format (#{format_file}):"
    puts File.read(format_file)
  end

  # Example 3: Append vs Overwrite modes
  puts "\n3. Append vs Overwrite Modes"
  puts "=" * 30

  append_file = File.join(demo_dir, 'append_demo.log')
  overwrite_file = File.join(demo_dir, 'overwrite_demo.log')

  # Append mode (default)
  append_transport = SmartMessage::Transport::FileTransport.new(
    file_path: append_file,
    write_mode: :append,
    format: :raw
  )

  # Overwrite mode
  overwrite_transport = SmartMessage::Transport::FileTransport.new(
    file_path: overwrite_file,
    write_mode: :overwrite,
    format: :raw
  )

  # Create messages for demonstration
  3.times do |i|
    # Append mode - messages accumulate
    temp_append = Class.new(SmartMessage::Base) do
      property :content, required: true
      from 'file_transport_demo'
    end
    temp_append.class_eval do
      transport append_transport
    end
    temp_append.new(content: "Append message #{i + 1}").publish

    # Overwrite mode - only the last message remains
    temp_overwrite = Class.new(SmartMessage::Base) do
      property :content, required: true
      from 'file_transport_demo'
    end
    temp_overwrite.class_eval do
      transport overwrite_transport
    end
    temp_overwrite.new(content: "Overwrite message #{i + 1}").publish
  end

  puts "\nAppend mode result (#{append_file}):"
  puts File.read(append_file)

  puts "\nOverwrite mode result (#{overwrite_file}):"
  puts File.read(overwrite_file)

  # Example 4: Custom serialization
  puts "\n4. Custom Serialization"
  puts "=" * 30

  csv_file = File.join(demo_dir, 'user_actions.csv')

  # Create a CSV-style transport with custom serializer
  csv_transport = SmartMessage::Transport::FileTransport.new(
    file_path: csv_file,
    format: :custom,
    serializer: ->(message) {
      # Custom CSV serialization
      "#{message.timestamp},#{message.user_id},#{message.action},\"#{message.details}\"\n"
    }
  )

  UserAction.class_eval do
    transport csv_transport
  end

  # Write CSV header manually
  File.write(csv_file, "timestamp,user_id,action,details\n")

  # Publish user action messages
  UserAction.new(user_id: '12345', action: 'login', details: {ip: '192.168.1.1'}).publish
  UserAction.new(user_id: '12345', action: 'view_profile', details: {page: 'settings'}).publish
  UserAction.new(user_id: '67890', action: 'purchase', details: {item_id: 'ABC123', amount: 29.99}).publish
  UserAction.new(user_id: '12345', action: 'logout', details: {}).publish

  puts "CSV file contents (#{csv_file}):"
  puts File.read(csv_file)

  # Example 5: File rotation
  puts "\n5. File Rotation"
  puts "=" * 30

  # Note: This demonstrates the concept - actual rotation would require external tools
  base_file = File.join(demo_dir, 'rotated.log')

  rotation_transport = SmartMessage::Transport::FileTransport.new(
    file_path: base_file,
    format: :json
  )

  temp_rotated = Class.new(SmartMessage::Base) do
    property :sequence, required: true
    property :data, required: true
    from 'file_transport_demo'
  end
  temp_rotated.class_eval do
    transport rotation_transport
  end

  # Simulate rotation by publishing messages and manually rotating
  5.times do |i|
    temp_rotated.new(sequence: i + 1, data: "Message #{i + 1}").publish

    # Simulate rotation after every 2 messages
    if (i + 1) % 2 == 0
      rotated_file = "#{base_file}.#{(i + 1) / 2}"
      FileUtils.mv(base_file, rotated_file) if File.exist?(base_file)
      puts "✓ Rotated to: #{rotated_file}"
    end
  end

  # Show rotated files
  Dir.glob("#{base_file}*").sort.each do |file|
    puts "\n#{file}:"
    puts File.read(file) if File.exist?(file) && File.size(file) > 0
  end

rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(3)
ensure
  # Cleanup
  FileUtils.rm_rf(demo_dir) if Dir.exist?(demo_dir)
  FileUtils.rm_rf('messages') if Dir.exist?('messages')
  puts "\n✓ Demo completed and cleaned up"
end
