#!/usr/bin/env ruby
# examples/redis_queue/04_load_balancing.rb
# Load balancing and consumer groups with Redis Queue Transport

require_relative '../../lib/smart_message'

puts "⚖️ Redis Queue Transport - Load Balancing Demo"
puts "=" * 50

#==============================================================================
# Transport Configuration
#==============================================================================

# Create shared transport for load balancing examples
shared_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 4,  # Use database 4 for load balancing examples
  queue_prefix: 'load_balance_demo',
  consumer_group: 'demo_workers',
  block_time: 500  # Fast response for demo
)

#==============================================================================
# Work Message Classes
#==============================================================================

class ProcessingTask < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 4,
    queue_prefix: 'load_balance_demo'
  }
  
  property :task_id, required: true
  property :task_type, required: true
  property :complexity, default: 'medium'  # low, medium, high
  property :estimated_seconds, default: 1
  property :payload, default: {}
  
  def process
    complexity_icon = case complexity
                     when 'high' then '🔥'
                     when 'medium' then '⚡'
                     when 'low' then '🍃'
                     else '⚙️'
                     end
    
    puts "#{complexity_icon} Processing #{task_id} [#{task_type}] - #{complexity} complexity (#{estimated_seconds}s)"
    
    # Simulate work
    sleep(estimated_seconds * 0.1)  # Scale down for demo
    
    puts "✅ Completed #{task_id} by worker #{Thread.current.object_id.to_s[-4..-1]}"
  end
end

class EmailTask < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 4,
    queue_prefix: 'load_balance_demo'
  }
  
  property :email_id, required: true
  property :recipient, required: true
  property :subject, required: true
  property :template, default: 'default'
  property :priority, default: 'normal'
  
  def process
    priority_icon = case priority
                   when 'urgent' then '🚨'
                   when 'high' then '❗'
                   when 'normal' then '📧'
                   when 'low' then '📮'
                   else '📬'
                   end
    
    worker_id = Thread.current.object_id.to_s[-4..-1]
    puts "#{priority_icon} Worker-#{worker_id}: Email #{email_id} → #{recipient}"
    puts "   Subject: #{subject} [#{priority}]"
    
    # Simulate email sending
    sleep(rand(0.5..1.5))
    
    puts "📤 Email #{email_id} sent by worker-#{worker_id}"
  end
end

class DataAnalysisTask < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 4,
    queue_prefix: 'load_balance_demo'
  }
  
  property :analysis_id, required: true
  property :dataset, required: true
  property :analysis_type, required: true
  property :rows, default: 1000
  property :columns, default: 10
  
  def process
    worker_id = Thread.current.object_id.to_s[-4..-1]
    puts "📊 Worker-#{worker_id}: Analyzing #{dataset} [#{analysis_type}]"
    puts "   Dataset: #{rows} rows × #{columns} columns"
    
    # Simulate analysis work
    sleep(rand(0.8..2.0))
    
    puts "🎯 Analysis #{analysis_id} completed by worker-#{worker_id}"
  end
end

#==============================================================================
# Consumer Group Setup
#==============================================================================

puts "\n👥 Setting up consumer groups for load balancing:"

# Group 1: General processing workers
puts "1️⃣ Setting up 'processing_workers' group (3 workers)"
processing_workers = []
3.times do |i|
  worker_thread = Thread.new do
    worker_transport = SmartMessage::Transport::RedisQueueTransport.new(
      url: 'redis://localhost:6379',
      db: 4,
      queue_prefix: 'load_balance_demo',
      consumer_group: 'processing_workers',
      block_time: 1000
    )
    
    # Subscribe to processing tasks directed to worker pool
    worker_transport.where
      .to('worker_pool')
      .consumer_group('processing_workers')
      .subscribe do |message_class, message_data|
        data = JSON.parse(message_data)
        worker_id = Thread.current.object_id.to_s[-4..-1]
        puts "⚙️ Worker-#{i+1}-#{worker_id} received: #{data['task_id'] || data['email_id'] || data['analysis_id']}"
      end
  end
  processing_workers << worker_thread
end

# Group 2: Email workers
puts "2️⃣ Setting up 'email_workers' group (2 workers)"
email_workers = []
2.times do |i|
  worker_thread = Thread.new do
    worker_transport = SmartMessage::Transport::RedisQueueTransport.new(
      url: 'redis://localhost:6379',
      db: 4,
      queue_prefix: 'load_balance_demo',
      consumer_group: 'email_workers',
      block_time: 1000
    )
    
    # Subscribe to email tasks
    worker_transport.where
      .type('EmailTask')
      .consumer_group('email_workers')
      .subscribe do |message_class, message_data|
        data = JSON.parse(message_data)
        worker_id = Thread.current.object_id.to_s[-4..-1]
        puts "📧 EmailWorker-#{i+1}-#{worker_id} received: #{data['email_id']}"
      end
  end
  email_workers << worker_thread
