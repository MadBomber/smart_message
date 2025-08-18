#!/usr/bin/env ruby
# examples/tmux_chat/shared_chat_system.rb
#
# Shared messaging system for the tmux chat visualization
# This provides the core message types and file-based transport for inter-pane communication

require_relative '../../lib/smart_message'
require 'fileutils'

# Create shared message queues directory
SHARED_DIR = '/tmp/smart_message_chat'
FileUtils.mkdir_p(SHARED_DIR)

# File-based transport for tmux communication
class FileTransport < SmartMessage::Transport::Base
  def default_options
    {
      queue_dir: SHARED_DIR,
      poll_interval: 0.1
    }
  end

  def configure
    @queue_dir = @options[:queue_dir]
    @poll_interval = @options[:poll_interval]
    @running = false
    @subscriber_thread = nil
    
    FileUtils.mkdir_p(@queue_dir)
  end

  def publish(message_header, message_payload)
    message_data = {
      header: message_header.to_h,
      payload: message_payload,
      timestamp: Time.now.to_f
    }
    
    # Write to room-specific queue file
    room_id = extract_room_id(message_payload)
    queue_file = File.join(@queue_dir, "#{room_id}.queue")
    
    File.open(queue_file, 'a') do |f|
      f.puts(JSON.generate(message_data))
      f.flush
    end
  end

  def start_subscriber
    return if @running
    
    @running = true
    @subscriber_thread = Thread.new do
      processed_positions = {}
      
      while @running
        Dir.glob(File.join(@queue_dir, "*.queue")).each do |queue_file|
          room_id = File.basename(queue_file, '.queue')
          
          if File.exist?(queue_file)
            lines = File.readlines(queue_file)
            start_pos = processed_positions[room_id] || 0
            
            lines[start_pos..-1].each do |line|
              begin
                message_data = JSON.parse(line.strip)
                header = SmartMessage::Header.new(message_data['header'])
                receive(header, message_data['payload'])
              rescue JSON::ParserError
                # Skip malformed lines
              end
            end
            
            processed_positions[room_id] = lines.length
          end
        end
        
        sleep(@poll_interval)
      end
    end
  end

  def stop_subscriber
    @running = false
    @subscriber_thread&.join
  end

  private

  def extract_room_id(payload)
    begin
      data = JSON.parse(payload)
      data['room_id'] || 'global'
    rescue
      'global'
    end
  end
end

# Register the file transport
SmartMessage::Transport.register(:file, FileTransport)

# Define the Chat Message
class ChatMessage < SmartMessage::Base
  property :message_id
  property :room_id
  property :sender_id
  property :sender_name
  property :content
  property :message_type  # 'user', 'bot', 'system'
  property :timestamp
  property :mentions
  property :metadata

  config do
    transport SmartMessage::Transport.create(:file)
    serializer SmartMessage::Serializer::JSON.new
  end

  def self.process(message_header, message_payload)
    # Default processing - agents will override this
  end
end

# Define Bot Command Message
class BotCommandMessage < SmartMessage::Base
  property :command_id
  property :room_id
  property :user_id
  property :user_name
  property :command
  property :parameters
  property :timestamp

  config do
    transport SmartMessage::Transport.create(:file)
    serializer SmartMessage::Serializer::JSON.new
  end

  def self.process(message_header, message_payload)
    # Default processing - bots will override this
  end
end

# Define System Notification Message
class SystemNotificationMessage < SmartMessage::Base
  property :notification_id
  property :room_id
  property :notification_type
  property :content
  property :timestamp
  property :metadata

  config do
    transport SmartMessage::Transport.create(:file)
    serializer SmartMessage::Serializer::JSON.new
  end

  def self.process(message_header, message_payload)
    # Default processing
  end
end

# Base Agent class with display utilities
class BaseAgent
  attr_reader :agent_id, :name, :active_rooms

  def initialize(agent_id:, name:, agent_type: 'agent')
    @agent_id = agent_id
    @name = name
    @agent_type = agent_type
    @active_rooms = []
    @display_buffer = []
    @transport = SmartMessage::Transport.create(:file)
    
    setup_display
    setup_subscriptions
    start_message_processing
  end

  def join_room(room_id)
    return if @active_rooms.include?(room_id)
    
    @active_rooms << room_id
    log_display("📥 Joined room: #{room_id}")
    
    send_system_notification(
      room_id: room_id,
      notification_type: 'user_joined',
      content: "#{@name} joined the room"
    )
  end

  def leave_room(room_id)
    return unless @active_rooms.include?(room_id)
    
    @active_rooms.delete(room_id)
    log_display("📤 Left room: #{room_id}")
    
    send_system_notification(
      room_id: room_id,
      notification_type: 'user_left',
      content: "#{@name} left the room"
    )
  end

  def send_message(room_id:, content:, message_type: 'user')
    return unless @active_rooms.include?(room_id)
    
    message = ChatMessage.new(
      message_id: generate_message_id,
      room_id: room_id,
      sender_id: @agent_id,
      sender_name: @name,
      content: content,
      message_type: message_type,
      timestamp: Time.now.iso8601,
      mentions: extract_mentions(content),
      metadata: { agent_type: @agent_type }
    )
    
    log_display("💬 [#{room_id}] #{@name}: #{content}")
    message.publish
  end

  def shutdown
    @active_rooms.dup.each { |room_id| leave_room(room_id) }
    @transport.stop_subscriber
    log_display("🔴 #{@name} shutdown")
  end

  protected

  def setup_display
    puts "\033[2J\033[H"  # Clear screen
    puts "┌─" + "─" * 50 + "┐"
    puts "│ #{@agent_type.upcase}: #{@name.center(44)} │"
    puts "├─" + "─" * 50 + "┤"
    puts "│ Rooms: #{@active_rooms.join(', ').ljust(42)} │"
    puts "├─" + "─" * 50 + "┤"
    puts "│ Messages:".ljust(51) + " │"
    puts "└─" + "─" * 50 + "┘"
    puts
  end

  def log_display(message)
    timestamp = Time.now.strftime("%H:%M:%S")
    puts "[#{timestamp}] #{message}"
  end

  def setup_subscriptions
    # Override in subclasses
  end

  def start_message_processing
    @transport.start_subscriber
  end

  def send_system_notification(room_id:, notification_type:, content:)
    notification = SystemNotificationMessage.new(
      notification_id: "NOTIF-#{Time.now.to_i}-#{rand(1000)}",
      room_id: room_id,
      notification_type: notification_type,
      content: content,
      timestamp: Time.now.iso8601,
      metadata: { triggered_by: @agent_id }
    )
    
    notification.publish
  end

  def generate_message_id
    "MSG-#{@agent_id}-#{Time.now.to_i}-#{rand(1000)}"
  end

  def extract_mentions(content)
    content.scan(/@(\w+)/).flatten
  end
end

# Cleanup utility
def cleanup_shared_queues
  FileUtils.rm_rf(SHARED_DIR) if Dir.exist?(SHARED_DIR)
end

# Signal handling for cleanup
trap('INT') do
  cleanup_shared_queues
  exit
end

trap('TERM') do
  cleanup_shared_queues
  exit
end