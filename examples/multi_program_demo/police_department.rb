#!/usr/bin/env ruby

require 'smart_message'
require 'smart_message/transport/redis_transport'
require 'smart_message/serializer/json'
require 'securerandom'
require 'logger'
require_relative 'messages/health_check_message'
require_relative 'messages/health_status_message'
require_relative 'messages/silent_alarm_message'
require_relative 'messages/police_dispatch_message'
require_relative 'messages/emergency_resolved_message'

class PoliceDepartment
  def initialize
    @service_name = 'police-department'
    @status = 'healthy'
    @start_time = Time.now
    @active_incidents = {}
    @available_units = ['Unit-101', 'Unit-102', 'Unit-103', 'Unit-104']
    setup_logging
    setup_messaging
    setup_signal_handlers
    setup_health_monitor
  end

  def setup_logging
    log_file = File.join(__dir__, 'police_department.log')
    @logger = Logger.new(log_file)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
    @logger.info("Police Department logging started")
  end

  def setup_messaging
    # Subscribe to health checks
    Messages::HealthCheckMessage.subscribe(broadcast: true) do |message|
      respond_to_health_check(message)
    end

    # Subscribe to silent alarms from banks
    Messages::SilentAlarmMessage.subscribe(to: @service_name) do |message|
      handle_silent_alarm(message)
    end
    
    puts "🚔 Police Department operational"
    puts "   Available units: #{@available_units.join(', ')}"
    puts "   Responding to health checks and silent alarms"
    puts "   Logging to: police_department.log"
    puts "   Press Ctrl+C to stop\n\n"
    @logger.info("Police Department operational with units: #{@available_units.join(', ')}")
  end

  def setup_signal_handlers
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        puts "\n🚔 Police Department signing off..."
        @logger.info("Police Department signing off")
        exit(0)
      end
    end
  end

  def setup_health_monitor
    @health_timer_mutex = Mutex.new
    @health_timer = nil
    start_health_countdown_timer
  end

  def start_health_countdown_timer
    @health_timer_mutex.synchronize do
      @health_timer&.kill  # Kill existing timer if any
      @health_timer = Thread.new do
        sleep(10)  # 10 second countdown
        shutdown_due_to_health_failure
      end
    end
  end

  def reset_health_timer
    start_health_countdown_timer
  end

  def start_service
    loop do
      check_incident_resolutions
      sleep(2)
    end
  rescue => e
    puts "🚔 Error in police service: #{e.message}"
    @logger.error("Error in police service: #{e.message}")
    retry
  end

  private

  def shutdown_due_to_health_failure
    covid_message = "🦠 EMERGENCY SHUTDOWN: Health Department has shut down all city services due to COVID-19 outbreak"
    puts "\n#{covid_message}"
    puts "🚔 Police Department going offline immediately..."
    @logger.fatal(covid_message)
    @logger.fatal("Police Department shutting down - no health checks received for more than 10 seconds")
    exit(1)
  end

  def respond_to_health_check(health_check)
    reset_health_timer  # Reset the countdown timer
    uptime = (Time.now - @start_time).to_i
    
    # Simulate occasional status changes
    if rand(100) < 5  # 5% chance of status change
      @status = ['healthy', 'warning'].sample
    end
    
    details = case @status
             when 'healthy' then "All units operational, #{@active_incidents.size} active incidents"
             when 'warning' then "High call volume, #{@active_incidents.size} active incidents"
             when 'critical' then "Multiple emergencies, all units deployed"
             when 'failed' then "System down, emergency protocols activated"
             end

    status_msg = Messages::HealthStatusMessage.new(
      service_name: @service_name,
      status: @status,
      timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      check_id: health_check.check_id,
      details: details,
      uptime_seconds: uptime,
      from: @service_name,
      to: nil  # Broadcast to health department
    )
    status_msg.publish
    @logger.info("Sent health status: #{@status} (#{details})")
  rescue => e
    puts "🚔 Error responding to health check: #{e.message}"
    @logger.error("Error responding to health check: #{e.message}")
  end

  def handle_silent_alarm(alarm)
    # Process silent alarm message
    puts "🚨 SILENT ALARM: #{alarm.bank_name} at #{alarm.location} - #{alarm.alarm_type.upcase} (#{alarm.severity} severity)"
    puts "   Details: #{alarm.details}" if alarm.details
    puts "   Time: #{alarm.timestamp}"
    @logger.warn("SILENT ALARM received: #{alarm.alarm_type} at #{alarm.location} (#{alarm.severity} severity)")
    
    # Assign available units
    units_needed = case alarm.severity
                  when 'low' then 1
                  when 'medium' then 2
                  when 'high' then 3
                  when 'critical' then 4
                  else 2
                  end

    assigned_units = @available_units.take(units_needed)
    @available_units = @available_units.drop(units_needed)

    dispatch_id = SecureRandom.hex(4)
    @active_incidents[dispatch_id] = {
      location: alarm.location,
      start_time: Time.now,
      units: assigned_units,
      type: alarm.alarm_type
    }

    # Send dispatch message
    dispatch = Messages::PoliceDispatchMessage.new(
      dispatch_id: dispatch_id,
      units_assigned: assigned_units,
      location: alarm.location,
      incident_type: alarm.alarm_type,
      priority: map_severity_to_priority(alarm.severity),
      estimated_arrival: "#{rand(3..8)} minutes",
      timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      from: @service_name,
      to: alarm._sm_header.from  # Send back to bank
    )
    dispatch.publish

    puts "🚔 Dispatched #{assigned_units.size} units to #{alarm.location}"
    puts "   Available units: #{@available_units.size}"
    @logger.info("Dispatched units #{assigned_units.join(', ')} to #{alarm.location} (#{dispatch_id})")
  rescue => e
    puts "🚔 Error handling silent alarm: #{e.message}"
    @logger.error("Error handling silent alarm: #{e.message}")
  end

  def check_incident_resolutions
    @active_incidents.each do |incident_id, incident|
      # Simulate incident resolution after 10-15 seconds
      duration = (Time.now - incident[:start_time]).to_i
      if duration > rand(10..15)
        resolve_incident(incident_id, incident, duration)
      end
    end
  end

  def resolve_incident(incident_id, incident, duration_seconds)
    # Return units to available pool
    @available_units.concat(incident[:units])
    @active_incidents.delete(incident_id)

    outcomes = ['Suspects apprehended', 'False alarm - all clear', 'Incident resolved peacefully', 'Suspects fled scene']
    
    resolution = Messages::EmergencyResolvedMessage.new(
      incident_id: incident_id,
      incident_type: incident[:type],
      location: incident[:location],
      resolved_by: @service_name,
      resolution_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      duration_minutes: (duration_seconds / 60.0).round(1),
      outcome: outcomes.sample,
      units_involved: incident[:units],
      from: @service_name,
      to: nil  # Broadcast
    )
    resolution.publish

    puts "🚔 Incident #{incident_id} resolved after #{(duration_seconds / 60.0).round(1)} minutes"
    puts "   Units #{incident[:units].join(', ')} now available"
    @logger.info("Incident #{incident_id} resolved: #{outcomes.last} after #{(duration_seconds / 60.0).round(1)} minutes")
  rescue => e
    puts "🚔 Error resolving incident: #{e.message}"
    @logger.error("Error resolving incident: #{e.message}")
  end

  def map_severity_to_priority(severity)
    case severity
    when 'low' then 'low'
    when 'medium' then 'medium'
    when 'high' then 'high'
    when 'critical' then 'emergency'
    else 'medium'
    end
  end
end

if __FILE__ == $0
  police_dept = PoliceDepartment.new
  police_dept.start_service
end