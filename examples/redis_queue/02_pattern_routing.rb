#!/usr/bin/env ruby
# examples/redis_queue/02_pattern_routing.rb
# Advanced pattern-based routing with Redis Queue Transport

require_relative '../../lib/smart_message'
require 'async'

puts "🎯 Redis Queue Transport - Pattern Routing Demo"
puts "=" * 50

#==============================================================================
# Transport Configuration
#==============================================================================

# Create transport instance for pattern subscriptions
transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 2,  # Use database 2 for pattern examples
  queue_prefix: 'pattern_demo',
  exchange_name: 'smart_message',
  consumer_timeout: 1,  # 1 second timeout for demo responsiveness
  test_mode: false  # Enable consumer tasks
)

#==============================================================================
# Message Classes with Enhanced Headers
#==============================================================================

class ServiceMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 2,
    queue_prefix: 'pattern_demo',
    exchange_name: 'smart_message',
    test_mode: false
  }
  
  property :service_name, required: true
  property :action, required: true
  property :payload, default: {}
  property :request_id, default: -> { SecureRandom.uuid }
  
  def process
    puts "🔧 Service: #{service_name} | Action: #{action} | ID: #{request_id}"
  end
end

class NotificationMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379', 
    db: 2,
    queue_prefix: 'pattern_demo'
  }
  
  property :notification_type, required: true
  property :recipient, required: true
  property :message_text, required: true
  property :priority, default: 'normal'
  
  def process
    priority_icon = case priority
                   when 'urgent' then '🚨'
                   when 'high' then '❗'
                   when 'normal' then '📢'
                   when 'low' then '📝'
                   else '📢'
                   end
    
    puts "#{priority_icon} Notification [#{notification_type}] → #{recipient}: #{message_text}"
  end
end

class OrderMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 2,
    queue_prefix: 'pattern_demo',
    exchange_name: 'smart_message',
    test_mode: false
  }
  
  property :order_id, required: true
  property :customer_id, required: true
  property :amount, required: true
  property :status, default: 'pending'
  
  def process
    puts "🛒 Order #{order_id}: Customer #{customer_id} - $#{amount} [#{status}]"
  end
end

#==============================================================================
# Pattern Subscription Setup
#==============================================================================

Async do
  puts "\n🔗 Setting up pattern subscriptions:"

# 1. Subscribe to messages TO specific services
puts "1️⃣ Subscribing to messages directed TO 'payment_service'"
transport.subscribe_pattern("#.*.payment_service") do |message_class, message_data|
  data = JSON.parse(message_data)
  puts "💳 Payment Service received: #{message_class} - #{data['action'] || data['notification_type'] || data['order_id']}"
end

puts "2️⃣ Subscribing to messages directed TO 'notification_service'"  
transport.subscribe_pattern("#.*.notification_service") do |message_class, message_data|
  data = JSON.parse(message_data)
  puts "📧 Notification Service received: #{message_class} - #{data['message_text'] || data['action']}"
end

# 2. Subscribe to messages FROM specific services
puts "3️⃣ Subscribing to messages FROM 'api_gateway'"
transport.subscribe_pattern("#.api_gateway.*") do |message_class, message_data|
  data = JSON.parse(message_data)
  puts "🌐 From API Gateway: #{message_class} - #{data['action'] || data['order_id']}"
end

puts "4️⃣ Subscribing to messages FROM 'mobile_app'"
transport.subscribe_pattern("#.mobile_app.*") do |message_class, message_data|
  data = JSON.parse(message_data)
  puts "📱 From Mobile App: #{message_class} - #{data['action'] || data['order_id']}"
end

# 3. Subscribe to specific message types
puts "5️⃣ Subscribing to ALL order messages"
transport.subscribe_pattern("order.#.*.*") do |message_class, message_data|
  data = JSON.parse(message_data)
  puts "📋 Order Audit: #{data['order_id']} - $#{data['amount']} [#{data['status']}]"
end

