#!/usr/bin/env ruby
# examples/10_message_deduplication.rb

require_relative '../lib/smart_message'

# Example demonstrating message deduplication with DDQ (Deduplication Queue)

# Message class with deduplication enabled
class OrderMessage < SmartMessage::Base
  version 1
  property :order_id, required: true
  property :amount, required: true
  
  from "order-service"
  
  # Configure deduplication
  ddq_size 100            # Keep track of last 100 message UUIDs
  ddq_storage :memory     # Use memory storage (could be :redis)
  enable_deduplication!   # Enable deduplication for this message class
  
  def self.process(message)
    puts "✅ Processing order: #{message.order_id} for $#{message.amount}"
    @@processed_orders ||= []
    @@processed_orders << message.order_id
  end
  
  def self.processed_orders
    @@processed_orders || []
  end
  
  def self.clear_processed
    @@processed_orders = []
  end
end

# Regular message class without deduplication
class NotificationMessage < SmartMessage::Base
  version 1
  property :message, required: true
  property :recipient, required: true
  
  from "notification-service"
  
  def self.process(message)
    puts "📧 Sending: '#{message.message}' to #{message.recipient}"
    @@sent_notifications ||= []
    @@sent_notifications << { message: message.message, recipient: message.recipient }
  end
  
  def self.sent_notifications
    @@sent_notifications || []
  end
  
  def self.clear_processed
    @@sent_notifications = []
  end
end

def demonstrate_deduplication
  puts "=== SmartMessage Deduplication Demo ==="
  puts
  
  # Setup transport and subscriptions
  transport = SmartMessage::Transport::MemoryTransport.new
  
  OrderMessage.transport(transport)
  OrderMessage.serializer(SmartMessage::Serializer::Json.new)
  OrderMessage.subscribe('OrderMessage.process')
  
  NotificationMessage.transport(transport)
  NotificationMessage.serializer(SmartMessage::Serializer::Json.new)
  NotificationMessage.subscribe('NotificationMessage.process')
  
  # Clear any previous state
  OrderMessage.clear_processed
  NotificationMessage.clear_processed
  OrderMessage.clear_ddq!
  
  puts "📊 DDQ Configuration:"
  config = OrderMessage.ddq_config
  puts "  - Enabled: #{config[:enabled]}"
  puts "  - Size: #{config[:size]}"
  puts "  - Storage: #{config[:storage]}"
  puts
  
  # Create a specific UUID for testing duplicates
  uuid = SecureRandom.uuid
  puts "🔍 Testing with UUID: #{uuid}"
  puts
  
  # Test 1: OrderMessage with deduplication
  puts "--- Test 1: OrderMessage (with deduplication) ---"
  
  # Create header with specific UUID
  header = SmartMessage::Header.new(
    uuid: uuid,
    message_class: "OrderMessage",
    published_at: Time.now,
    publisher_pid: Process.pid,
    version: 1,
    from: "order-service"
  )
  
  # First message
  order1 = OrderMessage.new(
    _sm_header: header,
    _sm_payload: { order_id: "ORD-001", amount: 99.99 }
  )
  
  puts "Publishing first order message..."
  order1.publish
  sleep 0.1  # Allow processing
  
  # Second message with SAME UUID (should be deduplicated)
  order2 = OrderMessage.new(
    _sm_header: header,
    _sm_payload: { order_id: "ORD-002", amount: 149.99 }
  )
  
  puts "Publishing duplicate order message (same UUID)..."
  order2.publish
  sleep 0.1  # Allow processing
  
  puts "📈 Results:"
  puts "  - Processed orders: #{OrderMessage.processed_orders.length}"
  puts "  - Orders: #{OrderMessage.processed_orders}"
  puts
  
  # Test 2: NotificationMessage without deduplication
  puts "--- Test 2: NotificationMessage (no deduplication) ---"
  
  # Create header with same UUID
  notification_header = SmartMessage::Header.new(
    uuid: uuid,  # Same UUID as orders!
    message_class: "NotificationMessage",
    published_at: Time.now,
    publisher_pid: Process.pid,
    version: 1,
    from: "notification-service"
  )
  
  # First notification
  notif1 = NotificationMessage.new(
    _sm_header: notification_header,
    _sm_payload: { message: "Order confirmed", recipient: "customer@example.com" }
  )
  
  puts "Publishing first notification..."
  notif1.publish
  sleep 0.1
  
  # Second notification with same UUID (should NOT be deduplicated)
  notif2 = NotificationMessage.new(
    _sm_header: notification_header,
    _sm_payload: { message: "Order shipped", recipient: "customer@example.com" }
  )
  
  puts "Publishing duplicate notification (same UUID)..."
  notif2.publish
  sleep 0.1
  
  puts "📈 Results:"
  puts "  - Sent notifications: #{NotificationMessage.sent_notifications.length}"
  puts "  - Notifications: #{NotificationMessage.sent_notifications}"
  puts
  
  # Show DDQ statistics
  puts "📊 DDQ Statistics:"
  stats = OrderMessage.ddq_stats
  if stats[:enabled]
    puts "  - Current count: #{stats[:current_count]}"
    puts "  - Utilization: #{stats[:utilization]}%"
    puts "  - Storage type: #{stats[:storage_type]}"
  else
    puts "  - DDQ not enabled"
  end
end

def demonstrate_memory_efficiency
  puts
  puts "=== Memory Usage Demonstration ==="
  puts
  
  # Show memory usage for different DDQ sizes
  test_sizes = [10, 100, 1000]
  
  test_sizes.each do |size|
    memory_usage = size * 48  # Approximate bytes per UUID
    puts "DDQ size #{size}: ~#{memory_usage} bytes (~#{(memory_usage / 1024.0).round(1)} KB)"
  end
  
  puts
  puts "💡 Memory is very reasonable - even 1000 entries uses less than 50KB!"
end

if __FILE__ == $0
  demonstrate_deduplication
  demonstrate_memory_efficiency
  
  puts
  puts "✨ Key Benefits:"
  puts "  - O(1) duplicate detection"
  puts "  - Configurable queue size"
  puts "  - Memory or Redis storage"
  puts "  - Per-message-class configuration"
  puts "  - Automatic integration with dispatcher"
  puts
  puts "🚀 Ready for production multi-transport scenarios!"
end