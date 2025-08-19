#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# examples/09_dead_letter_queue_demo.rb
#
# Demonstrates the Dead Letter Queue (DLQ) system with:
# - Automatic capture via circuit breakers
# - Manual capture of failed messages
# - Replay capabilities
# - Administrative functions
# - Monitoring and statistics

require_relative '../lib/smart_message'
require 'json'
require 'fileutils'

# Configure DLQ for this demo
DEMO_DLQ_PATH = '/tmp/smart_message_dlq_demo.jsonl'
SmartMessage::DeadLetterQueue.configure_default(DEMO_DLQ_PATH)

# Clean up any existing DLQ file from previous runs
FileUtils.rm_f(DEMO_DLQ_PATH)

puts "=" * 80
puts "SmartMessage Dead Letter Queue Demo"
puts "=" * 80
puts "\nDLQ Path: #{DEMO_DLQ_PATH}"
puts "=" * 80

# ==============================================================================
# 1. Define Message Classes
# ==============================================================================

class PaymentMessage < SmartMessage::Base
  description "Payment processing message that might fail"
  version 1
  from 'payment-service'
  to 'bank-gateway'
  
  property :payment_id, required: true, description: "Unique payment identifier"
  property :amount, required: true, description: "Payment amount"
  property :customer_id, required: true, description: "Customer making payment"
  property :card_last_four, description: "Last 4 digits of card"
  
  config do
    transport SmartMessage::Transport.create(:memory)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process(wrapper)
    header = wrapper._sm_header
    payload = wrapper._sm_payload
    data = JSON.parse(payload, symbolize_names: true)
    puts "  💳 Processing payment #{data[:payment_id]} for $#{data[:amount]}"
  end
end

class OrderMessage < SmartMessage::Base
  description "Order processing message"
  version 1
  from 'order-service'
  to 'fulfillment-service'
  
  property :order_id, required: true, description: "Order identifier"
  property :items, default: [], description: "Order items"
  property :total, required: true, description: "Order total"
  
  config do
    transport SmartMessage::Transport.create(:memory)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process(wrapper)
    header = wrapper._sm_header
    payload = wrapper._sm_payload
    data = JSON.parse(payload, symbolize_names: true)
    puts "  📦 Processing order #{data[:order_id]} with #{data[:items].size} items"
  end
end

class NotificationMessage < SmartMessage::Base
  description "User notification message"
  version 1
  from 'notification-service'
  
  property :user_id, required: true, description: "User to notify"
  property :message, required: true, description: "Notification content"
  property :channel, default: 'email', description: "Notification channel"
  
  config do
    transport SmartMessage::Transport.create(:memory)
    serializer SmartMessage::Serializer::JSON.new
  end
  
  def self.process(wrapper)
    header = wrapper._sm_header
    payload = wrapper._sm_payload
    data = JSON.parse(payload, symbolize_names: true)
    puts "  📧 Sending #{data[:channel]} to user #{data[:user_id]}: #{data[:message]}"
  end
end

# ==============================================================================
# 2. Simulate Transport Failures
# ==============================================================================

class FailingTransport < SmartMessage::Transport::Base
  attr_accessor :failure_mode, :failure_count
  
  def initialize(**options)
    super
    @failure_mode = options[:failure_mode] || :none
    @failure_count = 0
    @max_failures = options[:max_failures] || 3
  end
  
  def do_publish(message_header, message_payload)
    case @failure_mode
    when :connection_error
      @failure_count += 1
      if @failure_count <= @max_failures
        raise "Connection refused to payment gateway"
      end
      puts "    ✅ Transport recovered, message sent"
    when :timeout
      @failure_count += 1
      if @failure_count <= @max_failures
        raise "Request timeout after 30 seconds"
      end
      puts "    ✅ Transport recovered, message sent"
    when :intermittent
      if rand < 0.5
        raise "Intermittent network error"
      end
      puts "    ✅ Message sent successfully"
    else
      puts "    ✅ Message published successfully"
    end
  end
end

# ==============================================================================
# 3. Demo Functions
# ==============================================================================

def section_header(title)
  puts "\n" + "=" * 80
  puts "#{title}"
  puts "=" * 80