end

# Group 3: Analytics workers
puts "3️⃣ Setting up 'analytics_workers' group (4 workers)"
analytics_workers = []
4.times do |i|
  worker_thread = Thread.new do
    worker_transport = SmartMessage::Transport::RedisQueueTransport.new(
      url: 'redis://localhost:6379',
      db: 4,
      queue_prefix: 'load_balance_demo',
      consumer_group: 'analytics_workers',
      block_time: 1000
    )
    
    # Subscribe to analytics tasks
    worker_transport.where
      .type('DataAnalysisTask')
      .consumer_group('analytics_workers')
      .subscribe do |message_class, message_data|
        data = JSON.parse(message_data)
        worker_id = Thread.current.object_id.to_s[-4..-1]
        puts "📊 AnalyticsWorker-#{i+1}-#{worker_id} received: #{data['analysis_id']}"
      end
  end
  analytics_workers << worker_thread
end

# Give workers time to start
sleep 2

#==============================================================================
# Load Balancing Demonstration
#==============================================================================

puts "\n📤 Demonstrating load balancing with multiple workers:"

# Test 1: Processing tasks distributed among 3 workers
puts "\n🔸 Test 1: General processing tasks (distributed among 3 workers)"
5.times do |i|
  ProcessingTask.new(
    task_id: "PROC-#{sprintf('%03d', i + 1)}",
    task_type: ['data_import', 'file_conversion', 'image_resize', 'pdf_generation', 'backup'][i],
    complexity: ['low', 'medium', 'high', 'medium', 'low'][i],
    estimated_seconds: [1, 2, 3, 2, 1][i],
    payload: { batch_size: rand(100..1000) },
    _sm_header: {
      from: 'task_scheduler',
      to: 'worker_pool'
    }
  ).publish
end

sleep 3

# Test 2: Email tasks distributed among 2 workers
puts "\n🔸 Test 2: Email tasks (distributed among 2 workers)"
6.times do |i|
  EmailTask.new(
    email_id: "EMAIL-#{sprintf('%03d', i + 1)}",
    recipient: "user#{i + 1}@example.com",
    subject: [
      'Welcome to our service!',
      'Your order confirmation',
      'Password reset request',
      'Monthly newsletter',
      'Account verification required',
      'Special offer inside!'
    ][i],
    template: ['welcome', 'order', 'password_reset', 'newsletter', 'verification', 'promotion'][i],
    priority: ['normal', 'high', 'urgent', 'low', 'normal', 'high'][i],
    _sm_header: {
      from: 'email_service',
      to: 'email_queue'
    }
  ).publish
end

sleep 4

# Test 3: Analytics tasks distributed among 4 workers
puts "\n🔸 Test 3: Analytics tasks (distributed among 4 workers)"
8.times do |i|
  DataAnalysisTask.new(
    analysis_id: "ANALYSIS-#{sprintf('%03d', i + 1)}",
    dataset: "dataset_#{i + 1}",
    analysis_type: ['regression', 'classification', 'clustering', 'time_series', 'correlation', 'anomaly_detection', 'forecasting', 'segmentation'][i],
    rows: rand(1000..10000),
    columns: rand(5..50),
    _sm_header: {
      from: 'analytics_service',
      to: 'analytics_queue'
    }
  ).publish
end

sleep 5

#==============================================================================
# High-Volume Load Test
#==============================================================================

puts "\n🚀 High-volume load balancing test:"

# Publish many tasks rapidly to see load distribution
puts "Publishing 20 processing tasks rapidly..."
start_time = Time.now

20.times do |i|
  ProcessingTask.new(
    task_id: "LOAD-#{sprintf('%03d', i + 1)}",
    task_type: 'load_test',
    complexity: ['low', 'medium', 'high'].sample,
    estimated_seconds: rand(1..3),
    _sm_header: {
      from: 'load_tester',
      to: 'worker_pool'
    }
  ).publish
end

end_time = Time.now
puts "✅ Published 20 tasks in #{(end_time - start_time).round(3)} seconds"

# Wait for processing
puts "\n⏳ Waiting for load test completion..."
sleep 8

#==============================================================================
# Priority-Based Load Balancing
#==============================================================================

puts "\n⭐ Priority-based load balancing:"

# Set up priority workers
puts "Setting up high-priority worker group..."
priority_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 4,
  queue_prefix: 'load_balance_demo',
  consumer_group: 'priority_workers',
  block_time: 500
)

# Priority worker subscription
priority_worker = Thread.new do
  priority_transport.where
    .to('priority_queue')
    .consumer_group('priority_workers')
    .subscribe do |message_class, message_data|
      data = JSON.parse(message_data)
      puts "🌟 PRIORITY Worker handling: #{data['task_id'] || data['email_id']}"
    end
