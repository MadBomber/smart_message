#!/usr/bin/env ruby

require 'smart_message'
require 'smart_message/transport/redis_transport'
require 'smart_message/serializer/json'
require 'securerandom'
require 'logger'
require_relative 'messages/health_check_message'
require_relative 'messages/health_status_message'
require_relative 'messages/fire_emergency_message'
require_relative 'messages/fire_dispatch_message'
require_relative 'messages/emergency_resolved_message'

class FireDepartment
  def initialize
    @service_name = 'fire-department'
    @status = 'healthy'
    @start_time = Time.now
    @active_fires = {}
    @available_engines = ['Engine-1', 'Engine-2', 'Engine-3', 'Ladder-1', 'Rescue-1']
    setup_logging
    setup_messaging
    setup_signal_handlers
  end

  def setup_logging
    log_file = File.join(__dir__, 'fire_department.log')
    @logger = Logger.new(log_file)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
    @logger.info("Fire Department logging started")
  end

  def setup_messaging
    # Subscribe to health checks
    Messages::HealthCheckMessage.subscribe(broadcast: true) do |message|
      respond_to_health_check(message)
    end

    # Subscribe to fire emergencies from houses
    Messages::FireEmergencyMessage.subscribe(to: @service_name) do |message|
      handle_fire_emergency(message)
    end
    
    puts "🚒 Fire Department ready for service"
    puts "   Available engines: #{@available_engines.join(', ')}"
    puts "   Responding to health checks and fire emergencies"
    puts "   Logging to: fire_department.log"
    puts "   Press Ctrl+C to stop\n\n"
    @logger.info("Fire Department ready for service with engines: #{@available_engines.join(', ')}")
  end

  def setup_signal_handlers
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        puts "\n🚒 Fire Department out of service..."
        @logger.info("Fire Department out of service")
        exit(0)
      end
    end
  end

  def start_service
    loop do
      check_fire_resolutions
      sleep(3)
    end
  rescue => e
    puts "🚒 Error in fire service: #{e.message}"
    @logger.error("Error in fire service: #{e.message}")
    retry
  end

  private

  def respond_to_health_check(health_check)
    uptime = (Time.now - @start_time).to_i
    
    # Status depends on active fires and available engines
    @status = if @active_fires.size >= 3
               'critical'
             elsif @active_fires.size >= 2
               'warning'
             elsif @available_engines.size < 2
               'warning'
             else
               'healthy'
             end
    
    details = case @status
             when 'healthy' then "All engines available, #{@active_fires.size} active fires"
             when 'warning' then "#{@available_engines.size} engines available, #{@active_fires.size} active fires"
             when 'critical' then "All engines deployed, #{@active_fires.size} major fires"
             when 'failed' then "Equipment failure, emergency mutual aid requested"
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
    puts "🚒 Error responding to health check: #{e.message}"
    @logger.error("Error responding to health check: #{e.message}")
  end

  def handle_fire_emergency(emergency)
    # Process fire emergency message with colored output
    severity_color = case emergency.severity
                    when 'small' then "\e[33m"      # Yellow
                    when 'medium' then "\e[93m"     # Orange
                    when 'large' then "\e[31m"      # Red
                    when 'out_of_control' then "\e[91m" # Bright red
                    else "\e[0m"
                    end
    
    puts "🔥 #{severity_color}FIRE EMERGENCY\e[0m: #{emergency.house_address}"
    puts "   Type: #{emergency.fire_type} | Severity: #{emergency.severity.upcase}"
    puts "   Occupants: #{emergency.occupants_status}" if emergency.occupants_status
    puts "   Spread Risk: #{emergency.spread_risk}" if emergency.spread_risk
    puts "   Time: #{emergency.timestamp}"
    @logger.warn("FIRE EMERGENCY: #{emergency.fire_type} fire at #{emergency.house_address} (#{emergency.severity} severity)")
    
    # Determine engines needed based on fire severity
    engines_needed = case emergency.severity
                    when 'small' then 1
                    when 'medium' then 2
                    when 'large' then 3
                    when 'out_of_control' then @available_engines.size
                    else 2
                    end

    assigned_engines = @available_engines.take(engines_needed)
    @available_engines = @available_engines.drop(engines_needed)

    # Determine equipment needed
    equipment = determine_equipment_needed(emergency.fire_type, emergency.severity)

    dispatch_id = SecureRandom.hex(4)
    @active_fires[dispatch_id] = {
      address: emergency.house_address,
      start_time: Time.now,
      engines: assigned_engines,
      fire_type: emergency.fire_type,
      severity: emergency.severity
    }

    # Send dispatch message
    dispatch = Messages::FireDispatchMessage.new(
      dispatch_id: dispatch_id,
      engines_assigned: assigned_engines,
      location: emergency.house_address,
      fire_type: emergency.fire_type,
      equipment_needed: equipment,
      estimated_arrival: "#{rand(4..10)} minutes",
      timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      from: @service_name,
      to: emergency._sm_header.from  # Send back to house
    )
    dispatch.publish

    puts "🚒 Dispatched #{assigned_engines.size} engines to #{emergency.house_address}"
    puts "   Fire type: #{emergency.fire_type} (#{emergency.severity})"
    puts "   Available engines: #{@available_engines.size}"
    @logger.info("Dispatched engines #{assigned_engines.join(', ')} to #{emergency.house_address} (#{dispatch_id})")
  rescue => e
    puts "🚒 Error handling fire emergency: #{e.message}"
    @logger.error("Error handling fire emergency: #{e.message}")
  end

  def check_fire_resolutions
    @active_fires.each do |fire_id, fire|
      # Fire resolution time depends on severity (10-15 seconds)
      base_time = case fire[:severity]
                 when 'small' then 10..12
                 when 'medium' then 11..13
                 when 'large' then 12..14
                 when 'out_of_control' then 13..15
                 else 11..13
                 end
      
      duration = (Time.now - fire[:start_time]).to_i
      if duration > rand(base_time)
        resolve_fire(fire_id, fire, duration)
      end
    end
  end

  def resolve_fire(fire_id, fire, duration_seconds)
    # Return engines to available pool
    @available_engines.concat(fire[:engines])
    @active_fires.delete(fire_id)

    outcomes = [
      'Fire extinguished successfully',
      'Fire contained with minimal damage',
      'Structure saved, investigating cause',
      'Total loss, area secured'
    ]
    
    resolution = Messages::EmergencyResolvedMessage.new(
      incident_id: fire_id,
      incident_type: "#{fire[:fire_type]} fire",
      location: fire[:address],
      resolved_by: @service_name,
      resolution_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      duration_minutes: (duration_seconds / 60.0).round(1),
      outcome: outcomes.sample,
      units_involved: fire[:engines],
      from: @service_name,
      to: nil  # Broadcast
    )
    resolution.publish

    puts "🚒 Fire #{fire_id} extinguished after #{(duration_seconds / 60.0).round(1)} minutes"
    puts "   Engines #{fire[:engines].join(', ')} returning to station"
    @logger.info("Fire #{fire_id} extinguished: #{outcomes.last} after #{(duration_seconds / 60.0).round(1)} minutes")
  rescue => e
    puts "🚒 Error resolving fire: #{e.message}"
    @logger.error("Error resolving fire: #{e.message}")
  end

  def determine_equipment_needed(fire_type, severity)
    equipment = []
    
    case fire_type
    when 'kitchen'
      equipment << 'Class K extinguishers'
    when 'electrical'
      equipment << 'Class C extinguishers'
      equipment << 'Power shut-off tools'
    when 'basement'
      equipment << 'Ventilation fans'
      equipment << 'Search and rescue gear'
    when 'garage'
      equipment << 'Foam suppressant'
    when 'wildfire'
      equipment << 'Brush trucks'
      equipment << 'Water tenders'
    end

    if ['large', 'out_of_control'].include?(severity)
      equipment << 'Aerial ladder'
      equipment << 'Additional water supply'
    end

    equipment.join(', ')
  end
end

if __FILE__ == $0
  fire_dept = FireDepartment.new
  fire_dept.start_service
end