#!/usr/bin/env ruby
# examples/multi_program_demo/emergency_dispatch_center.rb

require_relative '../../lib/smart_message'
require_relative 'messages/emergency_911_message'
require_relative 'messages/fire_emergency_message'
require_relative 'messages/silent_alarm_message'

require_relative 'common/health_monitor'
require_relative 'common/logger'

class EmergencyDispatchCenter
  include Common::HealthMonitor
  include Common::Logger

  def initialize
    @service_name = 'emergency-dispatch-center'

    @status = 'healthy'
    @start_time = Time.now
    @call_counter = 0
    @active_calls = {}
    @dispatch_stats = Hash.new(0)

    setup_messaging
    setup_signal_handlers
    setup_health_monitor
  end


  def setup_messaging
    Messages::Emergency911Message.from(@service_name)
    Messages::FireEmergencyMessage.from(@service_name)
    Messages::SilentAlarmMessage.from(@service_name)

    # Subscribe to 911 emergency calls
    Messages::Emergency911Message.subscribe(to: '911') do |message|
      handle_emergency_call(message)
    end

    puts '📞 Emergency Dispatch Center (911) operational'
    puts '   Routing emergency calls to appropriate departments'
    puts '   Monitoring: Fire, Police, Medical, Accidents, Hazmat'
    puts '   Logging to: emergency_dispatch_center.log'
    puts "   Press Ctrl+C to stop\n\n"
    logger.info('Emergency Dispatch Center ready for 911 calls')
  end


  def get_status_details
    [@status, @details]
  end

  def setup_signal_handlers
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        puts "\n📞 Emergency Dispatch Center going offline..."
        show_statistics
        logger.info('Emergency Dispatch Center shutting down')
        exit(0)
      end
    end
  end


  def run
    puts '📞 Emergency Dispatch Center listening for 911 calls...'
    loop do
      sleep 1
      @status = 'healthy'
    end
  rescue StandardError => e
    puts "📞 Error in dispatch center: #{e.message}"
    logger.error({alert:"Error in dispatch center", message: e.message, traceback: e.backtrace})
    logger.error(e.backtrace.join("\n"))
  end

  private

  def handle_emergency_call(call)
    @call_counter += 1
    call_id = "911-#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{@call_counter.to_s.rjust(4, '0')}"

    # Color code based on severity
    severity_color = case call.severity
                     when 'critical' then "\e[91m" # Bright red
                     when 'high' then "\e[31m"     # Red
                     when 'medium' then "\e[33m"   # Yellow
                     else "\e[32m"                 # Green
                     end

    puts "\n#{severity_color}📞 911 CALL RECEIVED\e[0m ##{call_id}"
    puts "   📍 Location: #{call.caller_location}"
    puts "   🚨 Type: #{call.emergency_type.upcase}"
    puts "   📝 Description: #{call.description}"
    puts "   ⚠️  Severity: #{call.severity&.upcase || 'UNKNOWN'}"
    puts "   👤 Caller: #{call.caller_name || 'Anonymous'} (#{call.caller_phone || 'No phone'})"

    logger.warn("911 CALL #{call_id}: #{call.emergency_type} at #{call.caller_location} - #{call.description}")

    @active_calls[call_id] = {
      call: call,
      received_at: Time.now,
      dispatched_to: []
    }

    # Determine which departments to dispatch to
    departments_to_dispatch = determine_dispatch_departments(call)

    puts "   🚨 Dispatching to: #{departments_to_dispatch.join(', ')}"

    # Route to appropriate departments
    departments_to_dispatch.each do |dept|
      route_to_department(call, dept, call_id)
      @dispatch_stats[dept] += 1
    end

    # After a delay, consider the call handled
    Thread.new do
      sleep(rand(60..180)) # Simulate response time
      if @active_calls[call_id]
        puts "📞 Call #{call_id} marked as handled"
        logger.info("Call #{call_id} handled after #{(Time.now - @active_calls[call_id][:received_at]).round} seconds")
        @active_calls.delete(call_id)
      end
    end
  rescue StandardError => e
    puts "📞 Error handling 911 call: #{e.message} #{e.backtrace.join("\n")}"
    logger.error({alert:"Error handling 911 call", message: e.message, traceback: e.backtrace})
  end


  def determine_dispatch_departments(call)
    departments = []

    # Fire department dispatch rules
    if call.fire_involved ||
       call.emergency_type == 'fire' ||
       call.emergency_type == 'rescue' ||
       (call.emergency_type == 'accident' && call.vehicles_involved && call.vehicles_involved > 2) ||
       call.hazardous_materials
      departments << 'fire_department'
    end

    # Police department dispatch rules
    if call.emergency_type == 'crime' ||
       call.weapons_involved ||
       call.suspects_on_scene ||
       call.emergency_type == 'accident' ||
       (call.emergency_type == 'other' && call.description =~ /theft|robbery|assault|break.?in|suspicious/i)
      departments << 'police_department'
    end

    # Medical (would go to EMS, but we'll send to fire for this demo)
    if (call.emergency_type == 'medical' ||
       call.injuries_reported ||
       (call.number_of_victims && call.number_of_victims > 0)) && !departments.include?('fire_department')
      departments << 'fire_department'
    end

    # Default to police if no specific department determined
    departments << 'police_department' if departments.empty?

    departments
  end


  def route_to_department(call, department, call_id)
    case department
    when 'fire_department'
      # Convert to FireEmergencyMessage for fire department
      if call.fire_involved || call.emergency_type == 'fire'
        fire_msg = Messages::FireEmergencyMessage.new(
          house_address: call.caller_location,
          fire_type: determine_fire_type(call),
          severity: call.severity || 'medium',
          occupants_status: build_occupants_status(call),
          spread_risk: call.hazardous_materials ? 'high' : 'medium',
          timestamp: call._sm_header.published_at,
          emergency_id: call_id
        )
        fire_msg._sm_header.from = '911-dispatch'
        fire_msg._sm_header.to   = 'fire_department'
        fire_msg.publish
        logger.info("Routed call #{call_id} to Fire Department as fire emergency")
      else
        # For rescue/medical, forward the 911 call directly
        forward_call = call.dup
        forward_call.call_id         = call_id
        forward_call._sm_header.from = '911-dispatch'
        forward_call._sm_header.to   = 'fire_department'
        forward_call.publish
        logger.info("Forwarded call #{call_id} to Fire Department for rescue/medical")
      end

    when 'police_department'
      # Forward all police calls directly as Emergency911Message
      forward_call = Messages::Emergency911Message.new(**call.to_h.merge(
                                                         call_id: call_id,
                                                         from: '911-dispatch',
                                                         to: 'police_department'
                                                       ))
      forward_call._sm_header.from = '911-dispatch'
      forward_call._sm_header.to   = 'police_department'
      forward_call.publish
      
      if call.emergency_type == 'crime' || call.weapons_involved || call.suspects_on_scene
        logger.info("Routed call #{call_id} to Police Department as crime report")
      else
        logger.info("Forwarded call #{call_id} to Police Department")
      end
    end

    @active_calls[call_id][:dispatched_to] << department if @active_calls[call_id]
  rescue StandardError => e
    logger.error({alert:"Error routing to #{department}", message: e.message, trace: e.backtrace})
    raise
  end


  def determine_fire_type(call)
    return 'chemical' if call.hazardous_materials
    return 'vehicle' if call.vehicles_involved && call.vehicles_involved > 0

    desc = call.description.downcase
    return 'electrical' if desc.include?('electrical') || desc.include?('wire')
    return 'grease' if desc.include?('kitchen') || desc.include?('grease')
    return 'chemical' if desc.include?('chemical') || desc.include?('gas')

    'general'
  end


  def determine_alarm_type(call)
    return 'armed_robbery' if call.weapons_involved
    return 'break_in' if call.description =~ /break.?in/i
    return 'assault' if call.description =~ /assault|attack/i
    return 'robbery' if call.description =~ /robbery|theft/i

    'suspicious_activity'
  end


  def build_occupants_status(call)
    if call.injuries_reported
      "#{call.number_of_victims || 'Unknown number of'} injured"
    elsif call.number_of_victims && call.number_of_victims > 0
      "#{call.number_of_victims} people involved"
    else
      'Unknown'
    end
  end


  def show_statistics
    puts "\n📊 Dispatch Statistics:"
    puts "   Total 911 calls handled: #{@call_counter}"
    puts "   Active calls: #{@active_calls.size}"
    puts '   Dispatches by department:'
    @dispatch_stats.each do |dept, count|
      puts "     #{dept}: #{count}"
    end
  end
end

# Run the dispatch center
if __FILE__ == $0
  dispatch = EmergencyDispatchCenter.new
  dispatch.run
end
