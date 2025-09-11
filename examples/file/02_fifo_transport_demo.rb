#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# FIFO Transport Demo
# 
# This example demonstrates SmartMessage's FileTransport with FIFO (named pipes).
# FIFOs enable real-time, process-to-process communication through the filesystem.

require_relative '../../lib/smart_message'
require 'tempfile'
require 'fileutils'

# Define message classes
Dir.mkdir('messages') unless Dir.exist?('messages')

class PipeMessage < SmartMessage::Base
  property :sender, required: true
  property :content, required: true
  property :timestamp, default: -> { Time.now.iso8601 }
  property :priority, default: 'normal'
  
  from 'fifo_transport_demo'
end

class StatusUpdate < SmartMessage::Base
  property :service, required: true
  property :status, required: true, valid: %w[starting running stopping stopped error]
  property :details, default: {}
  property :timestamp, default: -> { Time.now.iso8601 }
  
  from 'fifo_transport_demo'
end

puts "=== SmartMessage FIFO Transport Demo ==="
puts

# Check if FIFOs are supported on this system
def fifo_supported?
  return @fifo_supported if defined?(@fifo_supported)
  
  test_dir = Dir.mktmpdir('fifo_test')
  test_fifo = File.join(test_dir, 'test.fifo')
  
  result = system("mkfifo #{test_fifo} 2>/dev/null")
  @fifo_supported = result && File.exist?(test_fifo) && File.ftype(test_fifo) == "fifo"
  
  FileUtils.rm_rf(test_dir)
  @fifo_supported
rescue
  @fifo_supported = false
end

unless fifo_supported?
  puts "❌ FIFOs are not supported on this system"
  puts "This demo requires Unix-like systems with mkfifo support"
  exit 1
end

demo_dir = Dir.mktmpdir('fifo_demo')
puts "Demo directory: #{demo_dir}"

