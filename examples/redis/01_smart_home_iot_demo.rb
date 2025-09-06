#!/usr/bin/env ruby
# examples/04_redis_smart_home_iot.rb
#
# Redis Transport Example: Smart Home IoT Dashboard
#
# This example demonstrates Redis pub/sub messaging in a realistic IoT scenario
# where multiple smart home devices publish sensor data and receive commands
# through Redis channels. Each message type gets its own Redis channel for
# efficient routing and scaling.

require_relative '../../lib/smart_message'

begin
  require 'redis'
rescue LoadError
  puts "⚠️  Redis gem not available. Install with: gem install redis"
  exit 1
end

puts "=== SmartMessage Redis Example: Smart Home IoT Dashboard ==="
puts

# Suppress thread error reporting for cleaner output
# This prevents low-level socket error messages from Redis connection pools
# in Ruby 3.4+ that don't affect functionality
Thread.report_on_exception = false

# Configuration for Redis (falls back to memory if Redis not available)
def create_transport
  begin
    # Try Redis first - test the connection before creating transport
    test_redis = Redis.new(url: 'redis://localhost:6379', db: 1, timeout: 1)
    test_redis.ping
    test_redis.quit
    
    # If we get here, Redis is available
    puts "✅ Redis server detected, using Redis transport"
    SmartMessage::Transport.create(:redis,
      url: 'redis://localhost:6379',
      db: 1,  # Use database 1 for examples
      auto_subscribe: true,
      debug: false
    )
  rescue => e
    # Catch all Redis-related connection errors
    if e.class.name.include?('Redis') || e.class.name.include?('Connection') || e.is_a?(Errno::ECONNREFUSED)
      puts "⚠️  Redis not available (#{e.class.name}), falling back to memory transport"
      puts "   To use Redis: ensure Redis server is running on localhost:6379"
    else
      puts "⚠️  Unexpected error connecting to Redis (#{e.class.name}: #{e.message})"
      puts "   Falling back to memory transport"
    end
    SmartMessage::Transport.create(:memory, auto_process: true)
  end
end

SHARED_TRANSPORT = create_transport

# Sensor Data Message - Published by IoT devices
class SensorDataMessage < SmartMessage::Base
  description "Real-time sensor data from smart home IoT devices"
  
  property :device_id, 
    description: "Unique identifier for the IoT device (e.g., THERM-001)"
  property :device_type, 
    description: "Type of device: 'thermostat', 'security_camera', 'door_lock', 'smoke_detector'"
  property :location, 
    description: "Physical location of device: 'living_room', 'kitchen', 'bedroom', 'garage'"
  property :sensor_type, 
    description: "Type of sensor reading: 'temperature', 'humidity', 'motion', 'status'"
  property :value, 
    description: "Numeric or boolean sensor reading value"
  property :unit, 
    description: "Unit of measurement: 'celsius', 'percent', 'boolean', 'lux'"
  property :timestamp, 
    description: "ISO8601 timestamp when sensor reading was taken"
  property :battery_level, 
    description: "Battery percentage for battery-powered devices (0-100)"

  config do
    transport SHARED_TRANSPORT
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    sensor_data = JSON.parse(message_payload)
    icon = case sensor_data['device_type']
           when 'thermostat' then '🌡️'
           when 'security_camera' then '📹'
           when 'door_lock' then '🚪'
           when 'smoke_detector' then '🔥'
           else '📊'
           end
    
    puts "#{icon} Sensor data: #{sensor_data['device_id']} (#{sensor_data['location']}) - #{sensor_data['sensor_type']}: #{sensor_data['value']} #{sensor_data['unit']}"
  end
end

# Device Command Message - Sent to control IoT devices
class DeviceCommandMessage < SmartMessage::Base
  description "Commands sent to control and configure smart home IoT devices"
  
  property :device_id, 
    description: "Target device identifier to receive the command"
  property :command, 
    description: "Command to execute: 'set_temperature', 'lock_door', 'start_recording', 'test_alarm'"
  property :parameters, 
    description: "Hash of command-specific parameters and values"
  property :requested_by, 
    description: "Identifier of user, system, or automation that requested this command"
  property :timestamp, 
    description: "ISO8601 timestamp when command was issued"

  config do
    transport SHARED_TRANSPORT
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    command_data = JSON.parse(message_payload)
    puts "🎛️  Command sent: #{command_data['command']} to #{command_data['device_id']} (requested by #{command_data['requested_by']})"
  end
