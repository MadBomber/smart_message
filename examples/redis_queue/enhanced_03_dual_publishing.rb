#!/usr/bin/env ruby
# examples/redis_queue/enhanced_03_dual_publishing.rb
# Redis Enhanced Transport - Dual Channel Publishing Demo

require_relative '../../lib/smart_message'
require 'smart_message/transport/redis_enhanced_transport'

puts "🚀 Redis Enhanced Transport - Dual Channel Publishing Demo"
puts "=" * 58

# Create both enhanced and basic Redis transports to demonstrate compatibility
enhanced_transport = SmartMessage::Transport::RedisEnhancedTransport.new(
  url: 'redis://localhost:6379',
  db: 4,  # Use database 4 for dual publishing examples
  auto_subscribe: true
)

basic_transport = SmartMessage::Transport::RedisTransport.new(
  url: 'redis://localhost:6379',
  db: 4,  # Same database to show cross-transport communication
  auto_subscribe: true
)

#==============================================================================
# Define Message Classes for Both Transports
#==============================================================================

class OrderStatusMessage < SmartMessage::Base
  from 'order-service'
  to 'customer-notification'
  
  transport enhanced_transport
  serializer SmartMessage::Serializer::Json.new
  
  property :order_id, required: true
  property :status, required: true
  property :customer_email, required: true
  property :updated_at, default: -> { Time.now.iso8601 }
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "📋 [ENHANCED] Order #{data['order_id']} status: #{data['status']}"
    puts "   Customer: #{data['customer_email']}"
    puts "   Channel: Enhanced (dual publishing)"
    puts "   From: #{header.from} → To: #{header.to}"
    puts
  end
end

# Same message class but using basic transport
class LegacyOrderMessage < SmartMessage::Base
  from 'legacy-system'
  
  transport basic_transport
  serializer SmartMessage::Serializer::Json.new
  
  property :order_id, required: true
  property :action, required: true
  property :details, default: {}
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "🔄 [BASIC] Legacy order #{data['order_id']} - #{data['action']}"
    puts "   Channel: Basic (single channel)"
    puts "   From: #{header.from}"
    puts
  end
end

# Message that demonstrates backwards compatibility
class CompatibilityTestMessage < SmartMessage::Base
  from 'test-service'
  to 'compatibility-test'
  
  # Will be configured dynamically to test both transports
  serializer SmartMessage::Serializer::Json.new
  
  property :test_id, required: true
  property :transport_type, required: true
  property :message_content, required: true
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "🧪 [#{data['transport_type'].upcase}] Test #{data['test_id']}"
    puts "   Content: #{data['message_content']}"
    puts "   From: #{header.from} → To: #{header.to}"
    puts
  end
end

#==============================================================================
# Demonstration Functions
#==============================================================================

def demonstrate_dual_publishing
  puts "🔄 Demonstrating dual channel publishing..."
  puts "Enhanced transport publishes to BOTH channels:"
  puts "  1. Original channel: 'OrderStatusMessage'"
  puts "  2. Enhanced channel: 'orderstatusmessage.order_service.customer_notification'"
  puts
  
  # Publish enhanced message
  order_status = OrderStatusMessage.new(
    order_id: 'ORD-2024-001',
    status: 'shipped',
    customer_email: 'customer@example.com'
  )
  
  puts "📤 Publishing OrderStatusMessage (enhanced transport)..."
  order_status.publish
  puts "✅ Message published to both original and enhanced channels"
  puts
end

def demonstrate_backwards_compatibility
  puts "🔙 Demonstrating backwards compatibility..."
  puts "Enhanced transport should receive messages from basic transport"
  puts
  
  # Publish from basic transport
  legacy_message = LegacyOrderMessage.new(
    order_id: 'ORD-LEGACY-001',
    action: 'processed',
    details: { processor: 'legacy_v1.2', timestamp: Time.now.to_i }
  )
  
  puts "📤 Publishing from basic Redis transport..."
  legacy_message.publish
  puts "✅ Basic transport message published"
  puts
end

def demonstrate_cross_transport_subscriptions(enhanced_transport)
  puts "🌉 Setting up cross-transport subscriptions..."
  puts
  
  # Enhanced transport subscribes to basic transport patterns
  enhanced_transport.subscribe_pattern("LegacyOrderMessage")  # Basic channel name
  enhanced_transport.subscribe_pattern("*.legacy_system.*")    # Enhanced pattern that won't match basic
  
  puts "✅ Enhanced transport subscribed to:"
  puts "   • 'LegacyOrderMessage' (basic channel)"
  puts "   • '*.legacy_system.*' (enhanced pattern)"
  puts
end

