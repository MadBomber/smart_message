#!/usr/bin/env ruby
# examples/03_many_to_many_chat.rb
#
# Many-to-Many Messaging Example: Distributed Chat System
#
# This example demonstrates many-to-many messaging where multiple chat agents
# can send messages to multiple chat rooms, and other agents receive and respond
# to messages based on their interests and capabilities.

require_relative '../../lib/smart_message'

puts "=== SmartMessage Example: Many-to-Many Distributed Chat ==="
puts

# Define the Chat Message
class ChatMessage < SmartMessage::Base
  description "Represents chat messages exchanged between users in chat rooms"
  
  property :message_id, 
    description: "Unique identifier for this chat message"
  property :room_id, 
    description: "Identifier of the chat room where message was sent"
  property :sender_id, 
    description: "Unique identifier of the user or bot sending the message"
  property :sender_name, 
    description: "Display name of the message sender"
  property :content, 
    description: "The actual text content of the chat message"
  property :message_type, 
    description: "Type of message: 'user', 'bot', or 'system'"
  property :timestamp, 
    description: "ISO8601 timestamp when message was sent"
  property :mentions, 
    description: "Array of user IDs mentioned in the message (@username)"
  property :metadata, 
    description: "Additional message data (reactions, edit history, etc.)"

  config do
    transport SmartMessage::Transport::MemoryTransport.new
  end

  def process(message)
    message_header, message_payload = message
    chat_data = JSON.parse(message_payload)
    puts "💬 Chat message in #{chat_data['room_id']}: #{chat_data['content']}"
  end
end

# Define Bot Command Message
class BotCommandMessage < SmartMessage::Base
  description "Represents commands sent to chat bots for processing"
  
  property :command_id, 
    description: "Unique identifier for this bot command"
  property :room_id, 
    description: "Chat room where the command was issued"
  property :user_id, 
    description: "User who issued the bot command"
  property :command, 
    description: "The bot command name (e.g., 'weather', 'help', 'joke')"
  property :parameters, 
    description: "Array of parameters passed to the bot command"
  property :timestamp, 
    description: "ISO8601 timestamp when command was issued"

  config do
    transport SmartMessage::Transport::MemoryTransport.new
  end

  def process(message)
    message_header, message_payload = message
    command_data = JSON.parse(message_payload)
    puts "🤖 Bot command: #{command_data['command']} in #{command_data['room_id']}"
  end
end

# Define System Notification Message
class SystemNotificationMessage < SmartMessage::Base
  description "System-generated notifications about chat room events and status changes"
  
  property :notification_id, 
    description: "Unique identifier for this system notification"
  property :room_id, 
    description: "Chat room affected by this notification"
  property :notification_type, 
    description: "Type of notification: 'user_joined', 'user_left', 'room_created', etc."
  property :content, 
    description: "Human-readable description of the system event"
  property :timestamp, 
    description: "ISO8601 timestamp when the system event occurred"
  property :metadata, 
    description: "Additional system event data and context"

  config do
    transport SmartMessage::Transport::MemoryTransport.new
  end

  def process(message)
    message_header, message_payload = message
    notif_data = JSON.parse(message_payload)
    puts "🔔 System: #{notif_data['content']} in #{notif_data['room_id']}"
  end
end

