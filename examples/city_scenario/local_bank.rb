#!/usr/bin/env ruby
# examples/city_scenario/local_bank.rb
# frozen_string_literal: true
#
# A bank that occasionally sends a silent alarm to the Police Department
# and waits for the police dispatch that answers it.
#
#   CITY_ALARM_CHANCE   percent chance of an alarm per activity (default 8)

require_relative 'common/service'
require_relative 'common/health_monitor'
require_relative 'messages/silent_alarm_message'
require_relative 'messages/police_dispatch_message'

class LocalBank
  include Common::Service
  include Common::HealthMonitor

  NAME                = 'first-national-bank'
  LOCATION            = '123 Main Street'
  POLICE              = 'police_department'
  ALARM_CHANCE        = Integer(ENV.fetch('CITY_ALARM_CHANCE', '8')) # percent
  SECONDS_BETWEEN_ALARMS = 300
  ALARM_DETAILS       = {
    'robbery'             => 'Armed individuals at teller window, customers on floor',
    'vault_breach'        => 'Unauthorized access attempt detected in vault area',
    'suspicious_activity' => 'Multiple individuals casing the building, unusual behavior'
  }.freeze
  ACTIVITIES          = [
    'Customer transaction completed', 'ATM refilled', 'Vault inspection completed',
    'Security patrol completed', 'System backup completed'
  ].freeze
  PRIORITY_COLORS     = { 'low' => "\e[32m", 'medium' => "\e[33m", 'high' => "\e[93m", 'emergency' => "\e[31m" }.freeze

  def initialize
    setup_service(NAME)
    @alarm_active    = false
    @last_alarm_time = nil
    @security_level  = 'normal'

    setup_messaging
    setup_health_monitor
  end

  def setup_messaging
    Messages::PoliceDispatchMessage.subscribe(to: NAME) do |dispatch|
      handling('police dispatch') { handle_police_response(dispatch) }
    end

    puts <<~BANNER
      🏦 #{NAME} open for business
         Location: #{LOCATION}
         Security level: #{@security_level}
         Press Ctrl+C to close

    BANNER
    logger.info("#{NAME} open for business at #{LOCATION}")
  end

  def start_operations
    reason = run_service(-> { rand(10..30) }) { synchronize { simulate_bank_activity } }
    shutdown_service(reason, "#{NAME} closing for the day...")
  end

  # @return [Array(String, String)] status and details for a health check
  def get_status_details
    if @alarm_active
      ['critical', 'Security breach detected, lockdown protocols active']
    elsif @security_level == 'high'
      ['warning', 'Elevated security, monitoring active']
    else
      ['healthy', "All systems operational, security level: #{@security_level}"]
    end
  end

  # @return [Boolean] true when a new alarm may be raised now
  def alarm_allowed?(now = Time.now)
    !@alarm_active && (@last_alarm_time.nil? || now - @last_alarm_time >= SECONDS_BETWEEN_ALARMS)
  end

  def simulate_bank_activity
    return unless alarm_allowed?
    return trigger_silent_alarm if rand(100) < ALARM_CHANCE

    activity = ACTIVITIES.sample
    puts "🏦 #{activity}"
    logger.info("Normal operation: #{activity}")
  end

  # @return [Messages::SilentAlarmMessage] the published alarm
  def trigger_silent_alarm(alarm_type = ALARM_DETAILS.keys.sample)
    severity = alarm_type == 'robbery' ? 'critical' : %w[medium high critical].sample
    details  = ALARM_DETAILS.fetch(alarm_type)

    alarm = Messages::SilentAlarmMessage.new(
      bank_name:  NAME,
      location:   LOCATION,
      alarm_type: alarm_type,
      timestamp:  Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      severity:   severity,
      details:    details,
      from:       NAME,
      to:         POLICE
    )
    alarm.publish

    @alarm_active    = true
    @last_alarm_time = Time.now
    @security_level  = 'high'

    puts <<~ALARM
      🏦 🚨 SILENT ALARM TRIGGERED 🚨
         Type: #{alarm_type.upcase}
         Severity: #{severity.upcase}
         Details: #{details}
    ALARM
    logger.warn("SILENT ALARM TRIGGERED: #{alarm_type} (#{severity}) - #{details}")
    alarm
  end

  def handle_police_response(dispatch)
    puts <<~DISPATCH
      🚔 #{PRIORITY_COLORS.fetch(dispatch.priority, "\e[0m")}POLICE DISPATCH\e[0m ##{dispatch.dispatch_id}
         Units: #{dispatch.units_assigned.join(', ')}
         Incident: #{dispatch.incident_type} (#{dispatch.priority.upcase} priority)
         ETA: #{dispatch.estimated_arrival}
      🏦 Police response received - implementing security protocols...
    DISPATCH
    logger.info("Police response received: #{dispatch.units_assigned.join(', ')} dispatched, ETA #{dispatch.estimated_arrival}")

    # The incident is over a few minutes after the police arrive.
    Thread.new do
      sleep(rand(180..600))
      synchronize { resolve_security_incident }
    end
  end

  def resolve_security_incident
    @alarm_active   = false
    @security_level = 'normal'
    puts '🏦 ✅ Security incident resolved, returning to normal operations'
    logger.info('Security incident resolved, returning to normal operations')
  end

  def service_emoji = '🏦'
end

LocalBank.new.start_operations if __FILE__ == $PROGRAM_NAME
