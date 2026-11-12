#!/usr/bin/env ruby
# examples/redis/01_smart_home_iot_demo.rb
# frozen_string_literal: true
#
# Redis transport example: a smart home
#
# Three devices and a dashboard talk over Redis pub/sub.  Each message
# class is one Redis channel, prefixed with a namespace:
#
#   SensorDataMessage       devices   -> dashboard
#   AlertMessage            devices   -> dashboard
#   DeviceCommandMessage    app       -> one device (addressed with to:)
#   DashboardStatusMessage  dashboard -> everybody (broadcast)
#
# The script checks every outcome it demonstrates and exits non-zero when
# one of them is wrong.
#
#   bundle exec ruby -Ilib examples/redis/01_smart_home_iot_demo.rb

require 'forwardable'

require_relative 'support'
require_relative 'messages/sensor_data_message'
require_relative 'messages/device_command_message'
require_relative 'messages/alert_message'
require_relative 'messages/dashboard_status_message'

# A device publishes readings and alerts, and receives the commands that
# are addressed to it.
class SmartDevice
  attr_reader :device_id, :device_type, :location, :commands

  def initialize(device_id, device_type, location)
    @device_id   = device_id
    @device_type = device_type
    @location    = location
    @commands    = Thread::Queue.new
  end

  # Receive only the commands whose +to+ is this device.
  def listen
    DeviceCommandMessage.subscribe(to: device_id) { |command| handle_command(command) }
  end

  # Runs on a dispatcher thread.
  def handle_command(command)
    puts "  #{device_id} received #{command.command} #{command.parameters} from #{command.from}"
    @commands << command
  end

  def report(sensor_type, value, unit, battery_level: 90)
    SensorDataMessage.new(
      device_id:, device_type:, location:, sensor_type:, value:, unit:, battery_level:,
      from: device_id
    ).publish
  end

  def alert(alert_type, severity, text, requires_action: false)
    AlertMessage.new(
      alert_type:, severity:, device_id:, location:, message: text, requires_action:,
      from: device_id
    ).publish
  end

  # @return [Array<String>] the names of the commands received so far
  def received_commands
    Array.new(@commands.size) { @commands.pop }.each { |command| @commands << command }.map(&:command)
  end
end

# The dashboard collects what the devices publish and broadcasts a summary.
class Dashboard
  NAME = 'dashboard'

  attr_reader :readings, :alerts

  def initialize
    @readings = Thread::Queue.new
    @alerts   = Thread::Queue.new
  end

  def listen
    SensorDataMessage.subscribe { |reading| @readings << reading }
    AlertMessage.subscribe do |alert|
      puts "  dashboard received a #{alert.severity} alert from #{alert.from}: #{alert.message}"
      @alerts << alert
    end
  end

  # @return [SmartMessage::PublishResult]
  def broadcast_status
    DashboardStatusMessage.new(
      system_status:  @alerts.empty? ? 'normal' : 'alert',
      active_devices: @readings.size,
      active_alerts:  @alerts.size,
      from:           NAME
    ).publish
  end
end

# Sends commands to devices and listens for the dashboard's broadcast.
class MobileApp
  NAME = 'mobile-app'

  attr_reader :statuses

  def initialize
    @statuses = Thread::Queue.new
  end

  def listen
    DashboardStatusMessage.subscribe(broadcast: true, from: Dashboard::NAME) { |status| @statuses << status }
  end

  # @return [SmartMessage::PublishResult]
  def command(device, name, parameters = {})
    DeviceCommandMessage.new(
      command: name, parameters:, requested_by: 'demo user',
      from: NAME, to: device.device_id
    ).publish
  end
end

