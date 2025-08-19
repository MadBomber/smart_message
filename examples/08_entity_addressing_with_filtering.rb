#!/usr/bin/env ruby
# examples/08_entity_addressing_with_filtering.rb
#
# Demonstrates SmartMessage entity addressing and filtering capabilities including:
# - Point-to-point messaging with FROM/TO fields
# - Broadcast messaging (no TO field)
# - Entity-aware subscription filtering
# - Request-reply patterns with REPLY_TO
# - Instance-level addressing overrides
# - Gateway patterns

require_relative '../lib/smart_message'

puts "🎯 SmartMessage Entity Addressing & Filtering Demo"
puts "=" * 50

# Configure transport for demo
transport = SmartMessage::Transport.create(:stdout, loopback: true)
serializer = SmartMessage::Serializer::JSON.new

# =============================================================================
# Example 1: Entity-Aware Message Filtering
# =============================================================================

puts "\n🔍 Example 1: Entity-Aware Message Filtering"
puts "-" * 40

class ServiceMessage < SmartMessage::Base
  version 1
  description "Messages between microservices with filtering"
  
  from 'sender-service'
  
  property :message_type, required: true
  property :data, required: true
  property :timestamp, default: -> { Time.now.to_s }
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  # Different handlers for different subscription filters
  def self.process_broadcast(header, payload)
    data = JSON.parse(payload)
    puts "   📻 BROADCAST HANDLER received:"
    puts "      Type: #{data['message_type']}"
    puts "      From: #{header.from}, To: #{header.to || 'ALL'}"
    puts "      Data: #{data['data']}"
  end
  
  def self.process_directed(header, payload)
    data = JSON.parse(payload)
    puts "   🎯 DIRECTED HANDLER received:"
    puts "      Type: #{data['message_type']}"
    puts "      From: #{header.from} → To: #{header.to}"
    puts "      Data: #{data['data']}"
  end
  
  def self.process_from_admin(header, payload)
    data = JSON.parse(payload)
    puts "   👮 ADMIN HANDLER received:"
    puts "      Type: #{data['message_type']}"
    puts "      From: #{header.from} (ADMIN)"
    puts "      Data: #{data['data']}"
  end
end

# Subscribe with different filters
puts "\n📌 Setting up filtered subscriptions:"

# Subscribe to broadcast messages only
puts "   1. Subscribing to broadcast messages only..."
ServiceMessage.subscribe('ServiceMessage.process_broadcast', broadcast: true)

# Subscribe to messages directed to 'my-service'
puts "   2. Subscribing to messages for 'my-service' only..."
ServiceMessage.subscribe('ServiceMessage.process_directed', to: 'my-service')

# Subscribe to messages from 'admin-service'
puts "   3. Subscribing to messages from 'admin-service'..."
ServiceMessage.subscribe('ServiceMessage.process_from_admin', from: 'admin-service')

# Test different message types
puts "\n📤 Publishing test messages..."

# Broadcast message - should only be received by broadcast handler
broadcast_msg = ServiceMessage.new(
  message_type: 'system_announcement',
  data: 'System maintenance at 2 AM',
  from: 'sender-service'
)
broadcast_msg.to(nil)  # Explicitly set as broadcast
puts "\n1. Publishing broadcast message (no 'to' field)..."
broadcast_msg.publish
sleep(0.2)  # Allow time for handlers to process

# Directed message to 'my-service' - should only be received by directed handler
directed_msg = ServiceMessage.new(
  message_type: 'service_update',
  data: 'Update your configuration',
  from: 'sender-service'
)
directed_msg.to('my-service')
puts "\n2. Publishing message to 'my-service'..."
directed_msg.publish
sleep(0.2)  # Allow time for handlers to process

# Directed message to different service - should NOT be received
other_msg = ServiceMessage.new(
  message_type: 'other_update',
  data: 'This is for another service',
  from: 'sender-service'
)
other_msg.to('other-service')
puts "\n3. Publishing message to 'other-service' (should not be received)..."
other_msg.publish
sleep(0.2)  # Allow time to confirm no handlers process this

# Message from admin - should only be received by admin handler
admin_msg = ServiceMessage.new(
  message_type: 'admin_command',
  data: 'Restart all services',
  from: 'admin-service'
)
admin_msg.from('admin-service')
admin_msg.to('my-service')
puts "\n4. Publishing message from 'admin-service'..."
admin_msg.publish
sleep(0.2)  # Allow time for handlers to process

# =============================================================================
# Example 2: Combined Filters
# =============================================================================

puts "\n🔗 Example 2: Combined Subscription Filters"
puts "-" * 40

