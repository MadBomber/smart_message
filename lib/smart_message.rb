# lib/smart_message.rb
# encoding: utf-8
# frozen_string_literal: true

require 'zeitwerk'
require 'hashie'
require 'concurrent'

require_relative 'smart_message/version'

loader = Zeitwerk::Loader.for_gem
loader.tag = 'smart_message'
loader.inflector.inflect('ddq' => 'DDQ')
loader.ignore("#{__dir__}/smart_message/version.rb")
loader.setup

# SmartMessage abstracts messages from the backend transport process
module SmartMessage
  DEFAULT_SHUTDOWN_TIMEOUT = 5

  class << self
    # Global configuration for SmartMessage
    #
    # Usage:
    #   SmartMessage.configure do |config|
    #     config.logger    = MyApp::Logger.new
    #     config.transport = SmartMessage::Transport::MemoryTransport.new
    #     config.dlq_path  = '/var/lib/my_app/dead_letters.jsonl'
    #   end
    def configure
      yield(configuration)
      configuration
    end

    # Get the global configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Replace the global configuration.  Mainly useful for tests that
    # save and restore the configuration around a test case.
    def configuration=(config)
      @configuration = config
    end

    # Reset global configuration to defaults
    def reset_configuration!
      @configuration = Configuration.new
      DeadLetterQueue.reset_default!
      @configuration
    end

    # Stop every dispatcher that is still running, waiting up to +timeout+
    # seconds in total for in-flight handlers to finish.  Whatever is still
    # running after that is logged and written to the dead letter queue.
    #
    # Registered once with at_exit; applications may also call it directly.
    #
    # @param timeout [Numeric, nil] seconds; defaults to configuration.shutdown_timeout
    # @return [Boolean] true when every dispatcher drained in time
    def shutdown(timeout: nil)
      budget   = timeout || configuration.shutdown_timeout
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + budget

      Dispatcher.all.map do |dispatcher|
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        dispatcher.shutdown(timeout: [remaining, 0].max)
      end.all?
    end
  end
end

at_exit { SmartMessage.shutdown }
