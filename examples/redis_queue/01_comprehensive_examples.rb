#!/usr/bin/env ruby
# examples/redis_queue_transport_examples.rb
# Usage examples for RedisQueueTransport

require_relative '../../lib/smart_message'

# Configure Redis Queue transport
SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    url: 'redis://localhost:6379',
    db: 0,
    consumer_group: 'example_workers'
  }
end

#==============================================================================
# Example 1: Basic Message Publishing and Subscription
#==============================================================================

class WelcomeMessage < SmartMessage::Base
  transport :redis_queue
  
  property :user_name, required: true
  property :signup_date, default: -> { Time.now }
  
  def process
    puts "👋 Welcome #{user_name}! Account created on #{signup_date}"
  end
end

puts "=== Example 1: Basic Usage ==="

# Subscribe to process welcome messages
WelcomeMessage.subscribe

# Publish a welcome message
WelcomeMessage.new(
  user_name: 'Alice',
  _sm_header: { 
    from: 'signup_service',
    to: 'welcome_service' 
  }
).publish

sleep 2

#==============================================================================
# Example 2: Pattern-Based Subscriptions
#==============================================================================

class OrderMessage < SmartMessage::Base
  transport :redis_queue
  
  property :order_id, required: true
  property :amount, required: true
  property :customer_id, required: true
  
  def process
    puts "📦 Processing order #{order_id}: $#{amount} for customer #{customer_id}"
  end
end

puts "\n=== Example 2: Pattern Subscriptions ==="

# Get transport instance for pattern subscriptions
transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  consumer_group: 'order_processors'
)

# Subscribe to orders directed to fulfillment service
transport.subscribe_pattern("#.*.fulfillment_service") do |message_class, message_data|
  message = JSON.parse(message_data)
  puts "🏭 Fulfillment received: #{message_class} - #{message['order_id']}"
end

# Subscribe to orders from API gateway
transport.subscribe_pattern("#.api_gateway.*") do |message_class, message_data|
  message = JSON.parse(message_data) 
  puts "🌐 API Gateway order: #{message_class} - #{message['order_id']}"
end

# Subscribe to all order messages regardless of routing
transport.subscribe_pattern("order.#.*.*") do |message_class, message_data|
  message = JSON.parse(message_data)
  puts "📋 Order audit log: #{message['order_id']} - $#{message['amount']}"
end

# Publish orders with different routing
OrderMessage.new(
  order_id: 'ORD-001',
  amount: 99.99,
  customer_id: 'CUST-123',
  _sm_header: {
    from: 'api_gateway',
    to: 'fulfillment_service'
  }
).publish

OrderMessage.new(
  order_id: 'ORD-002', 
  amount: 149.50,
  customer_id: 'CUST-456',
  _sm_header: {
    from: 'mobile_app',
    to: 'fulfillment_service'
  }
).publish

sleep 3

#==============================================================================
# Example 3: Fluent API Usage
#==============================================================================

class NotificationMessage < SmartMessage::Base
  transport :redis_queue
  
  property :message_text, required: true
  property :priority, default: 'normal'
  property :user_id
  
  def process
    puts "🔔 Notification [#{priority}]: #{message_text}"
  end
end

puts "\n=== Example 3: Fluent API ==="

# Set up transport for fluent examples
notification_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  consumer_group: 'notification_workers'
)

# Subscribe to notifications for specific user
notification_transport.where
  .type('NotificationMessage')
  .to('user_123')
  .consumer_group('user_notifications')
  .subscribe do |message_class, message_data|
    message = JSON.parse(message_data)
    puts "👤 Personal notification for user_123: #{message['message_text']}"
  end

# Subscribe to high priority notifications from admin
notification_transport.where
  .from('admin_service')
  .subscribe do |message_class, message_data|
    message = JSON.parse(message_data)
    puts "⚠️  Admin notification: #{message['message_text']}"
  end

# Publish various notifications
NotificationMessage.new(
  message_text: "Your order has shipped!",
  priority: 'high',
  user_id: 'user_123',
  _sm_header: {
    from: 'shipping_service',
    to: 'user_123'
  }
).publish

NotificationMessage.new(
  message_text: "System maintenance scheduled for tonight",
  priority: 'urgent', 
  _sm_header: {
    from: 'admin_service',
    to: 'broadcast'
  }
).publish

sleep 2

#==============================================================================
# Example 4: Load Balancing with Consumer Groups
#==============================================================================

