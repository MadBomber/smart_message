#!/usr/bin/env ruby
# examples/tmux_chat/bot_agent.rb
#
# Bot agent for tmux chat visualization

require_relative 'shared_chat_system'

class BotChatAgent < BaseAgent
  def initialize(bot_id:, name:, capabilities: [])
    @capabilities = capabilities
    @command_count = 0
    super(agent_id: bot_id, name: name, agent_type: 'bot')
    
    log_display("🤖 Bot #{@name} online!")
    log_display("🔧 Capabilities: #{@capabilities.join(', ')}")
    log_display("⚡ Listening for commands and messages...")
    log_display("")
  end

  def setup_subscriptions
    # Subscribe to bot commands and chat messages
    BotCommandMessage.subscribe("BotChatAgent.handle_bot_command_#{@agent_id}")
    ChatMessage.subscribe("BotChatAgent.handle_chat_message_#{@agent_id}")
    
    # Register this instance
    @@bots ||= {}
    @@bots[@agent_id] = self
  end

  def run
    # Start processing messages and wait
    begin
      while true
        sleep(1)
      end
    rescue Interrupt
      shutdown
    end
  end

  # Class method routing for SmartMessage
  def self.method_missing(method_name, *args)
    if method_name.to_s.start_with?('handle_bot_command_')
      bot_id = method_name.to_s.split('_').last
      bot = (@@bots ||= {})[bot_id]
      bot&.handle_bot_command(*args)
    elsif method_name.to_s.start_with?('handle_chat_message_')
      bot_id = method_name.to_s.split('_').last
      bot = (@@bots ||= {})[bot_id]
      bot&.handle_chat_message(*args)
    else
      super
    end
  end

  def handle_bot_command(message_header, message_payload)
    command_data = JSON.parse(message_payload)
    
    # Only handle commands in rooms we're in and commands we can handle
    return unless @active_rooms.include?(command_data['room_id'])
    return unless can_handle_command?(command_data['command'])
    
    @command_count += 1
    log_display("⚡ Processing command: /#{command_data['command']} (#{@command_count})")
    
    process_command(command_data)
  end

  def handle_chat_message(message_header, message_payload)
    chat_data = JSON.parse(message_payload)
    
    # Only process messages from rooms we're in and not our own messages
    return unless @active_rooms.include?(chat_data['room_id'])
    return if chat_data['sender_id'] == @agent_id
    
    # Don't respond to other bots to avoid infinite loops
    return if chat_data['message_type'] == 'bot'
    
    # Log the message
    log_display("👁️  [#{chat_data['room_id']}] #{chat_data['sender_name']}: #{chat_data['content']}")
    
    # Check if it's a bot command
    if chat_data['content'].start_with?('/')
      handle_inline_command(chat_data)
    else
      # Respond to certain keywords from human users only
      respond_to_keywords(chat_data)
    end
  end

  def can_handle_command?(command)
    @capabilities.include?(command)
  end

  private

  def handle_inline_command(chat_data)
    content = chat_data['content']
    command_parts = content[1..-1].split(' ')
    command = command_parts.first
    parameters = command_parts[1..-1]
    
    return unless can_handle_command?(command)
    
    # Create bot command message
    bot_command = BotCommandMessage.new(
      command_id: "CMD-#{@agent_id}-#{Time.now.to_i}-#{rand(1000)}",
      room_id: chat_data['room_id'],
      user_id: chat_data['sender_id'],
      user_name: chat_data['sender_name'],
      command: command,
      parameters: parameters,
      timestamp: Time.now.iso8601
    )
    
    bot_command.publish
  end

  def process_command(command_data)
    case command_data['command']
    when 'weather'
      handle_weather_command(command_data)
    when 'joke'
      handle_joke_command(command_data)
    when 'help'
      handle_help_command(command_data)
    when 'stats'
      handle_stats_command(command_data)
    when 'time'
      handle_time_command(command_data)
    when 'echo'
      handle_echo_command(command_data)
    else
      send_bot_response(
        room_id: command_data['room_id'],
        content: "🤷‍♂️ Sorry, I don't know how to handle /#{command_data['command']}"
      )
    end
  end

  def respond_to_keywords(chat_data)
    content = chat_data['content'].downcase
    
    if content.include?('hello') || content.include?('hi')
      send_bot_response(
        room_id: chat_data['room_id'],
        content: "Hello #{chat_data['sender_name']}! 👋"
      )
    elsif content.include?('help') && !content.start_with?('/')
      send_bot_response(
        room_id: chat_data['room_id'],
        content: "Type /help to see my commands! 🤖"
      )
    elsif content.include?('thank')
      send_bot_response(
        room_id: chat_data['room_id'], 
        content: "You're welcome! 😊"
      )
    end
  end

  def handle_weather_command(command_data)
    location = command_data['parameters'].first || 'your location'
    weather_responses = [
      "☀️ It's sunny and 72°F in #{location}!",
      "🌧️ Looks like rain and 65°F in #{location}",
      "❄️ Snow expected, 32°F in #{location}",
      "⛅ Partly cloudy, 68°F in #{location}",
      "🌪️ Tornado warning in #{location}! (Just kidding, it's nice)"
    ]
    
    # Simulate API delay
    Thread.new do
      sleep(0.5)
      send_bot_response(
        room_id: command_data['room_id'],
        content: weather_responses.sample
      )
    end
  end

  def handle_joke_command(command_data)
    jokes = [
      "Why don't scientists trust atoms? Because they make up everything! 😄",
      "Why did the scarecrow win an award? He was outstanding in his field! 🌾",
      "What do you call a fake noodle? An impasta! 🍝",
      "Why don't eggs tell jokes? They'd crack each other up! 🥚",
      "What do you call a sleeping bull? A bulldozer! 😴",
      "Why don't robots ever panic? They have enough bytes! 🤖"
    ]
    
    send_bot_response(
      room_id: command_data['room_id'],
      content: jokes.sample
    )
  end

  def handle_help_command(command_data)
    help_text = @capabilities.map do |cmd|
      "  /#{cmd} - #{get_command_description(cmd)}"
    end.join("\n")
    
    send_bot_response(
      room_id: command_data['room_id'],
      content: "🤖 #{@name} Commands:\n#{help_text}"
    )
  end

  def handle_stats_command(command_data)
    send_bot_response(
      room_id: command_data['room_id'],
      content: "📊 Bot Stats:\n" +
               "  • Active rooms: #{@active_rooms.length}\n" +
               "  • Commands processed: #{@command_count}\n" +
               "  • Capabilities: #{@capabilities.length}\n" +
               "  • Uptime: #{Time.now.strftime('%H:%M:%S')}"
    )
  end

  def handle_time_command(command_data)
    timezone = command_data['parameters'].first || 'local'
    current_time = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    
    send_bot_response(
      room_id: command_data['room_id'],
      content: "🕒 Current time (#{timezone}): #{current_time}"
    )
  end

  def handle_echo_command(command_data)
    message = command_data['parameters'].join(' ')
    if message.empty?
      message = "Echo! Echo! Echo! 📢"
    end
    
    send_bot_response(
      room_id: command_data['room_id'],
      content: "🔊 Echo: #{message}"
    )
  end

  def get_command_description(command)
    descriptions = {
      'weather' => 'Get weather information',
      'joke' => 'Tell a random joke',
      'help' => 'Show this help message',
      'stats' => 'Show bot statistics',
      'time' => 'Show current time',
      'echo' => 'Echo your message'
    }
    
    descriptions[command] || 'No description available'
  end

  def send_bot_response(room_id:, content:)
    send_message(room_id: room_id, content: content, message_type: 'bot')
    log_display("💬 Replied to [#{room_id}]: #{content}")
  end
end

# Main execution
if __FILE__ == $0
  if ARGV.length < 2
    puts "Usage: #{$0} <bot_id> <name> [capability1,capability2,...]"
    puts "Example: #{$0} helpbot HelpBot help,stats,time"
    exit 1
  end
  
  bot_id = ARGV[0]
  name = ARGV[1]
  capabilities = ARGV[2] ? ARGV[2].split(',') : ['help']
  
  bot = BotChatAgent.new(bot_id: bot_id, name: name, capabilities: capabilities)
  bot.run
end