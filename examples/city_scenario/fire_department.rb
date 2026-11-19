#!/usr/bin/env ruby
# examples/city_scenario/fire_department.rb
# frozen_string_literal: true
#
# Responds to fire emergencies from houses and from the Emergency Dispatch
# Center, and to the medical, rescue, hazmat and accident 911 calls the
# dispatch center routes here.

require 'securerandom'

require_relative 'common/service'
require_relative 'common/health_monitor'
require_relative 'messages/fire_emergency_message'
require_relative 'messages/fire_dispatch_message'
require_relative 'messages/emergency_resolved_message'
require_relative 'messages/emergency_911_message'

class FireDepartment
  include Common::Service
  include Common::HealthMonitor

  NAME               = 'fire_department'
  ENGINES_FOR_FIRE   = { 'small' => 1, 'medium' => 2, 'large' => 3, 'out_of_control' => 5 }.freeze
  FIRE_COLORS        = { 'small' => "\e[33m", 'medium' => "\e[93m", 'large' => "\e[31m", 'out_of_control' => "\e[91m" }.freeze
  EQUIPMENT_FOR_FIRE = {
    'kitchen'    => ['Class K extinguishers'],
    'electrical' => ['Class C extinguishers', 'Power shut-off tools'],
    'basement'   => ['Ventilation fans', 'Search and rescue gear'],
    'garage'     => ['Foam suppressant'],
    'wildfire'   => ['Brush trucks', 'Water tenders']
  }.freeze
  # How each kind of 911 call is answered: incident id prefix, the units
  # that are sent first when they are free, and how many units go.
  CALL_RESPONSES = {
    'medical'  => { prefix: 'MED', preferred: %w[Rescue-1],          units: ->(call) { call.severity == 'critical' ? 2 : 1 } },
    'rescue'   => { prefix: 'RSC', preferred: %w[Rescue-1 Ladder-1], units: ->(_call) { 2 } },
    'hazmat'   => { prefix: 'HAZ', preferred: [],                    units: ->(_call) { 3 } },
    'accident' => { prefix: 'MVA', preferred: [],                    units: ->(call) { call.vehicles_involved.to_i > 3 ? 3 : 2 } }
  }.freeze
  DEFAULT_RESPONSE = { prefix: 'EMG', preferred: [], units: ->(_call) { 1 } }.freeze
  OUTCOMES         = [
    'Fire extinguished successfully', 'Fire contained with minimal damage',
    'Structure saved, investigating cause', 'Total loss, area secured'
  ].freeze

  def initialize
    setup_service(NAME)
    @active_incidents  = {}
    @available_engines = %w[Engine-1 Engine-2 Engine-3 Ladder-1 Rescue-1]

    setup_messaging
    setup_health_monitor
  end

  def setup_messaging
    Messages::FireEmergencyMessage.subscribe(to: NAME) { |fire| handling('fire emergency') { handle_fire_emergency(fire) } }
    Messages::Emergency911Message.subscribe(to: NAME) { |call| handling('911 call') { handle_911_call(call) } }

    puts <<~BANNER
      🚒 Fire Department ready for service
         Available engines: #{@available_engines.join(', ')}
         Responding to health checks, fire emergencies, and 911 medical/rescue calls
         Press Ctrl+C to stop

    BANNER
    logger.info("Fire Department ready for service with engines: #{@available_engines.join(', ')}")
  end

  def start_service
    reason = run_service(3) { synchronize { check_resolutions } }
    shutdown_service(reason, 'Fire Department out of service...')
  end

  # @return [Array(String, String)] status and details for a health check
  def get_status_details
    incidents = @active_incidents.size
    engines   = @available_engines.size

    if incidents >= 3
      ['critical', "#{engines} engines available, #{incidents} active incidents"]
    elsif incidents >= 2 || engines < 2
      ['warning', "#{engines} engines available, #{incidents} active incidents"]
    else
      ['healthy', "All engines available, #{incidents} active incidents"]
    end
  end

  def handle_fire_emergency(emergency)
    puts <<~FIRE
      🔥 #{FIRE_COLORS.fetch(emergency.severity, "\e[0m")}FIRE EMERGENCY\e[0m: #{emergency.house_address}
         Type: #{emergency.fire_type} | Severity: #{emergency.severity.upcase}
         Occupants: #{emergency.occupants_status || 'unknown'}
         Spread Risk: #{emergency.spread_risk || 'unknown'}
         Time: #{emergency.timestamp}
    FIRE
    logger.warn("FIRE EMERGENCY: #{emergency.fire_type} fire at #{emergency.house_address} (#{emergency.severity} severity)")

    dispatch_id = SecureRandom.hex(4)
    engines     = assign_engines(dispatch_id, "#{emergency.fire_type} fire", emergency.house_address,
                                 ENGINES_FOR_FIRE.fetch(emergency.severity, 2), severity: emergency.severity)
    return if engines.empty?

    Messages::FireDispatchMessage.new(
      dispatch_id:       dispatch_id,
      engines_assigned:  engines,
      location:          emergency.house_address,
      fire_type:         emergency.fire_type,
      equipment_needed:  equipment_needed(emergency.fire_type, emergency.severity),
      estimated_arrival: "#{rand(4..10)} minutes",
      timestamp:         Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      from:              NAME,
      to:                emergency.from
    ).publish
  end

  def handle_911_call(call)
    puts <<~CALL

      🚒 911 EMERGENCY from #{call.from}
         📍 Location: #{call.caller_location}
         🚨 Type: #{call.emergency_type.upcase}
         📝 Description: #{call.description}
         👤 Caller: #{call.caller_name || 'Unknown'}
    CALL
    logger.warn("911 Emergency: #{call.emergency_type} at #{call.caller_location} - #{call.description}")

    response = CALL_RESPONSES.fetch(call.emergency_type, DEFAULT_RESPONSE)
    assign_engines("#{response[:prefix]}-#{SecureRandom.hex(3)}", call.emergency_type, call.caller_location,
                   response[:units].call(call), preferred: response[:preferred], severity: call.severity)
  end

  # Take up to +wanted+ engines out of the pool, preferred units first.
  #
  # @return [Array<String>] the assigned engines; empty when none are free
  def assign_engines(incident_id, type, location, wanted, preferred: [], severity: nil)
    engines = choose_engines(@available_engines, wanted, preferred)
    if engines.empty?
      puts "🚒 ⚠️  No units available for #{type} at #{location}!"
      logger.error("No units available for #{type} at #{location}")
      return engines
    end

    @available_engines -= engines
    @active_incidents[incident_id] = {
      type: type, location: location, engines: engines, severity: severity,
      start_time: Time.now, resolve_after: rand(10..15)
    }
    puts "🚒 Dispatched #{engines.join(', ')} to #{type} at #{location} (#{@available_engines.size} engines left)"
    logger.info("Dispatched #{engines.join(', ')} to #{type} #{incident_id}")
    engines
  end

  # @return [Array<String>] up to +wanted+ of +available+, preferred first
  def choose_engines(available, wanted, preferred = [])
    chosen = (preferred & available).first(wanted)
    chosen + (available - chosen).first(wanted - chosen.size)
  end

  # Incidents resolve themselves 10-15 seconds after dispatch.
  def check_resolutions(now = Time.now)
    due = @active_incidents.select { |_id, incident| now - incident[:start_time] > incident[:resolve_after] }
    due.each { |incident_id, incident| resolve_incident(incident_id, incident, now - incident[:start_time]) }
  end

  def resolve_incident(incident_id, incident, duration_seconds)
    @available_engines.concat(incident[:engines])
    @active_incidents.delete(incident_id)
    minutes = (duration_seconds / 60.0).round(1)
    outcome = incident[:type].end_with?('fire') ? OUTCOMES.sample : 'Scene cleared'

    Messages::EmergencyResolvedMessage.new(
      incident_id:      incident_id,
      incident_type:    incident[:type],
      location:         incident[:location],
      resolved_by:      NAME,
      resolution_time:  Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      duration_minutes: minutes,
      outcome:          outcome,
      units_involved:   incident[:engines],
      from:             NAME
    ).publish

    puts "🚒 #{incident[:type]} #{incident_id} resolved after #{minutes} minutes; #{incident[:engines].join(', ')} returning to station"
    logger.info("Incident #{incident_id} resolved: #{outcome} after #{minutes} minutes")
  end

  # @return [String] the equipment a fire of this type and severity needs
  def equipment_needed(fire_type, severity)
    equipment = EQUIPMENT_FOR_FIRE.fetch(fire_type, [])
    equipment += ['Aerial ladder', 'Additional water supply'] if %w[large out_of_control].include?(severity)
    equipment.join(', ')
  end

  def service_emoji = '🚒'
end

FireDepartment.new.start_service if __FILE__ == $PROGRAM_NAME