end

sleep 1

# Publish priority tasks
puts "Publishing high-priority tasks..."
3.times do |i|
  ProcessingTask.new(
    task_id: "PRIORITY-#{sprintf('%03d', i + 1)}",
    task_type: 'critical_task',
    complexity: 'high',
    estimated_seconds: 1,
    _sm_header: {
      from: 'urgent_scheduler',
      to: 'priority_queue'
    }
  ).publish
end

# Publish priority emails
2.times do |i|
  EmailTask.new(
    email_id: "URGENT-EMAIL-#{sprintf('%03d', i + 1)}",
    recipient: "admin#{i + 1}@company.com",
    subject: 'URGENT: System Alert',
    priority: 'urgent',
    _sm_header: {
      from: 'alert_system',
      to: 'priority_queue'
    }
  ).publish
end

sleep 3

#==============================================================================
# Load Balancing Statistics
#==============================================================================

puts "\n📊 Load Balancing Statistics:"

# Show queue statistics
stats = shared_transport.queue_stats
puts "\nQueue lengths after load balancing:"
total_queued = 0
stats.each do |queue_name, info|
  total_queued += info[:length]
  puts "  #{queue_name}: #{info[:length]} messages (#{info[:consumers]} consumers)"
end

puts "\nTotal messages remaining in queues: #{total_queued}"

# Show routing table for consumer groups
routing_table = shared_transport.routing_table
puts "\nActive consumer group patterns:"
routing_table.each do |pattern, queues|
  puts "  Pattern: '#{pattern}'"
  puts "    Queues: #{queues.join(', ')}"
end

#==============================================================================
# Worker Performance Comparison
#==============================================================================

puts "\n⚡ Worker Performance Demonstration:"

# Create workers with different processing speeds
puts "Creating workers with different performance characteristics..."

# Fast worker
fast_worker_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 4,
  queue_prefix: 'load_balance_demo',
  consumer_group: 'performance_test_workers'
)

fast_worker = Thread.new do
  fast_worker_transport.where
    .to('performance_test')
    .consumer_group('performance_test_workers')
    .subscribe do |message_class, message_data|
      data = JSON.parse(message_data)
      puts "🚀 FAST Worker: #{data['task_id']} (processed quickly)"
      sleep(0.1)  # Fast processing
    end
end

# Slow worker
slow_worker_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 4,
  queue_prefix: 'load_balance_demo',
  consumer_group: 'performance_test_workers'
)

slow_worker = Thread.new do
  slow_worker_transport.where
    .to('performance_test')
    .consumer_group('performance_test_workers')
    .subscribe do |message_class, message_data|
      data = JSON.parse(message_data)
      puts "🐌 SLOW Worker: #{data['task_id']} (processing slowly...)"
      sleep(2.0)  # Slow processing
    end
end

sleep 1

# Send tasks to both workers
puts "Sending 10 tasks to mixed-speed worker group..."
10.times do |i|
  ProcessingTask.new(
    task_id: "PERF-#{sprintf('%03d', i + 1)}",
    task_type: 'performance_test',
    complexity: 'medium',
    _sm_header: {
      from: 'performance_tester',
      to: 'performance_test'
    }
  ).publish
end

puts "⏳ Observing how Redis Queue balances load between fast and slow workers..."
sleep 8

#==============================================================================
# Cleanup
#==============================================================================

puts "\n🧹 Cleaning up workers and connections..."

# Stop all worker threads
[processing_workers, email_workers, analytics_workers, priority_worker, fast_worker, slow_worker].flatten.each do |thread|
  thread.kill if thread.alive?
end

# Disconnect transports
shared_transport.disconnect
priority_transport.disconnect
fast_worker_transport.disconnect
slow_worker_transport.disconnect

puts "\n⚖️ Load balancing demonstration completed!"

puts "\n💡 Load Balancing Features Demonstrated:"
puts "   ✓ Consumer groups for work distribution"
puts "   ✓ Multiple workers sharing same queue"
puts "   ✓ Round-robin task distribution"
puts "   ✓ Different worker group configurations"
puts "   ✓ High-volume load testing"
puts "   ✓ Priority-based routing"
puts "   ✓ Mixed-performance worker handling"
puts "   ✓ Real-time queue monitoring"

puts "\n🚀 Key Benefits:"
puts "   • Automatic load distribution via Redis BRPOP"
puts "   • Scalable worker pool management"
puts "   • Fair work distribution among workers"
puts "   • Consumer group isolation"
puts "   • High-throughput task processing"
puts "   • Fault-tolerant worker coordination"
puts "   • Zero-configuration load balancing"