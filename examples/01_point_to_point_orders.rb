#!/usr/bin/env ruby
# examples/01_point_to_point_orders.rb
#
# 1-to-1 Messaging Example: Order Processing System
# 
# This example demonstrates point-to-point messaging between an OrderService
# and a PaymentService. Each order gets processed by exactly one payment processor.

require_relative '../lib/smart_message'

puts "=== SmartMessage Example: Point-to-Point Order Processing ==="
puts

# Define the Order Message
class OrderMessage < SmartMessage::Base
  description "Represents customer orders for processing through the payment system"
  
  property :order_id, 
    description: "Unique identifier for the order (e.g., ORD-1001)"
  property :customer_id, 
    description: "Unique identifier for the customer placing the order"
  property :amount, 
    description: "Total order amount in decimal format (e.g., 99.99)"
  property :currency, 
    default: 'USD',
    description: "ISO currency code for the order (defaults to USD)"
  property :payment_method, 
    description: "Payment method selected by customer (credit_card, debit_card, paypal, etc.)"
  property :items, 
    description: "Array of item names or descriptions included in the order"

  # Configure to use memory transport for this example
  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end

  # Default processing - just logs the order
  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    order_data = JSON.parse(message_payload)
    puts "📋 Order received: #{order_data['order_id']} for $#{order_data['amount']}"
  end
end

# Define the Payment Response Message  
class PaymentResponseMessage < SmartMessage::Base
  description "Contains payment processing results sent back to the order system"
  
  property :order_id, 
    description: "Reference to the original order being processed"
  property :payment_id, 
    description: "Unique identifier for the payment transaction (e.g., PAY-5001)"
  property :status, 
    description: "Payment processing status: 'success', 'failed', or 'pending'"
  property :message, 
    description: "Human-readable description of the payment result"
  property :processed_at, 
    description: "ISO8601 timestamp when the payment was processed"

  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end

  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    response_data = JSON.parse(message_payload)
    status_emoji = case response_data['status']
                   when 'success' then '✅'
                   when 'failed' then '❌'
                   when 'pending' then '⏳'
                   else '❓'
                   end
    
    puts "#{status_emoji} Payment #{response_data['status']}: Order #{response_data['order_id']} - #{response_data['message']}"
  end
end

# Order Service - Creates and sends orders
class OrderService
  def initialize
    puts "🏪 OrderService: Starting up..."
    @order_counter = 1000
  end

  def create_order(customer_id:, amount:, payment_method:, items:)
    order_id = "ORD-#{@order_counter += 1}"
    
    puts "\n🏪 OrderService: Creating order #{order_id}"
    
    order = OrderMessage.new(
      order_id: order_id,
      customer_id: customer_id,
      amount: amount,
      payment_method: payment_method,
      items: items,
      from: 'OrderService'
    )
    
    puts "🏪 OrderService: Sending order to payment processing..."
    order.publish
    
    order_id
  end
end

# Payment Service - Processes orders and sends responses
class PaymentService
  def initialize
    puts "💳 PaymentService: Starting up..."
    @payment_counter = 5000
    
    # Subscribe to order messages with custom processor
    OrderMessage.subscribe('PaymentService.process_order')
  end

  def self.process_order(wrapper)
    processor = new
    processor.handle_order(wrapper)
  end

  def handle_order(wrapper)
    message_header, message_payload = wrapper.split
    order_data = JSON.parse(message_payload)
    payment_id = "PAY-#{@payment_counter += 1}"
    
    puts "💳 PaymentService: Processing payment for order #{order_data['order_id']}"
    
    # Simulate payment processing logic
    success = simulate_payment_processing(order_data)
    
    # Send response back
    response = PaymentResponseMessage.new(
      order_id: order_data['order_id'],
      payment_id: payment_id,
      status: success ? 'success' : 'failed',
      message: success ? 'Payment processed successfully' : 'Insufficient funds',
      processed_at: Time.now.iso8601,
      from: 'PaymentService'
    )
    
    puts "💳 PaymentService: Sending payment response..."
    response.publish
  end

  private

  def simulate_payment_processing(order_data)
    # Simulate processing time
    sleep(0.1)
    
    # Simulate success/failure based on amount (fail large orders for demo)
    order_data['amount'] < 1000
  end
end

# Demo Runner
class OrderProcessingDemo
  def run
    puts "🚀 Starting Order Processing Demo\n"
    
    # Start services
    order_service = OrderService.new
    payment_service = PaymentService.new
    
    # Subscribe to payment responses
    PaymentResponseMessage.subscribe
    
    puts "\n" + "="*60
    puts "Processing Sample Orders"
    puts "="*60
    
    # Create some sample orders
    orders = [
      {
        customer_id: "CUST-001",
        amount: 99.99,
        payment_method: "credit_card",
        items: ["Widget A", "Widget B"]
      },
      {
        customer_id: "CUST-002", 
        amount: 1299.99,  # This will fail (too large)
        payment_method: "debit_card",
        items: ["Premium Widget", "Extended Warranty"]
      },
      {
        customer_id: "CUST-003",
        amount: 45.50,
        payment_method: "paypal",
        items: ["Small Widget"]
      }
    ]

    orders.each_with_index do |order_params, index|
      puts "\n--- Order #{index + 1} ---"
      order_id = order_service.create_order(**order_params)
      
      # Brief pause between orders for clarity
      sleep(0.5)
    end
    
    # Give time for all async processing to complete
    puts "\n⏳ Waiting for all payments to process..."
    sleep(2)
    
    puts "\n✨ Demo completed!"
    puts "\nThis example demonstrated:"
    puts "• Point-to-point messaging between OrderService and PaymentService"
    puts "• Bidirectional communication with request/response pattern"
    puts "• JSON serialization of complex message data"
    puts "• STDOUT transport with loopback for local demonstration"
  end
end

# Run the demo if this file is executed directly
if __FILE__ == $0
  demo = OrderProcessingDemo.new
  demo.run
end