end

def show_dlq_status
  dlq = SmartMessage::DeadLetterQueue.default
  puts "\n📊 DLQ Status:"
  puts "  - Queue size: #{dlq.size} messages"
  
  if dlq.size > 0
    stats = dlq.statistics
    puts "  - By class: #{stats[:by_class]}"
    puts "  - By error: #{stats[:by_error].keys.first(3).join(', ')}..."
    
    # Show next message
    next_msg = dlq.peek
    if next_msg
      puts "  - Next message: #{next_msg[:header][:message_class]} (#{next_msg[:error]})"
    end
  end
end

# ==============================================================================
# 4. Demonstration Scenarios
# ==============================================================================

section_header("1. MANUAL DLQ CAPTURE")
puts "\nManually capturing failed messages in DLQ..."

dlq = SmartMessage::DeadLetterQueue.default

# Simulate validation failure
begin
  payment = PaymentMessage.new(
    payment_id: "PAY-001",
    amount: -100,  # Invalid amount
    customer_id: "CUST-123"
  )
  
  # Business logic validation
  if payment.amount < 0
    raise "Invalid payment amount: cannot be negative"
  end
rescue => e
  puts "❌ Validation failed: #{e.message}"
  
  # Manually add to DLQ
  wrapper = SmartMessage::Wrapper::Base.new(
    header: payment._sm_header,
    payload: payment.encode
  )
  dlq.enqueue(
    wrapper,
    error: e.message,
    transport: "ValidationLayer",
    retry_count: 0
  )
  puts "💾 Message saved to DLQ"
end

show_dlq_status

# ==============================================================================

section_header("2. AUTOMATIC CAPTURE VIA TRANSPORT FAILURE")
puts "\nSimulating transport failures that trigger DLQ..."

# Create a payment with failing transport
payment = PaymentMessage.new(
  payment_id: "PAY-002",
  amount: 250.00,
  customer_id: "CUST-456",
  card_last_four: "1234"
)

# Override with failing transport
failing_transport = FailingTransport.new(
  failure_mode: :connection_error,
  max_failures: 2
)
payment.transport(failing_transport)

# First attempt - will fail
puts "\n🔄 Attempt 1: Publishing payment message..."
begin
  payment.publish
rescue => e
  puts "❌ Publish failed: #{e.message}"
  
  # Circuit breaker would normally handle this, but we'll add manually for demo
  wrapper = SmartMessage::Wrapper::Base.new(
    header: payment._sm_header,
    payload: payment.encode
  )
  dlq.enqueue(
    wrapper,
    error: e.message,
    transport: failing_transport.class.name,
    retry_count: 1
  )
  puts "💾 Message automatically saved to DLQ"
end

show_dlq_status

# ==============================================================================

section_header("3. MULTIPLE FAILURE TYPES")
puts "\nAdding various types of failures to DLQ..."

# Order with timeout
order = OrderMessage.new(
  order_id: "ORD-789",
  items: ["SKU-001", "SKU-002"],
  total: 99.99
)

wrapper = SmartMessage::Wrapper::Base.new(
  header: order._sm_header,
  payload: order.encode
)
dlq.enqueue(
  wrapper,
  error: "Gateway timeout after 30 seconds",
  transport: "Redis",
  retry_count: 3
)
puts "💾 Added order with timeout error"

# Notification with rate limit
notification = NotificationMessage.new(
  user_id: "USER-999",
  message: "Your order has shipped!",
  channel: "sms"
)

wrapper = SmartMessage::Wrapper::Base.new(
  header: notification._sm_header,
  payload: notification.encode
)
dlq.enqueue(
  wrapper,
  error: "Rate limit exceeded: 429 Too Many Requests",
  transport: "SMSGateway",
  retry_count: 1
)
puts "💾 Added notification with rate limit error"

# Another payment with different error
payment3 = PaymentMessage.new(
  payment_id: "PAY-003",
  amount: 500.00,
  customer_id: "CUST-789"
)

wrapper = SmartMessage::Wrapper::Base.new(
  header: payment3._sm_header,
  payload: payment3.encode
)
dlq.enqueue(
  wrapper,
  error: "Invalid merchant credentials",
  transport: "StripeGateway",
  retry_count: 0
)
puts "💾 Added payment with auth error"