end

# Alert Message - For critical notifications
class AlertMessage < SmartMessage::Base
  description "Critical alerts and notifications from smart home monitoring systems"
  
  property :alert_id, 
    description: "Unique identifier for this alert event"
  property :severity, 
    description: "Alert severity level: 'low', 'medium', 'high', 'critical'"
  property :alert_type, 
    description: "Type of alert: 'security_breach', 'fire_detected', 'device_offline', 'battery_low'"
  property :device_id, 
    description: "Device that triggered the alert (if applicable)"
  property :location, 
    description: "Physical location where alert was triggered"
  property :message, 
    description: "Human-readable description of the alert condition"
  property :timestamp, 
    description: "ISO8601 timestamp when alert was generated"
  property :requires_action, 
    description: "Boolean indicating if immediate human action is required"

  config do
    transport SHARED_TRANSPORT
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    alert_data = JSON.parse(message_payload)
    severity_icon = case alert_data['severity']
                   when 'low' then '💙'
                   when 'medium' then '💛'
                   when 'high' then '🧡'
                   when 'critical' then '🚨'
                   else '📢'
                   end
    
    puts "#{severity_icon} ALERT [#{alert_data['severity'].upcase}]: #{alert_data['message']} (#{alert_data['device_id']})"
  end
end

# Dashboard Status Message - System-wide status updates
class DashboardStatusMessage < SmartMessage::Base
  property :system_status    # 'normal', 'warning', 'alert'
  property :active_devices
  property :offline_devices
  property :active_alerts
  property :last_updated
  property :summary_stats    # Hash with various metrics

  config do
    transport SHARED_TRANSPORT
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    status_data = JSON.parse(message_payload)
    status_icon = case status_data['system_status']
                 when 'normal' then '✅'
                 when 'warning' then '⚠️'
                 when 'alert' then '🚨'
                 else '📊'
                 end
    
    puts "#{status_icon} Dashboard: #{status_data['active_devices']} devices online, #{status_data['active_alerts']} active alerts"
  end
end

# Smart Thermostat Device
class SmartThermostat
  def initialize(device_id, location)
    @device_id = device_id
    @location = location
    @current_temp = 20.0 + rand(5.0)  # Random starting temperature
    @target_temp = 22.0
    @battery_level = 85 + rand(15)
    @running = false
    
    puts "🌡️  Smart Thermostat #{@device_id} initialized in #{@location}"
    
    # Subscribe to commands for this device
    DeviceCommandMessage.subscribe("SmartThermostat.handle_command")
  end

  def self.handle_command(wrapper)
    message_header, message_payload = wrapper.split
    command_data = JSON.parse(message_payload)
    
    # Only process commands intended for thermostats with our device ID
    return unless command_data['device_id']&.start_with?('THERM-')
    return unless ['set_temperature', 'get_status'].include?(command_data['command'])
    
    puts "🌡️  Thermostat #{command_data['device_id']} received command: #{command_data['command']}"
    
    # Process the command
    case command_data['command']
    when 'set_temperature'
      target_temp = command_data.dig('parameters', 'target')
      puts "    Setting target temperature to #{target_temp}°C" if target_temp
    when 'get_status'
      puts "    Reporting current status"
    end
  end

  def start_monitoring
    @running = true
    
    Thread.new do
      while @running
        # Simulate temperature readings
        @current_temp += (rand - 0.5) * 0.5  # Small random changes
        @battery_level -= 0.1 if rand < 0.1   # Occasional battery drain
        
        # Publish sensor data
        sensor_msg = SensorDataMessage.new(
          device_id: @device_id,
          device_type: 'thermostat',
          location: @location,
          sensor_type: 'temperature',
          value: @current_temp.round(1),
          unit: 'celsius',
          timestamp: Time.now.iso8601,
          battery_level: @battery_level.round(1),
          from: @device_id
        )
        puts "🌡️  #{@device_id}: Publishing temperature #{@current_temp.round(1)}°C"
        sensor_msg.publish

        # Check for alerts
        if @current_temp > 28.0
          AlertMessage.new(
            alert_id: "TEMP-#{Time.now.to_i}",
            severity: 'high',
            alert_type: 'high_temperature',
            device_id: @device_id,
            location: @location,
            message: "Temperature too high: #{@current_temp.round(1)}°C",
            timestamp: Time.now.iso8601,
            requires_action: true,
            from: @device_id
          ).publish
        end

        sleep(3 + rand(2))  # Publish every 3-5 seconds
      end
    end
  end

  def stop_monitoring
    @running = false
  end