puts "6️⃣ Subscribing to ALL notification messages"
transport.subscribe_pattern("notification.#.*.*") do |message_class, message_data|
  data = JSON.parse(message_data)
  puts "📊 Notification Log: #{data['notification_type']} → #{data['recipient']} [#{data['priority']}]"
end

# 4. Subscribe to urgent messages across all services
puts "7️⃣ Subscribing to urgent notifications from ANY service"
transport.subscribe_pattern("notification.#.*.#") do |message_class, message_data|
  data = JSON.parse(message_data)
  if data['priority'] == 'urgent'
    puts "🚨 URGENT ALERT: #{data['message_text']} → #{data['recipient']}"
  end
end

# 5. Subscribe to broadcast messages
puts "8️⃣ Subscribing to broadcast messages"
transport.subscribe_pattern("#.*.broadcast") do |message_class, message_data|
  data = JSON.parse(message_data)
  puts "📻 Broadcast: #{message_class} - #{data['message_text'] || data['action']}"
end

  # Wait for subscriptions to initialize
  sleep 1

  #============================================================================
  # Pattern Routing Demonstration
  #============================================================================

  puts "\n📤 Publishing messages with different routing patterns:"

  # Messages directed to payment service
  puts "\n🔸 Messages TO payment_service:"
ServiceMessage.new(
  service_name: 'payment_service',
  action: 'process_payment',
  payload: { amount: 99.99, card_token: 'tok_123' },
  _sm_header: {
    from: 'api_gateway',
    to: 'payment_service'
  }
).publish

OrderMessage.new(
  order_id: 'ORD-001',
  customer_id: 'CUST-123',
  amount: 99.99,
  status: 'payment_pending',
  _sm_header: {
    from: 'order_service',
    to: 'payment_service'
  }
).publish

  # Messages directed to notification service
  puts "\n🔸 Messages TO notification_service:"
NotificationMessage.new(
  notification_type: 'email',
  recipient: 'user@example.com',
  message_text: 'Your order has been confirmed',
  priority: 'normal',
  _sm_header: {
    from: 'order_service',
    to: 'notification_service'
  }
).publish

ServiceMessage.new(
  service_name: 'notification_service',
  action: 'send_sms',
  payload: { phone: '+1234567890', message: 'OTP: 123456' },
  _sm_header: {
    from: 'auth_service',
    to: 'notification_service'
  }
).publish

  # Messages FROM api_gateway
  puts "\n🔸 Messages FROM api_gateway:"
ServiceMessage.new(
  service_name: 'user_service',
  action: 'create_user',
  payload: { name: 'John Doe', email: 'john@example.com' },
  _sm_header: {
    from: 'api_gateway',
    to: 'user_service'
  }
).publish

OrderMessage.new(
  order_id: 'ORD-002',
  customer_id: 'CUST-456', 
  amount: 149.50,
  status: 'pending',
  _sm_header: {
    from: 'api_gateway',
    to: 'order_service'
  }
).publish

  # Messages FROM mobile_app
  puts "\n🔸 Messages FROM mobile_app:"
NotificationMessage.new(
  notification_type: 'push',
  recipient: 'device_token_123',
  message_text: 'New message from friend',
  priority: 'normal',
  _sm_header: {
    from: 'mobile_app',
    to: 'notification_service'
  }
).publish

OrderMessage.new(
  order_id: 'ORD-003',
  customer_id: 'CUST-789',
  amount: 24.99,
  status: 'cart_pending',
  _sm_header: {
    from: 'mobile_app',
    to: 'cart_service'
  }
).publish

  # Urgent notifications
  puts "\n🔸 Urgent notifications:"
NotificationMessage.new(
  notification_type: 'alert',
  recipient: 'admin@company.com',
  message_text: 'Server CPU usage above 95%',
  priority: 'urgent',
  _sm_header: {
    from: 'monitoring_service',
    to: 'admin_service'
  }
).publish

