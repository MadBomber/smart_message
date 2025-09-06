#!/usr/bin/env ruby
# examples/redis_queue/01_basic_messaging.rb
# Basic Redis Queue Transport messaging demonstration

require_relative '../../lib/smart_message'
require 'async'

puts "🚀 Redis Queue Transport - Basic Messaging Demo"
puts "=" * 50

# Configure SmartMessage to use Redis Queue transport
SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    url: 'redis://localhost:6379',
    db: 1,  # Use database 1 for examples
    queue_prefix: 'demo_queue',
    exchange_name: 'smart_message',
    test_mode: false  # Enable consumer tasks for real processing
  }
end

#==============================================================================
# Define Message Classes
#==============================================================================

class WelcomeMessage < SmartMessage::Base
  transport :redis_queue
  
  property :user_name, required: true
  property :email
  property :signup_date, default: -> { Time.now.strftime('%Y-%m-%d %H:%M:%S') }
  
  def process
    puts "👋 Welcome #{user_name}! (#{email}) - Signed up: #{signup_date}"
    puts "   Message processed at: #{Time.now.strftime('%H:%M:%S.%L')}"
  end
end

class OrderNotification < SmartMessage::Base
  transport :redis_queue
  
  property :order_id, required: true
  property :customer_name, required: true
  property :total_amount, required: true
  property :status, default: 'pending'
  
  def process
    puts "📦 Order #{order_id}: $#{total_amount} for #{customer_name} [#{status}]"
    puts "   Order processed at: #{Time.now.strftime('%H:%M:%S.%L')}"
  end
end

class SystemAlert < SmartMessage::Base
  transport :redis_queue
  
  property :alert_type, required: true
  property :message, required: true
  property :severity, default: 'info'
  property :timestamp, default: -> { Time.now }
  
  def process
    icon = case severity
           when 'critical' then '🚨'
           when 'warning' then '⚠️'
           when 'info' then 'ℹ️'
           else '📢'
           end
    
    puts "#{icon} [#{alert_type.upcase}] #{message}"
    puts "   Severity: #{severity} - Time: #{timestamp.strftime('%H:%M:%S')}"
  end
end

#==============================================================================
# Basic Publishing and Subscription Demo
#==============================================================================

Async do
  puts "\n📤 Publishing Messages..."

  # Subscribe to all message types
  puts "Setting up subscribers..."
  WelcomeMessage.subscribe
  OrderNotification.subscribe  
  SystemAlert.subscribe

  # Wait for subscribers to initialize
  sleep 0.5

# Publish welcome messages
puts "\n1️⃣ Publishing Welcome Messages:"
welcome1 = WelcomeMessage.new(
  user_name: 'Alice Johnson',
  email: 'alice@example.com'
)
welcome1.publish

welcome2 = WelcomeMessage.new(
  user_name: 'Bob Smith', 
  email: 'bob@example.com'
)
welcome2.publish

# Publish order notifications
puts "\n2️⃣ Publishing Order Notifications:"
order1 = OrderNotification.new(
  order_id: 'ORD-001',
  customer_name: 'Alice Johnson',
  total_amount: 149.99,
  status: 'confirmed'
)
order1.publish

order2 = OrderNotification.new(
  order_id: 'ORD-002',
  customer_name: 'Bob Smith',
  total_amount: 89.50,
  status: 'processing'
)
order2.publish

# Publish system alerts
puts "\n3️⃣ Publishing System Alerts:"
alert1 = SystemAlert.new(
  alert_type: 'database',
  message: 'Database connection restored after brief outage',
  severity: 'info'
)
alert1.publish

alert2 = SystemAlert.new(
  alert_type: 'security',
  message: 'Multiple failed login attempts detected',
  severity: 'warning'
)
alert2.publish

alert3 = SystemAlert.new(
  alert_type: 'system',
  message: 'Critical: Disk usage above 95%',
  severity: 'critical'
)
alert3.publish

  # Wait for message processing
  puts "\n⏳ Processing messages..."
  sleep 3

  #============================================================================
  # Message Statistics
  #============================================================================

  puts "\n📊 Message Statistics:"

  # Get transport instance for statistics
  transport = SmartMessage::Transport::RedisQueueTransport.new(
    url: 'redis://localhost:6379',
    db: 1,
    queue_prefix: 'demo_queue',
    exchange_name: 'smart_message',
    test_mode: true  # Statistics only, no consumers
  )

  # Show queue statistics
  stats = transport.queue_stats
  if stats.any?
    stats.each do |queue_name, info|
      puts "  Queue: #{queue_name}"
      puts "    Length: #{info[:length]} messages"
      puts "    Pattern: #{info[:pattern] || 'N/A'}"
      puts "    Consumers: #{info[:consumers] || 0}"
      puts ""
    end
  else
    puts "  No queues found (all messages processed successfully)"
  end

  transport.disconnect

  #============================================================================
  # Performance Demonstration
  #============================================================================

  puts "\n🏃‍♀️ Performance Test - Publishing 100 messages rapidly:"

  start_time = Time.now

  100.times do |i|
    message = SystemAlert.new(
      alert_type: 'performance_test',
      message: "Performance test message ##{i + 1}",
      severity: 'info'
    )
    message.publish
  end

  end_time = Time.now
  duration = end_time - start_time

  puts "✅ Published 100 messages in #{duration.round(3)} seconds"
  puts "   Rate: #{(100 / duration).round(1)} messages/second"

  # Wait for processing
  sleep 2
end

puts "\n🎯 Basic messaging demonstration completed!"
puts "   ✓ Published welcome messages"
puts "   ✓ Published order notifications" 
puts "   ✓ Published system alerts"
puts "   ✓ Demonstrated high-throughput publishing"
puts "   ✓ All messages processed via Redis Queue transport"

puts "\n💡 Key Features Demonstrated:"
puts "   • Simple pub/sub messaging with Async framework"
puts "   • Automatic message serialization"
puts "   • Queue-based reliable delivery"
puts "   • Multiple message types"
puts "   • High-performance publishing"
puts "   • Fiber-based concurrency for scalable processing"