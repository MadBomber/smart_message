#!/usr/bin/env ruby
# examples/run_all.rb
# frozen_string_literal: true
#
# Runs the example scripts, each in its own process, and reports one line
# per script: PASS, FAIL or SKIP.  The output of a failed script is printed
# after its line.  The exit status is 1 when any script failed.
#
#   bundle exec ruby examples/run_all.rb           # everything
#   bundle exec ruby examples/run_all.rb memory    # only paths containing "memory"
#   bundle exec rake examples
#
# Environment:
#   EXAMPLE_TIMEOUT               seconds allowed per script (default 30)
#   SMART_MESSAGE_TEST_REDIS_URL  Redis for examples/redis (default
#                                 redis://localhost:6379); when no server
#                                 answers there, those scripts are skipped
#
# examples/city_scenario and examples/performance_metrics are long-running,
# multi-process demos and are not part of this run.

require 'rbconfig'
require 'socket'
require 'tempfile'
require 'uri'

module ExampleRunner
  ROOT     = File.expand_path('..', __dir__)
  PATTERNS = %w[
    examples/memory/[0-9][0-9]_*.rb
    examples/file/[0-9][0-9]_*.rb
    examples/redis/[0-9][0-9]_*.rb
    examples/multi_transport_example.rb
  ].freeze
  DEFAULT_TIMEOUT   = 30
  DEFAULT_REDIS_URL = 'redis://localhost:6379'

  Result = Data.define(:script, :status, :seconds, :output)

  module_function

  # @param filters [Array<String>] keep scripts whose path contains any of these
  # @return [Array<String>] script paths relative to the repository root
  def scripts(filters = [])
    found = PATTERNS.flat_map { Dir.glob(it, base: ROOT).sort }
    found = found.reject { File.basename(it).start_with?('00_') }
    filters.empty? ? found : found.select { |script| filters.any? { script.include?(it) } }
  end

  def redis_script?(script) = script.start_with?('examples/redis/')

  def redis_url = ENV.fetch('SMART_MESSAGE_TEST_REDIS_URL', DEFAULT_REDIS_URL)

  def timeout = Float(ENV.fetch('EXAMPLE_TIMEOUT', DEFAULT_TIMEOUT))

  # Does a Redis server answer at +url+?  Any reply to PING counts, an
  # authentication error included.
  def redis_available?(url = redis_url)
    uri = URI.parse(url)
    Socket.tcp(uri.host || 'localhost', uri.port || 6379, connect_timeout: 1) do |socket|
      socket.write("PING\r\n")
      !socket.wait_readable(1).nil? && socket.readpartial(64).start_with?('+', '-')
    end
  rescue SystemCallError, IOError, URI::InvalidURIError
    false
  end

  # The command that runs one script from the repository root.
  def command_for(script)
    [RbConfig.ruby, '-rbundler/setup', '-Ilib', script]
  end

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # Wait for +pid+ for at most +seconds+; kill it when it takes longer.
  # @return [Process::Status, nil] nil when the process was killed
  def wait_with_timeout(pid, seconds)
    deadline = monotonic_now + seconds
    loop do
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status if status
      break if monotonic_now >= deadline

      sleep 0.05
    end
    terminate(pid)
    nil
  end

  def terminate(pid)
    Process.kill('KILL', pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  # Run one script, capturing stdout and stderr together.
  # @return [Result]
  def run(script, limit: timeout)
    started = monotonic_now
    Tempfile.create('example_output') do |log|
      pid     = Process.spawn(*command_for(script), chdir: ROOT, in: File::NULL, out: log, err: log)
      status  = wait_with_timeout(pid, limit)
      output  = File.read(log.path)
      output += "\n(killed after #{limit} seconds)\n" if status.nil?
      Result.new(script: script, status: status&.success? ? :pass : :fail, seconds: monotonic_now - started, output: output)
    end
  end

  def skip(script, reason)
    Result.new(script: script, status: :skip, seconds: 0.0, output: reason)
  end

  # @return [Result] run the script, or skip it when it needs Redis and there is none
  def result_for(script, redis_up:)
    return skip(script, "no Redis server at #{redis_url}") if redis_script?(script) && !redis_up

    run(script)
  end

  def report_line(result)
    line = format('%-5s %-55s %5.1fs', result.status.to_s.upcase, result.script, result.seconds)
    result.status == :skip ? "#{line}  (#{result.output})" : line
  end

  def report(result, out: $stdout)
    out.puts report_line(result)
    out.puts result.output.gsub(/^/, '    | ') if result.status == :fail
    out.flush
  end

  def summary(results)
    counts = results.map(&:status).tally
    format('%d passed, %d failed, %d skipped', counts.fetch(:pass, 0), counts.fetch(:fail, 0), counts.fetch(:skip, 0))
  end

  # @return [Boolean] true when no script failed
  def call(filters = [], out: $stdout)
    selected = scripts(filters)
    redis_up = selected.any? { redis_script?(it) } && redis_available?
    results  = selected.map { |script| result_for(script, redis_up: redis_up).tap { report(it, out: out) } }

    out.puts "\n#{summary(results)}"
    results.any? && results.none? { it.status == :fail }
  end
end

exit(ExampleRunner.call(ARGV) ? 0 : 1) if $PROGRAM_NAME == __FILE__
