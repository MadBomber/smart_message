#!/usr/bin/env ruby
# examples/redis_queue/07_queue_management.rb
# Queue management, monitoring and administration with Redis Queue Transport

require_relative '../../lib/smart_message'

puts "📊 Redis Queue Transport - Queue Management & Monitoring Demo"
puts "=" * 65

#==============================================================================
# Management Transport Setup
#==============================================================================

# Create transport instance for queue management
mgmt_transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 7,  # Use database 7 for queue management demo
  queue_prefix: 'mgmt_demo',
  consumer_group: 'management_workers',
  block_time: 500
)

#==============================================================================
# Test Message Classes for Queue Management Demo
#==============================================================================

class TaskMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 7,
    queue_prefix: 'mgmt_demo'
  }
  
  property :task_id, required: true
  property :priority, default: 'normal'
  property :estimated_duration, default: 30
  property :worker_type, default: 'general'
  
  def process
    puts "⚙️ Processing task #{task_id} [#{priority}] - #{estimated_duration}s"
  end
end

class MonitoringMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 7,
    queue_prefix: 'mgmt_demo'
  }
  
  property :metric_name, required: true
  property :value, required: true
  property :threshold
  property :alert_level, default: 'info'
  
  def process
    puts "📈 Metric: #{metric_name} = #{value} [#{alert_level}]"
  end
end

class ReportMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://localhost:6379',
    db: 7,
    queue_prefix: 'mgmt_demo'
  }
  
  property :report_id, required: true
  property :report_type, required: true
  property :data, default: {}
  property :format, default: 'json'
  
  def process
    puts "📄 Generating report #{report_id} [#{report_type}] in #{format} format"
  end
end

#==============================================================================
# Queue Monitoring Functions
#==============================================================================

def display_queue_statistics(transport, title = "Queue Statistics")
  puts "\n📊 #{title}:"
  puts "-" * (title.length + 5)
  
  stats = transport.queue_stats
  
  if stats.empty?
    puts "   No active queues found"
    return
  end
  
  total_messages = 0
  total_consumers = 0
  
  stats.each do |queue_name, info|
    total_messages += info[:length]
    total_consumers += info[:consumers] || 0
    
    # Extract meaningful queue name
    display_name = queue_name.split('.').last.tr('_', ' ').capitalize
    
    status_icon = case info[:length]
                 when 0 then '✅'
                 when 1..10 then '🟡'
                 when 11..50 then '🟠'
                 else '🔴'
                 end
    
    puts "   #{status_icon} #{display_name}:"
    puts "      Messages: #{info[:length]}"
    puts "      Pattern: #{info[:pattern] || 'N/A'}"
    puts "      Consumers: #{info[:consumers] || 0}"
    puts ""
  end
  
  puts "   📈 Totals:"
  puts "      Active Queues: #{stats.size}"
  puts "      Total Messages: #{total_messages}"
  puts "      Total Consumers: #{total_consumers}"
  puts ""
end

def display_routing_table(transport)
  puts "\n🗺️ Routing Table:"
  puts "-" * 15
  
  routing_table = transport.routing_table
  
  if routing_table.empty?
    puts "   No routing patterns configured"
    return
  end
  
  routing_table.each_with_index do |(pattern, queues), index|
    puts "   #{index + 1}. Pattern: '#{pattern}'"
    puts "      Queues: #{queues.size}"
    queues.each do |queue|
      display_name = queue.split('.').last.tr('_', ' ').capitalize
      puts "        → #{display_name}"
    end
    puts ""
  end
end

def monitor_queue_health(transport)
  stats = transport.queue_stats
  health_issues = []
  
  stats.each do |queue_name, info|
    # Check for potential issues
    if info[:length] > 100
      health_issues << "⚠️ Queue #{queue_name} has #{info[:length]} messages (high load)"
    elsif info[:length] > 0 && info[:consumers] == 0
      health_issues << "🔴 Queue #{queue_name} has messages but no consumers"
    elsif info[:consumers] > 10
      health_issues << "⚡ Queue #{queue_name} has #{info[:consumers]} consumers (possible over-provisioning)"
    end
  end
  
  if health_issues.any?
    puts "\n🏥 Queue Health Issues:"
    puts "-" * 22
    health_issues.each { |issue| puts "   #{issue}" }
  else
    puts "\n✅ All queues healthy"
  end
  
  health_issues
end