end

# Security Camera Device
class SecurityCamera
  def initialize(device_id, location)
    @device_id = device_id
    @location = location
    @motion_detected = false
    @recording = false
    @battery_level = 90 + rand(10)
    @running = false
    
    puts "📹 Security Camera #{@device_id} initialized in #{@location}"
    
    DeviceCommandMessage.subscribe("SecurityCamera.handle_command")
  end

  def self.handle_command(wrapper)
    message_header, message_payload = wrapper.split
    command_data = JSON.parse(message_payload)
    
    # Only process commands intended for cameras with our device ID
    return unless command_data['device_id']&.start_with?('CAM-')
    return unless ['start_recording', 'stop_recording', 'get_status'].include?(command_data['command'])
    
    puts "📹 Camera #{command_data['device_id']} received command: #{command_data['command']}"
    
    # Process the command
    case command_data['command']
    when 'start_recording'
      duration = command_data.dig('parameters', 'duration') || 30
      puts "    Starting recording for #{duration} seconds"
    when 'stop_recording'
      puts "    Stopping recording"
    when 'get_status'
      puts "    Reporting camera status"
    end
  end

  def start_monitoring
    @running = true
    
    Thread.new do
      while @running
        # Simulate motion detection
        motion_detected = rand < 0.3  # 30% chance of motion
        
        if motion_detected && !@motion_detected
          @motion_detected = true
          
          # Publish motion detection
          SensorDataMessage.new(
            device_id: @device_id,
            device_type: 'security_camera',
            location: @location,
            sensor_type: 'motion',
            value: true,
            unit: 'boolean',
            timestamp: Time.now.iso8601,
            battery_level: @battery_level.round(1),
            from: @device_id
          ).publish

          # Send security alert
          AlertMessage.new(
            alert_id: "MOTION-#{Time.now.to_i}",
            severity: 'medium',
            alert_type: 'motion_detected',
            device_id: @device_id,
            location: @location,
            message: "Motion detected in #{@location}",
            timestamp: Time.now.iso8601,
            requires_action: false,
            from: @device_id
          ).publish
          
          # Auto-start recording
          DeviceCommandMessage.new(
            device_id: @device_id,
            command: 'start_recording',
            parameters: { duration: 30 },
            requested_by: 'motion_detector',
            timestamp: Time.now.iso8601,
            from: @device_id
          ).publish
          
        elsif !motion_detected && @motion_detected
          @motion_detected = false
          
          # Motion stopped
          SensorDataMessage.new(
            device_id: @device_id,
            device_type: 'security_camera',
            location: @location,
            sensor_type: 'motion',
            value: false,
            unit: 'boolean',
            timestamp: Time.now.iso8601,
            battery_level: @battery_level.round(1),
            from: @device_id
          ).publish
        end

        @battery_level -= 0.05 if rand < 0.1
        sleep(2 + rand(3))  # Check every 2-5 seconds
      end
    end
  end

  def stop_monitoring
    @running = false
  end
end

# Smart Door Lock
class SmartDoorLock
  def initialize(device_id, location)
    @device_id = device_id
    @location = location
    @locked = true
    @battery_level = 75 + rand(20)
    @running = false
    
    puts "🚪 Smart Door Lock #{@device_id} initialized at #{@location}"
    
    DeviceCommandMessage.subscribe("SmartDoorLock.handle_command")
  end

  def self.handle_command(wrapper)
    message_header, message_payload = wrapper.split
    command_data = JSON.parse(message_payload)
    
    # Only process commands intended for door locks with our device ID
    return unless command_data['device_id']&.start_with?('LOCK-')
    return unless ['lock', 'unlock', 'get_status'].include?(command_data['command'])
    
    puts "🚪 Door Lock #{command_data['device_id']} received command: #{command_data['command']}"
    
    # Process the command
    case command_data['command']
    when 'lock'
      puts "    Locking door"
    when 'unlock'
      puts "    Unlocking door"
    when 'get_status'
      puts "    Reporting lock status"
    end
  end

  def start_monitoring
    @running = true
    
    Thread.new do
      while @running
        # Periodically report status
        SensorDataMessage.new(
          device_id: @device_id,
          device_type: 'door_lock',
          location: @location,
          sensor_type: 'status',
          value: @locked ? 'locked' : 'unlocked',
          unit: 'string',
          timestamp: Time.now.iso8601,
          battery_level: @battery_level.round(1),
          from: @device_id
        ).publish

        # Check for low battery
        if @battery_level < 20
          AlertMessage.new(
            alert_id: "BATTERY-#{Time.now.to_i}",
            severity: 'medium',
            alert_type: 'battery_low',
            device_id: @device_id,
            location: @location,
            message: "Door lock battery low: #{@battery_level.round(1)}%",
            timestamp: Time.now.iso8601,
            requires_action: true,
            from: @device_id
          ).publish
        end

        @battery_level -= 0.2 if rand < 0.1
        sleep(8 + rand(4))  # Report every 8-12 seconds
      end
    end
  end

  def stop_monitoring
    @running = false
  end
