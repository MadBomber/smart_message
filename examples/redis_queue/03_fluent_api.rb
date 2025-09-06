#!/usr/bin/env ruby
# examples/redis_queue/03_fluent_api.rb
# Demonstration of the Fluent API for Redis Queue Transport

require_relative '../../lib/smart_message'
require 'async'

puts "🎨 Redis Queue Transport - Fluent API Demo"
puts "=" * 50

#==============================================================================
# Transport Setup
#==============================================================================

transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 3,  # Use database 3 for fluent API examples
  queue_prefix: 'fluent_demo',
  exchange_name: 'smart_message',
  consumer_timeout: 1,  # 1 second timeout
  test_mode: false  # Enable consumer tasks
)

#==============================================================================
# Message Classes
#==============================================================================

class TaskMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 3,
    queue_prefix: 'fluent_demo',
    exchange_name: 'smart_message',
    test_mode: false
  }
  
  property :task_id, required: true
  property :task_type, required: true
  property :assigned_to
  property :priority, default: 'medium'
  property :estimated_hours, default: 1
  
  def process
    priority_icon = case priority
                   when 'critical' then '🔥'
                   when 'high' then '⚡'
                   when 'medium' then '⚖️'
                   when 'low' then '🐌'
                   else '📝'
                   end
    
    puts "#{priority_icon} Task #{task_id} [#{task_type}] → #{assigned_to} (#{estimated_hours}h)"
  end
end

class EventMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 3,
    queue_prefix: 'fluent_demo',
    exchange_name: 'smart_message',
    test_mode: false
  }
  
  property :event_type, required: true
  property :user_id
  property :session_id
  property :metadata, default: {}
  property :timestamp, default: -> { Time.now }
  
  def process
    puts "📈 Event: #{event_type} | User: #{user_id} | Session: #{session_id}"
    puts "   Metadata: #{metadata.inspect}" if metadata.any?
  end
end

class AlertMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 3,
    queue_prefix: 'fluent_demo',
    exchange_name: 'smart_message',
    test_mode: false
  }
  
  property :alert_id, required: true
  property :service, required: true
  property :level, required: true
  property :description, required: true
  property :tags, default: []
  
  def process
    level_icon = case level
                when 'critical' then '🚨'
                when 'warning' then '⚠️'
                when 'info' then 'ℹ️'
                else '📢'
                end
    
    puts "#{level_icon} Alert #{alert_id}: #{service} - #{description}"
    puts "   Tags: #{tags.join(', ')}" if tags.any?
  end
end

#==============================================================================
# Fluent API Subscription Examples
#==============================================================================

Async do
  puts "\n🎭 Setting up Fluent API subscriptions:"

# Example 1: Simple FROM subscription
puts "1️⃣ Subscribe to messages FROM 'api_service'"
subscription1 = transport.where
  .from('api_service')
  .subscribe do |message_class, message_data|
    data = JSON.parse(message_data)
    puts "🔵 API Service Message: #{message_class} - #{data['task_id'] || data['event_type'] || data['alert_id']}"
  end

# Example 2: Simple TO subscription
puts "2️⃣ Subscribe to messages TO 'task_processor'"
subscription2 = transport.where
  .to('task_processor')
  .subscribe do |message_class, message_data|
    data = JSON.parse(message_data)
    puts "🟢 Task Processor: #{message_class} - #{data['task_id'] || data['task_type']}"
  end

# Example 3: Type-specific subscription
puts "3️⃣ Subscribe to TaskMessage types only"
subscription3 = transport.where
  .type('TaskMessage')
  .subscribe do |message_class, message_data|
    data = JSON.parse(message_data)
    puts "📋 Task Only: #{data['task_id']} - #{data['task_type']} [#{data['priority']}]"
  end

# Example 4: Combined FROM and TO
puts "4️⃣ Subscribe FROM 'web_app' TO 'event_processor'" 
subscription4 = transport.where
  .from('web_app')
  .to('event_processor')
  .subscribe do |message_class, message_data|
    data = JSON.parse(message_data)
    puts "🌐➡️📊 Web→Events: #{message_class} - #{data['event_type']}"
  end

# Example 5: Consumer group with load balancing
puts "5️⃣ Subscribe with consumer group 'alert_handlers'"
subscription5 = transport.where
  .type('AlertMessage')
  .consumer_group('alert_handlers')
  .subscribe do |message_class, message_data|
    data = JSON.parse(message_data)
    fiber_id = Async::Task.current.object_id.to_s[-4..-1]
    puts "⚡ Fiber-#{fiber_id}: Alert #{data['alert_id']} [#{data['level']}]"
  end