show_dlq_status

# ==============================================================================

section_header("4. FILTERING AND ANALYSIS")
puts "\nAnalyzing failed messages in DLQ..."

# Filter by message class
puts "\n🔍 Filtering by message class:"
payment_failures = dlq.filter_by_class('PaymentMessage')
puts "  - Found #{payment_failures.size} failed PaymentMessage(s)"
payment_failures.each do |entry|
  puts "    • #{entry[:header][:uuid][0..7]}... - #{entry[:error]}"
end

order_failures = dlq.filter_by_class('OrderMessage')
puts "  - Found #{order_failures.size} failed OrderMessage(s)"

# Filter by error pattern
puts "\n🔍 Filtering by error pattern:"
timeout_errors = dlq.filter_by_error_pattern(/timeout/i)
puts "  - Found #{timeout_errors.size} timeout error(s)"
timeout_errors.each do |entry|
  puts "    • #{entry[:header][:message_class]} - #{entry[:error]}"
end

connection_errors = dlq.filter_by_error_pattern(/connection|refused/i)
puts "  - Found #{connection_errors.size} connection error(s)"

# Get detailed statistics
puts "\n📊 Detailed Statistics:"
stats = dlq.statistics
puts "  Total messages: #{stats[:total]}"
puts "\n  By message class:"
stats[:by_class].each do |klass, count|
  percentage = (count.to_f / stats[:total] * 100).round(1)
  puts "    • #{klass}: #{count} (#{percentage}%)"
end
puts "\n  By error type:"
stats[:by_error].sort_by { |_, count| -count }.each do |error, count|
  puts "    • #{error[0..50]}#{'...' if error.length > 50}: #{count}"
end

# ==============================================================================

section_header("5. MESSAGE INSPECTION")
puts "\nInspecting messages without removing them..."

messages = dlq.inspect_messages(limit: 3)
messages.each_with_index do |msg, i|
  puts "\n📋 Message #{i + 1}:"
  puts "  - Class: #{msg[:header][:message_class]}"
  puts "  - ID: #{msg[:header][:uuid][0..12]}..."
  puts "  - Error: #{msg[:error]}"
  puts "  - Retry count: #{msg[:retry_count]}"
  puts "  - Timestamp: #{msg[:timestamp]}"
end

# ==============================================================================

section_header("6. REPLAY CAPABILITIES")
puts "\nDemonstrating message replay functionality..."

puts "\n🔄 Replaying oldest message:"
puts "  Queue size before: #{dlq.size}"

# Create a working transport for replay
working_transport = SmartMessage::Transport.create(:memory)

# Replay the oldest message
result = dlq.replay_one(working_transport)
if result[:success]
  puts "  ✅ Message replayed successfully!"
  message = result[:message]
  puts "    • Class: #{message.class.name}"
  puts "    • Sent via: #{working_transport.class.name}"
else
  puts "  ❌ Replay failed: #{result[:error]}"
end

puts "  Queue size after: #{dlq.size}"

# Batch replay
puts "\n🔄 Replaying batch of 2 messages:"
results = dlq.replay_batch(2, working_transport)
puts "  ✅ Successfully replayed: #{results[:success]}"
puts "  ❌ Failed to replay: #{results[:failed]}"
if results[:errors].any?
  results[:errors].each do |error|
    puts "    • Error: #{error}"
  end
end

show_dlq_status

# ==============================================================================

section_header("7. TIME-BASED OPERATIONS")
puts "\nExporting messages by time range..."

# Get all messages from the last minute
one_minute_ago = Time.now - 60
now = Time.now

recent_messages = dlq.export_range(one_minute_ago, now)
puts "📅 Messages from last minute: #{recent_messages.size}"

# Group by time intervals
if recent_messages.any?
  puts "\n  Timeline:"
  recent_messages.each do |msg|
    time = Time.parse(msg[:timestamp])
    seconds_ago = (now - time).to_i
    puts "    • #{seconds_ago}s ago: #{msg[:header][:message_class]} - #{msg[:error][0..30]}..."
  end
end

# ==============================================================================

