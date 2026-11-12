#!/usr/bin/env ruby
# examples/city_scenario/visitor.rb
# frozen_string_literal: true
#
# A visitor who reports what they see in the city.  The visitor knows
# nothing about the city's message classes in advance: an agent reads
# their descriptions, chooses one for each observation, and fills it in.
#
#   ruby visitor.rb             an observation every 15 seconds
#   ruby visitor.rb 5           an observation every 5 seconds
#   ruby visitor.rb --once      one observation, then exit
#
# See smart_message_ai_agent.rb for how the language model is used and
# what happens without one.

require_relative 'smart_message_ai_agent'
Dir[File.join(__dir__, 'messages', '*.rb')].each { |file| require file }

class Visitor < SmartMessageAIAgent
  NAME       = 'visitor'
  # The message classes a member of the public may send, and to whom.
  RECIPIENTS = {
    'Emergency911Message'  => '911',
    'FireEmergencyMessage' => 'fire_department',
    'SilentAlarmMessage'   => 'police_department'
  }.freeze
  # Observation types, mapped to Emergency911Message::VALID_EMERGENCY_TYPES
  EMERGENCY_TYPES = Hash.new('other').merge(
    'crime' => 'crime', 'fire' => 'fire', 'accident' => 'accident',
    'medical' => 'medical', 'hazmat' => 'hazmat', 'rescue' => 'rescue'
  ).freeze
  SCENARIOS = [
    { type: 'crime',      description: 'Witnessed armed robbery at convenience store',
      context: 'A visitor witnessed an armed robbery at a local convenience store. Two suspects with weapons.' },
    { type: 'fire',       description: 'Smoke coming from apartment building',
      context: 'A visitor noticed heavy smoke coming from a third-floor apartment window.' },
    { type: 'accident',   description: 'Multi-car collision at intersection',
      context: 'A visitor witnessed a three-car collision at a busy intersection. People may be injured.' },
    { type: 'medical',    description: 'Person collapsed on sidewalk',
      context: 'A visitor found an elderly person who collapsed on the sidewalk, unconscious but breathing.' },
    { type: 'suspicious', description: 'Someone breaking into parked cars',
      context: 'A visitor observed someone systematically checking car doors and breaking into unlocked vehicles.' },
    { type: 'hazmat',     description: 'Chemical smell from abandoned truck',
      context: 'A visitor noticed a strong chemical odor coming from an abandoned delivery truck.' },
    { type: 'rescue',     description: 'Child stuck on roof',
      context: 'A visitor spotted a child stuck on a roof, unable to get down safely.' }
  ].freeze

  def initialize
    super(NAME)
    @observation_count = 0
  end

  def include_message_class?(message_class)
    RECIPIENTS.key?(message_class.name.split('::').last)
  end

  def recipient_for(message_class)
    RECIPIENTS[message_class.name.split('::').last]
  end

  def build_selection_context(scenario)
    <<~CONTEXT
      You are helping a visitor to a city report an incident they witnessed.
      Scenario: #{scenario[:context]}
      Choose the message type of the city's emergency communication system that fits best.
      For a member of the public, Emergency911Message is usually the right one.
    CONTEXT
  end

  def build_property_context(scenario, message_class)
    <<~CONTEXT
      You are filling in a #{message_class} report for an incident a visitor witnessed.
      Scenario: #{scenario[:context]}
      Use only the listed valid values where a property names them. Leave out properties you cannot know.
    CONTEXT
  end

  def fallback_message_class(available, _scenario)
    available.fetch('Emergency911Message') { available.values.first }
  end

  def generate_fallback_values(_message_class, scenario)
    {
      caller_name:       'Anonymous Visitor',
      caller_phone:      '555-0123',
      caller_location:   '456 Oak Street',
      emergency_type:    EMERGENCY_TYPES[scenario[:type]],
      description:       scenario[:description],
      severity:          'high',
      weapons_involved:  scenario[:type] == 'crime',
      suspects_on_scene: %w[crime suspicious].include?(scenario[:type]),
      fire_involved:     scenario[:type] == 'fire'
    }
  end

  # @return [SmartMessage::Base, nil] the published report, or nil when it failed
  def report_observation(scenario = SCENARIOS.sample)
    @observation_count += 1
    puts <<~OBSERVATION

      #{'=' * 60}
      📍 OBSERVATION ##{@observation_count} - #{Time.now.strftime('%H:%M:%S')}
         Type: #{scenario[:type].upcase}
         What I see: #{scenario[:description]}
    OBSERVATION

    message = send_message_for_scenario(scenario)
    puts "   ✅ Report sent via #{message.class.name.split('::').last} to #{message.to || 'everybody'}"
    message
  rescue StandardError => e
    puts "   ❌ Could not report: #{e.message}"
    logger.error("Observation ##{@observation_count} could not be reported: #{e.class.name} - #{e.message}")
    nil
  end

  def run_continuous(interval_seconds = 15)
    puts <<~BANNER
      👁️  Smart Visitor - observation reporting (AI #{ai_available ? 'on' : 'off, using fallback rules'})
         A new observation every #{interval_seconds} seconds
         Logging to: #{Common::City.log_file(NAME)}
         Press Ctrl+C to stop
    BANNER

    reason = run_service(interval_seconds) { report_observation }
    shutdown_service(reason, "Visitor signing off after #{@observation_count} observations.")
  end

  def service_emoji = '👁️'
end

if __FILE__ == $PROGRAM_NAME
  visitor = Visitor.new

  if %w[--once -o].include?(ARGV[0])
    reported = visitor.report_observation
    Common::City.teardown!
    exit(reported ? 0 : 1)
  else
    visitor.run_continuous(ARGV[0] ? Float(ARGV[0]) : 15)
  end
end
