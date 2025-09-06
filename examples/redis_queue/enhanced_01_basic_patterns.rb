#!/usr/bin/env ruby
# examples/redis_queue/enhanced_01_basic_patterns.rb
# Redis Enhanced Transport - Basic Pattern Subscriptions Demo

require_relative '../../lib/smart_message'
require 'smart_message/transport/redis_enhanced_transport'

puts "🚀 Redis Enhanced Transport - Basic Pattern Subscriptions Demo"
puts "=" * 60

# Create enhanced Redis transport instance
transport = SmartMessage::Transport::RedisEnhancedTransport.new(
  url: 'redis://localhost:6379',
  db: 2,  # Use database 2 for enhanced transport examples
  auto_subscribe: true
)

#==============================================================================
# Define Message Classes
#==============================================================================

class OrderMessage < SmartMessage::Base
  from 'e-commerce-api'
  to 'order-processor'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :order_id, required: true
  property :customer_id, required: true
  property :amount, required: true
  property :items, default: []
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "📦 [OrderMessage] Processing order #{data['order_id']}"
    puts "   Customer: #{data['customer_id']}, Amount: $#{data['amount']}"
    puts "   From: #{header.from} → To: #{header.to}"
    puts "   Enhanced Channel: ordermessage.#{header.from.gsub('-', '_')}.#{header.to.gsub('-', '_')}"
    puts
  end
end

class PaymentMessage < SmartMessage::Base
  from 'payment-gateway'
  to 'bank-service'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :payment_id, required: true
  property :amount, required: true
  property :currency, default: 'USD'
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "💳 [PaymentMessage] Processing payment #{data['payment_id']}"
    puts "   Amount: #{data['amount']} #{data['currency']}"
    puts "   From: #{header.from} → To: #{header.to}"
    puts "   Enhanced Channel: paymentmessage.#{header.from.gsub('-', '_')}.#{header.to.gsub('-', '_')}"
    puts
  end
end

class AlertMessage < SmartMessage::Base
  from 'monitoring-service'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :alert_type, required: true
  property :severity, required: true
  property :message, required: true
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "🚨 [AlertMessage] #{data['severity'].upcase} ALERT: #{data['alert_type']}"
    puts "   Message: #{data['message']}"
    puts "   From: #{header.from} → To: #{header.to || 'broadcast'}"
    puts "   Enhanced Channel: alertmessage.#{header.from.gsub('-', '_')}.#{(header.to || 'broadcast').gsub('-', '_')}"
    puts
  end
end

#==============================================================================
# Demonstration Functions
#==============================================================================

def demo_basic_pattern_subscriptions(transport)
  puts "🔍 Setting up basic pattern subscriptions..."
  puts
  
  # Subscribe to specific message patterns
  transport.subscribe_pattern("ordermessage.*.*")       # All order messages
  transport.subscribe_pattern("*.payment_gateway.*")    # All messages from payment gateway
  transport.subscribe_pattern("*.*.bank_service")       # All messages to bank service
  transport.subscribe_pattern("alertmessage.*.*")       # All alert messages
  
  puts "✅ Subscribed to patterns:"
  puts "   • ordermessage.*.* (all order messages)"
  puts "   • *.payment_gateway.* (all from payment gateway)" 
  puts "   • *.*.bank_service (all to bank service)"
  puts "   • alertmessage.*.* (all alert messages)"
  puts
end

def demo_convenience_subscriptions(transport)
  puts "🎯 Setting up convenience method subscriptions..."
  puts
  
  # Use convenience methods
  transport.subscribe_to_recipient('order-processor')
  transport.subscribe_from_sender('monitoring-service')
  transport.subscribe_to_type('PaymentMessage')
  transport.subscribe_to_alerts  # Subscribes to emergency/alert/alarm/critical patterns
  transport.subscribe_to_broadcasts
  
  puts "✅ Convenience subscriptions added:"
  puts "   • subscribe_to_recipient('order-processor')"
  puts "   • subscribe_from_sender('monitoring-service')"
  puts "   • subscribe_to_type('PaymentMessage')"
  puts "   • subscribe_to_alerts (emergency/alert/alarm/critical patterns)"
  puts "   • subscribe_to_broadcasts"
  puts
end

def publish_sample_messages
  puts "📤 Publishing sample messages..."
  puts
  
  # Publish order message
  order = OrderMessage.new(
    order_id: 'ORD-001',
    customer_id: 'CUST-123',
    amount: 99.99,
    items: ['Widget A', 'Widget B']
  )
  order.publish
  
  # Publish payment message
  payment = PaymentMessage.new(
    payment_id: 'PAY-001',
    amount: 99.99,
    currency: 'USD'
  )
  payment.publish
  
  # Publish alert message (broadcast)
  alert = AlertMessage.new(
    alert_type: 'system_overload',
    severity: 'warning',
    message: 'CPU usage exceeding 80%'
  )
  alert.to(nil)  # Make it a broadcast
  alert.publish
  
  # Publish targeted alert
  critical_alert = AlertMessage.new(
    alert_type: 'database_connection_lost',
    severity: 'critical',
    message: 'Primary database connection failed'
  )
  critical_alert.to('ops-team')
  critical_alert.publish
  
  puts "✅ Published 4 sample messages"
  puts
end

#==============================================================================
# Main Demonstration
#==============================================================================

begin
  puts "🔧 Checking Redis connection..."
  unless transport.connected?
    puts "❌ Redis not available. Please start Redis server:"
    puts "   brew services start redis  # macOS"
    puts "   sudo service redis start   # Linux"
    exit 1
  end
  puts "✅ Connected to Redis"
  puts
  
  # Set up subscriptions
  demo_basic_pattern_subscriptions(transport)
  demo_convenience_subscriptions(transport)
  
  # Subscribe message classes to their handlers
  OrderMessage.subscribe
  PaymentMessage.subscribe
  AlertMessage.subscribe
  
  puts "⏳ Waiting for subscriptions to be established..."
  sleep 1
  
  # Publish sample messages
  publish_sample_messages
  
  puts "⏳ Processing messages (waiting 3 seconds)..."
  sleep 3
  
  puts "📊 Pattern Subscription Status:"
  pattern_subscriptions = transport.instance_variable_get(:@pattern_subscriptions)
  if pattern_subscriptions
    pattern_subscriptions.each do |pattern|
      puts "   • #{pattern}"
    end
  else
    puts "   No pattern subscriptions found"
  end
  puts
  
  puts "🎉 Demo completed! Check the output above to see how messages were routed."
  puts "💡 Notice how messages are published to both original channels (OrderMessage)"
  puts "   and enhanced channels (ordermessage.e_commerce_api.order_processor)"
  
rescue Interrupt
  puts "\n👋 Demo interrupted by user"
rescue => e
  puts "💥 Error: #{e.message}"
  puts e.backtrace[0..3]
ensure
  puts "\n🧹 Cleaning up..."
  transport&.disconnect
  puts "✅ Disconnected from Redis"
end