class WorkTask < SmartMessage::Base
  transport :redis_queue
  
  property :task_id, required: true
  property :task_type, required: true
  property :estimated_duration, default: 60
  
  def process
    puts "⚙️  Worker #{Thread.current.object_id} processing task #{task_id} (#{task_type})"
    sleep(rand(1..3)) # Simulate work
    puts "✅ Task #{task_id} completed by worker #{Thread.current.object_id}"
  end
end

puts "\n=== Example 4: Load Balanced Workers ==="

# Create multiple workers sharing same consumer group
worker_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  consumer_group: 'task_workers'
)

# Start 3 worker threads that share the same queue
workers = 3.times.map do |i|
  Thread.new do
    worker_transport.where
      .to('worker_pool')
      .consumer_group('task_workers')
      .subscribe do |message_class, message_data|
        message = JSON.parse(message_data)
        puts "👷 Worker-#{i+1} received: #{message['task_id']}"
      end
  end
end

# Publish multiple tasks - they'll be distributed among workers
5.times do |i|
  WorkTask.new(
    task_id: "TASK-#{i+1}",
    task_type: 'data_processing',
    estimated_duration: rand(30..120),
    _sm_header: {
      from: 'job_scheduler',
      to: 'worker_pool'
    }
  ).publish
end

sleep 5
workers.each(&:kill)

#==============================================================================
# Example 5: Emergency Alert System with Broadcast
#==============================================================================

class EmergencyAlert < SmartMessage::Base
  transport :redis_queue
  
  property :alert_type, required: true
  property :message, required: true
  property :severity, default: 'medium'
  property :affected_areas, default: []
  
  def process
    puts "🚨 EMERGENCY ALERT [#{severity}]: #{alert_type} - #{message}"
    if affected_areas.any?
      puts "📍 Affected areas: #{affected_areas.join(', ')}"
    end
  end
end

puts "\n=== Example 5: Emergency Alert System ==="

# Set up alert transport
alert_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  consumer_group: 'emergency_responders'
)

# Emergency services subscribe to alerts
alert_transport.subscribe_to_alerts do |message_class, message_data|
  message = JSON.parse(message_data)
  puts "🚒 Fire Department received: #{message['alert_type']}"
end

alert_transport.where
  .from('security_service')
  .subscribe do |message_class, message_data|
    message = JSON.parse(message_data)
    puts "👮 Police Department received security alert: #{message['alert_type']}"
  end

alert_transport.subscribe_to_broadcasts do |message_class, message_data|
  message = JSON.parse(message_data)
  puts "🏥 Hospital received broadcast: #{message['alert_type']}"
end

# Publish different types of emergency alerts
EmergencyAlert.new(
  alert_type: 'FIRE',
  message: 'Building fire reported at Main Street complex',
  severity: 'high',
  affected_areas: ['Downtown', 'Main Street'],
  _sm_header: {
    from: 'fire_detection_system',
    to: 'fire_department'
  }
).publish

EmergencyAlert.new(
  alert_type: 'SECURITY_BREACH',
  message: 'Unauthorized access detected in server room',
  severity: 'critical',
  _sm_header: {
    from: 'security_service',
    to: 'security_team'
  }
).publish

EmergencyAlert.new(
  alert_type: 'WEATHER_WARNING',
  message: 'Severe thunderstorm approaching, take shelter',
  severity: 'high',
  _sm_header: {
    from: 'weather_service',
    to: 'broadcast'
  }
).publish

sleep 3

#==============================================================================
# Example 6: Microservice Communication Pattern
#==============================================================================

class ServiceRequest < SmartMessage::Base
  transport :redis_queue
  
  property :request_id, required: true
  property :service_name, required: true
  property :action, required: true
  property :payload, default: {}
  
  def process
    puts "🔧 #{service_name.upcase} processing #{action}: #{request_id}"
  end
end

class ServiceResponse < SmartMessage::Base
  transport :redis_queue
  
  property :request_id, required: true
  property :service_name, required: true
  property :status, required: true
  property :result, default: {}
  
  def process
    puts "✉️  Response from #{service_name}: #{status} for #{request_id}"
  end
end

puts "\n=== Example 6: Microservice Communication ==="

# Set up service transport
service_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  consumer_group: 'microservices'
)

# Services subscribe to their specific requests
service_transport.where
  .to('user_service')
  .subscribe do |message_class, message_data|
    request = JSON.parse(message_data)
    puts "👤 User Service handling: #{request['action']} (#{request['request_id']})"
    
    # Send response back
    ServiceResponse.new(
      request_id: request['request_id'],
      service_name: 'user_service',
      status: 'completed',
      result: { user_data: 'retrieved' },
      _sm_header: {
        from: 'user_service',
        to: 'api_gateway'
      }
    ).publish
  end

