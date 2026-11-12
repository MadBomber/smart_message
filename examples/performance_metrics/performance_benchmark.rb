#!/usr/bin/env ruby
# examples/performance_metrics/performance_benchmark.rb
# frozen_string_literal: true
#
# Measures publish and handler throughput of the dispatcher's thread pool
# over the in-process memory transport, for five kinds of handler work.
#
#   bundle exec ruby -Ilib examples/performance_metrics/performance_benchmark.rb [SUBJECT]
#
# SUBJECT labels the run (default "baseline"), so runs of different
# branches or settings can be compared with compare_benchmarks.rb.
#
# Environment:
#   BENCHMARK_SCALE        multiplies every scenario's message count (default 1;
#                          1 finishes in a few seconds, 10 is a long run)
#   BENCHMARK_MAX_THREADS  dispatcher pool size (default: SmartMessage's default)
#   BENCHMARK_TIMEOUT      seconds to wait for one scenario's handlers (default 60)
#   BENCHMARK_RESULTS_DIR  where the JSON result is written
#                          (default: <tmpdir>/smart_message_benchmarks)

require 'benchmark'
require 'etc'
require 'json'
require 'fileutils'
require 'tmpdir'

require_relative 'messages/benchmark_message'

class PerformanceBenchmark
  SCENARIOS = {
    cpu_light: { name: 'CPU Light',  iterations: 1000 },
    cpu_heavy: { name: 'CPU Heavy',  iterations: 500, computation: 10_000 },
    io_light:  { name: 'I/O Light',  iterations: 800, sleep: 0.001 },
    io_heavy:  { name: 'I/O Heavy',  iterations: 200, sleep: 0.01 },
    mixed:     { name: 'Mixed Load', iterations: 600, computation: 5_000, sleep: 0.005 }
  }.freeze

  PROCESSED = Concurrent::AtomicFixnum.new(0)

  # The handler every scenario uses.  Runs on a dispatcher thread.
  def self.process(message)
    work(message.computation_cycles, message.sleep_duration)
    PROCESSED.increment
  end

  # @return [Float] the result of +cycles+ iterations of floating point work
  def self.work(cycles, sleep_duration)
    result = 0.0
    cycles.to_i.times { |i| result += Math.sqrt(i) * Math.sin(i) }
    sleep(sleep_duration) if sleep_duration.to_f.positive?
    result
  end

  # @return [String] the directory results are written to and read from
  def self.results_dir(env = ENV)
    env.fetch('BENCHMARK_RESULTS_DIR') { File.join(Dir.tmpdir, 'smart_message_benchmarks') }
  end

  # @return [Hash] SCENARIOS with every message count multiplied by +scale+
  def self.scaled_scenarios(scale)
    SCENARIOS.transform_values do |config|
      config.merge(iterations: [(config[:iterations] * scale).round, 1].max)
    end
  end

  attr_reader :results

  def initialize(subject: 'baseline', scale: 1.0, max_threads: nil, timeout: 60, results_dir: self.class.results_dir)
    @subject     = subject
    @scenarios   = self.class.scaled_scenarios(scale)
    @timeout     = timeout
    @results_dir = results_dir
    @results     = {}
    @work_dir    = Dir.mktmpdir('smart_message_benchmark_')

    SmartMessage.configure do |config|
      config.dlq_path               = File.join(@work_dir, 'dead_letters.jsonl')
      config.dispatcher_max_threads = max_threads if max_threads
    end

    @transport = SmartMessage::Transport::MemoryTransport.new
    BenchmarkMessage.transport(@transport)
    BenchmarkMessage.subscribe('PerformanceBenchmark.process')
  end

  # @return [Boolean] true when every message of every scenario was processed
  def run
    print_banner
    total_runtime = Benchmark.realtime do
      @scenarios.each { |key, config| @results[key] = run_scenario(key, config) }
    end

    print_report(total_runtime)
    save_results(total_runtime)
    complete?
  ensure
    cleanup
  end

  # @return [Boolean]
  def complete?
    @results.size == @scenarios.size &&
      @results.values.all? { |result| result[:messages_processed] == result[:messages_generated] }
  end

  # Publish one scenario's messages and wait for their handlers.
  #
  # @return [Hash] the scenario's measurements
  def run_scenario(key, config)
    puts "\nRunning scenario: #{config[:name]} (#{config[:iterations]} messages)"
    messages = build_messages(key, config)
    before   = PROCESSED.value
    errors   = 0
    publish_time = processing_time = 0.0

    total_time = Benchmark.realtime do
      publish_time    = Benchmark.realtime { errors = publish_all(messages) }
      processing_time = Benchmark.realtime { wait_for(before + messages.size - errors) }
    end

    measurements(config, messages.size, errors, PROCESSED.value - before, total_time, publish_time, processing_time)
  end

  # @return [Array<BenchmarkMessage>]
  def build_messages(key, config)
    Array.new(config[:iterations]) do |index|
      BenchmarkMessage.new(
        scenario_id:        key.to_s,
        message_id:         "#{key}_#{index}",
        computation_cycles: config.fetch(:computation, 0),
        sleep_duration:     config.fetch(:sleep, 0)
      )
    end
  end

  # @return [Integer] how many messages could not be published
  def publish_all(messages)
    messages.count do |message|
      message.publish
      false
    rescue SmartMessage::Errors::Error => e
      warn "  publish failed: #{e.message}"
      true
    end
  end

  # Poll until the handlers have processed +target+ messages in total.
  #
  # @return [Boolean] false when the timeout passed first
  def wait_for(target)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
    until PROCESSED.value >= target
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        warn "  timed out after #{@timeout}s waiting for handlers"
        return false
      end
      sleep(0.005)
    end
    true
  end

  def measurements(config, generated, errors, processed, total_time, publish_time, processing_time)
    result = {
      name:               config[:name],
      messages_generated: generated,
      messages_published: generated - errors,
      messages_processed: processed,
      errors:             errors,
      times:              { total: total_time, publish: publish_time, processing: processing_time },
      throughput:         {
        messages_per_second: processed / total_time,
        publish_rate:        (generated - errors) / publish_time
      },
      dispatcher_stats:   @transport.dispatcher.status
    }
    puts "  processed #{processed}/#{generated} in #{total_time.round(3)}s " \
         "(#{result[:throughput][:messages_per_second].round(1)} msg/sec)"
    result
  end

  def print_banner
    puts <<~BANNER
      SmartMessage #{SmartMessage::VERSION} performance benchmark
      Subject:    #{@subject}
      Ruby:       #{RUBY_VERSION} (#{RUBY_PLATFORM})
      Processors: #{Etc.nprocessors}
      Pool size:  #{SmartMessage.configuration.dispatcher_max_threads} threads
    BANNER
  end

  def print_report(total_runtime)
    best = @results.values.max_by { |result| result[:throughput][:messages_per_second] }
    rows = @results.values.map do |result|
      format('  %-11s %5d/%-5d  %8.3fs  %10.1f msg/sec  publish %10.1f msg/sec',
             result[:name], result[:messages_processed], result[:messages_generated],
             result[:times][:total], result[:throughput][:messages_per_second],
             result[:throughput][:publish_rate])
    end

    puts <<~REPORT

      #{'=' * 78}
      PERFORMANCE BENCHMARK REPORT (#{@subject})
      #{'=' * 78}
      #{rows.join("\n")}

      Total runtime:   #{total_runtime.round(3)}s
      Memory (RSS):    #{memory_mb.round(1)} MB
      Best throughput: #{best[:name]}
    REPORT
  end

  # @return [String] the file the results were written to
  def save_results(total_runtime)
    FileUtils.mkdir_p(@results_dir)
    path = File.join(@results_dir, "benchmark_results_#{@subject}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json")
    File.write(path, JSON.pretty_generate(report_data(total_runtime)))
    puts "Results saved to: #{path}"
    path
  end

  def report_data(total_runtime)
    {
      benchmark_info:   {
        timestamp:             Time.now.iso8601,
        subject:               @subject,
        smart_message_version: SmartMessage::VERSION,
        ruby_version:          RUBY_VERSION,
        platform:              RUBY_PLATFORM,
        processors:            Etc.nprocessors
      },
      overall_stats:    { total_runtime: total_runtime, memory_used_mb: memory_mb },
      scenario_results: @results
    }
  end

  # @return [Float] resident set size of this process in MB (0.0 when unknown)
  def memory_mb
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  rescue StandardError
    0.0
  end

  def cleanup
    BenchmarkMessage.unsubscribe!
    SmartMessage.shutdown
    FileUtils.remove_entry(@work_dir) if File.directory?(@work_dir)
  end
end

if __FILE__ == $PROGRAM_NAME
  max_threads = ENV['BENCHMARK_MAX_THREADS']
  benchmark   = PerformanceBenchmark.new(
    subject:     ARGV.shift || 'baseline',
    scale:       Float(ENV.fetch('BENCHMARK_SCALE', '1')),
    max_threads: max_threads && Integer(max_threads),
    timeout:     Float(ENV.fetch('BENCHMARK_TIMEOUT', '60'))
  )
  exit(benchmark.run ? 0 : 1)
end
