# examples/city_scenario/common/service.rb
# frozen_string_literal: true

require_relative 'logger'

module Common
  # What every long-running city program shares: a name, a logger, a lock
  # for the state its handlers change, and a main loop that ends on
  # Ctrl+C, SIGTERM, or a call to #request_stop.
  #
  # Handlers run on the dispatcher's thread pool while the main loop runs
  # on the main thread, so both change service state inside #synchronize.
  module Service
    include Common::Logger

    attr_reader :service_name

    # @param service_name [String] this program's address (its messages' +from+)
    def setup_service(service_name)
      @service_name  = service_name
      @service_lock  = Monitor.new
      @stop_requests = Thread::Queue.new
      setup_logger(name: service_name)
    end

    def synchronize(&)
      @service_lock.synchronize(&)
    end

    # Run a handler's work under the service lock.  A failure is shown and
    # logged, then raised again so the dispatcher writes the message to
    # the dead letter queue.
    def handling(what)
      synchronize { yield }
    rescue StandardError => e
      puts "#{service_emoji} Error handling #{what}: #{e.message}"
      logger.error("Error handling #{what}: #{e.class.name} - #{e.message}")
      raise
    end

    # Ask the main loop to end.
    def request_stop(reason = :stop)
      @stop_requests << reason
    end

    # Turn Ctrl+C and SIGTERM into stop requests.  The request is made from
    # a new thread: a push made inside the signal handler itself does not
    # wake a main thread that is waiting on the queue.
    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { Thread.new { request_stop(signal) } }
      end
    end

    # Call the block, wait, and repeat until a stop is requested.
    #
    # @param interval [Numeric, #call] seconds between calls, or something
    #   that returns them
    # @return [Object] the reason given to #request_stop ('INT' or 'TERM'
    #   for a signal)
    def run_service(interval)
      trap_signals

      loop do
        run_step { yield }
        reason = @stop_requests.pop(timeout: interval.respond_to?(:call) ? interval.call : interval)
        return reason if reason
      end
    end

    # Run one pass of the main loop; an error is reported, not fatal.
    def run_step
      yield
    rescue StandardError => e
      puts "#{service_emoji} Error in #{service_name}: #{e.message}"
      logger.error("Error in #{service_name}: #{e.class.name} - #{e.message}")
    end

    # Say goodbye, disconnect, and exit: status 1 after a health failure.
    def shutdown_service(reason, farewell)
      puts "\n#{service_emoji} #{farewell}"
      logger.info("#{service_name} stopping (#{reason})")
      Common::City.teardown!
      exit(reason == :health_failure ? 1 : 0)
    end

    def service_emoji
      '🔧'
    end
  end
end
