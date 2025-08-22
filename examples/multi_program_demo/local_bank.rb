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

class LocalBank
  def initialize
    @service_name = 'first-national-bank'
    @location = '123 Main Street'
    @status = 'healthy'
    @start_time = Time.now
    @alarm_active = false
    @last_alarm_time = nil
    @security_level = 'normal'
    setup_logging
    setup_messaging
    setup_signal_handlers
    setup_health_monitor
  end

  def setup_logging
    log_file = File.join(__dir__, 'local_bank.log')
    @logger = Logger.new(log_file)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
    @logger.info("Local Bank logging started")
  end

  def setup_messaging
    # Subscribe to health checks
    Messages::HealthCheckMessage.subscribe(broadcast: true) do |message|
      respond_to_health_check(message)
    end

    # Subscribe to police dispatch responses
    Messages::PoliceDispatchMessage.subscribe(to: @service_name) do |message|
      handle_police_response(message)
    end
    
    puts "🏦 #{@service_name} open for business"
    puts "   Location: #{@location}"
    puts "   Security level: #{@security_level}"
    puts "   Logging to: local_bank.log"
    puts "   Press Ctrl+C to close\n\n"
    @logger.info("#{@service_name} open for business at #{@location}")
  end

  def setup_signal_handlers
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        puts "\n🏦 #{@service_name} closing for the day..."
        @logger.info("#{@service_name} closing for the day")
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

  def start_operations
    loop do
      simulate_bank_activity
      sleep(rand(10..30))  # Random activities every 10-30 seconds
    end
  rescue => e
    puts "🏦 Error in bank operations: #{e.message}"
    @logger.error("Error in bank operations: #{e.message}")
    retry
  end

  private

  def shutdown_due_to_health_failure
    covid_message = "🦠 EMERGENCY SHUTDOWN: Health Department has shut down all city services due to COVID-19 outbreak"
    puts "\n#{covid_message}"
    puts "🏦 #{@service_name} closing immediately..."
    @logger.fatal(covid_message)
    @logger.fatal("#{@service_name} shutting down - no health checks received for more than 10 seconds")
    exit(1)
  end

  def respond_to_health_check(health_check)
    reset_health_timer  # Reset the countdown timer
    uptime = (Time.now - @start_time).to_i
    
    # Simulate occasional system issues
    if rand(100) < 3  # 3% chance of issues
      @status = ['healthy', 'warning'].sample
    end
    
    details = case @status
             when 'healthy' then "All systems operational, security level: #{@security_level}"
             when 'warning' then "Network latency detected, backup systems active"
             when 'critical' then "Security breach detected, lockdown protocols active"
             when 'failed' then "Systems offline, emergency procedures in effect"
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
    puts "🏦 Error responding to health check: #{e.message}"
    @logger.error("Error responding to health check: #{e.message}")
  end

  def simulate_bank_activity
    # Only trigger alarms occasionally and not too frequently
    return if @alarm_active
    return if @last_alarm_time && (Time.now - @last_alarm_time) < 300  # 5 minutes minimum between alarms
    
    # 8% chance of suspicious activity
    if rand(100) < 8
      trigger_silent_alarm
    else
      # Normal bank operations
      activities = [
        'Customer transaction completed',
        'ATM refilled',
        'Vault inspection completed',
        'Security patrol completed',
        'System backup completed'
      ]
      activity = activities.sample
      puts "🏦 #{activity}"
      @logger.info("Normal operation: #{activity}")
    end
  end

  def trigger_silent_alarm
    @alarm_active = true
    @last_alarm_time = Time.now
    @security_level = 'high'
    
    alarm_types = ['robbery', 'vault_breach', 'suspicious_activity']
    severities = ['medium', 'high', 'critical']
    
    alarm_type = alarm_types.sample
    severity = alarm_type == 'robbery' ? 'critical' : severities.sample
    
    details = case alarm_type
             when 'robbery'
               'Armed individuals at teller window, customers on floor'
             when 'vault_breach'
               'Unauthorized access attempt detected in vault area'
             when 'suspicious_activity'
               'Multiple individuals casing the building, unusual behavior'
             end

    alarm = Messages::SilentAlarmMessage.new(
      bank_name: @service_name,
      location: @location,
      alarm_type: alarm_type,
      timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      severity: severity,
      details: details,
      from: @service_name,
      to: 'police-department'
    )
    alarm.publish

    puts "🏦 🚨 SILENT ALARM TRIGGERED 🚨"
    puts "   Type: #{alarm_type.upcase}"
    puts "   Severity: #{severity.upcase}"
    puts "   Details: #{details}"
    @logger.warn("SILENT ALARM TRIGGERED: #{alarm_type} (#{severity}) - #{details}")
  rescue => e
    puts "🏦 Error triggering silent alarm: #{e.message}"
    @logger.error("Error triggering silent alarm: #{e.message}")
  end

  def handle_police_response(dispatch)
    # Process police dispatch message with colored output
    priority_color = case dispatch.priority
                    when 'low' then "\e[32m"        # Green
                    when 'medium' then "\e[33m"     # Yellow
                    when 'high' then "\e[93m"       # Orange
                    when 'emergency' then "\e[31m"  # Red
                    else "\e[0m"
                    end
    
    puts "🚔 #{priority_color}POLICE DISPATCH\e[0m ##{dispatch.dispatch_id}"
    puts "   Units: #{dispatch.units_assigned.join(', ')}"
    puts "   Location: #{dispatch.location}"
    puts "   Incident: #{dispatch.incident_type} (#{dispatch.priority.upcase} priority)"
    puts "   ETA: #{dispatch.estimated_arrival}" if dispatch.estimated_arrival
    puts "   Dispatched: #{dispatch.timestamp}"
    
    puts "🏦 Police response received - #{dispatch.units_assigned.size} units dispatched"
    puts "   ETA: #{dispatch.estimated_arrival}"
    puts "   Implementing security protocols..."
    @logger.info("Police response received: #{dispatch.units_assigned.join(', ')} dispatched, ETA #{dispatch.estimated_arrival}")
    
    # Simulate resolution after police arrive
    Thread.new do
      sleep(rand(180..600))  # 3-10 minutes for resolution
      resolve_security_incident
    end
  rescue => e
    puts "🏦 Error handling police response: #{e.message}"
    @logger.error("Error handling police response: #{e.message}")
  end

  def resolve_security_incident
    @alarm_active = false
    @security_level = 'normal'
    
    puts "🏦 ✅ Security incident resolved"
    puts "   Returning to normal operations"
    puts "   Security level: #{@security_level}"
    @logger.info("Security incident resolved, returning to normal operations")
  rescue => e
    puts "🏦 Error resolving security incident: #{e.message}"
    @logger.error("Error resolving security incident: #{e.message}")
  end
end

if __FILE__ == $0
  bank = LocalBank.new
  bank.start_operations
end