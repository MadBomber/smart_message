#!/usr/bin/env ruby
# examples/city_scenario/citizen.rb
# frozen_string_literal: true
#
# A citizen who calls 911.
#
#   ruby citizen.rb         interactive: press Enter to make a call
#   ruby citizen.rb auto    a call every 15-30 seconds
#
#   CITY_CALL_INTERVAL   seconds between automatic calls (default: random 15-30)

require_relative 'common/service'
require_relative 'messages/emergency_911_message'

class Citizen
  include Common::Service

  NAME      = 'citizen'
  DISPATCH  = '911'
  NAMES     = ['John Smith', 'Mary Johnson', 'Robert Williams', 'Patricia Brown', 'Michael Davis'].freeze
  LOCATIONS = [
    '123 Main Street', '456 Oak Avenue', '789 Pine Lane', '321 Elm Drive',
    '654 Maple Road', '987 Cedar Court', '147 Birch Way', '258 Spruce Boulevard'
  ].freeze
  SCENARIOS = [
    { type: 'fire',     severity: 'high',     description: 'House is on fire! Smoke everywhere!', fire: true, injuries: true, victims: 2 },
    { type: 'fire',     severity: 'critical', description: 'Kitchen grease fire spreading to cabinets!', fire: true },
    { type: 'medical',  severity: 'critical', description: 'Heart attack! Person unconscious!', injuries: true, victims: 1 },
    { type: 'medical',  severity: 'high',     description: 'Elderly person fell down stairs, bleeding heavily', injuries: true, victims: 1 },
    { type: 'crime',    severity: 'high',     description: "Break-in in progress! I can see them in my neighbor's house!", suspects: true },
    { type: 'crime',    severity: 'critical', description: 'Armed robbery at the corner store!', weapons: true, suspects: true },
    { type: 'crime',    severity: 'medium',   description: 'My car was stolen from my driveway' },
    { type: 'accident', severity: 'medium',   description: 'Two car collision at the intersection', vehicles: 2, injuries: true, victims: 2 },
    { type: 'accident', severity: 'critical', description: 'Multi-car pileup on the highway! At least 5 cars!', vehicles: 5, injuries: true, victims: 8, fire: true },
    { type: 'accident', severity: 'low',      description: 'Fender bender in parking lot', vehicles: 2 },
    { type: 'rescue',   severity: 'high',     description: 'Child stuck in storm drain!', victims: 1 },
    { type: 'rescue',   severity: 'critical', description: 'Person trapped in collapsed building!', injuries: true, victims: 2 },
    { type: 'hazmat',   severity: 'critical', description: 'Chemical spill from overturned truck! Strong fumes!', hazmat: true, injuries: true, victims: 3 },
    { type: 'other',    severity: 'low',      description: 'Suspicious person looking into car windows', suspects: true },
    { type: 'other',    severity: 'medium',   description: 'Power lines down across the road' }
  ].freeze

  def initialize
    setup_service(NAME)
  end

  # Build the 911 call for a scenario.  Nothing is published.
  #
  # @return [Messages::Emergency911Message]
  def build_call(scenario, caller_name: NAMES.sample, location: LOCATIONS.sample)
    Messages::Emergency911Message.new(
      caller_name:         caller_name,
      caller_phone:        "555-#{rand(1000..9999)}",
      caller_location:     location,
      emergency_type:      scenario[:type],
      description:         scenario[:description],
      severity:            scenario[:severity],
      injuries_reported:   scenario[:injuries],
      number_of_victims:   scenario[:victims],
      fire_involved:       scenario[:fire],
      weapons_involved:    scenario[:weapons],
      hazardous_materials: scenario[:hazmat],
      vehicles_involved:   scenario[:vehicles],
      suspects_on_scene:   scenario[:suspects],
      from:                "citizen-#{caller_name.downcase.tr(' ', '_')}",
      to:                  DISPATCH
    )
  end

  # @return [Messages::Emergency911Message, nil] the call, or nil when it could not be placed
  def make_emergency_call(scenario = SCENARIOS.sample)
    call = build_call(scenario)
    puts <<~CALL

      📱 Citizen making 911 call...
         Caller: #{call.caller_name}
         Location: #{call.caller_location}
         Emergency: #{call.emergency_type} - #{call.description}
    CALL

    call.publish
    puts '   ✅ 911 call placed successfully'
    logger.info("911 call placed: #{call.emergency_type} at #{call.caller_location} - #{call.description}")
    call
  rescue SmartMessage::Errors::Error => e
    puts "   ❌ Error making 911 call: #{e.message}"
    logger.error("Error making 911 call: #{e.class.name} - #{e.message}")
    nil
  end

  def run_interactive
    puts <<~HELP
      👤 Citizen 911 Emergency Caller
         Press Enter to make a random 911 call
         Type 'auto' for automatic calls every 15-30 seconds
         Type 'quit' to exit

    HELP

    loop do
      print 'Action (enter/auto/quit): '
      case $stdin.gets&.chomp&.downcase
      when ''                        then make_emergency_call
      when 'auto'                    then return run_automatic
      when 'quit', 'q', 'exit', nil  then break
      else puts "Unknown command. Press Enter for call, 'auto' for automatic, 'quit' to exit"
      end
    end

    shutdown_service(:quit, 'Citizen exiting...')
  end

  def run_automatic
    puts "\n👤 Starting automatic 911 calls. Press Ctrl+C to stop\n\n"
    reason = run_service(-> { call_interval }) { make_emergency_call }
    shutdown_service(reason, 'Stopping automatic calls...')
  end

  # @return [Numeric] seconds until the next automatic call
  def call_interval(env = ENV)
    env.key?('CITY_CALL_INTERVAL') ? Float(env['CITY_CALL_INTERVAL']) : rand(15..30)
  end

  def service_emoji = '👤'
end

if __FILE__ == $PROGRAM_NAME
  citizen = Citizen.new
  ARGV[0] == 'auto' ? citizen.run_automatic : citizen.run_interactive
end