class AlertMessage < SmartMessage::Base
  version 1
  description "Alert messages with combined filtering"
  
  from 'alert-service'  # Default from field
  
  property :severity, required: true
  property :alert_text, required: true
  property :source_system
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process_critical_or_broadcast(header, payload)
    data = JSON.parse(payload)
    icon = data['severity'] == 'critical' ? '🚨' : '📢'
    puts "   #{icon} ALERT MONITOR received:"
    puts "      Severity: #{data['severity'].upcase}"
    puts "      From: #{header.from}, To: #{header.to || 'ALL'}"
    puts "      Alert: #{data['alert_text']}"
  end
  
  def self.process_from_monitoring(header, payload)
    data = JSON.parse(payload)
    puts "   📊 MONITORING TEAM received:"
    puts "      From: #{header.from} (monitoring system)"
    puts "      Severity: #{data['severity']}"
    puts "      Alert: #{data['alert_text']}"
  end
end

# Clear previous subscriptions
AlertMessage.unsubscribe!

# Subscribe to broadcasts OR messages to 'alert-service'
puts "\n📌 Setting up combined filter subscriptions:"
puts "   1. Subscribe to broadcasts OR messages to 'alert-service'..."
AlertMessage.subscribe(
  'AlertMessage.process_critical_or_broadcast',
  broadcast: true,
  to: 'alert-service'
)

# Subscribe to messages from specific monitoring systems
puts "   2. Subscribe to messages from monitoring systems..."
AlertMessage.subscribe(
  'AlertMessage.process_from_monitoring',
  from: ['monitoring-system-1', 'monitoring-system-2']
)

# Test combined filters
puts "\n📤 Publishing alert messages..."

# Broadcast alert - should be received by first handler
broadcast_alert = AlertMessage.new(
  severity: 'warning',
  alert_text: 'CPU usage high across cluster',
  source_system: 'cluster-monitor',
  from: 'monitoring-system-1'
)
broadcast_alert.from('monitoring-system-1')
broadcast_alert.to(nil)  # Broadcast
puts "\n1. Broadcasting alert..."
broadcast_alert.publish
sleep(0.2)  # Allow time for handlers to process

# Directed alert to 'alert-service' - should be received by first handler
directed_alert = AlertMessage.new(
  severity: 'critical',
  alert_text: 'Database connection lost',
  source_system: 'db-monitor',
  from: 'monitoring-system-2'
)
directed_alert.from('monitoring-system-2')
directed_alert.to('alert-service')
puts "\n2. Sending critical alert to 'alert-service'..."
directed_alert.publish
sleep(0.2)  # Allow time for handlers to process

# Alert to different service - should only be received by monitoring handler
other_alert = AlertMessage.new(
  severity: 'info',
  alert_text: 'Backup completed successfully',
  source_system: 'backup-system',
  from: 'monitoring-system-1'
)
other_alert.from('monitoring-system-1')
other_alert.to('backup-service')
puts "\n3. Sending info alert to 'backup-service'..."
other_alert.publish
sleep(0.2)  # Allow time for handlers to process

# =============================================================================
# Example 3: Point-to-Point with Filtering
# =============================================================================

puts "\n📡 Example 3: Point-to-Point Messaging with Filtering"
puts "-" * 40

class OrderMessage < SmartMessage::Base
  version 1
  description "Order processing with selective subscription"
  
  from 'order-service'
  to 'fulfillment-service'
  reply_to 'order-service'
  
  property :order_id, required: true
  property :priority, default: 'normal'
  property :items, required: true
  property :total_amount, required: true
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process_high_priority(header, payload)
    data = JSON.parse(payload)
    puts "   🚀 HIGH PRIORITY ORDER HANDLER:"
    puts "      Order ID: #{data['order_id']} (PRIORITY: #{data['priority'].upcase})"
    puts "      From: #{header.from} → To: #{header.to}"
    puts "      Total: $#{data['total_amount']}"
  end
  
  def self.process_normal(header, payload)
    data = JSON.parse(payload)
    puts "   📦 NORMAL ORDER HANDLER:"
    puts "      Order ID: #{data['order_id']}"
    puts "      From: #{header.from} → To: #{header.to}"
    puts "      Total: $#{data['total_amount']}"
  end
end

# Clear and set up filtered subscriptions
OrderMessage.unsubscribe!

puts "\n📌 Setting up order processing subscriptions:"
# Only the fulfillment service subscribes
puts "   1. Fulfillment service subscribes to orders..."
OrderMessage.subscribe('OrderMessage.process_normal', to: 'fulfillment-service')

# High-priority team also monitors high-value orders
puts "   2. Priority team subscribes to high-value orders..."
OrderMessage.subscribe('OrderMessage.process_high_priority', to: 'fulfillment-service')

# Send different types of orders
puts "\n📤 Publishing orders..."