# Human Chat Agent
class HumanChatAgent
  attr_reader :user_id, :name, :active_rooms

  def initialize(user_id:, name:)
    @user_id = user_id
    @name = name
    @active_rooms = []
    @message_counter = 0

    puts "👤 #{@name} (#{@user_id}): Joining chat system..."
    
    # Subscribe to all message types this agent cares about
    ChatMessage.subscribe("HumanChatAgent.handle_chat_message_#{@user_id}")
    SystemNotificationMessage.subscribe("HumanChatAgent.handle_system_notification_#{@user_id}")
  end

  def join_room(room_id)
    return if @active_rooms.include?(room_id)
    
    @active_rooms << room_id
    puts "👤 #{@name}: Joining room #{room_id}"
    
    # Send system notification
    send_system_notification(
      room_id: room_id,
      notification_type: 'user_joined',
      content: "#{@name} joined the room"
    )
  end

  def leave_room(room_id)
    return unless @active_rooms.include?(room_id)
    
    @active_rooms.delete(room_id)
    puts "👤 #{@name}: Leaving room #{room_id}"
    
    send_system_notification(
      room_id: room_id,
      notification_type: 'user_left',
      content: "#{@name} left the room"
    )
  end

  def send_message(room_id:, content:, mentions: [])
    return unless @active_rooms.include?(room_id)
    
    puts "👤 #{@name}: Sending message to #{room_id}: '#{content}'"
    
    # Check if this is a bot command
    if content.start_with?('/')
      send_bot_command(room_id, content)
    else
      message = ChatMessage.new(
        message_id: generate_message_id,
        room_id: room_id,
        sender_id: @user_id,
        sender_name: @name,
        content: content,
        message_type: 'user',
        timestamp: Time.now.iso8601,
        mentions: mentions,
        metadata: { client: 'human_agent' },
        from: @user_id
      )
      
      message.publish
    end
  end

  # Class method for message handling (required by SmartMessage)
  def self.method_missing(method_name, *args)
    if method_name.to_s.start_with?('handle_chat_message_')
      user_id = method_name.to_s.split('_').last
      agent = @@agents[user_id]
      agent&.handle_chat_message(*args)
    elsif method_name.to_s.start_with?('handle_system_notification_')
      user_id = method_name.to_s.split('_').last
      agent = @@agents[user_id]
      agent&.handle_system_notification(*args)
    else
      super
    end
  end

  def self.register_agent(agent)
    @@agents ||= {}
    @@agents[agent.user_id] = agent
  end

  def handle_message(message)
    message_header, message_payload = message
    chat_data = JSON.parse(message_payload)
    
    # Only process messages from rooms we're in and not our own messages
    return unless @active_rooms.include?(chat_data['room_id'])
    return if chat_data['sender_id'] == @user_id
    
    puts "👤 #{@name}: Received message in #{chat_data['room_id']}"
    
    # Respond if mentioned
    if chat_data['mentions']&.include?(@user_id)
      respond_to_mention(chat_data)
    end
  end

  def handle_system_notification(message)
    message_header, message_payload = message
    notif_data = JSON.parse(message_payload)
    
    # Only process notifications from rooms we're in
    return unless @active_rooms.include?(notif_data['room_id'])
    
    puts "👤 #{@name}: Received system notification in #{notif_data['room_id']}"
  end

  private

  def send_bot_command(room_id, content)
    command_parts = content[1..-1].split(' ')
    command = command_parts.first
    parameters = command_parts[1..-1]
    
    bot_command = BotCommandMessage.new(
      command_id: "CMD-#{Time.now.to_i}-#{rand(1000)}",
      room_id: room_id,
      user_id: @user_id,
      command: command,
      parameters: parameters,
      timestamp: Time.now.iso8601,
      from: @user_id
    )
    
    bot_command.publish
  end

  def respond_to_mention(chat_data)
    # Simulate thinking time
    sleep(0.2)
    
    responses = [
      "Thanks for mentioning me!",
      "I'm here, what's up?",
      "How can I help?",
      "Yes, I saw that!",
      "Interesting point!"
    ]
    
    send_message(
      room_id: chat_data['room_id'],
      content: responses.sample
    )
  end

  def send_system_notification(room_id:, notification_type:, content:)
    notification = SystemNotificationMessage.new(
      notification_id: "NOTIF-#{Time.now.to_i}-#{rand(1000)}",
      room_id: room_id,
      notification_type: notification_type,
      content: content,
      timestamp: Time.now.iso8601,
      metadata: { triggered_by: @user_id },
      from: @user_id
    )
    
    notification.publish
  end

  def generate_message_id
    @message_counter += 1
    "MSG-#{@user_id}-#{@message_counter}"
  end
end

