# examples/support/example_helper.rb
# frozen_string_literal: true
#
# Shared plumbing for the example scripts:
#
#   Example.title / Example.section   headings
#   Example.tmp_path('file.jsonl')    a path in a directory removed at exit
#   Example.inbox                     thread-safe record of what handlers saw
#   Example.wait_until { ... }        poll a condition with a deadline
#   Example.wait_for_idle(transport)  wait for running handlers to finish
#   Example.check('text') { ... }     verify an outcome; exit 1 when it is wrong
#   Example.finish                    print the summary line (last statement)
#
# Loading this file points the dead letter queue at the temporary
# directory, so no example writes into the repository or the home directory.

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))

require 'tmpdir'
require 'fileutils'
require 'smart_message'
require 'breaker_machines'

module Example
  DEFAULT_TIMEOUT = 5 # seconds

  # What the handlers received, grouped by a name the example chooses.
  # Handlers run on pool threads, so every access takes the lock.
  class Inbox
    def initialize
      @items = Hash.new { |hash, key| hash[key] = [] }
      @mutex = Mutex.new
    end

    def add(name, item)
      @mutex.synchronize { @items[name] << item }
      item
    end

    # @return [Array] a copy of what was recorded under +name+
    def [](name)
      @mutex.synchronize { @items[name].dup }
    end

    def count(name) = self[name].size

    def clear
      @mutex.synchronize { @items.clear }
    end
  end

  class << self
    def inbox = @inbox ||= Inbox.new

    # @return [String] this run's temporary directory
    def tmp_dir = @tmp_dir ||= Dir.mktmpdir('smart_message_example')

    def tmp_path(*parts) = File.join(tmp_dir, *parts)

    def title(text)   = puts("\n=== #{text} ===")
    def section(text) = puts("\n--- #{text}")

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Poll the block until it is truthy or +timeout+ seconds have passed.
    # @return [Boolean] did the condition become true in time?
    def wait_until(timeout: DEFAULT_TIMEOUT, interval: 0.01)
      deadline = monotonic_now + timeout
      until yield
        return false if monotonic_now >= deadline

        sleep interval
      end
      true
    end

    # @return [Boolean] true when no handler is running or queued
    def idle?(transport)
      dispatcher = transport.dispatcher
      dispatcher.status[:in_flight].zero? && dispatcher.queue_length.zero?
    end

    # Wait for the handlers of these transports to finish.
    def wait_for_idle(*transports, timeout: DEFAULT_TIMEOUT)
      wait_until(timeout: timeout) { transports.all? { idle?(it) } }
    end

    # Verify one outcome.  A wrong outcome ends the script with status 1.
    def check(description)
      abort "FAILED: #{description}" unless yield

      @checks = checks + 1
      puts "  ok: #{description}"
    end

    def checks = @checks || 0

    # The last statement of every example.
    def finish
      abort 'FAILED: the example verified nothing' if checks.zero?

      puts "\nOK: #{checks} checks passed"
    end

    # Send dead letters to the temporary directory.
    def isolate_dead_letters(config = SmartMessage.configuration)
      config.dlq_path = tmp_path('dead_letters.jsonl')
    end

    # Stop the dispatchers, then remove everything the example wrote.
    def cleanup
      SmartMessage.shutdown
      FileUtils.remove_entry(@tmp_dir) if @tmp_dir && File.directory?(@tmp_dir)
    end
  end
end

# Registered before the temporary directory exists, so the directory is
# removed however the script ends.
at_exit { Example.cleanup }

$stdout.sync = true # keep stdout and stderr in order when both are captured

Example.isolate_dead_letters

# Keep BreakerMachines from announcing every circuit state change
BreakerMachines.configure { |config| config.log_events = false }
