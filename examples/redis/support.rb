# examples/redis/support.rb
# frozen_string_literal: true
#
# Shared setup for the Redis examples.
#
# Every run gets its own Redis namespace (pub/sub channels are global to a
# Redis server, so this is what keeps a run from seeing anybody else's
# messages) and its own temporary directory for the log file and the dead
# letter queue.  Nothing is written into the repository.

require 'fileutils'
require 'securerandom'
require 'tmpdir'

require_relative '../../lib/smart_message'

module RedisExample
  REDIS_URL = ENV.fetch('SMART_MESSAGE_TEST_REDIS_URL', 'redis://localhost:6379')

  @transports = []
  @failures   = []

  module_function

  # @return [String] the channel prefix for this run
  def namespace
    @namespace ||= "sm_example_#{SecureRandom.hex(4)}"
  end

  # @return [String] a temporary directory, removed by #finish!
  def work_dir
    @work_dir ||= Dir.mktmpdir('smart_message_redis_example_')
  end

  # Point SmartMessage's log file and dead letter queue at the work
  # directory, and make one Redis transport the default for every message
  # class that does not set its own.
  #
  # @return [SmartMessage::Transport::RedisTransport]
  def configure!
    shared = transport
    SmartMessage.configure do |config|
      config.logger    = File.join(work_dir, 'smart_message.log')
      config.dlq_path  = File.join(work_dir, 'dead_letters.jsonl')
      config.transport = shared
    end
    shared
  end

  # Build a Redis transport in this run's namespace.  Exits with a clear
  # message when no Redis server answers.
  #
  # @return [SmartMessage::Transport::RedisTransport]
  def transport(**options)
    instance = SmartMessage::Transport::RedisTransport.new(url: REDIS_URL, namespace: namespace, **options)
    abort_without_redis unless instance.connected?

    @transports << instance
    instance
  end

  # Poll until the block is true.  Handlers run on a thread pool, so an
  # example waits for an outcome with a deadline instead of sleeping.
  #
  # @return [Boolean] the block's final answer
  def wait_until(timeout: 5, interval: 0.02)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep(interval)
    end
    true
  end

  # Record and print one verified outcome.
  #
  # @return [Boolean] passed
  def check(description, passed)
    @failures << description unless passed
    puts "  #{passed ? 'ok  ' : 'FAIL'}  #{description}"
    passed ? true : false
  end

  # @return [Array<String>] descriptions of the checks that failed
  def failures
    @failures.dup
  end

  # Disconnect every transport, stop the dispatchers, remove the work
  # directory, and exit non-zero when any check failed.
  def finish!
    cleanup
    return puts("\nAll checks passed.") if @failures.empty?

    abort "\n#{@failures.size} check(s) failed:\n#{@failures.map { |failure| "  - #{failure}" }.join("\n")}"
  end

  # Safe to call more than once.
  def cleanup
    @transports.each(&:disconnect)
    @transports.clear
    SmartMessage.shutdown
    return unless @work_dir

    SmartMessage::Logger.default.close
    SmartMessage.configuration.logger = nil
    FileUtils.remove_entry(@work_dir) if File.directory?(@work_dir)
    @work_dir = nil
  end

  def abort_without_redis
    cleanup
    abort "No Redis server answered at #{REDIS_URL}. Start one, or set SMART_MESSAGE_TEST_REDIS_URL."
  end
end

# An example that dies on an exception still leaves nothing behind.
at_exit { RedisExample.cleanup }