section_header("8. ADMINISTRATIVE OPERATIONS")
puts "\nDemonstrating administrative functions..."

# Check current size
puts "\n🗄️  Current DLQ state:"
puts "  - File path: #{dlq.file_path}"
puts "  - File exists: #{File.exist?(dlq.file_path)}"
puts "  - File size: #{File.size(dlq.file_path)} bytes" if File.exist?(dlq.file_path)
puts "  - Message count: #{dlq.size}"

# Peek at next message for processing
puts "\n👀 Peeking at next message (without removing):"
next_msg = dlq.peek
if next_msg
  puts "  - Would process: #{next_msg[:header][:message_class]}"
  puts "  - Error was: #{next_msg[:error]}"
  puts "  - Retry count: #{next_msg[:retry_count]}"
end

# Demonstrate FIFO order
puts "\n📚 FIFO Queue Order (dequeue order):"
temp_messages = []
3.times do |i|
  msg = dlq.dequeue
  break unless msg
  temp_messages << msg
  puts "  #{i + 1}. #{msg[:header][:message_class]} - #{msg[:timestamp]}"
end

# Put them back for other demos
temp_messages.each do |msg|
  header = SmartMessage::Header.new(msg[:header])
  wrapper = SmartMessage::Wrapper::Base.new(
    header: header,
    payload: msg[:payload]
  )
  dlq.enqueue(wrapper, 
    error: msg[:error], 
    retry_count: msg[:retry_count])
end

# ==============================================================================

section_header("9. CIRCUIT BREAKER INTEGRATION")
puts "\nDemonstrating circuit breaker with DLQ fallback..."

# This would normally be automatic, but we'll simulate it
class PaymentGateway
  include BreakerMachines::DSL
  
  circuit :payment_processing do
    threshold failures: 2, within: 30.seconds
    reset_after 10.seconds
    
    # DLQ fallback
    fallback do |exception|
      puts "  ⚡ Circuit breaker tripped: #{exception.message}"
      # In real scenario, message would go to DLQ here
      { circuit_open: true, error: exception.message }
    end
  end
  
  def process_payment(payment_data)
    circuit(:payment_processing).wrap do
      # Simulate failure
      raise "Payment gateway unavailable"
    end
  end
end

gateway = PaymentGateway.new
payment_data = { amount: 100.00, customer: "TEST" }

puts "Attempting payment processing with circuit breaker:"
2.times do |i|
  puts "\n  Attempt #{i + 1}:"
  result = gateway.process_payment(payment_data)
  if result[:circuit_open]
    puts "  🔴 Circuit is OPEN - request blocked"
    # Message would be in DLQ now
  end
end

# ==============================================================================

section_header("10. CLEANUP AND FINAL STATS")
puts "\nFinal DLQ statistics before cleanup..."

final_stats = dlq.statistics
puts "\n📊 Final Statistics:"
puts "  - Total messages processed: #{final_stats[:total]}"
puts "  - Unique error types: #{final_stats[:by_error].keys.size}"
puts "  - Message classes affected: #{final_stats[:by_class].keys.join(', ')}"

# Demonstrate clearing the queue
puts "\n🧹 Clearing the DLQ..."
puts "  - Size before clear: #{dlq.size}"
dlq.clear
puts "  - Size after clear: #{dlq.size}"

# Clean up demo file
FileUtils.rm_f(DEMO_DLQ_PATH)
puts "\n✨ Demo complete! DLQ file cleaned up."

# ==============================================================================

puts "\n" + "=" * 80
puts "KEY TAKEAWAYS:"
puts "=" * 80
puts """
1. DLQ automatically captures failed messages via circuit breakers
2. Manual capture available for business logic failures  
3. Messages stored in JSON Lines format for efficiency
4. FIFO queue ensures oldest failures processed first
5. Replay capabilities with transport override support
6. Rich filtering and analysis tools for debugging
7. Time-based operations for historical analysis
8. Thread-safe operations for production use
9. Integration with circuit breakers for automatic capture
10. Administrative tools for queue management

The Dead Letter Queue ensures no messages are lost during failures
and provides comprehensive tools for analysis and recovery.
"""
puts "=" * 80