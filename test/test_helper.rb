$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require 'tmpdir'
require 'fileutils'
require 'securerandom'
require 'stringio'
require 'redis'

require 'smart_message'

# Everything a test run writes (dead letters, log files, transport files)
# goes into one temporary directory that is removed when the run ends.
# Nothing is written to the working directory.
TEST_RUN_DIR = Dir.mktmpdir('smart_message_test')

# Redis pub/sub channels and keys are global to the server, so every test
# run uses its own namespace.
TEST_RUN_ID = SecureRandom.hex(4)

# The baseline configuration every test starts from.
def apply_test_configuration(config = SmartMessage.configuration)
  config.reset!
  config.logger    = nil # no logging unless a test asks for it
  config.dlq_path  = File.join(TEST_RUN_DIR, 'dead_letters.jsonl')
  config
end

apply_test_configuration

require 'breaker_machines'

# Keep BreakerMachines from announcing every circuit state change
BreakerMachines.configure { |config| config.log_events = false }

require 'minitest/autorun'
require 'minitest/power_assert'
require 'minitest/mock'
require 'shoulda'

# amazing_print 3.x expects ActiveSupport::LogSubscriber whenever
# ActiveSupport is loaded (BreakerMachines loads it).
require 'active_support/log_subscriber'
require 'ap'
require 'debug_me'
include DebugMe

unless defined?(DebugMeDefaultOptions)
  DebugMeDefaultOptions = {
    tag: 'DEBUG:',   # A tag to prepend to each output line
    time: true,      # Include a time-stamp in front of the tag
    header: true,    # Print a header string before printing the variables
    lvar: true,      # Include local variables
    ivar: true,      # Include instance variables in the output
    cvar: true,      # Include class variables in the output
    cconst: true,    # Include class constants
    file: File.open(File.join(TEST_RUN_DIR, 'debug_me.log'), 'a') # The output file
  }
end

Minitest.after_run { FileUtils.remove_entry(TEST_RUN_DIR) if File.directory?(TEST_RUN_DIR) }

# Short name used throughout the tests
SS = SmartMessage::Stats

module SmartMessageTestSupport
  # Every test gets the baseline configuration and an empty dead letter
  # queue, and leaves the global configuration as it found it.
  def before_setup
    @saved_configuration = SmartMessage.configuration
    SmartMessage.configuration = apply_test_configuration(SmartMessage::Configuration.new)
    SmartMessage::Logger.reset!
    SmartMessage::DeadLetterQueue.reset_default!
    SmartMessage::DeadLetterQueue.default.clear
    super
  end

  def after_teardown
    super
  ensure
    SmartMessage.configuration = @saved_configuration
    SmartMessage::Logger.reset!
    SmartMessage::DeadLetterQueue.reset_default!
  end

  # A path inside the run's temporary directory, unique per call.
  def temp_path(name)
    File.join(TEST_RUN_DIR, "#{SecureRandom.hex(4)}_#{name}")
  end

  # The default dead letter queue (in the run's temporary directory).
  def dlq
    SmartMessage::DeadLetterQueue.default
  end

  # Wait until the block is true.  Fails the test on timeout, so a missing
  # delivery is a failure and never a skip.
  def wait_until(timeout: 5, message: 'condition was not met in time')
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      flunk("Timed out after #{timeout}s: #{message}") if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    true
  end

  # Wait for a transport's dispatcher to finish every scheduled handler.
  def wait_for_dispatch(transport, timeout: 5)
    dispatcher = transport.dispatcher
    wait_until(timeout: timeout, message: 'dispatcher did not drain') do
      dispatcher.status[:in_flight].zero? && dispatcher.queue_length.zero?
    end
  end

  # Skip a test only when no Redis server answers PING.  Any failure
  # after that is a real failure.
  def require_redis!(url = REDIS_TEST_URL)
    client = ::Redis.new(url: url)
    client.ping
  rescue ::Redis::BaseError => e
    skip "Redis not available at #{url}: #{e.message}"
  ensure
    client&.close
  end

  # A namespace for Redis channels and keys that no other test or run uses.
  def redis_namespace
    "sm_test_#{TEST_RUN_ID}_#{SecureRandom.hex(3)}"
  end
end

REDIS_TEST_URL = ENV.fetch('SMART_MESSAGE_TEST_REDIS_URL', 'redis://localhost:6379')

Minitest::Test.include(SmartMessageTestSupport)
