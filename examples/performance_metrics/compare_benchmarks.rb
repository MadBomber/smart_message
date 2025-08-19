#!/usr/bin/env ruby
# compare_benchmarks.rb
#
# Compares benchmark results between multiple subjects/implementations
# Usage: ruby compare_benchmarks.rb subject1 subject2 [subject3 ...]
# Will find and compare JSON files for each subject

require 'json'
require 'optparse'
require 'fileutils'

# Try to load visualization gems, but don't fail if they're not available
begin
  require 'unicode_plot'
  GRAPHICS_AVAILABLE = true
rescue LoadError
  GRAPHICS_AVAILABLE = false
  puts "📊 Note: Install 'unicode_plot' gem for graphical visualizations"
  puts "  Run: gem install unicode_plot"
  puts ""
end

class BenchmarkComparator
  def initialize(subjects)
    @subjects = subjects
    @subject_data = {}
    @subject_files = {}
    
    load_subject_data
  end

  def compare
    puts "🔄 SMARTMESSAGE PERFORMANCE COMPARISON"
    puts "=" * 80
    
    @subjects.each_with_index do |subject, index|
      puts "Subject #{index + 1}: #{subject.upcase} (#{@subject_files[subject]})"
    end
    puts "=" * 80

    compare_overall_performance
    compare_scenario_performance  
    compare_resource_usage
    generate_summary
    
    # Add graphical visualizations if available
    if GRAPHICS_AVAILABLE
      generate_visualizations
    end
  end

  private
  
  def load_subject_data
    @subjects.each do |subject|
      # Find the most recent JSON file for this subject
      pattern = "benchmark_results_#{subject}_*.json"
      matching_files = Dir.glob(pattern).sort_by { |f| File.mtime(f) }
      
      if matching_files.empty?
        puts "❌ No benchmark files found for subject: #{subject}"
        puts "   Looking for pattern: #{pattern}"
        exit 1
      end
      
      latest_file = matching_files.last
      @subject_files[subject] = latest_file
      
      begin
        @subject_data[subject] = JSON.parse(File.read(latest_file))
      rescue JSON::ParserError => e
        puts "❌ Error parsing JSON file #{latest_file}: #{e.message}"
        exit 1
      rescue => e
        puts "❌ Error reading file #{latest_file}: #{e.message}"
        exit 1
      end
    end
  end

  def compare_overall_performance
    puts "\n📊 OVERALL PERFORMANCE COMPARISON"
    puts "-" * 60

    # Calculate overall metrics for each subject
    overall_metrics = {}
    @subjects.each do |subject|
      data = @subject_data[subject]
      runtime = data['overall_stats']['total_runtime']
      total_processed = total_messages_processed(data)
      throughput = total_processed / runtime
      
      overall_metrics[subject] = {
        runtime: runtime,
        total_processed: total_processed,
        throughput: throughput,
        memory: data['overall_stats']['memory_used_mb']
      }
    end

    # Runtime comparison
    puts "\nRuntime (seconds):"
    sorted_by_runtime = overall_metrics.sort_by { |_, metrics| metrics[:runtime] }
    sorted_by_runtime.each_with_index do |(subject, metrics), index|
      ranking = index == 0 ? "🏆" : "  "
      puts "  #{ranking} #{subject.ljust(15)}: #{metrics[:runtime].round(3)}s"
    end
    
    # Throughput comparison
    puts "\nThroughput (messages/second):"
    sorted_by_throughput = overall_metrics.sort_by { |_, metrics| -metrics[:throughput] }
    sorted_by_throughput.each_with_index do |(subject, metrics), index|
      ranking = index == 0 ? "🏆" : "  "
      puts "  #{ranking} #{subject.ljust(15)}: #{metrics[:throughput].round(1)} msg/sec"
    end
    
    # Memory usage comparison
    puts "\nMemory Usage (MB):"
    sorted_by_memory = overall_metrics.sort_by { |_, metrics| metrics[:memory] }
    sorted_by_memory.each_with_index do |(subject, metrics), index|
      ranking = index == 0 ? "🏆" : "  "
      puts "  #{ranking} #{subject.ljust(15)}: #{metrics[:memory].round(2)} MB"
    end
  end

  def compare_scenario_performance
    puts "\n📈 SCENARIO-BY-SCENARIO COMPARISON"
    puts "-" * 60

    # Get all scenarios from the first subject
    scenarios = @subject_data[@subjects.first]['scenario_results'].keys

    scenarios.each do |scenario|
      first_subject_data = @subject_data[@subjects.first]['scenario_results'][scenario]
      puts "\n#{first_subject_data['name']}:"
      
      # Collect metrics for all subjects
      scenario_metrics = {}
      @subjects.each do |subject|
        data = @subject_data[subject]['scenario_results'][scenario]
        scenario_metrics[subject] = {
          throughput: data['throughput']['messages_per_second'],
          time: data['times']['total'],
          errors: data['errors'] || 0,
          processed: data['messages_processed']
        }
      end
      
      # Throughput comparison
      puts "  Throughput (msg/sec):"
      sorted_by_throughput = scenario_metrics.sort_by { |_, metrics| -metrics[:throughput] }
      sorted_by_throughput.each_with_index do |(subject, metrics), index|
        ranking = index == 0 ? "🏆" : "  "
        puts "    #{ranking} #{subject.ljust(12)}: #{metrics[:throughput].round(1)}"
      end
      
      # Processing time comparison
      puts "  Processing Time (seconds):"
      sorted_by_time = scenario_metrics.sort_by { |_, metrics| metrics[:time] }
      sorted_by_time.each_with_index do |(subject, metrics), index|
        ranking = index == 0 ? "🏆" : "  "
        puts "    #{ranking} #{subject.ljust(12)}: #{metrics[:time].round(3)}"
      end
      
      # Error comparison (if any errors exist)
      total_errors = scenario_metrics.values.sum { |m| m[:errors] }
      if total_errors > 0
        puts "  Errors:"
        scenario_metrics.each do |subject, metrics|
          puts "    #{subject.ljust(15)}: #{metrics[:errors]}"
        end
      end
    end
  end

  def compare_resource_usage
    puts "\n💾 RESOURCE USAGE COMPARISON"
    puts "-" * 60

    puts "Memory Usage:"
    @subjects.each do |subject|
      data = @subject_data[subject]
      memory = data['overall_stats']['memory_used_mb']
      puts "  #{subject.ljust(15)}: #{memory.round(2)} MB"
    end
    
    puts "\nPlatform Information:"
    @subjects.each_with_index do |subject, index|
      platform_info = @subject_data[subject]['benchmark_info']
      puts "  #{subject.upcase}:"
      puts "    Ruby Version: #{platform_info['ruby_version']}"
      puts "    Platform:     #{platform_info['platform']}"
      puts "    Processors:   #{platform_info['processors'] || platform_info['processor_count']}"
      puts "    Timestamp:    #{platform_info['timestamp']}"
      puts "" unless index == @subjects.length - 1
    end
  end

  def generate_summary
    puts "\n🏆 PERFORMANCE SUMMARY"
    puts "=" * 80

    # Calculate overall rankings
    overall_metrics = {}
    @subjects.each do |subject|
      data = @subject_data[subject]
      runtime = data['overall_stats']['total_runtime']
      total_processed = total_messages_processed(data)
      throughput = total_processed / runtime
      memory = data['overall_stats']['memory_used_mb']
      
      overall_metrics[subject] = {
        throughput: throughput,
        runtime: runtime,
        memory: memory,
        total_processed: total_processed
      }
    end

    # Overall winners by category
    puts "\n🥇 CATEGORY WINNERS:"
    
    best_throughput = overall_metrics.max_by { |_, metrics| metrics[:throughput] }
    fastest_runtime = overall_metrics.min_by { |_, metrics| metrics[:runtime] }
    lowest_memory = overall_metrics.min_by { |_, metrics| metrics[:memory] }
    
    puts "  🚀 Highest Throughput: #{best_throughput[0].upcase} (#{best_throughput[1][:throughput].round(1)} msg/sec)"
    puts "  ⚡ Fastest Runtime:     #{fastest_runtime[0].upcase} (#{fastest_runtime[1][:runtime].round(3)}s)"
    puts "  💾 Lowest Memory:      #{lowest_memory[0].upcase} (#{lowest_memory[1][:memory].round(2)} MB)"

    # Scenario-by-scenario winners
    puts "\n📊 SCENARIO WINNERS:"
    scenarios = @subject_data[@subjects.first]['scenario_results'].keys
    scenarios.each do |scenario|
      scenario_metrics = {}
      @subjects.each do |subject|
        data = @subject_data[subject]['scenario_results'][scenario]
        scenario_metrics[subject] = data['throughput']['messages_per_second']
      end
      
      winner = scenario_metrics.max_by { |_, throughput| throughput }
      scenario_name = @subject_data[@subjects.first]['scenario_results'][scenario]['name']
      puts "  #{scenario_name.ljust(20)}: #{winner[0].upcase} (#{winner[1].round(1)} msg/sec)"
    end

    # Overall recommendation
    puts "\n💡 RECOMMENDATIONS:"
    
    # Find the best overall performer (combining throughput and memory efficiency)
    performance_scores = overall_metrics.map do |subject, metrics|
      # Normalize scores (higher throughput is better, lower memory is better)
      max_throughput = overall_metrics.values.map { |m| m[:throughput] }.max
      min_memory = overall_metrics.values.map { |m| m[:memory] }.min
      
      throughput_score = metrics[:throughput] / max_throughput
      memory_score = min_memory / metrics[:memory]
      combined_score = (throughput_score + memory_score) / 2
      
      [subject, combined_score]
    end
    
    best_overall = performance_scores.max_by { |_, score| score }
    
    puts "  ✅ Best Overall Performance: #{best_overall[0].upcase}"
    puts "     - Balanced combination of throughput and memory efficiency"
    
    # Generate optimization suggestions
    puts "\n🔧 OPTIMIZATION SUGGESTIONS:"
    puts "  • Test with larger message volumes to validate scalability"
    puts "  • Profile CPU utilization patterns during peak loads"
    puts "  • Consider workload-specific optimizations based on scenario winners"
    
    # Check for significant memory differences
    memory_values = overall_metrics.values.map { |m| m[:memory] }
    if memory_values.max > memory_values.min * 1.5
      puts "  • Investigate memory usage patterns - significant differences detected"
    end
    
    # Check for error patterns
    total_errors_by_subject = {}
    @subjects.each do |subject|
      total_errors = @subject_data[subject]['scenario_results'].values.sum { |s| s['errors'] || 0 }
      total_errors_by_subject[subject] = total_errors
    end
    
    if total_errors_by_subject.values.any? { |errors| errors > 0 }
      puts "  • Address error handling - some subjects had processing errors"
    end
  end

  def total_messages_processed(data)
    data['scenario_results'].values.sum { |scenario| scenario['messages_processed'] }
  end
  
  def generate_visualizations
    puts "\n" + "=" * 80
    puts "📊 GRAPHICAL VISUALIZATIONS"
    puts "=" * 80
    
    # Show color legend for subjects
    puts "\n🎨 Color Legend:"
    @subjects.each_with_index do |subject, idx|
      color_name = get_subject_color_name(idx)
      puts "  #{subject.upcase.ljust(15)}: #{color_name}"
    end
    
    visualize_overall_throughput
    visualize_scenario_throughput
    visualize_memory_usage
    visualize_processing_times
  end
  
  private
  
  def get_subject_color(index)
    colors = [:blue, :red, :green, :yellow, :cyan, :magenta]
    colors[index % colors.length]
  end
  
  def get_subject_color_name(index)
    color_names = ["Blue", "Red", "Green", "Yellow", "Cyan", "Magenta"]
    color_names[index % color_names.length]
  end
  
  def visualize_overall_throughput
    puts "\n📈 Overall Throughput Comparison"
    puts "-" * 60
    
    # Collect overall throughput data with colors
    labels = []
    values = []
    colors = []
    
    @subjects.each_with_index do |subject, idx|
      data = @subject_data[subject]
      runtime = data['overall_stats']['total_runtime']
      total_processed = total_messages_processed(data)
      throughput = total_processed / runtime
      
      labels << subject.upcase
      values << throughput
      colors << get_subject_color(idx)
    end
    
    # Create individual barplots for each subject with their own color
    # Then combine them into a single visualization
    max_value = values.max
    
    puts "\n  Overall Throughput (messages/second)"
    puts "  " + "─" * 60
    
    labels.each_with_index do |label, idx|
      bar_length = ((values[idx] / max_value) * 50).to_i
      bar = "█" * bar_length
      color = colors[idx]
      
      # Apply color to the bar using ANSI codes
      colored_bar = colorize_bar(bar, color)
      
      puts sprintf("  %-12s │%s %.1f", label, colored_bar, values[idx])
    end
    puts "  " + "─" * 60
    puts "                0" + " " * 45 + sprintf("%.0f", max_value)
  end
  
  def colorize_bar(text, color)
    color_codes = {
      blue: "\e[34m",
      red: "\e[31m",
      green: "\e[32m",
      yellow: "\e[33m",
      cyan: "\e[36m",
      magenta: "\e[35m"
    }
    reset = "\e[0m"
    
    "#{color_codes[color]}#{text}#{reset}"
  end
  
  def visualize_scenario_throughput
    puts "\n📊 Scenario Throughput Comparison"
    puts "-" * 60
    
    scenarios = @subject_data[@subjects.first]['scenario_results'].keys
    
    scenarios.each do |scenario|
      scenario_name = @subject_data[@subjects.first]['scenario_results'][scenario]['name']
      
      # Collect data for this scenario
      labels = []
      values = []
      colors = []
      
      @subjects.each_with_index do |subject, idx|
        data = @subject_data[subject]['scenario_results'][scenario]
        labels << subject.upcase
        values << data['throughput']['messages_per_second']
        colors << get_subject_color(idx)
      end
      
      # Create colored bar chart
      max_value = values.max
      
      puts "\n  #{scenario_name} - Throughput (msg/sec)"
      puts "  " + "─" * 60
      
      labels.each_with_index do |label, idx|
        bar_length = ((values[idx] / max_value) * 45).to_i
        bar = "█" * bar_length
        colored_bar = colorize_bar(bar, colors[idx])
        
        puts sprintf("  %-12s │%s %.1f", label, colored_bar, values[idx])
      end
      puts "  " + "─" * 60
    end
  end
  
  def visualize_memory_usage
    puts "\n💾 Memory Usage Comparison"
    puts "-" * 60
    
    # Collect memory data with colors
    labels = []
    values = []
    colors = []
    
    @subjects.each_with_index do |subject, idx|
      data = @subject_data[subject]
      labels << subject.upcase
      values << data['overall_stats']['memory_used_mb']
      colors << get_subject_color(idx)
    end
    
    # Create colored bar chart
    max_value = values.max
    
    puts "\n  Memory Usage (MB)"
    puts "  " + "─" * 60
    
    labels.each_with_index do |label, idx|
      bar_length = ((values[idx] / max_value) * 50).to_i
      bar = "█" * bar_length
      colored_bar = colorize_bar(bar, colors[idx])
      
      puts sprintf("  %-12s │%s %.2f MB", label, colored_bar, values[idx])
    end
    puts "  " + "─" * 60
    puts "                0" + " " * 45 + sprintf("%.0f MB", max_value)
  end
  
  def visualize_processing_times
    puts "\n⏱️  Processing Time Comparison by Scenario"
    puts "-" * 60
    
    scenarios = @subject_data[@subjects.first]['scenario_results'].keys
    
    # For each scenario, show processing times
    scenarios.each do |scenario|
      scenario_name = @subject_data[@subjects.first]['scenario_results'][scenario]['name']
      
      # Collect data for this scenario
      labels = []
      values = []
      colors = []
      
      @subjects.each_with_index do |subject, idx|
        data = @subject_data[subject]['scenario_results'][scenario]
        labels << subject.upcase
        values << data['times']['total']
        colors << get_subject_color(idx)
      end
      
      # Create colored bar chart
      max_value = values.max
      
      puts "\n  #{scenario_name} - Processing Time (seconds)"
      puts "  " + "─" * 60
      
      labels.each_with_index do |label, idx|
        bar_length = ((values[idx] / max_value) * 45).to_i
        bar = "█" * bar_length
        colored_bar = colorize_bar(bar, colors[idx])
        
        puts sprintf("  %-12s │%s %.3f", label, colored_bar, values[idx])
      end
      puts "  " + "─" * 60
    end
  end
end

# Command line interface
if __FILE__ == $0
  if ARGV.length < 2
    puts "Usage: ruby compare_benchmarks.rb subject1 subject2 [subject3 ...]"
    puts ""
    puts "Compares benchmark results between multiple subjects/implementations."
    puts "Will automatically find the most recent JSON file for each subject."
    puts ""
    puts "Example:"
    puts "  ruby compare_benchmarks.rb threadpool ractor"
    puts "  ruby compare_benchmarks.rb threadpool ractor async_queue"
    puts ""
    puts "Available benchmark files:"
    Dir.glob("benchmark_results_*.json").group_by { |f| f.match(/benchmark_results_(.+?)_\d+_\d+\.json/)[1] rescue "unknown" }.each do |subject, files|
      puts "  #{subject}: #{files.length} file(s), latest: #{files.sort_by { |f| File.mtime(f) }.last}"
    end
    exit 1
  end

  subjects = ARGV

  begin
    comparator = BenchmarkComparator.new(subjects)
    comparator.compare
  rescue => e
    puts "Error: #{e.message}"
    exit 1
  end
end