#!/usr/bin/env ruby
# examples/09_regex_filtering_microservices.rb

require_relative '../lib/smart_message'

# Example: Advanced Regex Filtering for Microservices Architecture
# 
# This example demonstrates how to use SmartMessage's regex filtering capabilities
# to build a sophisticated microservices routing system that supports:
# - Environment-based routing (dev, staging, prod)
# - Service pattern routing (payment-*, api-*, admin-*)
# - Mixed exact and pattern matching
# - Complex multi-criteria filtering

puts "🔍 SmartMessage Regex Filtering Demo"
puts "=" * 50

# Base message class for the microservices ecosystem
class MicroserviceMessage < SmartMessage::Base
  version 1
  
  # Set default 'from' to avoid header requirement issues
  from 'microservice-demo'
  
  property :service_id, required: true, description: "Originating service identifier"
  property :message_type, required: true, description: "Type of message being sent"
  property :data, description: "Message payload data"
  property :environment, default: 'dev', description: "Target environment"
  property :timestamp, default: -> { Time.now.iso8601 }, description: "Message timestamp"

  # Configure with STDOUT transport for demo visibility
  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
end

# Service-specific message types
class PaymentMessage < MicroserviceMessage
  description "Payment processing and transaction messages"
  
  property :transaction_id, required: true
  property :amount, required: true
  property :currency, default: 'USD'
  
  def self.process(wrapper)
    header = wrapper._sm_header
    payload = wrapper._sm_payload
    msg_data = JSON.parse(payload)
    puts "💳 PaymentMessage processed by #{self.name}"
    puts "   From: #{header.from} → To: #{header.to}"
    puts "   Transaction: #{msg_data['transaction_id']} (#{msg_data['currency']} #{msg_data['amount']})"
    puts "   Environment: #{msg_data['environment']}"
    puts
  end
end

class OrderMessage < MicroserviceMessage
  description "Order management and fulfillment messages"
  
  property :order_id, required: true
  property :customer_id, required: true
  property :status, default: 'pending'
  
  def self.process(wrapper)
    header = wrapper._sm_header
    payload = wrapper._sm_payload
    msg_data = JSON.parse(payload)
    puts "📦 OrderMessage processed by #{self.name}"
    puts "   From: #{header.from} → To: #{header.to}"
    puts "   Order: #{msg_data['order_id']} for customer #{msg_data['customer_id']}"
    puts "   Status: #{msg_data['status']}, Environment: #{msg_data['environment']}"
    puts
  end
end

class AlertMessage < MicroserviceMessage
  description "System monitoring and alerting messages"
  
  property :alert_level, required: true
  property :component, required: true
  property :description, required: true
  
  def self.process(wrapper)
    header = wrapper._sm_header
    payload = wrapper._sm_payload
    msg_data = JSON.parse(payload)
    puts "🚨 AlertMessage processed by #{self.name}"
    puts "   From: #{header.from} → To: #{header.to}"
    puts "   Level: #{msg_data['alert_level']} - Component: #{msg_data['component']}"
    puts "   Description: #{msg_data['description']}"
    puts "   Environment: #{msg_data['environment']}"
    puts
  end
end

# Demonstration of different regex filtering patterns
def demonstrate_filtering_patterns
  puts "\n🎯 Setting up subscription filters..."
  
  # Clear any existing subscriptions
  [PaymentMessage, OrderMessage, AlertMessage].each(&:unsubscribe!)
  
  # 1. Environment-based filtering
  puts "\n1️⃣ Environment-based filtering:"
  puts "   - Development services receive dev/staging messages"
  puts "   - Production services receive only prod messages"
  
  PaymentMessage.subscribe("PaymentMessage.process_dev", to: /^(dev|staging)-.*/)
  PaymentMessage.subscribe("PaymentMessage.process_prod", to: /^prod-.*/)
  
  # 2. Service pattern filtering  
  puts "\n2️⃣ Service pattern filtering:"
  puts "   - Order services receive messages from payment services"
  puts "   - Alert services receive messages from any monitoring system"
  
  OrderMessage.subscribe("OrderMessage.process", from: /^payment-.*/)
  AlertMessage.subscribe("AlertMessage.process", from: /^(monitoring|health|system)-.*/)
  
  # 3. Mixed exact and pattern matching
  puts "\n3️⃣ Mixed filtering (exact + patterns):"
  puts "   - Specific services + pattern matching"
  
  # Alert service receives from admin, plus any system-* services
  AlertMessage.subscribe("AlertMessage.process_admin", from: ['admin', /^system-.*/, 'security'])
  
  # 4. Complex multi-criteria filtering
  puts "\n4️⃣ Complex multi-criteria filtering:"
  puts "   - Admin services to production environments only"
  
  OrderMessage.subscribe("OrderMessage.process_admin_prod", 
    from: /^admin-.*/, 
    to: /^prod-.*/)
  
  # 5. Broadcast + directed message filtering
  puts "\n5️⃣ Broadcast + directed filtering:"
  puts "   - Receive broadcast messages OR messages directed to api services"
  
  PaymentMessage.subscribe("PaymentMessage.process_api", 
    broadcast: true, 
    to: /^api-.*/)
  
  puts "\n✅ All subscription filters configured!"