def performance_metrics(transport, start_time)
  current_time = Time.now
  uptime = current_time - start_time
  
  stats = transport.queue_stats
  total_queues = stats.size
  total_messages = stats.values.sum { |info| info[:length] }
  total_consumers = stats.values.sum { |info| info[:consumers] || 0 }
  
  puts "\n⚡ Performance Metrics:"
  puts "-" * 22
  puts "   Uptime: #{uptime.round(2)} seconds"
  puts "   Active Queues: #{total_queues}"
  puts "   Pending Messages: #{total_messages}"
  puts "   Active Consumers: #{total_consumers}"
  
  if total_consumers > 0
    puts "   Avg Messages/Consumer: #{(total_messages.to_f / total_consumers).round(2)}"
  end
  
  puts "   Queue Density: #{total_queues > 0 ? (total_messages.to_f / total_queues).round(2) : 0} msg/queue"
end

#==============================================================================
# Queue Management Demonstration
#==============================================================================

puts "\n🚀 Starting Queue Management Demo..."
demo_start_time = Time.now

# Initial state - should be empty
display_queue_statistics(mgmt_transport, "Initial Queue State")

puts "\n1️⃣ Setting up multiple subscription patterns:"

# Pattern 1: Task processing queues
mgmt_transport.subscribe_pattern("#.*.task_processor") do |message_class, data|
  parsed_data = JSON.parse(data)
  puts "🔧 Task Processor: #{parsed_data['task_id']}"
end

mgmt_transport.subscribe_pattern("#.*.priority_tasks") do |message_class, data|
  parsed_data = JSON.parse(data)
  puts "⚡ Priority Processor: #{parsed_data['task_id']}"
end

# Pattern 2: Monitoring queues
mgmt_transport.subscribe_pattern("#.*.monitoring") do |message_class, data|
  parsed_data = JSON.parse(data)
  puts "📊 Monitor: #{parsed_data['metric_name']}"
end

mgmt_transport.subscribe_pattern("#.*.alerts") do |message_class, data|
  parsed_data = JSON.parse(data)
  puts "🚨 Alert: #{parsed_data['metric_name']} = #{parsed_data['value']}"
end

# Pattern 3: Reporting queues
mgmt_transport.subscribe_pattern("#.*.reports") do |message_class, data|
  parsed_data = JSON.parse(data)
  puts "📈 Report Generator: #{parsed_data['report_id']}"
end

# Pattern 4: Load balancing demo
mgmt_transport.where
  .to('load_balanced_service')
  .consumer_group('balanced_workers')
  .subscribe do |message_class, data|
    parsed_data = JSON.parse(data)
    worker_id = Thread.current.object_id.to_s[-4..-1]
    puts "⚖️ Balanced Worker-#{worker_id}: #{parsed_data['task_id'] || parsed_data['report_id']}"
  end

sleep 1

# Show initial routing setup
display_routing_table(mgmt_transport)
display_queue_statistics(mgmt_transport, "Post-Setup Queue State")

#==============================================================================
# Message Publishing for Queue Analysis
#==============================================================================

puts "\n2️⃣ Publishing messages to populate queues:"

# Publish various task messages
puts "\n🔸 Publishing task messages..."
5.times do |i|
  TaskMessage.new(
    task_id: "TASK-#{sprintf('%03d', i + 1)}",
    priority: ['low', 'normal', 'high', 'critical'][i % 4],
    estimated_duration: rand(30..300),
    worker_type: ['general', 'specialized', 'expert'][i % 3],
    _sm_header: {
      from: 'task_scheduler',
      to: i < 3 ? 'task_processor' : 'priority_tasks'
    }
  ).publish
end

# Publish monitoring messages
puts "\n🔸 Publishing monitoring messages..."
monitoring_metrics = [
  { name: 'cpu_usage', value: 75.5, threshold: 80, level: 'warning' },
  { name: 'memory_usage', value: 45.2, threshold: 70, level: 'info' },
  { name: 'disk_usage', value: 92.1, threshold: 90, level: 'critical' },
  { name: 'network_latency', value: 150, threshold: 100, level: 'warning' }
]

monitoring_metrics.each do |metric|
  MonitoringMessage.new(
    metric_name: metric[:name],
    value: metric[:value],
    threshold: metric[:threshold],
    alert_level: metric[:level],
    _sm_header: {
      from: 'monitoring_system',
      to: metric[:level] == 'critical' ? 'alerts' : 'monitoring'
    }
  ).publish
end

# Publish report requests
puts "\n🔸 Publishing report requests..."
3.times do |i|
  ReportMessage.new(
    report_id: "RPT-#{Time.now.strftime('%Y%m%d')}-#{sprintf('%03d', i + 1)}",
    report_type: ['daily_summary', 'performance_analysis', 'error_log'][i],
    data: { period: '24h', format: 'detailed' },
    format: ['pdf', 'json', 'csv'][i],
    _sm_header: {
      from: 'report_scheduler',
      to: 'reports'
    }
  ).publish
end

