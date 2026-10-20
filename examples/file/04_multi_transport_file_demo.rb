#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Multi-Transport File Demo
# 
# This example demonstrates advanced FileTransport usage including:
# - Combining FileTransport with other transports
# - Fan-out messaging to multiple files
# - Message routing based on content
# - Backup and archival strategies

require_relative '../../lib/smart_message'
require 'tempfile'
require 'fileutils'

# Define message classes
Dir.mkdir('messages') unless Dir.exist?('messages')

class AuditEvent < SmartMessage::Base
  property :event_type, required: true
  property :user_id, required: true
  property :action, required: true
  property :resource, required: true
  property :timestamp, default: -> { Time.now.iso8601 }
  property :severity, default: 'INFO', valid: %w[DEBUG INFO WARN ERROR CRITICAL]
  property :details, default: {}
  
  from 'multi_transport_file_demo'
end

class SystemMetric < SmartMessage::Base
  property :metric_name, required: true
  property :value, required: true
  property :unit, required: true
  property :host, required: true
  property :timestamp, default: -> { Time.now.iso8601 }
  property :tags, default: {}
  
  from 'multi_transport_file_demo'
end

class AlertMessage < SmartMessage::Base
  property :alert_id, required: true
  property :severity, required: true, valid: %w[LOW MEDIUM HIGH CRITICAL]
  property :message, required: true
  property :source, required: true
  property :timestamp, default: -> { Time.now.iso8601 }
  property :metadata, default: {}
  
  from 'multi_transport_file_demo'
end

puts "=== SmartMessage Multi-Transport File Demo ==="
puts

demo_dir = Dir.mktmpdir('multi_transport_demo')
puts "Demo directory: #{demo_dir}"