end

# IoT Dashboard Service
class IoTDashboard
  @@devices = {}
  @@alerts = []
  @@instance = nil

  def initialize
    @running = false
    
    puts "📊 IoT Dashboard starting up..."
    
    # Subscribe to all message types
    SensorDataMessage.subscribe("IoTDashboard.handle_sensor_data")
    AlertMessage.subscribe("IoTDashboard.handle_alert")
    DeviceCommandMessage.subscribe("IoTDashboard.log_command")
  end

  def self.handle_sensor_data(wrapper)
    message_header, message_payload = wrapper.split
    @@instance ||= new
    @@instance.process_sensor_data(message_header, message_payload)
  end

  def self.handle_alert(wrapper)
    message_header, message_payload = wrapper.split
    @@instance ||= new
    @@instance.process_alert(message_header, message_payload)
  end

  def self.log_command(wrapper)
    message_header, message_payload = wrapper.split
    @@instance ||= new
    @@instance.log_device_command(message_header, message_payload)
  end

  def process_sensor_data(message_header, message_payload)
    data = JSON.parse(message_payload)
    device_id = data['device_id']
    
    @@devices[device_id] = {
      device_type: data['device_type'],
      location: data['location'],
      last_seen: Time.now,
      battery_level: data['battery_level'],
      latest_reading: data
    }
  end

  def process_alert(message_header, message_payload)
    alert_data = JSON.parse(message_payload)
    @@alerts << alert_data
    @@alerts = @@alerts.last(10)  # Keep only last 10 alerts
  end

  def log_device_command(message_header, message_payload)
    command_data = JSON.parse(message_payload)
    puts "📊 Dashboard logged command: #{command_data['command']} → #{command_data['device_id']}"
  end

  def start_status_updates
    @running = true
    
    Thread.new do
      while @running
        sleep(10)  # Update every 10 seconds
        
        active_devices = @@devices.count { |_, device| Time.now - device[:last_seen] < 30 }
        offline_devices = @@devices.count { |_, device| Time.now - device[:last_seen] >= 30 }
        recent_alerts = @@alerts.count { |alert| Time.parse(alert['timestamp']) > Time.now - 300 }
        
        DashboardStatusMessage.new(
          system_status: recent_alerts > 0 ? 'alert' : 'normal',
          active_devices: active_devices,
          offline_devices: offline_devices,
          active_alerts: recent_alerts,
          last_updated: Time.now.iso8601,
          summary_stats: {
            total_devices: @@devices.size,
            avg_battery: @@devices.values.map { |d| d[:battery_level] || 100 }.sum / [@@devices.size, 1].max
          },
          from: 'IoTDashboard'
        ).publish
      end
    end
  end

  def stop_status_updates
    @running = false
  end

  def print_summary
    puts "\n" + "="*60
    puts "📊 DASHBOARD SUMMARY"
    puts "="*60
    puts "Active Devices: #{@@devices.size}"
    @@devices.each do |device_id, device|
      status = Time.now - device[:last_seen] < 30 ? "🟢 Online" : "🔴 Offline"
      puts "  #{device_id} (#{device[:device_type]}) - #{status}"
    end
    puts "\nRecent Alerts: #{@@alerts.size}"
    @@alerts.last(3).each do |alert|
      puts "  #{alert['severity'].upcase}: #{alert['message']}"
    end
    puts "="*60
  end
end