# The story the example tells, one step per method.
class SmartHomeDemo
  extend Forwardable

  def_delegators RedisExample, :configure!, :namespace, :check, :wait_until

  def initialize
    @transport  = configure!
    @thermostat = SmartDevice.new('THERM-001', 'thermostat',      'living_room')
    @camera     = SmartDevice.new('CAM-001',   'security_camera', 'front_door')
    @lock       = SmartDevice.new('LOCK-001',  'door_lock',       'main_entrance')
    @dashboard  = Dashboard.new
    @app        = MobileApp.new
  end

  def devices = [@thermostat, @camera, @lock]

  def run
    subscribe_everybody
    publish_readings_and_alerts
    send_commands
    broadcast_status
    reject_an_invalid_message
    publish_after_disconnect
  end

  def subscribe_everybody
    puts "\n1. Subscribing (namespace #{namespace})"
    @dashboard.listen
    @app.listen
    devices.each(&:listen)

    # subscribe returns once Redis has confirmed, so nothing published
    # from here on can be missed.
    channels = @transport.subscribed_channels
    check 'four channels are subscribed, all inside the namespace',
          channels.size == 4 && channels.all? { |channel| channel.start_with?("#{namespace}:") }
  end

  def publish_readings_and_alerts
    puts "\n2. Devices publish readings and alerts"
    results = [
      @thermostat.report('temperature', 29.5, 'celsius'),
      @camera.report('motion', true, 'boolean'),
      @lock.report('status', 'locked', 'string', battery_level: 15),
      @thermostat.alert('high_temperature', 'high', 'Temperature too high: 29.5 C', requires_action: true),
      @camera.alert('motion_detected', 'medium', 'Motion detected at the front door'),
      @lock.alert('battery_low', 'medium', 'Door lock battery low: 15%', requires_action: true)
    ]

    check 'every publish returned a successful PublishResult', results.all?(&:success?)
    check 'the dashboard received 3 readings', wait_until { @dashboard.readings.size == 3 }
    check 'the dashboard received 3 alerts',   wait_until { @dashboard.alerts.size == 3 }
  end

  def send_commands
    puts "\n3. The app sends each command to one device"
    @app.command(@thermostat, 'set_temperature', { target: 22.0 })
    @app.command(@camera, 'start_recording', { duration: 30 })
    @app.command(@lock, 'get_status')

    wait_until { devices.all? { |device| device.commands.size == 1 } }
    check 'the thermostat received only set_temperature', @thermostat.received_commands == %w[set_temperature]
    check 'the camera received only start_recording',     @camera.received_commands == %w[start_recording]
    check 'the lock received only get_status',            @lock.received_commands == %w[get_status]
  end

  def broadcast_status
    puts "\n4. The dashboard broadcasts a status summary"
    @dashboard.broadcast_status
    check 'the app received the broadcast', wait_until { @app.statuses.size == 1 }
    return if @app.statuses.empty?

    status = @app.statuses.pop
    puts "  status: #{status.system_status}, #{status.active_devices} devices, #{status.active_alerts} alerts"
    check 'the summary counts 3 devices and 3 alerts',
          status.system_status == 'alert' && status.active_devices == 3 && status.active_alerts == 3
  end

  def reject_an_invalid_message
    puts "\n5. An invalid message is rejected by publish"
    alert = AlertMessage.new(alert_type: 'test', severity: 'catastrophic', device_id: 'CAM-001',
                             message: 'not a real severity', from: 'CAM-001')
    error = publish_error(alert)
    puts "  #{error.class.name}: #{error.message}" if error
    check 'publish raised ValidationError', error.is_a?(SmartMessage::Errors::ValidationError)
    check 'the dashboard still has 3 alerts', @dashboard.alerts.size == 3
  end

  def publish_after_disconnect
    puts "\n6. Publishing after disconnect fails loudly and keeps the message"
    @transport.disconnect
    error = publish_error(SensorDataMessage.new(device_id: 'THERM-001', device_type: 'thermostat',
                                                sensor_type: 'temperature', value: 21.0, from: 'THERM-001'))
    puts "  #{error.class.name}: #{error.message}" if error
    check 'publish raised PublishError', error.is_a?(SmartMessage::Errors::PublishError)
    check 'the unpublished message is in the dead letter queue',
          SmartMessage::DeadLetterQueue.default.filter_by_class('SensorDataMessage').size == 1
  end

  # @return [StandardError, nil] what publishing the message raised
  def publish_error(message)
    message.publish
    nil
  rescue SmartMessage::Errors::Error => e
    e
  end
end

if __FILE__ == $PROGRAM_NAME
  puts '=== SmartMessage Redis example: smart home ==='
  SmartHomeDemo.new.run
  RedisExample.finish!
end
