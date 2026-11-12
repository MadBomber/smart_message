#!/usr/bin/env ruby
# examples/city_scenario/house.rb
# frozen_string_literal: true
#
# A house whose monitoring system occasionally reports a fire to the Fire
# Department and waits for the fire dispatch that answers it.
#
#   ruby house.rb ['456 Oak Street']
#
#   CITY_FIRE_CHANCE   percent chance of a fire per activity (default 6)

require_relative 'common/service'
require_relative 'common/health_monitor'
require_relative 'messages/fire_emergency_message'
require_relative 'messages/fire_dispatch_message'

class House
  include Common::Service
  include Common::HealthMonitor

  FIRE_DEPARTMENT       = 'fire_department'
  FIRE_CHANCE           = Integer(ENV.fetch('CITY_FIRE_CHANCE', '6')) # percent
  SECONDS_BETWEEN_FIRES = 600
  STREET_NAMES          = [
    'Oak Street', 'Maple Avenue', 'Pine Lane', 'Cedar Drive', 'Elm Court',
    'Birch Road', 'Willow Way', 'Ash Boulevard', 'Cherry Street', 'Poplar Lane'
  ].freeze
  ACTIVITIES            = [
    'Security system armed', 'Temperature adjusted', 'Motion detected - normal activity',
    'Smoke detector test completed', 'Door/window sensor check', 'All systems operational'
  ].freeze
  SPREAD_RISKS          = { 'small' => 'low', 'medium' => 'medium', 'large' => 'high', 'out_of_control' => 'high' }.freeze

  # @return [String] the service name of the house at +address+
  def self.service_name_for(address)
    "house-#{address.gsub(/\s+/, '-').downcase}"
  end

  def initialize(address = nil)
    @address = address || "#{rand(100..999)} #{STREET_NAMES.sample}"
    setup_service(self.class.service_name_for(@address))
    @fire_active     = false
    @last_fire_time  = nil
    @occupants       = rand(1..4)
    @occupant_status = 'safe'

    setup_messaging
    setup_health_monitor
  end

  def setup_messaging
    Messages::FireDispatchMessage.subscribe(to: service_name) do |dispatch|
      handling('fire dispatch') { handle_fire_response(dispatch) }
    end

    puts <<~BANNER
      🏠 House at #{@address} monitoring systems active
         Occupants: #{@occupants}
         Status: #{@occupant_status}
         Press Ctrl+C to shutdown monitoring

    BANNER
    logger.info("House monitoring started: #{@occupants} occupants, status: #{@occupant_status}")
  end

  def start_monitoring
    reason = run_service(-> { rand(15..45) }) { synchronize { simulate_house_activity } }
    shutdown_service(reason, "#{@address} monitoring system shutting down...")
  end

  # @return [Array(String, String)] status and details for a health check
  def get_status_details
    if @fire_active
      ['critical', "FIRE DETECTED - #{@occupants} occupants status: #{@occupant_status}"]
    elsif @occupant_status != 'safe'
      ['warning', "Emergency response active, #{@occupants} occupants #{@occupant_status}"]
    else
      ['healthy', "All systems normal, #{@occupants} occupants #{@occupant_status}"]
    end
  end

  # @return [Boolean] true when a new fire may start now
  def fire_allowed?(now = Time.now)
    !@fire_active && (@last_fire_time.nil? || now - @last_fire_time >= SECONDS_BETWEEN_FIRES)
  end

  def simulate_house_activity
    return unless fire_allowed?
    return start_fire if rand(100) < FIRE_CHANCE

    activity = ACTIVITIES.sample
    puts "🏠 #{activity}"
    logger.info("Normal activity: #{activity}")
  end

  # @return [Messages::FireEmergencyMessage] the published emergency
  def start_fire(fire_type = %w[kitchen electrical basement garage].sample)
    severity         = (fire_type == 'garage' ? %w[medium large out_of_control] : %w[small medium large]).sample
    occupants_status = occupants_status_for(severity)

    emergency = Messages::FireEmergencyMessage.new(
      house_address:    @address,
      fire_type:        fire_type,
      severity:         severity,
      timestamp:        Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      occupants_status: occupants_status,
      spread_risk:      SPREAD_RISKS.fetch(severity),
      from:             service_name,
      to:               FIRE_DEPARTMENT
    )
    emergency.publish

    @fire_active     = true
    @last_fire_time  = Time.now
    @occupant_status = occupants_status

    puts <<~FIRE
      🏠 🔥 FIRE EMERGENCY 🔥
         Address: #{@address}
         Type: #{fire_type.upcase}
         Severity: #{severity.upcase}
         Occupants: #{occupants_status}
    FIRE
    logger.warn("FIRE EMERGENCY: #{fire_type} fire (#{severity}) - Occupants: #{occupants_status}")
    emergency
  end

  # At night, or when the fire is out of control, people may be trapped.
  # @return [String] one of FireEmergencyMessage::VALID_OCCUPANTS_STATUS
  def occupants_status_for(severity, hour = Time.now.hour)
    night = hour >= 22 || hour <= 6
    severity == 'out_of_control' || night ? %w[evacuated trapped].sample : 'evacuated'
  end

  def handle_fire_response(dispatch)
    puts <<~DISPATCH
      🚒 \e[31mFIRE DISPATCH\e[0m ##{dispatch.dispatch_id}
         Engines: #{dispatch.engines_assigned.join(', ')}
         Fire Type: #{dispatch.fire_type}
         Equipment: #{dispatch.equipment_needed}
         ETA: #{dispatch.estimated_arrival}
    DISPATCH
    logger.info("Fire department response: #{dispatch.engines_assigned.join(', ')} dispatched, ETA #{dispatch.estimated_arrival}")

    if @occupant_status == 'trapped'
      @occupant_status = 'rescued'
      puts '🏠 🚒 Occupants successfully rescued!'
      logger.info('Occupants rescued by fire department')
    end

    # The fire is out a few minutes after the engines arrive.
    Thread.new do
      sleep(rand(300..900))
      synchronize { extinguish_fire }
    end
  end

  def extinguish_fire
    @fire_active     = false
    @occupant_status = 'safe'
    puts '🏠 ✅ Fire extinguished, all occupants safe'
    logger.info('Fire extinguished, all occupants safe, returning to normal')
  end

  def service_emoji = '🏠'
end

House.new(ARGV[0]).start_monitoring if __FILE__ == $PROGRAM_NAME