# Bot Agent - Responds to commands and provides services
class BotAgent
  def initialize(bot_id:, name:, capabilities: [])
    @bot_id = bot_id
    @name = name
    @capabilities = capabilities
    @active_rooms = []

    puts "🤖 #{@name} (#{@bot_id}): Starting bot with capabilities: #{@capabilities.join(', ')}"
    
    # Subscribe to bot commands and chat messages
    BotCommandMessage.subscribe('BotAgent.handle_bot_command')
    ChatMessage.subscribe('BotAgent.handle_chat_message')
  end

  def join_room(room_id)
    return if @active_rooms.include?(room_id)
    
    @active_rooms << room_id
    puts "🤖 #{@name}: Joining room #{room_id}"
    
    # Announce capabilities
    send_chat_message(
      room_id: room_id,
      content: "🤖 Hello! I'm #{@name}. Available commands: #{@capabilities.map { |c| "/#{c}" }.join(', ')}"
    )
  end

  def handle_command(message)
    message_header, message_payload = message
    command_data = JSON.parse(message_payload)
    @@bots ||= []
    
    # Find bot that can handle this command and is in the room
    capable_bot = @@bots.find do |bot|
      bot.can_handle_command?(command_data['command']) && 
      bot.in_room?(command_data['room_id'])
    end
    
    capable_bot&.process_command(command_data)
  end

  def handle_message(message)
    message_header, message_payload = message
    chat_data = JSON.parse(message_payload)
    @@bots ||= []
    
    # Let all bots in the room process the message
    @@bots.each do |bot|
      bot.process_chat_message(chat_data) if bot.in_room?(chat_data['room_id'])
    end
  end

  def self.register_bot(bot)
    @@bots ||= []
    @@bots << bot
  end

  def can_handle_command?(command)
    @capabilities.include?(command)
  end

  def in_room?(room_id)
    @active_rooms.include?(room_id)
  end

  def process_command(command_data)
    puts "🤖 #{@name}: Processing command /#{command_data['command']}"
    
    case command_data['command']
    when 'weather'
      handle_weather_command(command_data)
    when 'joke'
      handle_joke_command(command_data)
    when 'help'
      handle_help_command(command_data)
    when 'stats'
      handle_stats_command(command_data)
    else
      send_chat_message(
        room_id: command_data['room_id'],
        content: "Sorry, I don't know how to handle /#{command_data['command']}"
      )
    end
  end

  def process_chat_message(chat_data)
    # Don't respond to other bots to avoid infinite loops
    return if chat_data['message_type'] == 'bot'
    return if chat_data['sender_id'] == @bot_id  # Don't respond to our own messages
    
    # Bot can respond to certain keywords or patterns from human users only
    content = chat_data['content'].downcase
    
    if content.include?('hello') || content.include?('hi')
      send_chat_message(
        room_id: chat_data['room_id'],
        content: "Hello #{chat_data['sender_name']}! 👋"
      )
    elsif content.include?('help') && !content.start_with?('/')
      send_chat_message(
        room_id: chat_data['room_id'],
        content: "Type /help to see available commands!"
      )
    end
  end

  private

  def handle_weather_command(command_data)
    location = command_data['parameters'].first || 'your location'
    weather_responses = [
      "☀️ It's sunny in #{location}!",
      "🌧️ Looks like rain in #{location}",
      "❄️ Snow expected in #{location}",
      "⛅ Partly cloudy in #{location}"
    ]
    
    send_chat_message(
      room_id: command_data['room_id'],
      content: weather_responses.sample
    )
  end

  def handle_joke_command(command_data)
    jokes = [
      "Why don't scientists trust atoms? Because they make up everything!",
      "Why did the scarecrow win an award? He was outstanding in his field!",
      "What do you call a fake noodle? An impasta!",
      "Why don't eggs tell jokes? They'd crack each other up!"
    ]
    
    send_chat_message(
      room_id: command_data['room_id'],
      content: "😄 #{jokes.sample}"
    )
  end

  def handle_help_command(command_data)
    help_text = @capabilities.map { |cmd| "/#{cmd} - #{get_command_description(cmd)}" }.join("\n")
    
    send_chat_message(
      room_id: command_data['room_id'],
      content: "🤖 Available commands:\n#{help_text}"
    )
  end

  def handle_stats_command(command_data)
    send_chat_message(
      room_id: command_data['room_id'],
      content: "📊 Bot Stats: Active in #{@active_rooms.length} rooms, #{@capabilities.length} capabilities"
    )
  end

  def get_command_description(command)
    descriptions = {
      'weather' => 'Get weather information',
      'joke' => 'Tell a random joke',
      'help' => 'Show this help message',
      'stats' => 'Show bot statistics'
    }
    
    descriptions[command] || 'No description available'
  end

  def send_chat_message(room_id:, content:)
    message = ChatMessage.new(
      message_id: "BOT-MSG-#{Time.now.to_i}-#{rand(1000)}",
      room_id: room_id,
      sender_id: @bot_id,
      sender_name: @name,
      content: content,
      message_type: 'bot',
      timestamp: Time.now.iso8601,
      mentions: [],
      metadata: { bot_type: 'service_bot' },
      from: @bot_id
    )
    
    message.publish
  end
end

# Room Manager - Manages chat rooms and routing
class RoomManager
  def initialize
    puts "🏢 RoomManager: Starting up..."
    @rooms = {}
    
    # Subscribe to system notifications to track room membership
    SystemNotificationMessage.subscribe('RoomManager.handle_system_notification')
  end

  def create_room(room_id:, name:, description: '')
    return if @rooms.key?(room_id)
    
    @rooms[room_id] = {
      name: name,
      description: description,
      created_at: Time.now,
      members: []
    }
    
    puts "🏢 RoomManager: Created room #{room_id} (#{name})"
    
    # Send system notification
    notification = SystemNotificationMessage.new(
      notification_id: "ROOM-#{Time.now.to_i}",
      room_id: room_id,
      notification_type: 'room_created',
      content: "Room '#{name}' was created",
      timestamp: Time.now.iso8601,
      metadata: { description: description },
      from: 'RoomManager'
    )
    
    notification.publish
  end

  def handle_system_notification(message)
    message_header, message_payload = message
    @@instance ||= new
    @@instance.process_system_notification(message_header, message_payload)
  end

  def process_system_notification(message_header, message_payload)
    notif_data = JSON.parse(message_payload)
    room_id = notif_data['room_id']
    
    return unless @rooms.key?(room_id)
    
    case notif_data['notification_type']
    when 'user_joined'
      # Could track membership if needed
      puts "🏢 RoomManager: Noted user joined #{room_id}"
    when 'user_left'
      puts "🏢 RoomManager: Noted user left #{room_id}"
    end
  end

  def list_rooms
    @rooms
  end