begin
  # Example 1: Fan-out to Multiple Files
  puts "\n1. Fan-out to Multiple Files"
  puts "=" * 35
  
  # Create multiple file transports for different purposes
  main_log = File.join(demo_dir, 'main.log')
  audit_log = File.join(demo_dir, 'audit.log')
  backup_log = File.join(demo_dir, 'backup.log')
  
  main_transport = SmartMessage::Transport::FileTransport.new(
    file_path: main_log,
    format: :json
  )
  
  audit_transport = SmartMessage::Transport::FileTransport.new(
    file_path: audit_log,
    format: :yaml
  )
  
  backup_transport = SmartMessage::Transport::FileTransport.new(
    file_path: backup_log,
    format: :raw,
    serializer: ->(msg) { "#{msg.timestamp} | #{msg.event_type} | #{msg.user_id} | #{msg.action}\n" }
  )
  
  # Configure AuditEvent to use multiple transports
  AuditEvent.class_eval do
    transport [main_transport, audit_transport, backup_transport]
  end
  
  puts "✓ Configured fan-out to 3 files:"
  puts "  - Main log (JSON): #{main_log}"
  puts "  - Audit log (YAML): #{audit_log}"
  puts "  - Backup log (Custom): #{backup_log}"
  
  # Send audit events
  events = [
    { event_type: 'USER_LOGIN', user_id: 'alice', action: 'authenticate', resource: 'web_app' },
    { event_type: 'DATA_ACCESS', user_id: 'bob', action: 'read', resource: 'customer_db', severity: 'WARN' },
    { event_type: 'ADMIN_ACTION', user_id: 'admin', action: 'delete_user', resource: 'user_mgmt', severity: 'CRITICAL' },
    { event_type: 'USER_LOGOUT', user_id: 'alice', action: 'logout', resource: 'web_app' }
  ]
  
  events.each do |event_data|
    AuditEvent.new(**event_data).publish
    puts "  → Sent: #{event_data[:event_type]} by #{event_data[:user_id]}"
  end
  
  # Show results
  puts "\nMain Log (JSON):"
  puts File.read(main_log)
  
  puts "\nAudit Log (YAML):"
  puts File.read(audit_log)
  
  puts "\nBackup Log (Custom):"
  puts File.read(backup_log)

  # Example 2: Conditional File Routing
  puts "\n2. Conditional File Routing"
  puts "=" * 35
  
  # Create files for different severity levels
  info_file = File.join(demo_dir, 'info.log')
  warn_file = File.join(demo_dir, 'warnings.log')
  error_file = File.join(demo_dir, 'errors.log')
  
  # Create routing transports with filters
  info_transport = SmartMessage::Transport::FileTransport.new(
    file_path: info_file,
    format: :json,
    message_filter: ->(msg) { %w[DEBUG INFO].include?(msg.severity) }
  )
  
  warn_transport = SmartMessage::Transport::FileTransport.new(
    file_path: warn_file,
    format: :json,
    message_filter: ->(msg) { msg.severity == 'WARN' }
  )
  
  error_transport = SmartMessage::Transport::FileTransport.new(
    file_path: error_file,
    format: :json,
    message_filter: ->(msg) { %w[ERROR CRITICAL].include?(msg.severity) }
  )
  
  puts "✓ Configured conditional routing based on severity"
  puts "Note: Using simplified approach - routing messages to appropriate transports"
  
  # Create simple message classes for each severity level
  class InfoAuditEvent < SmartMessage::Base
    property :event_type, required: true
    property :user_id, required: true
    property :action, required: true
    property :resource, required: true
    property :severity, required: true
    from 'multi_transport_file_demo'
  end
  
  class WarnAuditEvent < SmartMessage::Base
    property :event_type, required: true
    property :user_id, required: true
    property :action, required: true
    property :resource, required: true
    property :severity, required: true
    from 'multi_transport_file_demo'
  end
  
  class ErrorAuditEvent < SmartMessage::Base
    property :event_type, required: true
    property :user_id, required: true
    property :action, required: true
    property :resource, required: true
    property :severity, required: true
    from 'multi_transport_file_demo'
  end
  
  InfoAuditEvent.class_eval { transport info_transport }
  WarnAuditEvent.class_eval { transport warn_transport }
  ErrorAuditEvent.class_eval { transport error_transport }
  
  # Send mixed severity events
  mixed_events = [
    { event_type: 'DEBUG_INFO', user_id: 'dev', action: 'debug', resource: 'api', severity: 'DEBUG' },
    { event_type: 'USER_ACTION', user_id: 'user1', action: 'view', resource: 'page', severity: 'INFO' },
    { event_type: 'SLOW_QUERY', user_id: 'system', action: 'query', resource: 'database', severity: 'WARN' },
    { event_type: 'FAILED_LOGIN', user_id: 'attacker', action: 'login', resource: 'auth', severity: 'ERROR' },
    { event_type: 'SYSTEM_DOWN', user_id: 'system', action: 'crash', resource: 'server', severity: 'CRITICAL' }
  ]
  
  mixed_events.each do |event_data|
    case event_data[:severity]
    when 'DEBUG', 'INFO'
      InfoAuditEvent.new(**event_data).publish
    when 'WARN'
      WarnAuditEvent.new(**event_data).publish
    when 'ERROR', 'CRITICAL'
      ErrorAuditEvent.new(**event_data).publish
    end
    puts "  → Routed #{event_data[:severity]} event to appropriate log"
  end
  
  # Show routing results
  puts "\nInfo Log (DEBUG/INFO):"
  puts File.read(info_file) if File.exist?(info_file) && File.size(info_file) > 0
  
  puts "\nWarning Log (WARN):"
  puts File.read(warn_file) if File.exist?(warn_file) && File.size(warn_file) > 0
  
  puts "\nError Log (ERROR/CRITICAL):"
  puts File.read(error_file) if File.exist?(error_file) && File.size(error_file) > 0

  # Example 3: File + Memory + STDOUT Multi-Transport
  puts "\n3. File + Memory + STDOUT Multi-Transport"
  puts "=" * 45
  
  metrics_file = File.join(demo_dir, 'metrics.log')
  
  file_transport = SmartMessage::Transport::FileTransport.new(
    file_path: metrics_file,
    format: :json
  )
  
  memory_transport = SmartMessage::Transport::MemoryTransport.new(
    auto_process: false
  )
  
  stdout_transport = SmartMessage::Transport::StdoutTransport.new(
    format: :pretty
  )
  
  SystemMetric.class_eval do
    transport [file_transport, memory_transport, stdout_transport]
  end
  
  puts "✓ Configured SystemMetric with 3 transports:"
  puts "  - File storage (persistent)"
  puts "  - Memory storage (fast access)"
  puts "  - STDOUT display (real-time monitoring)"
  
  # Send system metrics
  metrics = [
    { metric_name: 'cpu_usage', value: 45.2, unit: 'percent', host: 'web01' },
    { metric_name: 'memory_usage', value: 2048, unit: 'MB', host: 'web01' },
    { metric_name: 'disk_free', value: 15.8, unit: 'GB', host: 'web01' },
    { metric_name: 'response_time', value: 120, unit: 'ms', host: 'api01' }
  ]
  
  metrics.each do |metric_data|
    SystemMetric.new(**metric_data).publish
  end
  
  puts "\nFile storage contents:"
  puts File.read(metrics_file)
  
  puts "\nMemory storage contents:"
  memory_transport.messages.each_with_index do |msg, i|
    puts "  #{i + 1}. #{msg[:metric_name]}: #{msg[:value]} #{msg[:unit]} (#{msg[:host]})"
  end

  # Example 4: Archive and Cleanup Strategy
  puts "\n4. Archive and Cleanup Strategy"
  puts "=" * 40
  
  current_log = File.join(demo_dir, 'current.log')
  archive_dir = File.join(demo_dir, 'archive')
  Dir.mkdir(archive_dir)
  
  # Simulated archival transport
  class ArchivalTransport
    def initialize(current_file, archive_dir, max_size: 1024)
      @current_file = current_file
      @archive_dir = archive_dir
      @max_size = max_size
      @file_transport = SmartMessage::Transport::FileTransport.new(
        file_path: @current_file,
        format: :json
      )
    end
    
    def publish(message)
      # Check if rotation is needed
      if File.exist?(@current_file) && File.size(@current_file) > @max_size
        rotate_file
      end
      
      @file_transport.publish(message)
    end
    
    private
    
    def rotate_file
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      archive_file = File.join(@archive_dir, "archive_#{timestamp}.log")
      
      FileUtils.mv(@current_file, archive_file)
      puts "  → Archived #{@current_file} to #{archive_file}"
      
      # Recreate transport for new file
      @file_transport = SmartMessage::Transport::FileTransport.new(
        file_path: @current_file,
        format: :json
      )
    end
  end
  
  archival_transport = ArchivalTransport.new(current_log, archive_dir, max_size: 200)  # Small for demo
  
  class ArchivedAlert < SmartMessage::Base
    property :alert_id, required: true
    property :severity, required: true
    property :message, required: true
    property :source, required: true
    property :timestamp, default: -> { Time.now.iso8601 }
    
    from 'multi_transport_file_demo'
  end
  
  ArchivedAlert.class_eval do
    transport archival_transport
  end
  
  puts "✓ Configured archival transport with 200-byte rotation"
  
  # Send alerts to trigger rotation
  15.times do |i|
    ArchivedAlert.new(
      alert_id: "ALERT_#{i + 1}",
      severity: %w[LOW MEDIUM HIGH CRITICAL].sample,
      message: "Alert message #{i + 1} with some details to make it longer",
      source: 'monitoring_system'
    ).publish
  end
  
  puts "\nArchival results:"
  puts "Current log size: #{File.exist?(current_log) ? File.size(current_log) : 0} bytes"
  
  archive_files = Dir.glob(File.join(archive_dir, '*.log')).sort
  puts "Archive files created: #{archive_files.length}"
  archive_files.each do |file|
    puts "  - #{File.basename(file)} (#{File.size(file)} bytes)"
  end

  # Example 5: Performance Monitoring
  puts "\n5. Performance Monitoring"
  puts "=" * 30
  
  perf_file = File.join(demo_dir, 'performance.log')
  
  # Transport with performance metrics
  class PerformanceFileTransport < SmartMessage::Transport::FileTransport
    attr_reader :message_count, :total_write_time, :avg_write_time
    
    def initialize(*args)
      super
      @message_count = 0
      @total_write_time = 0.0
    end
    
    def publish(message)
      start_time = Time.now
      result = super
      end_time = Time.now
      
      @message_count += 1
      @total_write_time += (end_time - start_time)
      @avg_write_time = @total_write_time / @message_count
      
      result
    end
    
    def stats
      {
        messages_sent: @message_count,
        total_time: @total_write_time.round(4),
        average_time: @avg_write_time.round(4),
        messages_per_second: (@message_count / @total_write_time).round(2)
      }
    end
  end
  
  perf_transport = PerformanceFileTransport.new(
    file_path: perf_file,
    format: :json
  )
  
  class PerfTestMessage < SmartMessage::Base
    property :id, required: true
    property :data, required: true
    property :timestamp, default: -> { Time.now.iso8601 }
    
    from 'multi_transport_file_demo'
  end
  
  PerfTestMessage.class_eval do
    transport perf_transport
  end
  
  puts "✓ Starting performance test..."
  
  # Performance test
  test_count = 100
  start_time = Time.now
  
  test_count.times do |i|
    PerfTestMessage.new(
      id: i + 1,
      data: "Performance test message #{i + 1} with some payload data " * 5
    ).publish
  end
  
  end_time = Time.now
  total_time = end_time - start_time
  
  stats = perf_transport.stats
  
  puts "Performance Results:"
  puts "  - Messages sent: #{stats[:messages_sent]}"
  puts "  - Total time: #{total_time.round(4)}s"
  puts "  - Average write time: #{stats[:average_time]}s"
  puts "  - Messages per second: #{stats[:messages_per_second]}"
  puts "  - File size: #{File.size(perf_file)} bytes"

rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(3)
ensure
  # Cleanup
  FileUtils.rm_rf(demo_dir) if Dir.exist?(demo_dir)
  FileUtils.rm_rf('messages') if Dir.exist?('messages')
  puts "\n✓ Multi-transport demo completed and cleaned up"
end