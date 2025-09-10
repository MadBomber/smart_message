#!/usr/bin/env ruby
# examples/memory/00_run_all_demos.rb
#
# Master Demo Runner - Executes All SmartMessage Memory Transport Examples
#
# This script runs all the demo programs in the examples/memory directory
# in sequence, with clear banners to show which demo is currently running.

require 'fileutils'
require 'pathname'

class SmartMessageDemoRunner
  DEMO_PROGRAMS = [
    {
      file: "01_message_deduplication_demo.rb",
      title: "Message Deduplication with DDQ",
      description: "Demonstrates message deduplication patterns and duplicate message prevention",
      duration: "~10 seconds"
    },
    {
      file: "02_dead_letter_queue_demo.rb", 
      title: "Dead Letter Queue & Error Handling",
      description: "Shows DLQ pattern implementation with circuit breakers and error recovery",
      duration: "~15 seconds"
    },
    {
      file: "03_point_to_point_orders.rb",
      title: "Point-to-Point Order Processing",
      description: "Order processing system with 1:1 messaging between OrderService and PaymentService",
      duration: "~8 seconds"
    },
    {
      file: "04_publish_subscribe_events.rb",
      title: "Publish-Subscribe Event Broadcasting",
      description: "Event-driven architecture with multiple subscribers (Email, SMS, Audit)",
      duration: "~10 seconds"
    },
    {
      file: "05_many_to_many_chat.rb",
      title: "Many-to-Many Chat System",
      description: "Interactive chat system with rooms, bots, and human agents",
      duration: "~12 seconds"
    },
    {
      file: "06_stdout_publish_only.rb",
      title: "STDOUT Transport (Publish-Only)",
      description: "Demonstrates STDOUT transport for logging and external tool integration",
      duration: "~5 seconds"
    },
    {
      file: "07_proc_handlers_demo.rb",
      title: "Proc-Based Message Handlers",
      description: "Flexible message handlers using blocks, procs, lambdas, and methods",
      duration: "~8 seconds"
    },
    {
      file: "08_custom_logger_demo.rb",
      title: "Custom Logging Implementations",
      description: "Advanced logging with multiple loggers and custom formatting",
      duration: "~12 seconds"
    },
    {
      file: "09_error_handling_demo.rb",
      title: "Comprehensive Error Handling",
      description: "Error handling strategies, validation failures, and graceful degradation",
      duration: "~10 seconds"
    },
    {
      file: "10_entity_addressing_basic.rb",
      title: "Entity Addressing Basics",
      description: "Message routing by entity addresses with FROM/TO/REPLY_TO patterns",
      duration: "~8 seconds"
    },
    {
      file: "11_entity_addressing_with_filtering.rb",
      title: "Advanced Entity Addressing & Filtering",
      description: "Complex filtering patterns with regex-based address matching",
      duration: "~10 seconds"
    },
    {
      file: "12_regex_filtering_microservices.rb",
      title: "Microservices with Regex Filtering",
      description: "Service-to-service communication with environment-based filtering",
      duration: "~8 seconds"
    },
    {
      file: "13_header_block_configuration.rb",
      title: "Header Block Configuration",
      description: "Dynamic header configuration with block-based modification",
      duration: "~6 seconds"
    },
    {
      file: "14_global_configuration_demo.rb",
      title: "Global Configuration Management",
      description: "Global transport settings and configuration inheritance",
      duration: "~8 seconds"
    },
    {
      file: "15_logger_demo.rb",
      title: "Advanced Logger Configuration",
      description: "Logger configuration, log levels, and SmartMessage lifecycle integration",
      duration: "~10 seconds"
    },
    {
      file: "16_pretty_print_demo.rb",
      title: "Message Pretty-Printing",
      description: "Message inspection and debugging with pretty-print formatting",
      duration: "~5 seconds"
    }
  ].freeze

  def initialize
    @base_dir = File.dirname(__FILE__)
    @total_demos = DEMO_PROGRAMS.length
    @start_time = Time.now
  end

  def run_all
    print_main_banner
    print_overview
    
    DEMO_PROGRAMS.each_with_index do |demo, index|
      run_demo(demo, index + 1)
    end
    
    print_completion_summary
  end

  private

  # Helper method to calculate visual width of string accounting for emoji
  def visual_width(str)
    # Remove ANSI escape sequences if any
    clean_str = str.gsub(/\e\[[0-9;]*m/, '')
    
    # Count emoji and other wide characters
    emoji_count = clean_str.scan(/[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]/).length
    
    # Each emoji takes up 2 visual columns but counts as 1 character
    # So we add the emoji_count to get the actual visual width
    clean_str.length + emoji_count
  end

  # Helper method to pad string to exact visual width
  def pad_to_width(str, target_width)
    current_width = visual_width(str)
    if current_width <= target_width
      str + (" " * (target_width - current_width))
    else
      # Truncate if too long, being careful about emoji
      str[0...(target_width - current_width)]
    end
  end

  def print_main_banner
    puts "\n"
    puts "█" * 100
    puts "█" + " " * 98 + "█"
    puts "█" + pad_to_width("        🚀 SMARTMESSAGE COMPREHENSIVE DEMO SUITE 🚀        ", 98) + "█"
    puts "█" + " " * 98 + "█"
    puts "█" + pad_to_width("  Running all #{@total_demos} demo programs to showcase SmartMessage capabilities  ", 98) + "█"
    puts "█" + " " * 98 + "█"
    puts "█" * 100
    puts "\n"
  end

  def print_overview
    puts "📋 DEMO OVERVIEW:"
    puts "=" * 80
    
    DEMO_PROGRAMS.each_with_index do |demo, index|
      printf "  %2d. %-35s %s\n", 
             index + 1, 
             demo[:title], 
             "(#{demo[:duration]})"
    end
    
    total_time = DEMO_PROGRAMS.sum { |demo| 
      demo[:duration].scan(/\d+/).first.to_i 
    }
    
    puts "=" * 80
    puts "📊 Total estimated time: ~#{total_time} seconds (~#{(total_time/60.0).round(1)} minutes)"
    puts "🎯 Each demo runs independently with clear separation"
    puts "⏸️  Press Ctrl+C at any time to stop the demo suite"
    puts "\n"
  end

  def run_demo(demo, demo_number)
    file_path = File.join(@base_dir, demo[:file])
    
    unless File.exist?(file_path)
      print_error_banner(demo_number, demo[:title], "File not found: #{demo[:file]}")
      return
    end

    print_demo_banner(demo_number, demo)
    
    start_time = Time.now
    begin
      # Execute the demo program
      success = system("cd #{@base_dir} && ruby #{demo[:file]}")
      end_time = Time.now
      
      if success
        print_demo_completion(demo_number, demo[:title], end_time - start_time)
      else
        print_demo_error(demo_number, demo[:title], "Demo exited with error code")
      end
      
    rescue Interrupt
      puts "\n"
      puts "🛑 DEMO SUITE INTERRUPTED BY USER"
      puts "   Completed #{demo_number - 1} of #{@total_demos} demos"
      exit(0)
    rescue => e
      print_demo_error(demo_number, demo[:title], e.message)
    end
    
    print_demo_separator
  end

  def print_demo_banner(demo_number, demo)
    puts "┌" + "─" * 98 + "┐"
    puts "│" + " " * 98 + "│"
    puts "│" + pad_to_width("🔥 DEMO #{demo_number.to_s.rjust(2, '0')}/#{@total_demos.to_s.rjust(2, '0')}: #{demo[:title]}", 98) + "│"
    puts "│" + " " * 98 + "│"
    puts "│" + pad_to_width("📝 #{demo[:description]}", 98) + "│"
    puts "│" + pad_to_width("⏱️  Expected duration: #{demo[:duration]}", 98) + "│"
    puts "│" + pad_to_width("📁 File: #{demo[:file]}", 98) + "│"
    puts "│" + " " * 98 + "│"
    puts "└" + "─" * 98 + "┘"
    puts "\n"
  end

  def print_demo_completion(demo_number, title, actual_time)
    puts "\n"
    puts "✅ DEMO #{demo_number.to_s.rjust(2, '0')} COMPLETED: #{title}"
    puts "   ⏱️  Actual execution time: #{actual_time.round(2)} seconds"
    puts "\n"
  end

  def print_demo_error(demo_number, title, error_message)
    puts "\n"
    puts "❌ DEMO #{demo_number.to_s.rjust(2, '0')} FAILED: #{title}"
    puts "   🚨 Error: #{error_message}"
    puts "   ⏭️  Continuing with next demo..."
    puts "\n"
  end

  def print_error_banner(demo_number, title, error_message)
    puts "┌" + "─" * 98 + "┐"
    puts "│" + pad_to_width("❌ DEMO #{demo_number.to_s.rjust(2, '0')}/#{@total_demos.to_s.rjust(2, '0')} ERROR: #{title}", 98) + "│"
    puts "│" + " " * 98 + "│"
    puts "│" + pad_to_width("🚨 #{error_message}", 98) + "│"
    puts "│" + " " * 98 + "│"
    puts "└" + "─" * 98 + "┘"
    puts "\n"
  end

  def print_demo_separator
    puts "═" * 100
    puts "\n"
    sleep(1) # Brief pause between demos for readability
  end

  def print_completion_summary
    total_time = Time.now - @start_time
    
    puts "\n"
    puts "🏁" * 50
    puts "🏁" + " " * 96 + "🏁"
    puts "🏁" + pad_to_width("         🎉 ALL DEMOS COMPLETED SUCCESSFULLY! 🎉         ", 96) + "🏁"
    puts "🏁" + " " * 96 + "🏁"
    puts "🏁" + pad_to_width("  Total execution time: #{total_time.round(2)} seconds (#{(total_time/60.0).round(2)} minutes)  ", 96) + "🏁"
    puts "🏁" + pad_to_width("  Demos completed: #{@total_demos}  ", 96) + "🏁"
    puts "🏁" + " " * 96 + "🏁"
    puts "🏁" * 50
    puts "\n"
    
    puts "📋 WHAT YOU'VE SEEN:"
    puts "=" * 80
    puts "✅ Message deduplication and Dead Letter Queue patterns"
    puts "✅ Point-to-point, publish-subscribe, and many-to-many messaging"  
    puts "✅ STDOUT transport for debugging and external integration"
    puts "✅ Advanced message handlers (procs, blocks, lambdas)"
    puts "✅ Comprehensive logging and error handling strategies"
    puts "✅ Entity addressing and advanced message filtering"
    puts "✅ Microservices communication patterns"
    puts "✅ Configuration management and message inspection"
    puts "\n"
    
    puts "🚀 NEXT STEPS:"
    puts "=" * 80
    puts "• Explore individual demos: ruby examples/memory/<demo_file>"
    puts "• Check out Redis Queue examples: examples/redis_queue/"
    puts "• View comprehensive documentation: docs/"
    puts "• Start building with SmartMessage in your projects!"
    puts "\n"
    
    puts "💡 For more information:"
    puts "   📖 README.md - Getting started guide"
    puts "   🔧 examples/memory/README.md - Detailed example descriptions"
    puts "   📚 https://github.com/MadBomber/smart_message - Full documentation"
    puts "\n"
  end
end

# Allow running directly or requiring as a library
if __FILE__ == $0
  puts "Starting SmartMessage Demo Suite..."
  puts "Press Ctrl+C to interrupt at any time."
  puts "\n"
  
  runner = SmartMessageDemoRunner.new
  runner.run_all
end