#!/usr/bin/env ruby
# Redis Statistics Monitor for SmartMessage Demo
# Shows comprehensive pub/sub and performance statistics

require 'redis'
require 'json'
require 'io/console'

class RedisStats
  def initialize
    @redis = Redis.new
    @start_time = Time.now
    @message_counts = Hash.new(0)
    @channel_stats = Hash.new { |h, k| h[k] = { last_count: 0, rate: 0, total_messages: 0 } }
    @previous_stats = {}
    @previous_command_stats = {}
    @refresh_rate = 2
    
    # Get terminal size with fallback
    if IO.console
      @terminal_height, @terminal_width = IO.console.winsize
    else
      # Fallback for non-TTY environments
      @terminal_height = (ENV['LINES'] || 24).to_i
      @terminal_width = (ENV['COLUMNS'] || 80).to_i
    end
    
    # Initialize terminal
    setup_terminal
    show_startup_message
    setup_signal_handlers
  end

  def setup_terminal
    # Hide cursor, enable alternate screen buffer
    print "\e[?25l"      # Hide cursor
    print "\e[?1049h"    # Enable alternate screen buffer
    print "\e[2J"        # Clear screen
    print "\e[H"         # Move cursor to home position
  end

  def restore_terminal
    # Show cursor, disable alternate screen buffer
    print "\e[?1049l"    # Disable alternate screen buffer
    print "\e[?25h"      # Show cursor
    print "\e[2J"        # Clear screen
    print "\e[H"         # Move cursor to home position
  end

  def show_startup_message
    clear_screen
    center_text("📊 Redis Statistics Monitor for SmartMessage")
    center_text("Monitoring Redis pub/sub and performance metrics...")
    center_text("Press 'q' to quit, 'r' to refresh, '+/-' to change refresh rate")
    center_text("")
    center_text("Loading... please wait")
    sleep(1)
  end

  def setup_signal_handlers
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        cleanup_and_exit
      end
    end
  end

  def cleanup_and_exit
    restore_terminal
    puts "\n📊 Redis statistics monitor shutting down..."
    show_final_summary
    exit(0)
  end

  def start_monitoring
    # Only set up interactive mode if we have a console
    interactive_mode = IO.console && STDIN.tty?
    
    if interactive_mode
      # Make stdin non-blocking for key detection
      STDIN.echo = false
      STDIN.raw!
    end
    
    loop do
      # Update terminal size if console is available
      if IO.console
        @terminal_height, @terminal_width = IO.console.winsize
      end
      
      # Check for keyboard input (non-blocking) only in interactive mode
      if interactive_mode && IO.select([STDIN], nil, nil, 0)
        key = STDIN.getc
        case key
        when 'q', 'Q', "\e"  # q, Q, or Escape to quit
          cleanup_and_exit
        when 'r', 'R'        # r or R to refresh immediately
          # Just continue the loop to refresh
        when '+'             # Increase refresh rate
          @refresh_rate = [@refresh_rate - 0.5, 0.5].max
          show_status_message("Refresh rate: #{@refresh_rate}s") if interactive_mode
        when '-'             # Decrease refresh rate
          @refresh_rate = [@refresh_rate + 0.5, 10.0].min
          show_status_message("Refresh rate: #{@refresh_rate}s") if interactive_mode
        when 'h', 'H', '?'   # Help
          show_help_overlay if interactive_mode
        end
      end
      
      render_dashboard
      sleep(@refresh_rate)
    end
  rescue => e
    restore_terminal
    puts "❌ Error monitoring Redis stats: #{e.message}"
    puts "#{e.backtrace.first(3).join("\n")}"
    exit(1)
  ensure
    restore_terminal
  end

  def render_dashboard
    clear_screen
    
    # Calculate available space
    content_lines = []
    content_lines << build_header
    content_lines << build_separator
    content_lines += build_pubsub_overview
    content_lines << ""
    content_lines += build_channel_analytics
    content_lines << ""
    content_lines += build_command_statistics
    content_lines << ""
    content_lines += build_latency_metrics
    content_lines << ""
    content_lines += build_network_stats
    content_lines << ""
    content_lines += build_connection_stats
    content_lines << ""
    content_lines << build_footer
    
    # Display content with proper positioning
    content_lines.each_with_index do |line, index|
      if index < @terminal_height - 1  # Leave space for status line
        move_cursor(index + 1, 1)
        print line.ljust(@terminal_width)[0, @terminal_width]
      end
    end
    
    # Status line at bottom
    move_cursor(@terminal_height, 1)
    status_line = "Last: #{Time.now.strftime('%H:%M:%S')} | Rate: #{@refresh_rate}s | Press 'h' for help, 'q' to quit"
    print "\e[7m#{status_line.ljust(@terminal_width)[0, @terminal_width]}\e[0m"  # Reverse video
  end

  private

  def clear_screen
    print "\e[2J\e[H"
  end

  def move_cursor(row, col)
    print "\e[#{row};#{col}H"
  end

  def center_text(text)
    padding = (@terminal_width - text.length) / 2
    puts " " * [padding, 0].max + text
  end

  def show_status_message(message)
    move_cursor(@terminal_height - 1, 1)
    print "\e[K"  # Clear line
    print "\e[33m#{message}\e[0m"  # Yellow text
    sleep(1)
  end

  def show_help_overlay
    help_lines = [
      "┌─ HELP ─────────────────────────────────────────┐",
      "│                                                │",
      "│  Controls:                                     │",
      "│    q/Q/Esc : Quit                             │",
      "│    r/R     : Refresh immediately              │",
      "│    +       : Increase refresh rate            │",
      "│    -       : Decrease refresh rate            │",
      "│    h/H/?   : Show this help                   │",
      "│                                                │",
      "│  Dashboard shows:                              │",
      "│    • Active Redis pub/sub channels            │",
      "│    • Real-time performance metrics            │",
      "│    • SmartMessage activity breakdown          │",
      "│    • Connection and memory statistics         │",
      "│                                                │",
      "│         Press any key to continue...          │",
      "└────────────────────────────────────────────────┘"
    ]
    
    start_row = (@terminal_height - help_lines.length) / 2
    help_lines.each_with_index do |line, index|
      move_cursor(start_row + index, (@terminal_width - 50) / 2)
      print "\e[44m\e[37m#{line}\e[0m"  # Blue background, white text
    end
    
    STDIN.getc  # Wait for any key
  end

  def build_header
    uptime = (Time.now - @start_time).to_i
    title = "📊 Redis Statistics Dashboard"
    subtitle = "SmartMessage City Demo | Uptime: #{format_duration(uptime)}"
    
    # Center text within terminal width
    title_line = title.center(@terminal_width)
    subtitle_line = subtitle.center(@terminal_width)
    
    title_line
  end

  def build_separator
    "=" * [@terminal_width, 80].min
  end

  def build_footer
    "=" * [@terminal_width, 80].min
  end

  def build_pubsub_overview
    lines = []
    lines << "🔀 PUB/SUB OVERVIEW:"
    lines << "-" * 40

    # Get active channels and subscriber info
    channels = @redis.pubsub("channels")
    total_subscribers = 0
    
    info = @redis.info("stats")
    pubsub_channels = info["pubsub_channels"] || 0
    pubsub_patterns = info["pubsub_patterns"] || 0
    pubsub_clients = info["pubsub_clients"] || 0
    
    # Calculate message activity
    publish_stats = extract_command_stats(info, "publish")
    total_publishes = publish_stats[:calls]
    publish_rate = calculate_publish_rate(publish_stats)
    
    lines << "   📊 Channels: #{pubsub_channels} active, #{pubsub_patterns} patterns"
    lines << "   👥 Clients: #{pubsub_clients} subscribed"
    lines << "   📨 Messages: #{format_number(total_publishes)} total, #{publish_rate}/sec"
    lines << "   📡 Avg Latency: #{publish_stats[:avg_latency]}μs"
    
    lines
  end

  def build_channel_analytics
    lines = []
    lines << "📺 CHANNEL ANALYTICS:"
    lines << "-" * 40

    # Get detailed channel information
    channels = @redis.pubsub("channels")
    
    if channels.empty?
      lines << "   No active channels"
      return lines
    end

    # SmartMessage channels analysis
    message_types = [
      { name: "HealthCheck", pattern: "HealthCheckMessage", desc: "Health monitoring" },
      { name: "HealthStatus", pattern: "HealthStatusMessage", desc: "Status responses" },
      { name: "FireEmergency", pattern: "FireEmergencyMessage", desc: "Fire alerts" },
      { name: "FireDispatch", pattern: "FireDispatchMessage", desc: "Fire dispatch" },
      { name: "SilentAlarm", pattern: "SilentAlarmMessage", desc: "Bank alarms" },
      { name: "PoliceDispatch", pattern: "PoliceDispatchMessage", desc: "Police dispatch" },
      { name: "EmergencyResolved", pattern: "EmergencyResolvedMessage", desc: "Resolutions" }
    ]

    message_types.each do |msg_type|
      channel = "Messages::#{msg_type[:pattern]}"
      if channels.include?(channel)
        subscriber_count = @redis.pubsub("numsub", channel)[1] || 0
        
        # Calculate estimated message rate for this channel
        rate = estimate_channel_message_rate(msg_type[:name])
        
        status_icon = subscriber_count > 0 ? "🟢" : "🔴"
        rate_display = rate > 0 ? "#{rate.round(1)}/sec" : "idle"
        
        lines << "   #{status_icon} #{msg_type[:name].ljust(13)} #{subscriber_count} subs | #{rate_display.ljust(8)} | #{msg_type[:desc]}"
      end
    end
    
    lines
  end

  def build_command_statistics  
    lines = []
    lines << "📊 COMMAND STATISTICS:"
    lines << "-" * 40

    info = @redis.info("stats")
    
    # Extract key pub/sub commands
    commands = [
      { name: "PUBLISH", key: "publish" },
      { name: "PUBSUB", key: "pubsub|numsub" },
      { name: "SUBSCRIBE", key: "subscribe" }
    ]
    
    commands.each do |cmd|
      stats = extract_command_stats(info, cmd[:key])
      next if stats[:calls] == 0
      
      rate = calculate_command_rate(cmd[:key], stats)
      
      lines << "   📈 #{cmd[:name].ljust(12)} #{format_number(stats[:calls])} calls | #{rate}/sec | #{stats[:avg_latency]}μs avg"
    end
    
    # Total command summary
    total_commands = info["total_commands_processed"]&.to_i || 0
    current_ops = info["instantaneous_ops_per_sec"]&.to_i || 0
    
    lines << ""
    lines << "   📊 Total Commands: #{format_number(total_commands)}"
    lines << "   ⚡ Current Rate: #{current_ops} ops/sec"
    
    lines
  end

  def build_latency_metrics
    lines = []
    lines << "⏱️  LATENCY METRICS:"
    lines << "-" * 40

    info = @redis.info("stats")
    
    # Extract latency percentiles for pub/sub commands
    latency_data = [
      { cmd: "PUBLISH", key: "latency_percentiles_usec_publish" },
      { cmd: "PUBSUB", key: "latency_percentiles_usec_pubsub|numsub" }
    ]
    
    latency_data.each do |cmd_data|
      if info[cmd_data[:key]]
        percentiles = parse_latency_percentiles(info[cmd_data[:key]])
        lines << "   ⏱️  #{cmd_data[:cmd].ljust(10)} P50: #{percentiles[:p50]}μs | P99: #{percentiles[:p99]}μs | P99.9: #{percentiles[:p999]}μs"
      end
    end
    
    # Show slow log if available
    begin
      slowlog_len = @redis.slowlog("len")
      if slowlog_len > 0
        lines << ""
        lines << "   🐌 Slow Queries: #{slowlog_len} in log"
      end
    rescue
      # Ignore slowlog errors
    end
    
    lines
  end

  def build_network_stats
    lines = []
    lines << "🌐 NETWORK STATISTICS:"
    lines << "-" * 40

    info = @redis.info("stats")
    
    # Current network I/O
    input_kbps = info["instantaneous_input_kbps"]&.to_f || 0.0
    output_kbps = info["instantaneous_output_kbps"]&.to_f || 0.0
    
    # Total network I/O
    total_input = info["total_net_input_bytes"]&.to_i || 0
    total_output = info["total_net_output_bytes"]&.to_i || 0
    
    # Calculate message size estimates
    publish_stats = extract_command_stats(info, "publish")
    avg_message_size = calculate_avg_message_size(total_output, publish_stats[:calls])
    
    lines << "   📥 Input: #{input_kbps.round(2)} KB/s | #{format_bytes(total_input)} total"
    lines << "   📤 Output: #{output_kbps.round(2)} KB/s | #{format_bytes(total_output)} total"
    lines << "   📊 Avg Message Size: #{format_bytes(avg_message_size)}"
    lines << "   🔄 I/O Ratio: #{calculate_io_ratio(total_input, total_output)}"
    
    lines
  end

  def build_performance_stats
    lines = []
    lines << "⚡ PERFORMANCE METRICS:"
    lines << "-" * 40

    info = @redis.info("stats")
    current_stats = {
      total_commands: info["total_commands_processed"]&.to_i || 0,
      total_connections: info["total_connections_received"]&.to_i || 0,
      ops_per_sec: info["instantaneous_ops_per_sec"]&.to_i || 0,
      input_kbps: info["instantaneous_input_kbps"]&.to_f || 0.0,
      output_kbps: info["instantaneous_output_kbps"]&.to_f || 0.0
    }

    # Calculate deltas since last check
    if @previous_stats.any?
      commands_delta = current_stats[:total_commands] - @previous_stats[:total_commands]
      connections_delta = current_stats[:total_connections] - @previous_stats[:total_connections]
      
      lines << "   📈 Commands Processed: #{format_number(current_stats[:total_commands])} (+#{commands_delta})"
      lines << "   🔗 Total Connections: #{format_number(current_stats[:total_connections])} (+#{connections_delta})"
    else
      lines << "   📈 Commands Processed: #{format_number(current_stats[:total_commands])}"
      lines << "   🔗 Total Connections: #{format_number(current_stats[:total_connections])}"
    end

    lines << "   ⚡ Operations/sec: #{current_stats[:ops_per_sec]}"
    lines << "   📥 Input: #{current_stats[:input_kbps].round(2)} KB/s"
    lines << "   📤 Output: #{current_stats[:output_kbps].round(2)} KB/s"

    @previous_stats = current_stats
    lines
  end

  def build_message_breakdown
    lines = []
    lines << "📨 SMARTMESSAGE BREAKDOWN:"
    lines << "-" * 40

    message_types = [
      { name: "HealthCheck", desc: "Health monitoring broadcasts" },
      { name: "HealthStatus", desc: "Service status responses" },
      { name: "FireEmergency", desc: "House fire alerts" },
      { name: "FireDispatch", desc: "Fire truck dispatches" },
      { name: "SilentAlarm", desc: "Bank security alerts" },
      { name: "PoliceDispatch", desc: "Police unit dispatches" },
      { name: "EmergencyResolved", desc: "Incident resolutions" }
    ]

    message_types.each do |msg|
      channel = "Messages::#{msg[:name]}Message"
      subscribers = @redis.pubsub("numsub", channel)[1] || 0
      
      status_icon = subscribers > 0 ? "🟢" : "🔴"
      lines << "   #{status_icon} #{msg[:name].ljust(15)} #{subscribers} subs | #{msg[:desc]}"
    end
    
    lines
  end

  def build_connection_stats
    lines = []
    lines << "🔌 CONNECTION INFO:"
    lines << "-" * 40

    info = @redis.info("clients")
    connected_clients = info["connected_clients"] || 0
    blocked_clients = info["blocked_clients"] || 0
    max_clients = info["maxclients"] || 0

    lines << "   👥 Connected Clients: #{connected_clients}/#{max_clients}"
    lines << "   ⏸️  Blocked Clients: #{blocked_clients}"
    
    # Show client list (limited)
    begin
      client_list = @redis.client("list")
      # Handle both string and array responses
      clients = client_list.is_a?(Array) ? client_list : client_list.split("\n")
      lines << "   📋 Active Connections:"
      clients.first(3).each do |client|  # Reduced to 3 to save space
        if client.include?("cmd=") && client.include?("addr=")
          addr = client[/addr=([^\s]+)/, 1]
          cmd = client[/cmd=([^\s]+)/, 1] 
          lines << "      🔸 #{addr} | #{cmd}" if addr && cmd
        end
      end
      lines << "      ... (showing first 3)" if clients.size > 3
    rescue => e
      lines << "   📋 Connection details unavailable: #{e.message}"
    end
    
    lines
  end

  def build_memory_stats
    lines = []
    lines << "💾 MEMORY USAGE:"
    lines << "-" * 40

    info = @redis.info("memory")
    used_memory = info["used_memory"]&.to_i || 0
    used_memory_peak = info["used_memory_peak"]&.to_i || 0
    used_memory_rss = info["used_memory_rss"]&.to_i || 0

    lines << "   💾 Used Memory: #{format_bytes(used_memory)}"
    lines << "   📈 Peak Memory: #{format_bytes(used_memory_peak)}"
    lines << "   🖥️  RSS Memory: #{format_bytes(used_memory_rss)}"
    
    lines
  end

  def show_final_summary
    uptime = (Time.now - @start_time).to_i
    puts "\n📊 Final Summary:"
    puts "   Monitor ran for: #{format_duration(uptime)}"
    
    info = @redis.info("stats")
    total_commands = info["total_commands_processed"]&.to_i || 0
    puts "   Total commands processed: #{format_number(total_commands)}"
    
    if uptime > 0
      avg_commands_per_sec = total_commands.to_f / uptime
      puts "   Average commands/sec: #{avg_commands_per_sec.round(2)}"
    end
  end

  def format_duration(seconds)
    if seconds < 60
      "#{seconds}s"
    elsif seconds < 3600
      "#{seconds / 60}m #{seconds % 60}s"
    else
      "#{seconds / 3600}h #{(seconds % 3600) / 60}m"
    end
  end

  def format_number(num)
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def format_bytes(bytes)
    units = ['B', 'KB', 'MB', 'GB']
    size = bytes.to_f
    unit_index = 0
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end
    
    "#{size.round(2)} #{units[unit_index]}"
  end

  # Advanced metrics helper methods
  def extract_command_stats(info, command_key)
    cmdstat_key = "cmdstat_#{command_key}"
    cmdstat_data = info[cmdstat_key]
    
    if cmdstat_data
      # Parse: "calls=8081,usec=47004,usec_per_call=5.82,rejected_calls=0,failed_calls=0"
      stats = {}
      cmdstat_data.split(',').each do |pair|
        key, value = pair.split('=')
        stats[key.to_sym] = value.to_f
      end
      
      {
        calls: stats[:calls]&.to_i || 0,
        total_usec: stats[:usec]&.to_f || 0.0,
        avg_latency: stats[:usec_per_call]&.round(2) || 0.0,
        rejected: stats[:rejected_calls]&.to_i || 0,
        failed: stats[:failed_calls]&.to_i || 0
      }
    else
      {
        calls: 0,
        total_usec: 0.0,
        avg_latency: 0.0,
        rejected: 0,
        failed: 0
      }
    end
  end

  def calculate_publish_rate(publish_stats)
    return "0.0" if @previous_command_stats.empty?
    
    current_calls = publish_stats[:calls]
    previous_calls = @previous_command_stats.dig(:publish, :calls) || current_calls
    
    calls_delta = current_calls - previous_calls
    rate = calls_delta.to_f / @refresh_rate
    
    # Update previous stats
    @previous_command_stats[:publish] = publish_stats
    
    rate.round(1).to_s
  end

  def calculate_command_rate(command_key, current_stats)
    return "0.0" if @previous_command_stats.empty?
    
    current_calls = current_stats[:calls]
    previous_calls = @previous_command_stats.dig(command_key.to_sym, :calls) || current_calls
    
    calls_delta = current_calls - previous_calls
    rate = calls_delta.to_f / @refresh_rate
    
    # Update previous stats
    @previous_command_stats[command_key.to_sym] = current_stats
    
    rate.round(1).to_s
  end

  def estimate_channel_message_rate(message_type)
    # Estimate based on message type patterns
    case message_type
    when "HealthCheck"
      # Health checks happen every 5 seconds from health dept
      0.2
    when "HealthStatus"  
      # All services respond to health checks (5+ services * 0.2)
      1.0
    when "FireEmergency"
      # Fires are occasional (houses have 6% chance per 15-45 seconds)
      0.1
    when "FireDispatch"
      # Fire dispatch matches fire emergencies
      0.1
    when "SilentAlarm"
      # Bank alarms are occasional (8% chance per 10-30 seconds)
      0.05
    when "PoliceDispatch"
      # Police dispatch matches alarms
      0.05
    when "EmergencyResolved"
      # Resolutions match emergencies
      0.15
    else
      0.0
    end
  end

  def parse_latency_percentiles(percentiles_string)
    # Parse: "p50=3.007,p99=26.111,p99.9=185.343"
    percentiles = {}
    percentiles_string.split(',').each do |pair|
      key, value = pair.split('=')
      case key
      when 'p50'
        percentiles[:p50] = value.to_f.round(1)
      when 'p99'
        percentiles[:p99] = value.to_f.round(1)
      when 'p99.9'
        percentiles[:p999] = value.to_f.round(1)
      end
    end
    percentiles
  end

  def calculate_avg_message_size(total_output, total_messages)
    return 0 if total_messages == 0
    total_output.to_f / total_messages
  end

  def calculate_io_ratio(input, output)
    return "N/A" if input == 0 && output == 0
    return "∞" if input == 0
    
    ratio = output.to_f / input
    "#{ratio.round(2)}:1"
  end
end

if __FILE__ == $0
  stats = RedisStats.new
  stats.start_monitoring
end