#!/usr/bin/env ruby

HEALTH_CHECK_RATE = 5 # seconds; setting to zero gets overruns and 1300+ msg/sec

require 'smart_message'
require 'smart_message/transport/redis_transport'
require 'smart_message/serializer/json'
require 'securerandom'
require 'logger'
require_relative 'messages/health_check_message'
require_relative 'messages/health_status_message'

class HealthDepartment
  def initialize
    @service_name = 'health-department'
    @check_counter = 0
    setup_logging
    setup_messaging
    setup_signal_handlers
  end

  def setup_logging
    log_file = File.join(__dir__, 'health_department.log')
    @logger = Logger.new(log_file)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
    @logger.info("Health Department logging started")
  end

  def setup_messaging
    # Subscribe to all broadcast health status messages
    Messages::HealthStatusMessage.subscribe(broadcast: true) do |message|
      # Process health status message with colored output
      status_color = case message.status
                    when 'healthy' then "\e[32m"    # Green
                    when 'warning' then "\e[33m"    # Yellow
                    when 'critical' then "\e[93m"   # Orange
                    when 'failed' then "\e[31m"     # Red
                    else "\e[0m"                     # Reset
                    end

      puts "#{status_color}#{message.service_name}: #{message.status.upcase}\e[0m #{message.details}"
      @logger.info("Received health status: #{message.service_name} = #{message.status} (#{message.details})")
    end

    puts "🏥 Health Department started"
    puts "   Monitoring city services health status..."
    puts "   Will send HealthCheck broadcasts every 5 seconds"
    puts "   Logging to: health_department.log"
    puts "   Press Ctrl+C to stop\n\n"
    @logger.info("Health Department started monitoring city services")
  end

  def setup_signal_handlers
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        puts "\n🏥 Health Department shutting down..."
        @logger.info("Health Department shutting down")
        exit(0)
      end
    end
  end

  def start_monitoring
    loop do
      send_health_check
      sleep(HEALTH_CHECK_RATE)
    end
  rescue => e
    puts "🏥 Error in health monitoring: #{e.message}"
    @logger.error("Error in health monitoring: #{e.message}")
    retry
  end

  private

  def send_health_check
    @check_counter += 1
    check_id = SecureRandom.uuid
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')

    health_check = Messages::HealthCheckMessage.new(
      timestamp: timestamp,
      check_id: check_id,
      from: @service_name,
      to: nil  # Broadcast
    )

    puts "🏥 Broadcasting health check ##{@check_counter} (#{check_id[0..7]}...)"
    @logger.info("Broadcasting health check ##{@check_counter} (#{check_id})")

    health_check.publish
  rescue => e
    puts "🏥 Error sending health check: #{e.message}"
    @logger.error("Error sending health check: #{e.message}")
  end
end

if __FILE__ == $0
  health_dept = HealthDepartment.new
  health_dept.start_monitoring
end
