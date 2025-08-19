#!/usr/bin/env ruby
# examples/tmux_chat/human_agent.rb
#
# Human chat agent for tmux visualization

require_relative 'shared_chat_system'

begin
  require 'io/console'
rescue LoadError
  # Console methods may not be available, handled gracefully
end

class HumanChatAgent < BaseAgent
  def initialize(user_id:, name:)
    @message_counter = 0
    super(agent_id: user_id, name: name, agent_type: 'human')
    
    log_display("👤 Human agent #{@name} ready!")
    log_display("Commands: /join <room>, /leave <room>, /list, /quit")
    log_display("Type messages to send to current rooms")
    log_display("")
  end

  def setup_subscriptions
    # Subscribe to chat messages
    ChatMessage.subscribe("HumanChatAgent.handle_chat_message_#{@agent_id}")
    SystemNotificationMessage.subscribe("HumanChatAgent.handle_system_notification_#{@agent_id}")
    
    # Register this instance for method dispatch
    @@agents ||= {}
    @@agents[@agent_id] = self
  end

  def start_interactive_session
    while true
      begin
        print "> "
        input = STDIN.gets&.chomp
        break if input.nil?
        
        next if input.strip.empty?
        
        if input.start_with?('/')
          handle_command(input)
        else
          send_to_active_rooms(input)
        end
      rescue Interrupt
        break
      end
    end
    
    shutdown
  end

  # Class method routing for SmartMessage
  def self.method_missing(method_name, *args)
    if method_name.to_s.start_with?('handle_chat_message_')
      user_id = method_name.to_s.split('_').last
      agent = (@@agents ||= {})[user_id]
      agent&.handle_chat_message(*args)
    elsif method_name.to_s.start_with?('handle_system_notification_')
      user_id = method_name.to_s.split('_').last
      agent = (@@agents ||= {})[user_id]
      agent&.handle_system_notification(*args)
    else
      super
    end
  end

  def handle_chat_message(wrapper)
    message_header = wrapper._sm_header
    message_payload = wrapper._sm_payload
    chat_data = JSON.parse(message_payload)
    
    # Only process messages from rooms we're in and not our own messages
    return unless @active_rooms.include?(chat_data['room_id'])
    return if chat_data['sender_id'] == @agent_id
    
    sender_emoji = case chat_data['message_type']
                   when 'bot' then '🤖'
                   when 'system' then '🔔'
                   else '👤'
                   end
    
    log_display("#{sender_emoji} [#{chat_data['room_id']}] #{chat_data['sender_name']}: #{chat_data['content']}")
    
    # Auto-respond if mentioned
    if chat_data['mentions']&.include?(@name.downcase) || chat_data['content'].include?("@#{@name}")
      respond_to_mention(chat_data)
    end
  end

  def handle_system_notification(wrapper)
    message_header = wrapper._sm_header
    message_payload = wrapper._sm_payload
    notif_data = JSON.parse(message_payload)
    
    # Only process notifications from rooms we're in
    return unless @active_rooms.include?(notif_data['room_id'])
    
    log_display("🔔 [#{notif_data['room_id']}] #{notif_data['content']}")
  end

  private

  def handle_command(input)
    parts = input[1..-1].split(' ')
    command = parts[0]
    args = parts[1..-1]
    
    case command
    when 'join'
      if args.empty?
        log_display("❌ Usage: /join <room_id>")
      else
        join_room(args[0])
        update_display_header
      end
    when 'leave'
      if args.empty?
        log_display("❌ Usage: /leave <room_id>")
      else
        leave_room(args[0])
        update_display_header
      end
    when 'list'
      log_display("📋 Active rooms: #{@active_rooms.empty? ? 'none' : @active_rooms.join(', ')}")
    when 'quit', 'exit'
      log_display("👋 Goodbye!")
      exit(0)
    when 'help'
      log_display("📖 Commands:")
      log_display("   /join <room>  - Join a chat room")
      log_display("   /leave <room> - Leave a chat room") 
      log_display("   /list         - List active rooms")
      log_display("   /quit         - Exit the chat")
    else
      log_display("❌ Unknown command: /#{command}. Type /help for help.")
    end
  end

  def send_to_active_rooms(message)
    if @active_rooms.empty?
      log_display("❌ You're not in any rooms. Use /join <room> to join a room.")
      return
    end
    
    @active_rooms.each do |room_id|
      send_message(room_id: room_id, content: message)
    end
  end

  def respond_to_mention(chat_data)
    responses = [
      "Thanks for mentioning me!",
      "I'm here, what's up?", 
      "How can I help?",
      "Yes, I saw that!",
      "Interesting point!"
    ]
    
    # Delay response slightly to make it feel natural
    Thread.new do
      sleep(0.5 + rand)
      send_message(
        room_id: chat_data['room_id'],
        content: responses.sample
      )
    end
  end

  def update_display_header
    # Move cursor to update rooms line
    print "\033[4;9H"  # Move to line 4, column 9
    print "#{@active_rooms.join(', ').ljust(42)}"
    # Move cursor to bottom (default to 40 lines if console unavailable)
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
  if ARGV.length < 2
    puts "Usage: #{$0} <user_id> <name>"
    puts "Example: #{$0} alice Alice"
    exit 1
  end
  
  user_id = ARGV[0]
  name = ARGV[1]
  
  agent = HumanChatAgent.new(user_id: user_id, name: name)
  agent.start_interactive_session
end