# Demo Runner for Redis Smart Home
class SmartHomeDemo
  def run
    puts "🚀 Starting Smart Home IoT Demo with Redis Transport\n"
    
    # Start dashboard
    dashboard = IoTDashboard.new
    
    # Subscribe to all message types for logging
    SensorDataMessage.subscribe
    DeviceCommandMessage.subscribe
    AlertMessage.subscribe
    DashboardStatusMessage.subscribe
    
    puts "\n" + "="*60
    puts "Initializing Smart Home Devices"
    puts "="*60
    
    # Create devices
    thermostat = SmartThermostat.new("THERM-001", "living_room")
    camera = SecurityCamera.new("CAM-001", "front_door")
    door_lock = SmartDoorLock.new("LOCK-001", "main_entrance")
    
    puts "\n" + "="*60
    puts "Starting Device Monitoring (Redis Pub/Sub Active)"
    puts "="*60
    
    # Start all monitoring
    thermostat.start_monitoring
    camera.start_monitoring
    door_lock.start_monitoring
    dashboard.start_status_updates
    
    # Simulate some manual commands
    puts "\n🎛️  Sending some manual commands..."
    sleep(2)
    
    cmd_msg = DeviceCommandMessage.new(
      device_id: "THERM-001",
      command: "set_temperature",
      parameters: { target: 24.0 },
      requested_by: "mobile_app",
      timestamp: Time.now.iso8601,
      from: 'SmartHomeDemo'
    )
    puts "🎛️  Publishing command: set_temperature for THERM-001"
    cmd_msg.publish
    
    sleep(3)
    
    DeviceCommandMessage.new(
      device_id: "CAM-001",
      command: "start_recording",
      parameters: { duration: 60 },
      requested_by: "security_schedule",
      timestamp: Time.now.iso8601,
      from: 'SmartHomeDemo'
    ).publish
    
    sleep(2)
    
    DeviceCommandMessage.new(
      device_id: "LOCK-001",
      command: "get_status",
      parameters: {},
      requested_by: "mobile_app",
      timestamp: Time.now.iso8601,
      from: 'SmartHomeDemo'
    ).publish
    
    puts "\n⏳ Monitoring for 30 seconds (watch the Redis channels!)..."
    puts "   Each message type uses its own Redis channel for efficient routing"
    
    # Let it run for a while
    sleep(30)
    
    # Show dashboard summary
    dashboard.print_summary
    
    # Stop monitoring
    puts "\n🛑 Stopping monitoring..."
    thermostat.stop_monitoring
    camera.stop_monitoring
    door_lock.stop_monitoring
    dashboard.stop_status_updates
    
    # Final stats
    puts "\n✨ Demo completed!"
    
    transport_name = SHARED_TRANSPORT.class.name.include?('Redis') ? 'Redis' : 'Memory'
    puts "\n📡 Transport used: #{transport_name}"
    
    puts "\nThis example demonstrated:"
    if SHARED_TRANSPORT.class.name.include?('Redis')
      puts "• Redis pub/sub transport with automatic channel routing"
      puts "• Multiple device types publishing to separate Redis channels:"
      puts "  - SensorDataMessage → 'SensorDataMessage' channel"
      puts "  - DeviceCommandMessage → 'DeviceCommandMessage' channel"  
      puts "  - AlertMessage → 'AlertMessage' channel"
      puts "  - DashboardStatusMessage → 'DashboardStatusMessage' channel"
      puts "• Real-time IoT device communication and monitoring"
      puts "• Event-driven architecture with automatic message routing"
      puts "• Scalable pub/sub pattern supporting multiple subscribers per channel"
      puts "\n🔧 Redis Commands you could run to see the channels:"
      puts "  redis-cli -n 1 PUBSUB CHANNELS"
      puts "  redis-cli -n 1 MONITOR"
    else
      puts "• Memory transport with in-process message routing (Redis fallback)"
      puts "• Multiple device types with simulated IoT communication"
      puts "• Event-driven architecture and message processing"
      puts "• Real-time device monitoring and alerting"
      puts "\n💡 To see Redis transport in action:"
      puts "  1. Install Redis: brew install redis (macOS) or apt install redis (Linux)"
      puts "  2. Start Redis: redis-server"
      puts "  3. Re-run this example"
    end
  end
end

# Run the demo if this file is executed directly
if __FILE__ == $0
  demo = SmartHomeDemo.new
  demo.run
end