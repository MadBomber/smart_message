#!/usr/bin/env ruby
# performance_benchmark.rb
#
# A comprehensive performance measurement tool to compare implementation subjects

SUBJECT = ARGV.shift || "unknown"


require 'bundler/setup'
require 'benchmark'
require 'json'
require 'fileutils'
require_relative '../../lib/smart_message'

class PerformanceBenchmark
  SCENARIOS = {
    cpu_light: { name: "CPU Light", iterations: 1000, sleep: 0 },
    cpu_heavy: { name: "CPU Heavy", iterations: 500, computation: 10000 },
    io_light: { name: "I/O Light", iterations: 800, sleep: 0.001 },
    io_heavy: { name: "I/O Heavy", iterations: 200, sleep: 0.01 },
    mixed: { name: "Mixed Load", iterations: 600, computation: 5000, sleep: 0.005 }
  }.freeze

  def initialize
    @results = {}
    @start_time = nil
    @memory_before = nil
    @dispatcher = SmartMessage::Dispatcher.new
    setup_test_messages
  end

  def run_all_scenarios
    puts "🚀 Starting SmartMessage Performance Benchmark"
    puts "Ruby Version: #{RUBY_VERSION}"
    puts "Platform: #{RUBY_PLATFORM}"
    puts "Processor Count: #{processor_count}"
    puts "=" * 60

    @start_time = Time.now
    @memory_before = memory_usage

    SCENARIOS.each do |scenario_key, config|
      puts "\n📊 Running scenario: #{config[:name]}"
      run_scenario(scenario_key, config)
    end

    generate_report
    save_results
  end

  private

  def setup_test_messages
    # Define test message classes for different scenarios

    # CPU Light - Simple message processing
    define_message_class(:CpuLightMessage, :process_cpu_light)

    # CPU Heavy - Computation-intensive processing
    define_message_class(:CpuHeavyMessage, :process_cpu_heavy)

    # I/O Light - Short sleep simulation
    define_message_class(:IoLightMessage, :process_io_light)

    # I/O Heavy - Longer I/O simulation
    define_message_class(:IoHeavyMessage, :process_io_heavy)

    # Mixed - Both CPU and I/O
    define_message_class(:MixedMessage, :process_mixed)
  end

  def define_message_class(class_name, processor_method)
    message_class = Class.new(SmartMessage::Base) do
      property :scenario_id, required: true
      property :message_id, required: true
      property :timestamp, required: true
      property :computation_cycles
      property :sleep_duration

      def process
        # This gets called by the processor methods
      end
    end

    # Set the class name first
    Object.const_set(class_name, message_class)

    # Now set the from address after the class has a name
    message_class.from('benchmark-service')

    # Configure transport and serializer - need to capture dispatcher reference
    dispatcher = @dispatcher
    message_class.config do
      transport   SmartMessage::Transport::MemoryTransport.new(dispatcher: dispatcher, auto_process: true)
      serializer  SmartMessage::Serializer::JSON.new
    end

    # Register processor with dispatcher
    @dispatcher.add(class_name.to_s, "PerformanceBenchmark.#{processor_method}")
  end

  def run_scenario(scenario_key, config)
    scenario_start = Time.now
    processed_count = 0
    errors = 0

    # Setup monitoring
    completed_before = @dispatcher.completed_task_count rescue 0

    # Generate and publish messages
    messages = generate_messages(scenario_key, config)

    publish_start = Time.now
    messages.each do |message|
      begin
        message.publish
      rescue => e
        errors += 1
        puts "Error publishing message: #{e.message}" if errors < 5
      end
    end
    publish_time = Time.now - publish_start

    # Wait for processing to complete
    target_completed = completed_before + config[:iterations] - errors
    processing_start = Time.now

    wait_for_completion(target_completed, config[:iterations])
    processing_time = Time.now - processing_start

    completed_after = @dispatcher.completed_task_count rescue target_completed
    actually_processed = completed_after - completed_before

    scenario_time = Time.now - scenario_start

    # Store results
    @results[scenario_key] = {
      name: config[:name],
      messages_generated: config[:iterations],
      messages_published: config[:iterations] - errors,
      messages_processed: actually_processed,
      errors: errors,
      times: {
        total: scenario_time,
        publish: publish_time,
        processing: processing_time
      },
      throughput: {
        messages_per_second: actually_processed / scenario_time,
        publish_rate: (config[:iterations] - errors) / publish_time
      },
      dispatcher_stats: @dispatcher.status
    }

    puts "  ✅ Processed #{actually_processed}/#{config[:iterations]} messages in #{scenario_time.round(3)}s"
    puts "  📈 Throughput: #{(actually_processed / scenario_time).round(1)} msg/sec"
    puts "  🚀 Publish rate: #{((config[:iterations] - errors) / publish_time).round(1)} msg/sec"
    puts "  ❌ Errors: #{errors}" if errors > 0
  end

  def generate_messages(scenario_key, config)
    message_class = Object.const_get(scenario_class_name(scenario_key))

    config[:iterations].times.map do |i|
      message_class.new(
        scenario_id: scenario_key.to_s,
        message_id: "#{scenario_key}_#{i}",
        timestamp: Time.now.to_f,
        computation_cycles: config[:computation],
        sleep_duration: config[:sleep]
      )
    end
  end

  def scenario_class_name(scenario_key)
    case scenario_key
    when :cpu_light then :CpuLightMessage
    when :cpu_heavy then :CpuHeavyMessage
    when :io_light then :IoLightMessage
    when :io_heavy then :IoHeavyMessage
    when :mixed then :MixedMessage
    end
  end

  def wait_for_completion(target_completed, max_iterations)
    timeout = 60 # seconds
    start_wait = Time.now

    while (Time.now - start_wait) < timeout
      current_completed = @dispatcher.completed_task_count rescue 0

      if current_completed >= target_completed
        break
      end

      # Check if dispatcher is still running
      unless @dispatcher.running?
        puts "  ⚠️  Dispatcher stopped running"
        break
      end

      sleep 0.1
    end

    if (Time.now - start_wait) >= timeout
      puts "  ⚠️  Timeout waiting for message processing"
    end
  end


  def generate_report
    puts "\n" + "=" * 60
    puts "📋 PERFORMANCE BENCHMARK REPORT"
    puts "=" * 60

    total_time = Time.now - @start_time
    memory_after = memory_usage
    memory_used = memory_after - @memory_before

    puts "\n📊 Overall Stats:"
    puts "  Total runtime: #{total_time.round(3)}s"
    puts "  Memory used: #{memory_used.round(2)} MB"
    puts "  Implementation Subject: #{SUBJECT}"

    puts "\n📈 Scenario Results:"
    @results.each do |scenario_key, data|
      puts "\n  #{data[:name]}:"
      puts "    Messages: #{data[:messages_processed]}/#{data[:messages_generated]}"
      puts "    Total time: #{data[:times][:total].round(3)}s"
      puts "    Throughput: #{data[:throughput][:messages_per_second].round(1)} msg/sec"
      puts "    Publish rate: #{data[:throughput][:publish_rate].round(1)} msg/sec"
      puts "    Errors: #{data[:errors]}" if data[:errors] > 0
    end

    puts "\n🏆 Best Performing Scenarios:"
    sorted_by_throughput = @results.sort_by { |k, v| -v[:throughput][:messages_per_second] }
    sorted_by_throughput.first(3).each_with_index do |(scenario_key, data), index|
      puts "  #{index + 1}. #{data[:name]}: #{data[:throughput][:messages_per_second].round(1)} msg/sec"
    end
  end

  def save_results
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    filename = "benchmark_results_#{SUBJECT}_#{timestamp}.json"

    report_data = {
      benchmark_info: {
        timestamp:    Time.now.iso8601,
        subject:      SUBJECT,
        ruby_version: RUBY_VERSION,
        platform:     RUBY_PLATFORM,
        processors:   processor_count
      },
      overall_stats: {
        total_runtime:  Time.now - @start_time,
        memory_used_mb: memory_usage - @memory_before
      },
      scenario_results: @results
    }

    File.write(filename, JSON.pretty_generate(report_data))
    puts "\n💾 Results saved to: #{filename}"
  end

  def memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0 # Convert KB to MB
  rescue
    0
  end

  def processor_count
    case RUBY_PLATFORM
    when /linux/
      `nproc`.to_i
    when /darwin/
      `sysctl -n hw.ncpu`.to_i
    else
      `echo $NUMBER_OF_PROCESSORS`.to_i
    end
  rescue
    4 # fallback
  end

  # Processor methods called by the dispatcher

  def self.process_cpu_light(message_header, encoded_message)
    # Simple processing - just decode
    message_data = JSON.parse(encoded_message)
    message_data['processed_at'] = Time.now.to_f
  end

  def self.process_cpu_heavy(message_header, encoded_message)
    message_data = JSON.parse(encoded_message)

    # CPU-intensive computation
    cycles = message_data['computation_cycles'] || 10000
    result = 0
    cycles.times { |i| result += Math.sqrt(i) * Math.sin(i) }

    message_data['processed_at'] = Time.now.to_f
    message_data['computation_result'] = result
  end

  def self.process_io_light(message_header, encoded_message)
    message_data = JSON.parse(encoded_message)

    # Light I/O simulation
    sleep_time = message_data['sleep_duration'] || 0.001
    sleep(sleep_time)

    message_data['processed_at'] = Time.now.to_f
  end

  def self.process_io_heavy(message_header, encoded_message)
    message_data = JSON.parse(encoded_message)

    # Heavy I/O simulation
    sleep_time = message_data['sleep_duration'] || 0.01
    sleep(sleep_time)

    message_data['processed_at'] = Time.now.to_f
  end

  def self.process_mixed(message_header, encoded_message)
    message_data = JSON.parse(encoded_message)

    # Combined CPU and I/O
    cycles = message_data['computation_cycles'] || 5000
    sleep_time = message_data['sleep_duration'] || 0.005

    result = 0
    cycles.times { |i| result += Math.sqrt(i) }
    sleep(sleep_time)

    message_data['processed_at'] = Time.now.to_f
    message_data['computation_result'] = result
  end
end

# Run the benchmark if called directly
if __FILE__ == $0
  benchmark = PerformanceBenchmark.new
  benchmark.run_all_scenarios
end