# Example 6: Complex multi-criteria subscription
puts "6️⃣ Subscribe FROM admin services TO monitoring with group"
subscription6 = transport.where
  .from(/^admin_.*/)  # Regex pattern for admin services
  .to('monitoring_service')
  .consumer_group('monitoring_workers')
  .subscribe do |message_class, message_data|
    data = JSON.parse(message_data)
    puts "👑📊 Admin→Monitor: #{message_class}"
  end

# Example 7: Type and destination combination
puts "7️⃣ Subscribe to EventMessage TO analytics services"
subscription7 = transport.where
  .type('EventMessage')
  .to(/.*analytics.*/)  # Any service with 'analytics' in name
  .subscribe do |message_class, message_data|
    data = JSON.parse(message_data)
    puts "📈🎯 Events→Analytics: #{data['event_type']} - User #{data['user_id']}"
  end

  # Wait for subscriptions to initialize
  sleep 1

  #============================================================================
  # Pattern Building Demonstration
  #============================================================================

  puts "\n🏗️ Pattern Building Examples:"

  # Show how different fluent combinations create patterns
  builders = [
    transport.where.from('api_service'),
    transport.where.to('task_processor'),
    transport.where.type('TaskMessage'),
    transport.where.from('web_app').to('event_processor'),
    transport.where.type('AlertMessage').from('monitoring'),
    transport.where.to('analytics_service').type('EventMessage')
  ]

  builders.each_with_index do |builder, i|
    pattern = builder.build
    puts "#{i + 1}. Pattern: '#{pattern}'"
  end

  #============================================================================
  # Message Publishing Examples
  #============================================================================

  puts "\n📤 Publishing messages to demonstrate fluent subscriptions:"

  # Messages FROM api_service (triggers subscription 1)
  puts "\n🔸 Messages FROM api_service:"
TaskMessage.new(
  task_id: 'TASK-001',
  task_type: 'data_processing',
  assigned_to: 'task_processor',
  priority: 'high',
  _sm_header: { from: 'api_service', to: 'task_processor' }
).publish

EventMessage.new(
  event_type: 'api_call',
  user_id: 'user123',
  session_id: 'sess456',
  metadata: { endpoint: '/api/tasks', method: 'POST' },
  _sm_header: { from: 'api_service', to: 'analytics_service' }
).publish

  # Messages TO task_processor (triggers subscription 2)
  puts "\n🔸 Messages TO task_processor:"
TaskMessage.new(
  task_id: 'TASK-002',
  task_type: 'image_processing',
  assigned_to: 'task_processor',
  priority: 'medium',
  estimated_hours: 3,
  _sm_header: { from: 'upload_service', to: 'task_processor' }
).publish

TaskMessage.new(
  task_id: 'TASK-003',
  task_type: 'email_processing',
  assigned_to: 'task_processor',
  priority: 'low',
  _sm_header: { from: 'mail_service', to: 'task_processor' }
).publish

  # TaskMessage types (triggers subscription 3)
  puts "\n🔸 Various TaskMessage types:"
TaskMessage.new(
  task_id: 'TASK-004',
  task_type: 'backup_database',
  assigned_to: 'backup_service',
  priority: 'critical',
  estimated_hours: 2,
  _sm_header: { from: 'scheduler', to: 'backup_service' }
).publish

  # Web app to event processor (triggers subscription 4)
  puts "\n🔸 Web app to event processor:"
EventMessage.new(
  event_type: 'page_view',
  user_id: 'user789',
  session_id: 'sess123',
  metadata: { page: '/dashboard', referrer: '/login' },
  _sm_header: { from: 'web_app', to: 'event_processor' }
).publish

EventMessage.new(
  event_type: 'button_click',
  user_id: 'user789',
  session_id: 'sess123',
  metadata: { button_id: 'save_profile', page: '/settings' },
  _sm_header: { from: 'web_app', to: 'event_processor' }
).publish

  # Alert messages for consumer groups (triggers subscription 5)
  puts "\n🔸 Alert messages for load balancing:"
3.times do |i|
  AlertMessage.new(
    alert_id: "ALERT-#{sprintf('%03d', i + 1)}",
    service: ['database', 'cache', 'api'][i],
    level: ['critical', 'warning', 'info'][i],
    description: ["Database connection lost", "Cache hit rate below 80%", "API response time normal"][i],
    tags: [['db', 'urgent'], ['cache', 'performance'], ['api', 'info']][i],
    _sm_header: { from: 'monitoring_service', to: 'alert_handler' }
  ).publish