service_transport.where
  .to('payment_service')
  .subscribe do |message_class, message_data|
    request = JSON.parse(message_data)
    puts "💳 Payment Service handling: #{request['action']} (#{request['request_id']})"
    
    ServiceResponse.new(
      request_id: request['request_id'],
      service_name: 'payment_service',
      status: 'completed',
      result: { transaction_id: 'TXN-123' },
      _sm_header: {
        from: 'payment_service',
        to: 'api_gateway'
      }
    ).publish
  end

# API Gateway subscribes to responses
service_transport.where
  .to('api_gateway')
  .subscribe do |message_class, message_data|
    response = JSON.parse(message_data)
    puts "🌐 API Gateway received response: #{response['status']} from #{response['service_name']}"
  end

# Simulate API requests
ServiceRequest.new(
  request_id: 'REQ-001',
  service_name: 'user_service',
  action: 'get_user_profile',
  payload: { user_id: 12345 },
  _sm_header: {
    from: 'api_gateway',
    to: 'user_service'
  }
).publish

ServiceRequest.new(
  request_id: 'REQ-002', 
  service_name: 'payment_service',
  action: 'process_payment',
  payload: { amount: 99.99, card_token: 'tok_123' },
  _sm_header: {
    from: 'api_gateway',
    to: 'payment_service'
  }
).publish

sleep 4

#==============================================================================
# Example 7: Queue Management and Monitoring
#==============================================================================

puts "\n=== Example 7: Queue Management ==="

# Create transport for management operations
mgmt_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  consumer_group: 'management'
)

# Check queue statistics
puts "📊 Queue Statistics:"
stats = mgmt_transport.queue_stats
stats.each do |queue_name, info|
  puts "  #{queue_name}: #{info[:length]} messages, pattern: #{info[:pattern]}"
end

# Show routing table
puts "\n🗺️  Routing Table:"
routing_table = mgmt_transport.routing_table
routing_table.each do |pattern, queues|
  puts "  Pattern '#{pattern}' -> #{queues.join(', ')}"
end

# Publish a few more messages to see queue growth
3.times do |i|
  WelcomeMessage.new(
    user_name: "TestUser#{i+1}",
    _sm_header: {
      from: 'test_service',
      to: 'welcome_service'
    }
  ).publish
end

puts "\n📊 Updated Queue Statistics:"
updated_stats = mgmt_transport.queue_stats
updated_stats.each do |queue_name, info|
  puts "  #{queue_name}: #{info[:length]} messages"
end

#==============================================================================
# Cleanup
#==============================================================================

puts "\n🧹 Cleaning up..."

# Close transport connections
transport.disconnect if defined?(transport)
notification_transport.disconnect if defined?(notification_transport)
worker_transport.disconnect if defined?(worker_transport)
alert_transport.disconnect if defined?(alert_transport)
service_transport.disconnect if defined?(service_transport)
mgmt_transport.disconnect if defined?(mgmt_transport)

puts "✅ Redis Queue Transport examples completed!"

#==============================================================================
# Additional Usage Patterns
#==============================================================================

puts "\n📋 Additional Usage Patterns:\n"

puts <<~USAGE
  # Pattern matching examples:
  transport.subscribe_pattern("#.*.my_service")           # All messages TO my_service
  transport.subscribe_pattern("#.admin.*")                # All messages FROM admin
  transport.subscribe_pattern("order.#.*.*")              # All order messages
  transport.subscribe_pattern("emergency.#.*.broadcast")  # Emergency broadcasts
  
  # Fluent API examples:
  transport.where.from('api').to('service').subscribe     # Specific routing
  transport.where.type('AlertMessage').subscribe          # Message type filtering
  transport.where.consumer_group('workers').subscribe     # Load balancing
  
  # Convenience methods:
  transport.subscribe_to_recipient('my_service')          # Messages for me
  transport.subscribe_from_sender('trusted_service')      # Messages from trusted source
  transport.subscribe_to_broadcasts                       # Broadcast messages
  transport.subscribe_to_alerts                          # Emergency alerts
  
  # Queue management:
  transport.queue_stats                                   # Monitor queue lengths
  transport.routing_table                                 # View routing patterns
  transport.clear_queue('queue_name')                     # Clear specific queue
USAGE