NotificationMessage.new(
  notification_type: 'security',
  recipient: 'security@company.com', 
  message_text: 'Suspicious login attempt detected',
  priority: 'urgent',
  _sm_header: {
    from: 'security_service',
    to: 'admin_service'
  }
).publish

  # Broadcast messages
  puts "\n🔸 Broadcast messages:"
NotificationMessage.new(
  notification_type: 'system',
  recipient: 'all_users',
  message_text: 'Scheduled maintenance in 1 hour',
  priority: 'high',
  _sm_header: {
    from: 'admin_service',
    to: 'broadcast'
  }
).publish

ServiceMessage.new(
  service_name: 'all_services',
  action: 'health_check',
  payload: { timestamp: Time.now.to_i },
  _sm_header: {
    from: 'monitoring_service',
    to: 'broadcast'
  }
).publish

  # Wait for all messages to be processed
  puts "\n⏳ Processing messages with pattern routing..."
  sleep 5

  #============================================================================
  # Advanced Pattern Examples
  #============================================================================

  puts "\n🎓 Advanced Pattern Examples:"

  # Complex multi-service workflow
  puts "\n🔸 Multi-service workflow:"
ServiceMessage.new(
  service_name: 'inventory_service',
  action: 'reserve_items',
  payload: { order_id: 'ORD-004', items: ['ITEM-001', 'ITEM-002'] },
  _sm_header: {
    from: 'order_service',
    to: 'inventory_service'
  }
).publish

ServiceMessage.new(
  service_name: 'shipping_service', 
  action: 'calculate_shipping',
  payload: { order_id: 'ORD-004', zip_code: '12345' },
  _sm_header: {
    from: 'order_service', 
    to: 'shipping_service'
  }
).publish

  # Environment-specific routing
  puts "\n🔸 Environment-specific routing:"
ServiceMessage.new(
  service_name: 'logging_service',
  action: 'log_event',
  payload: { event: 'user_login', user_id: 'user_123' },
  _sm_header: {
    from: 'auth_service',
    to: 'prod_logging_service'
  }
).publish

ServiceMessage.new(
  service_name: 'analytics_service',
  action: 'track_event', 
  payload: { event: 'page_view', page: '/dashboard' },
  _sm_header: {
    from: 'web_app',
    to: 'dev_analytics_service'
  }
).publish

  sleep 3

  #============================================================================
  # Pattern Statistics and Routing Table
  #============================================================================

  puts "\n📊 Pattern Routing Statistics:"

  # Show routing table
  routing_table = transport.routing_table
  puts "\nActive routing patterns:"
  routing_table.each do |pattern, queues|
    puts "  Pattern: '#{pattern}'"
    puts "    Queues: #{queues.join(', ')}"
  end

  # Show queue statistics
  stats = transport.queue_stats
  puts "\nQueue statistics:"
  stats.each do |queue_name, info|
    puts "  #{queue_name}:"
    puts "    Length: #{info[:length]} messages"
    puts "    Pattern: #{info[:pattern]}"
    puts "    Consumers: #{info[:consumers]}"
    puts ""
  end

  # Cleanup
  transport.disconnect
end

puts "\n🎯 Pattern routing demonstration completed!"
puts "\n💡 Patterns Demonstrated:"
puts "   ✓ TO-based routing: #.*.service_name"
puts "   ✓ FROM-based routing: #.sender.*"
puts "   ✓ Type-based routing: message_type.#.*.*"
puts "   ✓ Priority routing: Complex conditional patterns"
puts "   ✓ Broadcast routing: #.*.broadcast"
puts "   ✓ Multi-pattern subscriptions"
puts "   ✓ Wildcard pattern matching (#, *)"
puts "   ✓ Queue statistics and monitoring"

puts "\n🚀 Key Benefits:"
puts "   • Surgical message routing precision"  
puts "   • Multiple subscribers per pattern"
puts "   • High-performance pattern matching with Async fibers"
puts "   • Real-time queue monitoring"
puts "   • Flexible routing table management"
puts "   • Fiber-based concurrency for massive scalability"