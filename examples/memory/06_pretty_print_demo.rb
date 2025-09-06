#!/usr/bin/env ruby
# show_me.rb - Demonstrates the pretty_print method on SmartMessage instances

require_relative '../../lib/smart_message'

# Define a sample order message
class OrderMessage < SmartMessage::Base
  version 1
  description "A message representing an e-commerce order"

  from 'e-commerce-api'
  to 'order-processor'

  property :order_id, required: true
  property :customer_name, required: true
  property :customer_email
  property :items, required: true
  property :total_amount, required: true
  property :shipping_address
  property :payment_info
  property :order_date
end

# Define a sample user notification message
class UserNotificationMessage < SmartMessage::Base
  version 2
  description "A notification message for users"

  from 'notification-service'
  to 'user-app'

  property :user_id, required: true
  property :notification_type, required: true
  property :title, required: true
  property :message_body, required: true
  property :metadata
  property :priority
  property :expires_at
end

puts "=" * 60
puts "SmartMessage pretty_print Method Demonstration"
puts "=" * 60

# Create an order message with complex nested data
puts "\n1. Order Message Example:"
puts "-" * 30

order = OrderMessage.new(
  order_id: "ORD-2024-001",
  customer_name: "Jane Smith",
  customer_email: "jane.smith@example.com",
  items: [
    {
      product_id: "PROD-123",
      name: "Wireless Headphones",
      quantity: 2,
      unit_price: 99.99,
      subtotal: 199.98
    },
    {
      product_id: "PROD-456",
      name: "Phone Case",
      quantity: 1,
      unit_price: 24.99,
      subtotal: 24.99
    }
  ],
  total_amount: 224.97,
  shipping_address: {
    street: "123 Main St",
    city: "Anytown",
    state: "CA",
    zip: "90210",
    country: "USA"
  },
  payment_info: {
    method: "credit_card",
    last_four: "1234",
    status: "authorized"
  },
  order_date: Time.now
)

puts ">"*22
ap order.to_h
puts "<"*22

order.pretty_print

# Create a user notification message
puts "\n\n2. User Notification Message Example:"
puts "-" * 40

notification = UserNotificationMessage.new(
  user_id: "user_789",
  notification_type: "order_update",
  title: "Your Order Has Shipped!",
  message_body: "Great news! Your order #ORD-2024-001 has been shipped and is on its way.",
  metadata: {
    tracking_number: "1Z999AA1234567890",
    carrier: "UPS",
    estimated_delivery: "2024-08-21",
    order_id: "ORD-2024-001",
    push_notification: true,
    email_notification: true
  },
  priority: "high",
  expires_at: Time.now + (7 * 24 * 60 * 60) # 7 days from now
)

notification.pretty_print

# Create a simple message to show minimal data
puts "\n\n3. Simple Message Example (Content Only):"
puts "-" * 40

class SimpleMessage < SmartMessage::Base
  from 'greeting-service'
  
  property :greeting, required: true
  property :recipient
end

simple = SimpleMessage.new(
  greeting: "Hello, World!",
  recipient: "Everyone"
)

simple.pretty_print

puts "\n\n4. Message with Header Information:"
puts "-" * 40
puts "Using pretty_print(include_header: true) to show both header and content:\n"

simple.pretty_print(include_header: true)

puts "\n" + "=" * 60
puts "Demonstration Complete!"
puts "=" * 60
puts "\nThe pretty_print method has two modes:"
puts "• pretty_print() - Shows only message content (default)"
puts "• pretty_print(include_header: true) - Shows header + content"
puts "\nThis filters out internal SmartMessage properties and presents"
puts "the data in a beautifully formatted, readable way using amazing_print."
