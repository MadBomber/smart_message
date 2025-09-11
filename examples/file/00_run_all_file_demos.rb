#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Run All File Transport Demos
# 
# This script runs all the FileTransport demonstration programs
# and provides a summary of each demo's capabilities.

require 'fileutils'

puts "🚀 SmartMessage FileTransport Demo Suite"
puts "=" * 50
puts

demos = [
  {
    file: '01_basic_file_transport_demo.rb',
    title: 'Basic File Transport Demo',
    description: 'Core FileTransport functionality including writing, formats, and modes'
  },
  {
    file: '02_fifo_transport_demo.rb', 
    title: 'FIFO Transport Demo',
    description: 'Named pipes (FIFO) for real-time inter-process communication'
  },
  {
    file: '03_file_watching_demo.rb',
    title: 'File Watching Demo', 
    description: 'Monitoring files for changes and processing new content'
  },
  {
    file: '04_multi_transport_file_demo.rb',
    title: 'Multi-Transport File Demo',
    description: 'Advanced patterns with multiple transports and routing'
  }
]

def run_demo(demo_file, title)
  puts "🔧 Running: #{title}"
  puts "-" * 60
  
  start_time = Time.now
  
  begin
    # Run the demo in a separate process to isolate any issues
    output = `ruby #{demo_file} 2>&1`
    exit_status = $?.exitstatus
    
    end_time = Time.now
    duration = (end_time - start_time).round(2)
    
    if exit_status == 0
      puts output
      puts "✅ SUCCESS - Completed in #{duration}s"
    else
      puts "❌ FAILED - Exit status: #{exit_status}"
      puts "Output:"
      puts output
    end
    
    return exit_status == 0
    
  rescue => e
    puts "❌ ERROR - #{e.message}"
    return false
  end
end

def check_system_requirements
  puts "🔍 Checking System Requirements"
  puts "-" * 40
  
  requirements = {
    'Ruby version' => RUBY_VERSION,
    'Platform' => RUBY_PLATFORM,
    'SmartMessage available' => File.exist?('../../lib/smart_message.rb')
  }
  
  requirements.each do |req, status|
    puts "  #{req}: #{status}"
  end
  
  # Check for FIFO support
  fifo_supported = false
  begin
    test_dir = Dir.mktmpdir('fifo_check')
    test_fifo = File.join(test_dir, 'test.fifo')
    fifo_supported = system("mkfifo #{test_fifo} 2>/dev/null") && File.exist?(test_fifo)
    FileUtils.rm_rf(test_dir)
  rescue
    fifo_supported = false
  end
  
  puts "  FIFO support: #{fifo_supported ? '✅ Available' : '❌ Not available'}"
  
  unless fifo_supported
    puts "  ⚠️  Note: FIFO demos will be skipped on this system"
  end
  
  puts
  return fifo_supported
end

def show_demo_menu(demos)
  puts "📋 Available Demos:"
  puts "-" * 20
  
  demos.each_with_index do |demo, index|
    puts "  #{index + 1}. #{demo[:title]}"
    puts "     #{demo[:description]}"
    puts
  end
  
  puts "  0. Run all demos"
  puts "  q. Quit"
  puts
end

def get_user_choice(max_choice)
  loop do
    print "Enter your choice (0-#{max_choice}, q): "
    input = gets.chomp.downcase
    
    return :quit if input == 'q'
    return 0 if input == '0'
    
    choice = input.to_i
    if choice >= 1 && choice <= max_choice
      return choice
    end
    
    puts "Invalid choice. Please try again."
  end
end

# Change to the examples/file directory
script_dir = File.dirname(__FILE__)
Dir.chdir(script_dir)

# Check system requirements
fifo_supported = check_system_requirements

# Interactive mode
if ARGV.empty?
  loop do
    show_demo_menu(demos)
    choice = get_user_choice(demos.length)
    
    break if choice == :quit
    
    puts
    
    if choice == 0
      # Run all demos
      puts "🚀 Running All Demos"
      puts "=" * 30
      puts
      
      success_count = 0
      total_start = Time.now
      
      demos.each_with_index do |demo, index|
        # Skip FIFO demo if not supported
        if demo[:file].include?('fifo') && !fifo_supported
          puts "⏭️  Skipping #{demo[:title]} (FIFO not supported)"
          puts
          next
        end
        
        if run_demo(demo[:file], demo[:title])
          success_count += 1
        end
        puts
      end
      
      total_time = (Time.now - total_start).round(2)
      
      puts "📊 Summary"
      puts "=" * 20
      puts "Successful demos: #{success_count}/#{demos.length}"
      puts "Total time: #{total_time}s"
      puts
      
    else
      # Run specific demo
      demo = demos[choice - 1]
      
      # Check if FIFO demo on unsupported system
      if demo[:file].include?('fifo') && !fifo_supported
        puts "❌ Cannot run #{demo[:title]} - FIFO not supported on this system"
        puts
        next
      end
      
      run_demo(demo[:file], demo[:title])
      puts
    end
  end
  
  puts "👋 Thanks for exploring SmartMessage FileTransport!"
  
else
  # Command line mode
  case ARGV[0]
  when 'all'
    puts "🚀 Running All Demos (Non-Interactive Mode)"
    puts "=" * 45
    puts
    
    success_count = 0
    
    demos.each do |demo|
      # Skip FIFO demo if not supported
      if demo[:file].include?('fifo') && !fifo_supported
        puts "⏭️  Skipping #{demo[:title]} (FIFO not supported)"
        puts
        next
      end
      
      if run_demo(demo[:file], demo[:title])
        success_count += 1
      end
      puts
    end
    
    puts "📊 Final Summary: #{success_count}/#{demos.length} demos successful"
    
  when 'list'
    puts "📋 Available FileTransport Demos:"
    demos.each_with_index do |demo, index|
      puts "  #{index + 1}. #{demo[:file]} - #{demo[:title]}"
    end
    
  when /^\d+$/
    choice = ARGV[0].to_i
    if choice >= 1 && choice <= demos.length
      demo = demos[choice - 1]
      
      if demo[:file].include?('fifo') && !fifo_supported
        puts "❌ Cannot run #{demo[:title]} - FIFO not supported on this system"
        exit 1
      end
      
      success = run_demo(demo[:file], demo[:title])
      exit(success ? 0 : 1)
    else
      puts "❌ Invalid demo number. Use 'list' to see available demos."
      exit 1
    end
    
  else
    puts "Usage:"
    puts "  #{$0}           # Interactive mode"
    puts "  #{$0} all       # Run all demos"
    puts "  #{$0} list      # List available demos"
    puts "  #{$0} N         # Run demo number N"
    exit 1
  end
end