end

# Demo Runner
class DistributedChatDemo
  def run
    puts "🚀 Starting Distributed Chat Demo\n"
    
    # Start room manager
    room_manager = RoomManager.new
    
    # Create some chat rooms
    room_manager.create_room(room_id: 'general', name: 'General Chat', description: 'Main discussion room')
    room_manager.create_room(room_id: 'tech', name: 'Tech Talk', description: 'Technology discussions')
    room_manager.create_room(room_id: 'random', name: 'Random', description: 'Off-topic conversations')
    
    sleep(0.5)
    
    # Create human agents
    alice = HumanChatAgent.new(user_id: 'user-001', name: 'Alice')
    bob = HumanChatAgent.new(user_id: 'user-002', name: 'Bob')
    carol = HumanChatAgent.new(user_id: 'user-003', name: 'Carol')
    
    # Register agents for message routing
    HumanChatAgent.register_agent(alice)
    HumanChatAgent.register_agent(bob)
    HumanChatAgent.register_agent(carol)
    
    # Create bot agents
    helper_bot = BotAgent.new(
      bot_id: 'bot-001', 
      name: 'HelperBot', 
      capabilities: ['help', 'stats']
    )
    
    fun_bot = BotAgent.new(
      bot_id: 'bot-002',
      name: 'FunBot',
      capabilities: ['joke', 'weather']
    )
    
    # Register bots
    BotAgent.register_bot(helper_bot)
    BotAgent.register_bot(fun_bot)
    
    sleep(0.5)
    
    puts "\n" + "="*80
    puts "Chat Simulation Starting"
    puts "="*80
    
    # Users join rooms
    alice.join_room('general')
    alice.join_room('tech')
    sleep(0.3)
    
    bob.join_room('general')
    bob.join_room('random')
    sleep(0.3)
    
    carol.join_room('tech')
    carol.join_room('random')
    sleep(0.3)
    
    # Bots join rooms
    helper_bot.join_room('general')
    helper_bot.join_room('tech')
    sleep(0.3)
    
    fun_bot.join_room('general')
    fun_bot.join_room('random')
    sleep(0.5)
    
    # Simulate conversation
    puts "\n--- Conversation in General ---"
    alice.send_message(room_id: 'general', content: 'Hello everyone!')
    sleep(0.5)
    
    bob.send_message(room_id: 'general', content: 'Hi Alice! How are you?')
    sleep(0.5)
    
    alice.send_message(room_id: 'general', content: '/help')
    sleep(0.8)
    
    bob.send_message(room_id: 'general', content: '/joke')
    sleep(0.8)
    
    puts "\n--- Conversation in Tech ---"
    alice.send_message(room_id: 'tech', content: 'Anyone working on Ruby today?')
    sleep(0.5)
    
    carol.send_message(room_id: 'tech', content: 'Yes! Working on messaging systems')
    sleep(0.5)
    
    alice.send_message(room_id: 'tech', content: 'Cool! @user-003 what kind of messaging?', mentions: ['user-003'])
    sleep(0.8)
    
    puts "\n--- Conversation in Random ---"
    bob.send_message(room_id: 'random', content: '/weather New York')
    sleep(0.8)
    
    carol.send_message(room_id: 'random', content: 'Hello fun bot!')
    sleep(0.5)
    
    # Some users leave
    puts "\n--- Users Leaving ---"
    alice.leave_room('tech')
    sleep(0.3)
    
    bob.leave_room('random')
    sleep(0.5)
    
    puts "\n✨ Demo completed!"
    puts "\nThis example demonstrated:"
    puts "• Many-to-many messaging between multiple agents"
    puts "• Different types of agents (humans, bots) in the same system"
    puts "• Room-based message routing and filtering"
    puts "• Multiple message types (chat, commands, notifications)"
    puts "• Dynamic subscription and unsubscription"
    puts "• Event-driven responses and interactions"
    puts "• Service discovery and capability advertisement"
    
    puts "\n🛑 Shutting down demo..."
    sleep(1) # Give any pending messages time to process
  end
end

# Run the demo if this file is executed directly
if __FILE__ == $0
  demo = DistributedChatDemo.new
  demo.run
end