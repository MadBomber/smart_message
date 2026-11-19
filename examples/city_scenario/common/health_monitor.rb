# examples/city_scenario/common/health_monitor.rb
# frozen_string_literal: true
#
# Answers the Health Department's health checks, and stops the service
# when no health check has arrived for FAIL_SAFE seconds.
#
# A class that includes this module also includes Common::Service and
# defines:
#
#   def get_status_details
#     [status, details]   # status is one of HealthStatusMessage::VALID_STATUS
#   end

require_relative '../messages/health_check_message'
require_relative '../messages/health_status_message'

module Common
  module HealthMonitor
    FAIL_SAFE = 15 # seconds

    def setup_health_monitor
      @last_health_check = monotonic_now

      Messages::HealthCheckMessage.subscribe(broadcast: true) do |health_check|
        respond_to_health_check(health_check)
      end

      @health_watchdog = Thread.new { watch_health_checks }
    end

    # @return [Boolean] true when the last health check is too long ago
    def health_check_overdue?(now = monotonic_now)
      now - @last_health_check > FAIL_SAFE
    end

    def watch_health_checks
      sleep(1) until health_check_overdue?

      warning = "No health checks received for over #{FAIL_SAFE} seconds!"
      puts "\n⚠️  WARNING: #{warning}"
      logger.fatal("#{warning} #{service_name} is going offline")
      request_stop(:health_failure)
    end

    # Reply to the sender of the health check.
    def respond_to_health_check(health_check)
      @last_health_check = monotonic_now
      status, details    = synchronize { get_status_details }

      Messages::HealthStatusMessage.new(
        service_name: service_name,
        status:       status,
        check_id:     health_check.check_id,
        details:      details,
        from:         service_name,
        to:           health_check.from
      ).publish

      logger.info("Sent health status: #{status} (#{details})")
    rescue StandardError => e
      puts "#{service_emoji} Error responding to health check: #{e.message}"
      logger.error("Error responding to health check: #{e.class.name} - #{e.message}")
      raise
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