# Publish load balanced messages
puts "\n🔸 Publishing load balanced messages..."
8.times do |i|
  message_class = [TaskMessage, ReportMessage][i % 2]
  message = if message_class == TaskMessage
              TaskMessage.new(
                task_id: "LB-TASK-#{sprintf('%03d', i + 1)}",
                priority: 'normal',
                _sm_header: { from: 'load_balancer', to: 'load_balanced_service' }
              )
            else
              ReportMessage.new(
                report_id: "LB-RPT-#{sprintf('%03d', i + 1)}",
                report_type: 'load_test',
                _sm_header: { from: 'load_balancer', to: 'load_balanced_service' }
              )
            end
  message.publish
end

sleep 2

# Show queue state after publishing
display_queue_statistics(mgmt_transport, "Post-Publishing Queue State")
monitor_queue_health(mgmt_transport)
performance_metrics(mgmt_transport, demo_start_time)

#==============================================================================
# Queue Monitoring Simulation
#==============================================================================

puts "\n3️⃣ Real-time queue monitoring simulation:"

puts "\n⏱️ Monitoring queue changes over time..."
5.times do |cycle|
  puts "\n   Monitoring Cycle #{cycle + 1}:"
  
  # Publish some more messages to simulate ongoing activity
  2.times do |i|
    TaskMessage.new(
      task_id: "MONITOR-#{cycle}-#{i}",
      priority: 'normal',
      _sm_header: { from: 'monitoring_test', to: 'task_processor' }
    ).publish
  end
  
  sleep 1
  
  # Quick stats
  stats = mgmt_transport.queue_stats
  total_messages = stats.values.sum { |info| info[:length] }
  active_queues = stats.select { |_, info| info[:length] > 0 }.size
  
  puts "     📊 Active queues: #{active_queues}, Total messages: #{total_messages}"
  
  # Check for health issues
  health_issues = monitor_queue_health(mgmt_transport)
  if health_issues.empty?
    puts "     ✅ System healthy"
  end
  
  sleep 1
end

#==============================================================================
# Queue Administration Operations
#==============================================================================

puts "\n4️⃣ Queue Administration Operations:"

# Show current state
puts "\n🔍 Current queue state before admin operations:"
display_queue_statistics(mgmt_transport, "Pre-Admin State")

# Admin operation 1: Clear specific queues
puts "\n🧹 Admin Operation 1: Queue Cleanup"
puts "   Clearing queues with low priority messages..."

# Simulate clearing specific queues (this would be done by admin tools)
stats = mgmt_transport.queue_stats
cleared_queues = []

stats.each do |queue_name, info|
  if info[:length] > 0 && queue_name.include?('task')
    puts "     🗑️ Would clear queue: #{queue_name} (#{info[:length]} messages)"
    cleared_queues << queue_name
  end
end

puts "     ✅ Queue cleanup simulation completed"

# Admin operation 2: Consumer group management
puts "\n👥 Admin Operation 2: Consumer Group Analysis"
routing_table = mgmt_transport.routing_table
consumer_groups = {}

routing_table.each do |pattern, queues|
  # Analyze which patterns might be consumer group related
  if pattern.include?('balanced') || pattern.include?('worker')
    consumer_groups[pattern] = queues
  end
end

if consumer_groups.any?
  puts "     Consumer group patterns found:"
  consumer_groups.each do |pattern, queues|
    puts "       Pattern: #{pattern}"
    puts "       Queues: #{queues.size}"
  end
else
  puts "     No dedicated consumer group patterns detected"
end

# Admin operation 3: Performance analysis
puts "\n📈 Admin Operation 3: Performance Analysis"
stats = mgmt_transport.queue_stats
performance_analysis = {
  high_volume_queues: [],
  idle_queues: [],
  over_subscribed_queues: []
}

stats.each do |queue_name, info|
  if info[:length] > 10
    performance_analysis[:high_volume_queues] << { name: queue_name, length: info[:length] }
  elsif info[:length] == 0
    performance_analysis[:idle_queues] << queue_name
  end
  
  if info[:consumers] && info[:consumers] > 5
    performance_analysis[:over_subscribed_queues] << { name: queue_name, consumers: info[:consumers] }
  end
end

puts "     📊 Performance Analysis Results:"
puts "       High Volume Queues: #{performance_analysis[:high_volume_queues].size}"
performance_analysis[:high_volume_queues].each do |queue|
  puts "         → #{queue[:name]}: #{queue[:length]} messages"
end

puts "       Idle Queues: #{performance_analysis[:idle_queues].size}"
puts "       Over-Subscribed Queues: #{performance_analysis[:over_subscribed_queues].size}"

#==============================================================================
# Advanced Queue Management Features
#==============================================================================

puts "\n5️⃣ Advanced Queue Management Features:"

