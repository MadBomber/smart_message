#!/usr/bin/env ruby
# examples/city_scenario/health_department.rb
# frozen_string_literal: true
#
# Broadcasts a health check every few seconds, shows the status each city
# service sends back, and reports resolved emergencies.

require_relative 'common/service'
require_relative 'messages/health_check_message'
require_relative 'messages/health_status_message'
require_relative 'messages/emergency_resolved_message'

class HealthDepartment
  include Common::Service

  NAME              = 'health-department'
  HEALTH_CHECK_RATE = Float(ENV.fetch('CITY_HEALTH_CHECK_RATE', '5')) # seconds
  STATUS_COLORS     = {
    'healthy'  => "\e[32m", # green
    'warning'  => "\e[33m", # yellow
    'critical' => "\e[93m", # orange
    'failed'   => "\e[31m"  # red
  }.freeze

  def initialize
    setup_service(NAME)
    @check_id = 0
    setup_messaging
  end

  def setup_messaging
    # Services address their status to the sender of the health check.
    Messages::HealthStatusMessage.subscribe(to: NAME) { |status| show_status(status) }
    Messages::EmergencyResolvedMessage.subscribe(broadcast: true) { |resolved| show_resolution(resolved) }

    puts <<~BANNER
      🏥 Health Department started
         Broadcasting a HealthCheck every #{HEALTH_CHECK_RATE} seconds
         Logging to: #{Common::City.log_file(NAME)}
         Press Ctrl+C to stop

    BANNER
    logger.info('Health Department started monitoring city services')
  end

  def start_monitoring
    reason = run_service(HEALTH_CHECK_RATE) { send_health_check }
    shutdown_service(reason, 'Health Department shutting down...')
  end

  # @return [Messages::HealthCheckMessage] the published health check
  def send_health_check
    @check_id += 1
    health_check = Messages::HealthCheckMessage.new(check_id: @check_id, from: NAME)
    health_check.publish

    puts "\n🏥 Broadcasting health check ##{@check_id} (#{health_check.uuid[0..7]}...)"
    logger.info("Broadcasting health check ##{@check_id}")
    health_check
  end

  def show_status(status)
    color = STATUS_COLORS.fetch(status.status, "\e[0m")
    puts "#{color}#{status.service_name}: #{status.status.upcase}\e[0m #{status.details}"
    logger.info("Received health status: #{status.service_name} = #{status.status} (#{status.details})")
  end

  def show_resolution(resolved)
    puts "✅ #{resolved.resolved_by} resolved #{resolved.incident_type} at #{resolved.location}: #{resolved.outcome}"
    logger.info("Incident #{resolved.incident_id} resolved by #{resolved.resolved_by}: #{resolved.outcome}")
  end

  def service_emoji = '🏥'
end

HealthDepartment.new.start_monitoring if __FILE__ == $PROGRAM_NAME