def test_transport_compatibility
  puts "🧪 Testing transport compatibility..."
  puts
  
  # Test 1: Enhanced message with enhanced transport
  CompatibilityTestMessage.config { transport enhanced_transport }
  
  enhanced_test = CompatibilityTestMessage.new(
    test_id: 'TEST-001',
    transport_type: 'enhanced',
    message_content: 'Testing dual channel publishing'
  )
  
  puts "📤 Test 1: Enhanced transport with enhanced message..."
  enhanced_test.publish
  
  # Test 2: Basic message with basic transport
  CompatibilityTestMessage.config { transport basic_transport }
  
  basic_test = CompatibilityTestMessage.new(
    test_id: 'TEST-002', 
    transport_type: 'basic',
    message_content: 'Testing single channel publishing'
  )
  
  puts "📤 Test 2: Basic transport with basic message..."
  basic_test.publish
  puts
end

def show_channel_comparison
  puts "📊 Channel Comparison:"
  puts "┌─────────────────┬───────────────────────┬────────────────────────────────────┐"
  puts "│ Transport Type  │ Original Channel      │ Enhanced Channel                   │"
  puts "├─────────────────┼───────────────────────┼────────────────────────────────────┤"
  puts "│ Basic           │ MessageClassName      │ (none)                             │"
  puts "│ Enhanced        │ MessageClassName      │ messageclassname.from.to           │"
  puts "└─────────────────┴───────────────────────┴────────────────────────────────────┘"
  puts
  
  puts "📋 Pattern Matching Examples:"
  puts "• Basic pattern:    'OrderStatusMessage'"
  puts "• Enhanced pattern: 'orderstatusmessage.order_service.customer_notification'"
  puts "• Wildcard pattern: '*.order_service.*' (matches all from order-service)"
  puts "• Type pattern:     'orderstatusmessage.*.*' (matches all order status messages)"
  puts
end

def monitor_redis_channels
  puts "👀 Monitoring Redis channels (simulation)..."
  puts "If you were monitoring Redis, you would see:"
  puts
  puts "BASIC TRANSPORT publishes to:"
  puts "  ├─ 'LegacyOrderMessage'"
  puts "  └─ 'CompatibilityTestMessage'"
  puts
  puts "ENHANCED TRANSPORT publishes to:"
  puts "  ├─ 'OrderStatusMessage' (backwards compatibility)"
  puts "  ├─ 'orderstatusmessage.order_service.customer_notification' (enhanced)"
  puts "  ├─ 'CompatibilityTestMessage' (backwards compatibility)"  
  puts "  └─ 'compatibilitytestmessage.test_service.compatibility_test' (enhanced)"
  puts
end

#==============================================================================
# Main Demonstration
#==============================================================================

begin
  puts "🔧 Checking Redis connections..."
  unless enhanced_transport.connected? && basic_transport.connected?
    puts "❌ Redis not available. Please start Redis server:"
    puts "   brew services start redis  # macOS"
    puts "   sudo service redis start   # Linux"
    exit 1
  end
  puts "✅ Connected to Redis (both transports)"
  puts
  
  # Show channel comparison
  show_channel_comparison
  
  # Set up cross-transport subscriptions
  demonstrate_cross_transport_subscriptions(enhanced_transport)
  
  # Subscribe message classes
  OrderStatusMessage.subscribe
  LegacyOrderMessage.subscribe
  CompatibilityTestMessage.subscribe
  
  puts "⏳ Waiting for subscriptions to be established..."
  sleep 1
  
  # Run demonstrations
  demonstrate_dual_publishing
  sleep 0.5
  
  demonstrate_backwards_compatibility  
  sleep 0.5
  
  test_transport_compatibility
  sleep 1
  
  puts "⏳ Processing messages (waiting 3 seconds)..."
  sleep 3
  
  # Show monitoring simulation
  monitor_redis_channels
  
  puts "🎉 Dual Publishing Demo completed!"
  puts
  puts "💡 Key Insights:"
  puts "   • Enhanced transport publishes to BOTH original and enhanced channels"
  puts "   • This provides backwards compatibility with basic Redis transport"
  puts "   • Enhanced patterns allow more sophisticated routing"
  puts "   • Basic transport only publishes to original channels"
  puts "   • Both transports can coexist and communicate"
  
rescue Interrupt
  puts "\n👋 Demo interrupted by user"
rescue => e
  puts "💥 Error: #{e.message}"
  puts e.backtrace[0..3]
ensure
  puts "\n🧹 Cleaning up..."
  enhanced_transport&.disconnect
  basic_transport&.disconnect
  puts "✅ Disconnected from Redis (both transports)"
end