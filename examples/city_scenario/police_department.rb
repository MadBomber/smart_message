#!/usr/bin/env ruby
# examples/city_scenario/police_department.rb
# frozen_string_literal: true
#
# Responds to silent alarms from banks and to 911 calls routed by the
# Emergency Dispatch Center.

require 'securerandom'

require_relative 'common/service'
require_relative 'common/health_monitor'
require_relative 'messages/silent_alarm_message'
require_relative 'messages/police_dispatch_message'
require_relative 'messages/emergency_resolved_message'
require_relative 'messages/emergency_911_message'

class PoliceDepartment
  include Common::Service
  include Common::HealthMonitor

  NAME                 = 'police_department'
  UNITS_FOR_ALARM      = { 'low' => 1, 'medium' => 2, 'high' => 3, 'critical' => 4 }.freeze
  PRIORITY_FOR_ALARM   = { 'low' => 'low', 'medium' => 'medium', 'high' => 'high', 'critical' => 'emergency' }.freeze
  UNITS_FOR_ACCIDENT   = { 'critical' => 3, 'high' => 2 }.freeze
  INCIDENT_PREFIXES    = { 'accident' => 'ACC', 'crime' => 'CRM' }.freeze
  CALL_COLORS          = { 'accident' => "\e[33m", 'crime' => "\e[31m" }.freeze
  OUTCOMES             = [
    'Suspects apprehended', 'False alarm - all clear', 'Incident resolved peacefully', 'Suspects fled scene'
  ].freeze

  def initialize
    setup_service(NAME)
    @active_incidents = {}
    @available_units  = %w[Unit-101 Unit-102 Unit-103 Unit-104]

    setup_messaging
    setup_health_monitor
  end

  def setup_messaging
    Messages::SilentAlarmMessage.subscribe(to: NAME) { |alarm| handling('silent alarm') { handle_silent_alarm(alarm) } }
    Messages::Emergency911Message.subscribe(to: NAME) { |call| handling('911 call') { handle_911_call(call) } }

    puts <<~BANNER
      🚔 Police Department operational
         Available units: #{@available_units.join(', ')}
         Responding to health checks, silent alarms, and 911 calls
         Press Ctrl+C to stop

    BANNER
    logger.info("Police Department operational with units: #{@available_units.join(', ')}")
  end

  def start_service
    reason = run_service(2) { synchronize { check_incident_resolutions } }
    shutdown_service(reason, 'Police Department signing off...')
  end

  # @return [Array(String, String)] status and details for a health check
  def get_status_details
    incidents = @active_incidents.size

    if @available_units.empty?
      ['critical', 'Multiple emergencies, all units deployed']
    elsif @available_units.size <= 1 || incidents >= 3
      ['warning', "High call volume, #{incidents} active incidents"]
    else
      ['healthy', "All units operational, #{incidents} active incidents"]
    end
  end

  def handle_silent_alarm(alarm)
    puts <<~ALARM
      🚨 SILENT ALARM: #{alarm.bank_name} at #{alarm.location} - #{alarm.alarm_type.upcase} (#{alarm.severity} severity)
         Details: #{alarm.details}
         Time: #{alarm.timestamp}
    ALARM
    logger.warn("SILENT ALARM received: #{alarm.alarm_type} at #{alarm.location} (#{alarm.severity} severity)")

    dispatch_id = SecureRandom.hex(4)
    units = assign_units(dispatch_id, alarm.alarm_type, alarm.location, UNITS_FOR_ALARM.fetch(alarm.severity, 2))
    return if units.empty?

    Messages::PoliceDispatchMessage.new(
      dispatch_id:       dispatch_id,
      units_assigned:    units,
      location:          alarm.location,
      incident_type:     alarm.alarm_type,
      priority:          PRIORITY_FOR_ALARM.fetch(alarm.severity, 'medium'),
      estimated_arrival: "#{rand(3..8)} minutes",
      timestamp:         Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      from:              NAME,
      to:                alarm.from
    ).publish
  end

  def handle_911_call(call)
    puts <<~CALL

      #{CALL_COLORS.fetch(call.emergency_type, "\e[36m")}🚔 911 CALL RECEIVED\e[0m from #{call.from}
         📍 Location: #{call.caller_location}
         🚨 Type: #{call.emergency_type.upcase}
         📝 Description: #{call.description}
         👤 Caller: #{call.caller_name || 'Unknown'}
    CALL
    logger.warn("911 Call: #{call.emergency_type} at #{call.caller_location} - #{call.description}")

    prefix      = INCIDENT_PREFIXES.fetch(call.emergency_type, 'GEN')
    incident_id = "#{prefix}-#{SecureRandom.hex(3)}"
    assign_units(incident_id, call.emergency_type, call.caller_location, units_for_call(call))
  end

  # @return [Integer] how many units a 911 call needs
  def units_for_call(call)
    case call.emergency_type
    when 'accident' then UNITS_FOR_ACCIDENT.fetch(call.severity, 1)
    when 'crime'    then call.weapons_involved ? 3 : 2
    else 1
    end
  end

  # Take up to +wanted+ units out of the pool for an incident.
  #
  # @return [Array<String>] the assigned units; empty when none are free
  def assign_units(incident_id, type, location, wanted)
    units = @available_units.shift(wanted)
    if units.empty?
      puts "🚔 ⚠️  No units available for #{type} at #{location}!"
      logger.error("No units available for #{type} at #{location}")
      return units
    end

    @active_incidents[incident_id] = {
      type: type, location: location, units: units, start_time: Time.now, resolve_after: rand(10..15)
    }
    puts "🚔 Dispatched #{units.join(', ')} to #{type} at #{location} (#{@available_units.size} units left)"
    logger.info("Dispatched #{units.join(', ')} to #{type} #{incident_id}")
    units
  end

  # Incidents resolve themselves 10-15 seconds after dispatch.
  def check_incident_resolutions(now = Time.now)
    due = @active_incidents.select { |_id, incident| now - incident[:start_time] > incident[:resolve_after] }
    due.each { |incident_id, incident| resolve_incident(incident_id, incident, now - incident[:start_time]) }
  end

  def resolve_incident(incident_id, incident, duration_seconds)
    @available_units.concat(incident[:units])
    @active_incidents.delete(incident_id)
    minutes = (duration_seconds / 60.0).round(1)
    outcome = OUTCOMES.sample

    Messages::EmergencyResolvedMessage.new(
      incident_id:      incident_id,
      incident_type:    incident[:type],
      location:         incident[:location],
      resolved_by:      NAME,
      resolution_time:  Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      duration_minutes: minutes,
      outcome:          outcome,
      units_involved:   incident[:units],
      from:             NAME
    ).publish

    puts "🚔 Incident #{incident_id} resolved after #{minutes} minutes; #{incident[:units].join(', ')} available again"
    logger.info("Incident #{incident_id} resolved: #{outcome} after #{minutes} minutes")
  end

  def service_emoji = '🚔'
end

PoliceDepartment.new.start_service if __FILE__ == $PROGRAM_NAME