end

# Simulate microservices sending messages
def simulate_microservice_traffic
  puts "\n📡 Simulating microservice message traffic..."
  puts "=" * 50
  
  # Sleep between messages for readability
  delay = 0.5
  
  # 1. Environment-based routing examples
  puts "\n🌍 Environment-based routing examples:"
  
  payment_msg = PaymentMessage.new(
    service_id: "payment-core",
    message_type: "transaction_complete",
    transaction_id: "TXN-001",
    amount: 99.99,
    data: { merchant: "Online Store" },
    environment: "dev"
  )
  payment_msg.from('payment-service')
  payment_msg.to('dev-payment-processor')
  payment_msg.publish
  sleep(delay)
  
  payment_msg = PaymentMessage.new(
    service_id: "payment-core",
    message_type: "transaction_complete", 
    transaction_id: "TXN-002",
    amount: 299.99,
    data: { merchant: "Enterprise Store" },
    environment: "prod"
  )
  payment_msg.from('payment-service')
  payment_msg.to('prod-payment-processor')
  payment_msg.publish
  sleep(delay)
  
  # 2. Service pattern routing examples
  puts "\n🔄 Service pattern routing examples:"
  
  order_msg = OrderMessage.new(
    service_id: "order-manager",
    message_type: "order_created",
    order_id: "ORD-123",
    customer_id: "CUST-456",
    status: "pending",
    data: { items: ["Widget A", "Widget B"] },
    environment: "prod"
  )
  order_msg.from('payment-gateway')  # Matches /^payment-.*/ pattern
  order_msg.to('order-service')
  order_msg.publish
  sleep(delay)
  
  # 3. Monitoring and alerting examples
  puts "\n📊 Monitoring and alerting examples:"
  
  alert_msg = AlertMessage.new(
    service_id: "health-checker",
    message_type: "system_alert",
    alert_level: "warning",
    component: "database",
    description: "High connection count detected",
    data: { current_connections: 95, max_connections: 100 },
    environment: "prod"
  )
  alert_msg.from('monitoring-system')  # Matches /^monitoring-.*/ pattern
  alert_msg.to('ops-dashboard')
  alert_msg.publish
  sleep(delay)
  
  # 4. Mixed filtering examples
  puts "\n🎭 Mixed filtering examples:"
  
  alert_msg = AlertMessage.new(
    service_id: "security-scanner", 
    message_type: "security_alert",
    alert_level: "critical",
    component: "authentication",
    description: "Multiple failed login attempts detected",
    data: { attempts: 50, ip: "192.168.1.100" },
    environment: "prod"
  )
  alert_msg.from('admin')  # Exact match in mixed array ['admin', /^system-.*/, 'security']
  alert_msg.to('security-dashboard')
  alert_msg.publish
  sleep(delay)
  
  alert_msg = AlertMessage.new(
    service_id: "system-monitor",
    message_type: "resource_alert", 
    alert_level: "warning",
    component: "memory",
    description: "Memory usage above threshold",
    data: { usage_percent: 85, threshold: 80 },
    environment: "staging"
  )
  alert_msg.from('system-metrics')  # Matches /^system-.*/ pattern
  alert_msg.to('ops-dashboard')
  alert_msg.publish
  sleep(delay)
  
  # 5. Complex multi-criteria examples
  puts "\n🎯 Complex multi-criteria examples:"
  
  order_msg = OrderMessage.new(
    service_id: "admin-portal",
    message_type: "admin_order_override",
    order_id: "ORD-999",
    customer_id: "ADMIN",
    status: "expedited",
    data: { priority: "high", reason: "VIP customer" },
    environment: "prod"
  )
  order_msg.from('admin-dashboard')  # Matches /^admin-.*/ pattern
  order_msg.to('prod-fulfillment')   # Matches /^prod-.*/ pattern
  order_msg.publish
  sleep(delay)
  
  # 6. Broadcast message examples
  puts "\n📢 Broadcast message examples:"
  
  payment_msg = PaymentMessage.new(
    service_id: "payment-system",
    message_type: "system_maintenance",
    transaction_id: "MAINT-001", 
    amount: 0,
    data: { 
      message: "Scheduled maintenance in 30 minutes",
      duration: "2 hours",
      affected_services: ["payment", "billing"]
    },
    environment: "prod"
  )
  payment_msg.from('admin')
  payment_msg.to(nil)  # Broadcast message
  payment_msg.publish
  sleep(delay)
  
  # 7. Messages that won't match filters
  puts "\n❌ Examples of messages that won't match filters:"
  
  # This won't match any filters (wrong from pattern)
  order_msg = OrderMessage.new(
    service_id: "user-service",
    message_type: "user_action",
    order_id: "ORD-NOFILT",
    customer_id: "USER-123",
    status: "ignored",
    environment: "dev"
  )
  order_msg.from('user-portal')  # Doesn't match /^payment-.*/ pattern
  order_msg.to('order-service')
  order_msg.publish
  puts "   ⚠️  This message won't be processed (wrong sender pattern)"
  sleep(delay)
  
  # This won't match the admin-prod filter (wrong environment)
  order_msg = OrderMessage.new(
    service_id: "admin-dev",
    message_type: "test_order", 
    order_id: "ORD-TEST",
    customer_id: "TEST-123",
    status: "test",
    environment: "dev"
  )
  order_msg.from('admin-panel')     # Matches /^admin-.*/ pattern  
  order_msg.to('dev-fulfillment')   # Doesn't match /^prod-.*/ pattern
  order_msg.publish
  puts "   ⚠️  This message won't match admin-prod filter (wrong environment)"
  sleep(delay)
  
  puts "\n✨ Message simulation complete!"
