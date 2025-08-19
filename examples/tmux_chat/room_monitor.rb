#!/usr/bin/env ruby
# examples/tmux_chat/room_monitor.rb
#
# Room activity monitor for tmux chat visualization

require_relative 'shared_chat_system'

begin
  require 'io/console'
rescue LoadError
  # Console methods may not be available, handled gracefully
end

class RoomMonitor < BaseAgent
  def initialize(room_id)
    @room_id = room_id
    @message_count = 0
    @user_count = 0
    @last_activity = Time.now
    @participants = Set.new
    
    super(agent_id: "monitor-#{room_id}", name: "Room Monitor", agent_type: 'monitor')
    
    join_room(@room_id)
    log_display("🏠 Monitoring room: #{@room_id}")
    log_display("📊 Waiting for activity...")
    log_display("")
  end

  def setup_subscriptions
    ChatMessage.subscribe("RoomMonitor.handle_chat_message_#{@agent_id}")
    SystemNotificationMessage.subscribe("RoomMonitor.handle_system_notification_#{@agent_id}")
    
    @@monitors ||= {}
    @@monitors[@agent_id] = self
  end

  def run
    # Update display every few seconds
    begin
      while true
        sleep(2)
        update_stats_display
      end
    rescue Interrupt
      shutdown
    end
  end

  # Class method routing
  def self.method_missing(method_name, *args)
    if method_name.to_s.start_with?('handle_chat_message_')
      monitor_id = method_name.to_s.split('_', 4).last
      monitor = (@@monitors ||= {})[monitor_id]
      monitor&.handle_chat_message(*args)
    elsif method_name.to_s.start_with?('handle_system_notification_')
      monitor_id = method_name.to_s.split('_', 4).last
      monitor = (@@monitors ||= {})[monitor_id]
      monitor&.handle_system_notification(*args)
    else
      super
    end
  end

  def handle_chat_message(wrapper)
    message_header, message_payload = wrapper.split
    chat_data = JSON.parse(message_payload)
    
    return unless chat_data['room_id'] == @room_id
    return if chat_data['sender_id'] == @agent_id
    
    @message_count += 1
    @last_activity = Time.now
    @participants.add(chat_data['sender_name'])
    
    sender_emoji = case chat_data['message_type']
                   when 'bot' then '🤖'
                   when 'system' then '🔔'
                   else '👤'
                   end
    
    # Show the message with metadata
    timestamp = Time.now.strftime("%H:%M:%S")
    log_display("#{sender_emoji} [#{timestamp}] #{chat_data['sender_name']}: #{chat_data['content']}")
    
    # Check for commands
    if chat_data['content'].start_with?('/')
      log_display("⚡ Command detected: #{chat_data['content']}")
    end
    
    # Check for mentions
    if chat_data['mentions'] && !chat_data['mentions'].empty?
      log_display("🏷️  Mentions: #{chat_data['mentions'].join(', ')}")
    end
  end

  def handle_system_notification(wrapper)
    message_header, message_payload = wrapper.split
    notif_data = JSON.parse(message_payload)
    
    return unless notif_data['room_id'] == @room_id
    
    case notif_data['notification_type']
    when 'user_joined'
      @user_count += 1
      log_display("📥 #{notif_data['content']}")
    when 'user_left'
      @user_count = [@user_count - 1, 0].max
      log_display("📤 #{notif_data['content']}")
    else
      log_display("🔔 #{notif_data['content']}")
    end
    
    @last_activity = Time.now
  end

  private

  def update_stats_display
    # Move cursor to update stats
    time_since_activity = Time.now - @last_activity
    activity_status = if time_since_activity < 10
                       "🟢 Active"
                     elsif time_since_activity < 60
                       "🟡 Quiet (#{time_since_activity.to_i}s ago)"
                     else
                       "🔴 Inactive (#{(time_since_activity / 60).to_i}m ago)"
                     end
    
    # Update the header area with stats
    print "\033[2;2H"  # Move to line 2
    room_info = " ROOM: #{@room_id} | #{activity_status} "
    print room_info.center(50)
    
    print "\033[4;2H"  # Move to line 4  
    stats_info = " Messages: #{@message_count} | Participants: #{@participants.size} "
    print stats_info.center(50)
    
    # Move cursor back to bottom (default to 40 lines if console unavailable)
    max_lines = begin
      IO.console&.winsize&.first || 40
    rescue
      40
    end
    print "\033[#{max_lines};1H"
  end
end

# Main execution
if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: #{$0} <room_id>"
    puts "Example: #{$0} general"
    exit 1
  end
  
  room_id = ARGV[0]
  monitor = RoomMonitor.new(room_id)
  monitor.run
end