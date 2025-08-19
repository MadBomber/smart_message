#!/usr/bin/env ruby
# examples/08_entity_addressing.rb
#
# Demonstrates SmartMessage entity addressing capabilities including:
# - Point-to-point messaging with FROM/TO fields
# - Broadcast messaging (no TO field)
# - Request-reply patterns with REPLY_TO
# - Instance-level addressing overrides
# - Gateway patterns

require_relative '../lib/smart_message'

puts "🎯 SmartMessage Entity Addressing Demo"
puts "=" * 50

# Configure transport for demo
transport = SmartMessage::Transport.create(:stdout, loopback: true)
serializer = SmartMessage::Serializer::JSON.new

# =============================================================================
# Example 1: Point-to-Point Messaging
# =============================================================================

puts "\n📡 Example 1: Point-to-Point Messaging"
puts "-" * 40

class OrderMessage < SmartMessage::Base
  version 1
  description "Direct order processing between order service and fulfillment"
  
  # Point-to-point addressing
  from 'order-service'
  to 'fulfillment-service'
  reply_to 'order-service'
  
  property :order_id, required: true
  property :customer_id, required: true
  property :items, required: true
  property :total_amount, required: true
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process(header, payload)
    data = JSON.parse(payload)
    puts "   🎯 FULFILLMENT SERVICE received order:"
    puts "      Order ID: #{data['order_id']}"
    puts "      From: #{header.from} → To: #{header.to}"
    puts "      Reply to: #{header.reply_to}"
    puts "      Customer: #{data['customer_id']}"
    puts "      Items: #{data['items'].join(', ')}"
    puts "      Total: $#{data['total_amount']}"
  end
end

# Subscribe and publish point-to-point message
OrderMessage.subscribe

order = OrderMessage.new(
  order_id: "ORD-2024-001",
  customer_id: "CUST-12345",
  items: ["Widget A", "Widget B", "Gadget C"],
  total_amount: 299.99
)

puts "\n📤 Publishing point-to-point order message..."
order.publish
sleep(0.2)  # Allow time for handlers to process

# =============================================================================
# Example 2: Broadcast Messaging
# =============================================================================

puts "\n📻 Example 2: Broadcast Messaging"
puts "-" * 40

class SystemAnnouncementMessage < SmartMessage::Base
  version 1
  description "System-wide announcements to all services"
  
  # Broadcast addressing (no 'to' field)
  from 'admin-service'
  # No 'to' field = broadcast to all subscribers
  
  property :message, required: true
  property :priority, default: 'normal'
  property :effective_time, required: true
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process(header, payload)
    data = JSON.parse(payload)
    priority_icon = data['priority'] == 'high' ? '🚨' : '📢'
    puts "   #{priority_icon} ALL SERVICES received announcement:"
    puts "      From: #{header.from}"
    puts "      To: #{header.to.nil? ? 'ALL (broadcast)' : header.to}"
    puts "      Priority: #{data['priority'].upcase}"
    puts "      Message: #{data['message']}"
    puts "      Effective: #{data['effective_time']}"
  end
end

# Subscribe and publish broadcast message
SystemAnnouncementMessage.subscribe

announcement = SystemAnnouncementMessage.new(
  message: "System maintenance scheduled for tonight at 2:00 AM EST",
  priority: 'high',
  effective_time: '2024-12-20 02:00:00 EST'
)

puts "\n📤 Publishing broadcast announcement..."
announcement.publish
sleep(0.2)  # Allow time for handlers to process

# =============================================================================
# Example 3: Request-Reply Pattern
# =============================================================================

puts "\n🔄 Example 3: Request-Reply Pattern"
puts "-" * 40

class UserLookupRequest < SmartMessage::Base
  version 1
  description "Request user information from user service"
  
  from 'web-service'
  to 'user-service'
  reply_to 'web-service'
  
  property :user_id, required: true
  property :request_id, required: true
  property :requested_fields, default: ['name', 'email']
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process(header, payload)
    data = JSON.parse(payload)
    puts "   🔍 USER SERVICE received lookup request:"
    puts "      Request ID: #{data['request_id']}"
    puts "      User ID: #{data['user_id']}"
    puts "      From: #{header.from} → To: #{header.to}"
    puts "      Reply to: #{header.reply_to}"
    puts "      Fields: #{data['requested_fields'].join(', ')}"
    
    # Simulate response (in real system, this would be a separate response message)
    puts "   ↩️  Simulated response would go to: #{header.reply_to}"
  end
end

class UserLookupResponse < SmartMessage::Base
  version 1
  description "Response with user information"
  
  from 'user-service'
  # 'to' will be set to the original request's 'reply_to'
  
  property :user_id, required: true
  property :request_id, required: true
  property :user_data
  property :success, default: true
  property :error_message
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process(header, payload)
    data = JSON.parse(payload)
    puts "   ✅ WEB SERVICE received lookup response:"
    puts "      Request ID: #{data['request_id']}"
    puts "      Success: #{data['success']}"
    puts "      User Data: #{data['user_data'] ? 'Present' : 'None'}"
    puts "      From: #{header.from} → To: #{header.to}"
  end
end