end

# Display filter configuration summary
def display_filter_summary
  puts "\n📋 Current Filter Configuration Summary:"
  puts "=" * 50
  
  # Get dispatcher to examine subscriptions
  dispatcher = PaymentMessage.transport.instance_variable_get(:@dispatcher)
  
  dispatcher.subscribers.each do |message_class, subscriptions|
    puts "\n#{message_class}:"
    subscriptions.each_with_index do |sub, index|
      filters = sub[:filters]
      method = sub[:process_method]
      
      puts "  #{index + 1}. #{method}"
      
      if filters[:from]
        from_desc = filters[:from].map do |f|
          f.is_a?(Regexp) ? f.inspect : "'#{f}'"
        end.join(', ')
        puts "     from: [#{from_desc}]"
      end
      
      if filters[:to]
        to_desc = filters[:to].map do |f|
          f.is_a?(Regexp) ? f.inspect : "'#{f}'"
        end.join(', ')
        puts "     to: [#{to_desc}]"
      end
      
      if filters[:broadcast]
        puts "     broadcast: #{filters[:broadcast]}"
      end
    end
  end
  
  puts "\n📊 Message Processing Statistics:"
  puts SS.stat.select { |k, v| k.include?('process') }
end

# Main demonstration
def main
  puts "\nThis example demonstrates SmartMessage's powerful regex filtering capabilities"
  puts "for building sophisticated microservices routing systems.\n"
  
  # Setup
  demonstrate_filtering_patterns
  
  # Wait a moment for subscriptions to be established
  sleep(1)
  
  # Simulate traffic
  simulate_microservice_traffic
  
  # Wait for message processing
  sleep(2)
  
  # Show results
  display_filter_summary
  
  puts "\n" + "=" * 60
  puts "🎉 Regex Filtering Demo Complete!"
  puts "=" * 60
  
  puts "\n💡 Key Takeaways:"
  puts "   • Use regex patterns for flexible service routing"
  puts "   • Combine exact matches with patterns in arrays"
  puts "   • Environment-based routing with regex patterns"
  puts "   • Multi-criteria filtering for complex scenarios"
  puts "   • Broadcast + directed message handling"
  puts "   • Validation prevents invalid filter types"
  puts "\n🔗 See CLAUDE.md and README.md for more filtering examples!"
end

# Handle script execution
if __FILE__ == $0
  begin
    main
  rescue Interrupt
    puts "\n\n👋 Demo interrupted by user"
    exit(0)
  rescue => e
    puts "\n❌ Error: #{e.message}"
    puts e.backtrace.first(5).map { |line| "   #{line}" }
    exit(1)
  end
end