# Normal order to fulfillment
normal_order = OrderMessage.new(
  order_id: "ORD-001",
  priority: 'normal',
  items: ["Widget A", "Widget B"],
  total_amount: 99.99,
  from: 'order-service'
)
puts "\n1. Publishing normal order to fulfillment..."
normal_order.publish
sleep(0.2)  # Allow time for handlers to process

# High priority order
high_priority_order = OrderMessage.new(
  order_id: "ORD-002",
  priority: 'high',
  items: ["Premium Widget", "Express Gadget"],
  total_amount: 999.99,
  from: 'order-service'
)
puts "\n2. Publishing high-priority order..."
high_priority_order.publish
sleep(0.2)  # Allow time for handlers to process

# Order to different service (should not be received)
misrouted_order = OrderMessage.new(
  order_id: "ORD-003",
  priority: 'normal',
  items: ["Test Item"],
  total_amount: 50.00,
  from: 'order-service'
)
misrouted_order.to('wrong-service')
puts "\n3. Publishing order to 'wrong-service' (should not be received)..."
misrouted_order.publish
sleep(0.2)  # Allow time to confirm no handlers process this

# =============================================================================
# Example 4: Request-Reply with Filtering
# =============================================================================

puts "\n🔄 Example 4: Request-Reply Pattern with Filtering"
puts "-" * 40

class ServiceRequest < SmartMessage::Base
  version 1
  description "Service requests with filtered responses"
  
  from 'request-service'  # Default from field
  
  property :request_id, required: true
  property :request_type, required: true
  property :data
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process_api_requests(header, payload)
    data = JSON.parse(payload)
    puts "   🌐 API SERVICE received request:"
    puts "      Request ID: #{data['request_id']}"
    puts "      Type: #{data['request_type']}"
    puts "      From: #{header.from} → To: #{header.to}"
    puts "      Reply To: #{header.reply_to}"
  end
  
  def self.process_data_requests(header, payload)
    data = JSON.parse(payload)
    puts "   💾 DATA SERVICE received request:"
    puts "      Request ID: #{data['request_id']}"
    puts "      Type: #{data['request_type']}"
    puts "      From: #{header.from} → To: #{header.to}"
  end
end

ServiceRequest.unsubscribe!

puts "\n📌 Setting up service request routing:"
# API service only handles requests directed to it
puts "   1. API service subscribes to its requests..."
ServiceRequest.subscribe('ServiceRequest.process_api_requests', to: 'api-service')

# Data service handles data requests
puts "   2. Data service subscribes to its requests..."
ServiceRequest.subscribe('ServiceRequest.process_data_requests', to: 'data-service')

puts "\n📤 Publishing service requests..."

# API request
api_request = ServiceRequest.new(
  request_id: SecureRandom.uuid,
  request_type: 'user_lookup',
  data: { user_id: 'USER-123' },
  from: 'web-frontend'
)
api_request.from('web-frontend')
api_request.to('api-service')
api_request.reply_to('web-frontend')
puts "\n1. Publishing API request..."
api_request.publish
sleep(0.2)  # Allow time for handlers to process

# Data request
data_request = ServiceRequest.new(
  request_id: SecureRandom.uuid,
  request_type: 'query',
  data: { table: 'orders', limit: 100 },
  from: 'analytics-service'
)
data_request.from('analytics-service')
data_request.to('data-service')
data_request.reply_to('analytics-service')
puts "\n2. Publishing data request..."
data_request.publish
sleep(0.2)  # Allow time for handlers to process

# =============================================================================
# Summary
# =============================================================================

puts "\n🎯 Entity Addressing & Filtering Summary"
puts "=" * 50
puts "✅ Point-to-Point: FROM/TO specified for direct routing"
puts "✅ Broadcast: FROM only, TO=nil for all broadcast subscribers"
puts "✅ Filtered Subscriptions: Subscribe to specific message patterns:"
puts "   • broadcast: true - Only receive broadcast messages"
puts "   • to: 'service-name' - Only receive messages directed to you"
puts "   • from: 'sender' - Only receive from specific senders"
puts "   • from: ['sender1', 'sender2'] - Receive from multiple senders"
puts "   • Combined filters work with OR logic for broadcast/to"
puts "✅ Request-Reply: REPLY_TO for response routing"
puts "✅ Instance Override: Runtime addressing changes"
puts "✅ Gateway Pattern: Message transformation and routing"
puts "\n💡 Filtering enables microservices to:"
puts "   • Ignore messages not meant for them"
puts "   • Handle broadcasts separately from directed messages"
puts "   • Route messages to appropriate handlers based on sender"
puts "   • Reduce processing overhead by filtering at subscription level"
puts "\nFor more details, see docs/addressing.md"