begin
  # Example 1: Basic FIFO Communication
  puts "\n1. Basic FIFO Communication"
  puts "=" * 35
  
  fifo_path = File.join(demo_dir, 'message_pipe.fifo')
  system("mkfifo #{fifo_path}")
  
  puts "✓ Created FIFO: #{fifo_path}"
  puts "FIFO type: #{File.ftype(fifo_path)}"
  
  # Configure FIFO transport
  fifo_transport = SmartMessage::Transport::FileTransport.new(
    file_path: fifo_path,
    file_type: :fifo,
    format: :json,
    enable_subscriptions: true,
    subscription_mode: :fifo_blocking
  )
  
  PipeMessage.class_eval do
    transport fifo_transport
  end
  
  # Set up a reader in a separate process
  reader_pid = fork do
    puts "[Reader] Starting FIFO reader process..."
    
    # Subscribe to messages
    received_messages = []
    fifo_transport.subscribe('PipeMessage', ->(msg) {
      received_messages << msg
      puts "[Reader] Received: #{msg.inspect}"
    }, {})
    
    # Keep reading for a short time
    sleep 3
    
    puts "[Reader] Received #{received_messages.length} messages"
    exit 0
  end
  
  # Give reader time to start
  sleep 0.5
  
  # Send messages from parent process
  puts "[Writer] Sending messages through FIFO..."
  
  PipeMessage.new(
    sender: 'process_1',
    content: 'Hello from the writer process!'
  ).publish
  
  PipeMessage.new(
    sender: 'process_1', 
    content: 'This is message #2',
    priority: 'high'
  ).publish
  
  PipeMessage.new(
    sender: 'process_1',
    content: 'Final message before closing'
  ).publish
  
  # Wait for reader to finish
  Process.wait(reader_pid)
  puts "✓ FIFO communication completed"

  # Example 2: Non-blocking FIFO Operations
  puts "\n2. Non-blocking FIFO Operations"
  puts "=" * 35
  
  nb_fifo_path = File.join(demo_dir, 'nonblocking.fifo')
  system("mkfifo #{nb_fifo_path}")
  
  # Configure non-blocking transport
  nb_transport = SmartMessage::Transport::FileTransport.new(
    file_path: nb_fifo_path,
    file_type: :fifo,
    format: :json,
    fifo_mode: :non_blocking
  )
  
  StatusUpdate.class_eval do
    transport nb_transport
  end
  
  puts "✓ Created non-blocking FIFO: #{nb_fifo_path}"
  
  # Start a background reader
  reader_thread = Thread.new do
    sleep 0.2  # Let writer get ahead
    
    begin
      File.open(nb_fifo_path, 'r') do |fifo|
        puts "[Reader] Opened FIFO for reading"
        while line = fifo.gets
          puts "[Reader] Read: #{line.chomp}"
        end
      end
    rescue => e
      puts "[Reader] Error: #{e.message}"
    end
  end
  
  # Send status updates
  puts "[Writer] Sending status updates..."
  
  %w[starting running stopping stopped].each_with_index do |status, i|
    StatusUpdate.new(
      service: 'web_server',
      status: status,
      details: { pid: 1234 + i, memory: "#{50 + i * 10}MB" }
    ).publish
    
    sleep 0.1  # Small delay between messages
  end
  
  # Close the FIFO from writer side to signal EOF
  nb_transport.disconnect
  
  reader_thread.join(2)  # Wait up to 2 seconds
  puts "✓ Non-blocking FIFO operations completed"

  # Example 3: FIFO Concepts Demonstration (Non-blocking)
  puts "\n3. FIFO Concepts Demonstration (Non-blocking)"
  puts "=" * 50
  
  simple_fifo_path = File.join(demo_dir, 'simple.fifo')
  system("mkfifo #{simple_fifo_path}")
  
  puts "✓ Created FIFO: #{simple_fifo_path}"
  puts "✓ Verified FIFO type: #{File.ftype(simple_fifo_path)}"
  
  puts "\nFIFO Characteristics:"
  puts "  - Named pipes for inter-process communication"
  puts "  - Blocking by default (writers wait for readers)"
  puts "  - First In, First Out data flow"
  puts "  - Persistent in filesystem until deleted"
  
  puts "\nDemonstrating FIFO creation and properties..."
  puts "  - FIFO exists: #{File.exist?(simple_fifo_path)}"
  puts "  - FIFO permissions: #{File.stat(simple_fifo_path).mode.to_s(8)}"
  puts "  - FIFO size: #{File.size(simple_fifo_path)} bytes (always 0 for FIFOs)"
  
  # Show transport configuration without actual message sending
  simple_transport = SmartMessage::Transport::FileTransport.new(
    file_path: simple_fifo_path,
    file_type: :fifo,
    format: :json
  )
  
  puts "\nFileTransport FIFO Configuration:"
  puts "  - File path: #{simple_transport.instance_variable_get(:@file_path) rescue 'configured'}"
  puts "  - Format: JSON"
  puts "  - Type: FIFO (named pipe)"
  puts "  - Note: Actual message sending requires concurrent reader process"
  
  puts "\n✓ FIFO concepts demonstration completed"

  # Example 4: Message Priority Classification (File-based)
  puts "\n4. Message Priority Classification (File-based)"
  puts "=" * 55
  
  # Use regular files instead of FIFOs to avoid blocking
  priority_file = File.join(demo_dir, 'priority_messages.log')
  
  priority_transport = SmartMessage::Transport::FileTransport.new(
    file_path: priority_file,
    format: :json
  )
  
  # Create a priority message class
  class PriorityMessage < SmartMessage::Base
    property :level, required: true, valid: %w[low normal high critical]
    property :message, required: true
    property :component, required: true
    
    from 'fifo_transport_demo'
  end
  
  PriorityMessage.class_eval do
    transport priority_transport
  end
  
  puts "Demonstrating priority message classification and logging..."
  
  # Send mixed priority messages
  messages = [
    { level: 'low', message: 'Debug information', component: 'logger' },
    { level: 'normal', message: 'User login successful', component: 'auth' },
    { level: 'high', message: 'Database connection slow', component: 'db' },
    { level: 'normal', message: 'Processing request', component: 'api' },
    { level: 'critical', message: 'Out of memory!', component: 'system' },
    { level: 'high', message: 'Security alert detected', component: 'security' },
    { level: 'low', message: 'Cache miss', component: 'cache' }
  ]
  
  puts "Processing and classifying priority messages..."
  high_priority_count = 0
  messages.each_with_index do |msg_data, i|
    msg = PriorityMessage.new(**msg_data)
    msg.publish
    
    if %w[high critical].include?(msg_data[:level])
      high_priority_count += 1
      puts "  → [HIGH PRIORITY] #{msg_data[:level].upcase}: #{msg_data[:component]} - #{msg_data[:message]}"
    else
      puts "  → [#{msg_data[:level]}]: #{msg_data[:component]} - #{msg_data[:message]}"
    end
  end
  
  puts "\nPriority Log Contents:"
  puts File.read(priority_file)
  
  puts "✓ Processed #{messages.length} messages (#{high_priority_count} high priority)"
  puts "✓ Message priority classification completed"

rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(3)
ensure
  # Cleanup files
  FileUtils.rm_rf(demo_dir) if Dir.exist?(demo_dir)
  FileUtils.rm_rf('messages') if Dir.exist?('messages')
  puts "\n✓ FIFO demo completed and cleaned up"
end