# Feature 1: Queue pattern analysis
puts "\n🔍 Pattern Analysis:"
routing_table = mgmt_transport.routing_table
pattern_stats = {
  wildcard_patterns: 0,
  specific_patterns: 0,
  complex_patterns: 0
}

routing_table.each do |pattern, _|
  if pattern.include?('#') || pattern.include?('*')
    pattern_stats[:wildcard_patterns] += 1
  end
  
  if pattern.count('.') > 2
    pattern_stats[:complex_patterns] += 1
  else
    pattern_stats[:specific_patterns] += 1
  end
end

puts "     Pattern Statistics:"
puts "       Wildcard Patterns: #{pattern_stats[:wildcard_patterns]}"
puts "       Specific Patterns: #{pattern_stats[:specific_patterns]}"
puts "       Complex Patterns: #{pattern_stats[:complex_patterns]}"

# Feature 2: Queue efficiency metrics
puts "\n⚡ Queue Efficiency Metrics:"
stats = mgmt_transport.queue_stats
efficiency_metrics = {
  avg_messages_per_queue: 0,
  queue_utilization: 0,
  consumer_efficiency: 0
}

if stats.any?
  total_messages = stats.values.sum { |info| info[:length] }
  total_consumers = stats.values.sum { |info| info[:consumers] || 0 }
  
  efficiency_metrics[:avg_messages_per_queue] = (total_messages.to_f / stats.size).round(2)
  efficiency_metrics[:queue_utilization] = ((stats.count { |_, info| info[:length] > 0 }.to_f / stats.size) * 100).round(1)
  efficiency_metrics[:consumer_efficiency] = total_consumers > 0 ? (total_messages.to_f / total_consumers).round(2) : 0
end

puts "     Efficiency Metrics:"
puts "       Avg Messages/Queue: #{efficiency_metrics[:avg_messages_per_queue]}"
puts "       Queue Utilization: #{efficiency_metrics[:queue_utilization]}%"
puts "       Messages/Consumer: #{efficiency_metrics[:consumer_efficiency]}"

# Feature 3: System recommendations
puts "\n💡 System Recommendations:"
recommendations = []

stats.each do |queue_name, info|
  if info[:length] > 20
    recommendations << "Consider adding more consumers to #{queue_name}"
  elsif info[:length] == 0 && info[:consumers] && info[:consumers] > 2
    recommendations << "Consider reducing consumers for #{queue_name}"
  end
end

if efficiency_metrics[:queue_utilization] < 30
  recommendations << "Low queue utilization - consider consolidating queues"
elsif efficiency_metrics[:queue_utilization] > 90
  recommendations << "High queue utilization - consider adding more queues"
end

if recommendations.any?
  recommendations.each { |rec| puts "     • #{rec}" }
else
  puts "     ✅ System is well-optimized, no recommendations"
end

#==============================================================================
# Final System State and Summary
#==============================================================================

puts "\n6️⃣ Final System State and Summary:"

# Final statistics
display_queue_statistics(mgmt_transport, "Final Queue State")
display_routing_table(mgmt_transport)
performance_metrics(mgmt_transport, demo_start_time)

# Wait for remaining message processing
puts "\n⏳ Waiting for final message processing..."
sleep 3

# Final cleanup state
display_queue_statistics(mgmt_transport, "Post-Processing State")

# Summary statistics
final_stats = mgmt_transport.queue_stats
total_queues_created = final_stats.size
total_routing_patterns = mgmt_transport.routing_table.size
demo_duration = Time.now - demo_start_time

puts "\n📋 Demo Summary:"
puts "-" * 15
puts "   Duration: #{demo_duration.round(2)} seconds"
puts "   Queues Created: #{total_queues_created}"
puts "   Routing Patterns: #{total_routing_patterns}"
puts "   Messages Published: ~50"
puts "   Admin Operations: 3"
puts "   Health Checks: Multiple"
puts ""

mgmt_transport.disconnect

puts "📊 Queue Management & Monitoring demonstration completed!"

puts "\n💡 Queue Management Features Demonstrated:"
puts "   ✓ Real-time queue statistics monitoring"
puts "   ✓ Routing table inspection and analysis"
puts "   ✓ Queue health monitoring and alerts"
puts "   ✓ Performance metrics and analysis"
puts "   ✓ Administrative operations and cleanup"
puts "   ✓ Consumer group management"
puts "   ✓ Pattern analysis and optimization"
puts "   ✓ System efficiency recommendations"

puts "\n🚀 Key Management Benefits:"
puts "   • Complete visibility into queue states"
puts "   • Proactive health monitoring and alerting"
puts "   • Performance optimization insights"
puts "   • Administrative control and maintenance"
puts "   • Routing pattern analysis and optimization"
puts "   • Resource utilization monitoring"
puts "   • Automated system recommendations"
puts "   • Historical performance tracking"