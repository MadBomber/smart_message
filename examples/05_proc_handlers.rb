#!/usr/bin/env ruby
# examples/05_proc_handlers.rb
#
# Proc and Block Handler Example
#
# This example demonstrates the new proc and block handler functionality
# in SmartMessage, showing different ways to subscribe to messages beyond
# the traditional self.process method.

require_relative '../lib/smart_message'

puts "=== SmartMessage Proc and Block Handler Example ==="
puts

# Define a simple notification message
class NotificationMessage < SmartMessage::Base
  description "System notifications processed by different types of handlers"
  
  property :type, 
    description: "Notification type: 'info', 'warning', 'error'"
  property :title, 
    description: "Short title or subject of the notification"
  property :message, 
    description: "Detailed notification message content"
  property :user_id, 
    description: "Target user ID for the notification (optional)"
  property :timestamp, 
    description: "ISO8601 timestamp when notification was created"

  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end

  # Default handler
  def self.process(message_header, message_payload)
    data = JSON.parse(message_payload)
    icon = case data['type']
           when 'info' then 'ℹ️'
           when 'warning' then '⚠️'
           when 'error' then '🚨'
           else '📢'
           end
    puts "#{icon} [DEFAULT] #{data['title']}: #{data['message']}"
  end
end

puts "🚀 Setting up different types of message handlers"
puts

# 1. Default handler (traditional way)
puts "1️⃣ Default handler subscription:"
default_id = NotificationMessage.subscribe
puts "   Subscribed with ID: #{default_id}"
puts

# 2. Block handler
puts "2️⃣ Block handler subscription:"
block_id = NotificationMessage.subscribe do |header, payload|
  data = JSON.parse(payload)
  if data['type'] == 'error'
    puts "🔥 [BLOCK] Critical error logged: #{data['title']}"
    # Could send to error tracking service here
  end
end
puts "   Subscribed with ID: #{block_id}"
puts

# 3. Proc handler
puts "3️⃣ Proc handler subscription:"
audit_logger = proc do |header, payload|
  data = JSON.parse(payload)
  timestamp = header.published_at.strftime('%Y-%m-%d %H:%M:%S')
  puts "📝 [AUDIT] #{timestamp} - User #{data['user_id']}: #{data['type'].upcase}"
end

proc_id = NotificationMessage.subscribe(audit_logger)
puts "   Subscribed with ID: #{proc_id}"
puts

# 4. Lambda handler
puts "4️⃣ Lambda handler subscription:"
warning_filter = lambda do |header, payload|
  data = JSON.parse(payload)
  if data['type'] == 'warning'
    puts "⚡ [LAMBDA] Warning for user #{data['user_id']}: #{data['message']}"
  end
end

lambda_id = NotificationMessage.subscribe(warning_filter)
puts "   Subscribed with ID: #{lambda_id}"
puts

# 5. Method handler (traditional, but shown for comparison)
puts "5️⃣ Method handler subscription:"
class NotificationService
  def self.handle_notifications(header, payload)
    data = JSON.parse(payload)
    puts "🏢 [SERVICE] Processing #{data['type']} notification for user #{data['user_id']}"
  end
end

method_id = NotificationMessage.subscribe("NotificationService.handle_notifications")
puts "   Subscribed with ID: #{method_id}"
puts

puts "=" * 60
puts "📡 Publishing test notifications (watch the different handlers respond!)"
puts "=" * 60
puts

# Test the handlers with different notification types
notifications = [
  {
    type: 'info',
    title: 'Welcome',
    message: 'Welcome to the system!',
    user_id: 'user123',
    timestamp: Time.now.iso8601
  },
  {
    type: 'warning',
    title: 'Low Disk Space',
    message: 'Your disk space is running low',
    user_id: 'user456',
    timestamp: Time.now.iso8601
  },
  {
    type: 'error',
    title: 'Database Connection Failed',
    message: 'Unable to connect to the database',
    user_id: 'system',
    timestamp: Time.now.iso8601
  }
]

notifications.each_with_index do |notification_data, index|
  puts "\n📤 Publishing notification #{index + 1}: #{notification_data[:title]}"

  notification = NotificationMessage.new(**notification_data)
  notification.publish

  # Give time for all handlers to process
  sleep(0.5)

  puts "   ✅ All handlers processed the #{notification_data[:type]} notification"
end

puts "\n" + "=" * 60
puts "🔧 Demonstrating handler management"
puts "=" * 60

# Show how to unsubscribe handlers
puts "\n🗑️  Unsubscribing the block handler..."
NotificationMessage.unsubscribe(block_id)
puts "   Block handler removed"

puts "\n📤 Publishing another error notification (block handler won't respond):"
error_notification = NotificationMessage.new(
  type: 'error',
  title: 'Another Error',
  message: 'This error won\'t trigger the block handler',
  user_id: 'test_user',
  timestamp: Time.now.iso8601
)

error_notification.publish
sleep(0.5)

puts "\n" + "=" * 60
puts "✨ Example completed!"
puts "=" * 60

puts "\nThis example demonstrated:"
puts "• ✅ Default self.process method (traditional)"
puts "• ✅ Block handlers with subscribe { |h,p| ... } (NEW!)"
puts "• ✅ Proc handlers with subscribe(proc { ... }) (NEW!)"
puts "• ✅ Lambda handlers with subscribe(lambda { ... }) (NEW!)"
puts "• ✅ Method handlers with subscribe('Class.method') (traditional)"
puts "• ✅ Handler unsubscription and management"
puts "\nEach handler type has its own use cases:"
puts "• 🎯 Default: Simple built-in processing"
puts "• 🔧 Blocks: Inline logic for specific subscriptions"
puts "• 🔄 Procs: Reusable handlers across message types"
puts "• ⚡ Lambdas: Strict argument checking and functional style"
puts "• 🏢 Methods: Organized, testable business logic"

puts "\n🎉 Choose the handler type that best fits your needs!"
