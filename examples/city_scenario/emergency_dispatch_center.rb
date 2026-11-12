#!/usr/bin/env ruby
# examples/city_scenario/emergency_dispatch_center.rb
# frozen_string_literal: true
#
# Answers 911 calls and routes each one to the Fire Department, the
# Police Department, or both.

require_relative 'common/service'
require_relative 'common/health_monitor'
require_relative 'messages/emergency_911_message'
require_relative 'messages/fire_emergency_message'

class EmergencyDispatchCenter
  include Common::Service
  include Common::HealthMonitor

  NAME            = 'emergency-dispatch-center'
  ADDRESS         = '911'
  FIRE            = 'fire_department'
  POLICE          = 'police_department'
  SEVERITY_COLORS = { 'critical' => "\e[91m", 'high' => "\e[31m", 'medium' => "\e[33m" }.freeze
  # 911 severities, mapped to FireEmergencyMessage::VALID_SEVERITY
  FIRE_SEVERITY   = { 'critical' => 'out_of_control', 'high' => 'large', 'medium' => 'medium', 'low' => 'small' }.freeze
  POLICE_KEYWORDS = /theft|robbery|assault|break.?in|suspicious/i

  def initialize
    setup_service(NAME)
    @call_counter   = 0
    @active_calls   = {}
    @dispatch_stats = Hash.new(0)

    setup_messaging
    setup_health_monitor
  end

  def setup_messaging
    Messages::Emergency911Message.subscribe(to: ADDRESS) { |call| handling('911 call') { handle_emergency_call(call) } }

    puts <<~BANNER
      📞 Emergency Dispatch Center (911) operational
         Routing emergency calls to appropriate departments
         Monitoring: Fire, Police, Medical, Accidents, Hazmat
         Press Ctrl+C to stop

    BANNER
    logger.info('Emergency Dispatch Center ready for 911 calls')
  end

  def run
    reason = run_service(5) { synchronize { close_handled_calls } }
    show_statistics
    shutdown_service(reason, 'Emergency Dispatch Center going offline...')
  end

  # @return [Array(String, String)] status and details for a health check
  def get_status_details
    ['healthy', "#{@call_counter} calls handled, #{@active_calls.size} active"]
  end

  def handle_emergency_call(call)
    @call_counter += 1
    call_id     = "911-#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{@call_counter.to_s.rjust(4, '0')}"
    departments = determine_dispatch_departments(call)

    puts <<~CALL

      #{SEVERITY_COLORS.fetch(call.severity, "\e[32m")}📞 911 CALL RECEIVED\e[0m ##{call_id}
         📍 Location: #{call.caller_location}
         🚨 Type: #{call.emergency_type.upcase}
         📝 Description: #{call.description}
         ⚠️  Severity: #{call.severity&.upcase || 'UNKNOWN'}
         👤 Caller: #{call.caller_name || 'Anonymous'} (#{call.caller_phone || 'No phone'})
         🚨 Dispatching to: #{departments.join(', ')}
    CALL
    logger.warn("911 CALL #{call_id}: #{call.emergency_type} at #{call.caller_location} - #{call.description}")

    @active_calls[call_id] = { received_at: Time.now, handled_after: rand(60..180), dispatched_to: departments }
    departments.each do |department|
      route_to_department(call, department, call_id)
      @dispatch_stats[department] += 1
    end
  end

  # @return [Array<String>] the departments a call goes to
  def determine_dispatch_departments(call)
    departments = []
    departments << FIRE   if fire_department_needed?(call)
    departments << POLICE if police_department_needed?(call)
    departments << POLICE if departments.empty?
    departments
  end

  def fire_department_needed?(call)
    call.fire_involved || call.hazardous_materials || call.injuries_reported ||
      %w[fire rescue medical hazmat].include?(call.emergency_type) ||
      call.number_of_victims.to_i.positive? ||
      (call.emergency_type == 'accident' && call.vehicles_involved.to_i > 2)
  end

  def police_department_needed?(call)
    call.weapons_involved || call.suspects_on_scene ||
      %w[crime accident].include?(call.emergency_type) ||
      (call.emergency_type == 'other' && call.description.match?(POLICE_KEYWORDS))
  end

  # A fire becomes a FireEmergencyMessage; every other call is forwarded
  # as it is, addressed to the department.
  #
  # @return [SmartMessage::PublishResult]
  def route_to_department(call, department, call_id)
    message = if department == FIRE && (call.fire_involved || call.emergency_type == 'fire')
                fire_emergency_for(call)
              else
                forwarded_call(call, department, call_id)
              end

    result = message.publish
    logger.info("Routed call #{call_id} to #{department} as #{message.class.name}")
    result
  end

  # @return [Messages::FireEmergencyMessage]
  def fire_emergency_for(call)
    Messages::FireEmergencyMessage.new(
      house_address:    call.caller_location,
      fire_type:        determine_fire_type(call),
      severity:         FIRE_SEVERITY.fetch(call.severity, 'medium'),
      occupants_status: call.injuries_reported ? 'trapped' : 'evacuated',
      spread_risk:      call.hazardous_materials ? 'high' : 'medium',
      timestamp:        Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      from:             NAME,
      to:               FIRE
    )
  end

  # @return [Messages::Emergency911Message] a new message with the call's properties
  def forwarded_call(call, department, call_id)
    Messages::Emergency911Message.new(
      **call.to_h.except(:_sm_header), call_id: call_id, dispatch_to: [department], from: NAME, to: department
    )
  end

  # @return [String] one of FireEmergencyMessage::VALID_FIRE_TYPES
  def determine_fire_type(call)
    description = call.description.downcase
    return 'kitchen'    if description.match?(/kitchen|grease/)
    return 'electrical' if description.match?(/electrical|wire/)
    return 'garage'     if description.include?('garage') || call.vehicles_involved.to_i.positive?

    'fire'
  end

  # A call counts as handled one to three minutes after it came in.
  def close_handled_calls(now = Time.now)
    handled = @active_calls.select { |_id, info| now - info[:received_at] > info[:handled_after] }
    handled.each_key do |call_id|
      @active_calls.delete(call_id)
      puts "📞 Call #{call_id} marked as handled"
      logger.info("Call #{call_id} handled")
    end
  end

  def show_statistics
    puts <<~STATS

      📊 Dispatch Statistics:
         Total 911 calls handled: #{@call_counter}
         Active calls: #{@active_calls.size}
         Dispatches by department: #{@dispatch_stats.map { |department, count| "#{department}: #{count}" }.join(', ')}
    STATS
  end

  def service_emoji = '📞'
end

EmergencyDispatchCenter.new.run if __FILE__ == $PROGRAM_NAME