# Subscribe to both request and response
UserLookupRequest.subscribe
UserLookupResponse.subscribe

# Send request
request = UserLookupRequest.new(
  user_id: "USER-789",
  request_id: SecureRandom.uuid,
  requested_fields: ['name', 'email', 'last_login']
)

puts "\n📤 Publishing user lookup request..."
request.publish
sleep(0.2)  # Allow time for handlers to process

# Send simulated response
response = UserLookupResponse.new(
  user_id: "USER-789",
  request_id: request.request_id,
  user_data: {
    name: "Alice Johnson",
    email: "alice@example.com",
    last_login: "2024-12-19 14:30:00"
  },
  success: true
)
response.to('web-service')  # Set reply destination

puts "\n📤 Publishing user lookup response..."
response.publish
sleep(0.2)  # Allow time for handlers to process

# =============================================================================
# Example 4: Instance-Level Addressing Override
# =============================================================================

puts "\n🔧 Example 4: Instance-Level Addressing Override"
puts "-" * 40

class PaymentMessage < SmartMessage::Base
  version 1
  description "Payment processing with configurable routing"
  
  # Default addressing
  from 'payment-service'
  to 'primary-bank-gateway'
  reply_to 'payment-service'
  
  property :payment_id, required: true
  property :amount, required: true
  property :account_id, required: true
  property :payment_method, default: 'credit_card'
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process(header, payload)
    data = JSON.parse(payload)
    gateway_icon = header.to.include?('backup') ? '🔄' : '🏦'
    puts "   #{gateway_icon} #{header.to.upcase} received payment:"
    puts "      Payment ID: #{data['payment_id']}"
    puts "      From: #{header.from} → To: #{header.to}"
    puts "      Amount: $#{data['amount']}"
    puts "      Account: #{data['account_id']}"
    puts "      Method: #{data['payment_method']}"
  end
end

PaymentMessage.subscribe

# Normal payment using class defaults
normal_payment = PaymentMessage.new(
  payment_id: "PAY-001",
  amount: 150.00,
  account_id: "ACCT-12345",
  payment_method: 'credit_card'
)

puts "\n📤 Publishing normal payment (using class defaults)..."
puts "   Class FROM: #{PaymentMessage.from}"
puts "   Class TO: #{PaymentMessage.to}"
normal_payment.publish
sleep(0.2)  # Allow time for handlers to process

# Override addressing for backup gateway
backup_payment = PaymentMessage.new(
  payment_id: "PAY-002",
  amount: 75.50,
  account_id: "ACCT-67890",
  payment_method: 'debit_card'
)

# Override instance addressing
backup_payment.to('backup-bank-gateway')
backup_payment.reply_to('payment-backup-service')

puts "\n📤 Publishing backup payment (with overrides)..."
puts "   Instance FROM: #{backup_payment.from}"
puts "   Instance TO: #{backup_payment.to}"
puts "   Instance REPLY_TO: #{backup_payment.reply_to}"
backup_payment.publish
sleep(0.2)  # Allow time for handlers to process

# =============================================================================
# Example 5: Gateway Pattern
# =============================================================================

puts "\n🌉 Example 5: Gateway Pattern"
puts "-" * 40

class ExternalAPIMessage < SmartMessage::Base
  version 1
  description "External API integration message"
  
  from 'api-gateway'
  to 'external-partner-service'
  
  property :api_call, required: true
  property :payload_data, required: true
  property :authentication_token
  property :partner_id, required: true
  
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process(header, payload)
    data = JSON.parse(payload)
    puts "   🌐 EXTERNAL PARTNER received API call:"
    puts "      API Call: #{data['api_call']}"
    puts "      From: #{header.from} → To: #{header.to}"
    puts "      Partner ID: #{data['partner_id']}"
    puts "      Has Auth Token: #{data['authentication_token'] ? 'Yes' : 'No'}"
    puts "      Payload Size: #{data['payload_data'].to_s.length} characters"
  end
end

ExternalAPIMessage.subscribe

# Create internal message
internal_data = {
  user_id: "USER-123",
  action: "update_profile",
  changes: { email: "newemail@example.com" }
}

# Transform for external API via gateway
external_message = ExternalAPIMessage.new(
  api_call: "PUT /api/v1/users/USER-123",
  payload_data: internal_data,
  authentication_token: "Bearer abc123xyz789",
  partner_id: "PARTNER-ALPHA"
)

# Gateway can override destination based on routing rules
if internal_data[:action] == "update_profile"
  external_message.to('partner-alpha-profile-service')
else
  external_message.to('partner-alpha-general-service')
end

puts "\n📤 Publishing external API message via gateway..."
external_message.publish
sleep(0.2)  # Allow time for handlers to process

# =============================================================================
# Summary
# =============================================================================

puts "\n🎯 Entity Addressing Summary"
puts "=" * 50
puts "✅ Point-to-Point: FROM/TO specified for direct routing"
puts "✅ Broadcast: FROM only, TO=nil for all subscribers"
puts "✅ Request-Reply: REPLY_TO for response routing"
puts "✅ Instance Override: Runtime addressing changes"
puts "✅ Gateway Pattern: Message transformation and routing"
puts "\nFor more details, see docs/addressing.md"