end

  # Admin messages to monitoring (triggers subscription 6)
  puts "\n🔸 Admin messages to monitoring:"
AlertMessage.new(
  alert_id: 'ADMIN-001',
  service: 'user_management',
  level: 'info',
  description: 'User privileges updated for admin user',
  tags: ['admin', 'security'],
  _sm_header: { from: 'admin_panel', to: 'monitoring_service' }
).publish

EventMessage.new(
  event_type: 'admin_action',
  user_id: 'admin123',
  metadata: { action: 'user_created', target_user: 'newuser456' },
  _sm_header: { from: 'admin_service', to: 'monitoring_service' }
).publish

  # Event messages to analytics (triggers subscription 7)
  puts "\n🔸 Event messages to analytics services:"
EventMessage.new(
  event_type: 'purchase_completed',
  user_id: 'customer123',
  session_id: 'shop_session_789',
  metadata: { order_id: 'ORD-789', amount: 149.99, items: 3 },
  _sm_header: { from: 'checkout_service', to: 'user_analytics' }
).publish

EventMessage.new(
  event_type: 'search_query',
  user_id: 'customer456',
  metadata: { query: 'wireless headphones', results: 24 },
  _sm_header: { from: 'search_service', to: 'search_analytics' }
).publish

  # Wait for message processing
  puts "\n⏳ Processing all messages..."
  sleep 5

  #============================================================================
  # Chained Fluent API Examples
  #============================================================================

  puts "\n🔗 Advanced Fluent API Chaining:"

  # Example of building and modifying subscriptions
  puts "\n8️⃣ Dynamic subscription building:"
base_subscription = transport.where.type('TaskMessage')

# Add criteria dynamically
urgent_tasks = base_subscription.from('urgent_processor')
pattern1 = urgent_tasks.build
puts "Dynamic pattern 1: #{pattern1}"

# Build different variations
analytics_tasks = base_subscription.to(/.*analytics.*/)
pattern2 = analytics_tasks.build  
puts "Dynamic pattern 2: #{pattern2}"

# Complex chaining
complex_subscription = transport.where
  .type('EventMessage')
  .from(/^(web|mobile)_app$/)  # From web or mobile app
  .to(/.*analytics.*/)         # To any analytics service
  .consumer_group('analytics_processors')

pattern3 = complex_subscription.build
puts "Complex pattern: #{pattern3}"

# Subscribe with the complex pattern
complex_subscription.subscribe do |message_class, message_data|
  data = JSON.parse(message_data)
  puts "🎯 Complex Match: #{data['event_type']} from mobile/web → analytics"
end

# Test the complex subscription
EventMessage.new(
  event_type: 'app_launch',
  user_id: 'mobile_user123',
  metadata: { platform: 'iOS', version: '2.1.0' },
  _sm_header: { from: 'mobile_app', to: 'mobile_analytics' }
).publish

  sleep 2

  #============================================================================
  # Subscription Management
  #============================================================================

  puts "\n📊 Fluent API Statistics:"

  # Show routing table
  routing_table = transport.routing_table
  puts "\nRouting patterns created by fluent API:"
  routing_table.each_with_index do |(pattern, queues), i|
    puts "#{i + 1}. '#{pattern}' → #{queues.size} queue(s)"
  end

  # Show queue statistics  
  stats = transport.queue_stats
  puts "\nQueue statistics:"
  total_messages = 0
  stats.each do |queue_name, info|
    total_messages += info[:length]
    puts "  #{queue_name}: #{info[:length]} messages"
  end

  puts "\nTotal messages in all queues: #{total_messages}"

  # Cleanup
  transport.disconnect
end

puts "\n🎨 Fluent API demonstration completed!"

puts "\n💡 Fluent API Features Demonstrated:"
puts "   ✓ .from() - Source-based filtering"
puts "   ✓ .to() - Destination-based filtering" 
puts "   ✓ .type() - Message type filtering"
puts "   ✓ .consumer_group() - Load balancing"
puts "   ✓ Method chaining for complex criteria"
puts "   ✓ Regex patterns in from/to filters"
puts "   ✓ Dynamic subscription building"
puts "   ✓ Pattern generation and inspection"

puts "\n🚀 Key Benefits:"
puts "   • Readable, expressive subscription syntax"
puts "   • Type-safe subscription building" 
puts "   • Flexible criteria combination"
puts "   • Runtime pattern inspection"
puts "   • Easy consumer group management with Async fibers"
puts "   • Complex routing made simple"
puts "   • Fiber-based concurrency for massive scalability"