#!/usr/bin/env ruby
# examples/redis_queue/enhanced_04_advanced_routing.rb
# Redis Enhanced Transport - Advanced Routing and Filtering Demo

require_relative '../../lib/smart_message'
require 'smart_message/transport/redis_enhanced_transport'
require 'json'

puts "🚀 Redis Enhanced Transport - Advanced Routing Demo"
puts "=" * 53

# Create enhanced Redis transport
transport = SmartMessage::Transport::RedisEnhancedTransport.new(
  url: 'redis://localhost:6379',
  db: 5,  # Use database 5 for advanced routing examples
  auto_subscribe: true
)

#==============================================================================
# Define Complex Microservices Message Classes
#==============================================================================

class ApiRequestMessage < SmartMessage::Base
  from 'api-gateway'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :request_id, required: true
  property :endpoint, required: true
  property :method, required: true
  property :user_id
  property :service_target, required: true
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "🌐 [API GATEWAY] #{data['method']} #{data['endpoint']}"
    puts "   Request ID: #{data['request_id']}"
    puts "   Target: #{data['service_target']}"
    puts "   User: #{data['user_id'] || 'anonymous'}"
    puts "   Route: #{header.from} → #{header.to}"
    puts
  end
end

class DatabaseQueryMessage < SmartMessage::Base
  from 'orm-layer'
  to 'database-service'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :query_id, required: true
  property :query_type, required: true  # SELECT, INSERT, UPDATE, DELETE
  property :table, required: true
  property :execution_time_ms
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "🗄️  [DATABASE] #{data['query_type']} on #{data['table']}"
    puts "   Query ID: #{data['query_id']}"
    puts "   Execution: #{data['execution_time_ms']}ms"
    puts "   Route: #{header.from} → #{header.to}"
    puts
  end
end

class LogMessage < SmartMessage::Base
  from 'various-services'
  to 'log-aggregator'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :log_id, required: true
  property :level, required: true      # DEBUG, INFO, WARN, ERROR, FATAL
  property :service, required: true
  property :message, required: true
  property :context, default: {}
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    level_emoji = {
      'DEBUG' => '🔍',
      'INFO' => 'ℹ️',
      'WARN' => '⚠️',
      'ERROR' => '❌',
      'FATAL' => '💀'
    }[data['level']] || '📝'
    
    puts "#{level_emoji} [LOG AGGREGATOR] #{data['level']} from #{data['service']}"
    puts "   #{data['message']}"
    puts "   Context: #{data['context']}" unless data['context'].empty?
    puts "   Route: #{header.from} → #{header.to}"
    puts
  end
end

class MetricsMessage < SmartMessage::Base
  from 'monitoring-agents'
  to 'metrics-collector'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :metric_id, required: true
  property :metric_name, required: true
  property :value, required: true
  property :tags, default: {}
  property :timestamp, default: -> { Time.now.to_f }
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "📊 [METRICS] #{data['metric_name']}: #{data['value']}"
    puts "   Tags: #{data['tags']}"
    puts "   From: #{header.from}"
    puts
  end
end

#==============================================================================
# Advanced Routing Demonstration Functions
#==============================================================================

def setup_service_specific_routing(transport)
  puts "🎯 Setting up service-specific routing patterns..."
  puts
  
  # Route API requests to specific services
  transport.where.from('api-gateway').to('user-service').subscribe
  transport.where.from('api-gateway').to('order-service').subscribe
  transport.where.from('api-gateway').to('payment-service').subscribe
  
  puts "✅ API Gateway routing configured for:"
  puts "   • user-service"
  puts "   • order-service" 
  puts "   • payment-service"
  puts
  
  # Database queries from different ORM layers
  transport.where.from('user-orm').type('DatabaseQueryMessage').subscribe
  transport.where.from('order-orm').type('DatabaseQueryMessage').subscribe
  transport.where.from('analytics-orm').type('DatabaseQueryMessage').subscribe
  
  puts "✅ Database query routing configured for:"
  puts "   • user-orm queries"
  puts "   • order-orm queries"
  puts "   • analytics-orm queries"
  puts
end

def setup_log_level_filtering(transport)
  puts "📋 Setting up log level filtering patterns..."
  puts
  
  # Different log processing based on level and service
  transport.subscribe_pattern("logmessage.user_service.log_aggregator")
  transport.subscribe_pattern("logmessage.payment_service.log_aggregator") 
  transport.subscribe_pattern("logmessage.critical_service.log_aggregator")
  
  puts "✅ Log filtering configured for:"
  puts "   • user-service logs"
  puts "   • payment-service logs"
  puts "   • critical-service logs"
  puts
end

def setup_metrics_collection_routing(transport)
  puts "📈 Setting up metrics collection routing..."
  puts
  
  # Collect metrics from different monitoring agents
  transport.where.type('MetricsMessage').from('cpu-monitor').subscribe
  transport.where.type('MetricsMessage').from('memory-monitor').subscribe
  transport.where.type('MetricsMessage').from('disk-monitor').subscribe
  transport.where.type('MetricsMessage').from('network-monitor').subscribe
  
  puts "✅ Metrics collection configured for:"
  puts "   • CPU monitoring"
  puts "   • Memory monitoring"
  puts "   • Disk monitoring"
  puts "   • Network monitoring"
  puts
end

def demonstrate_dynamic_routing
  puts "🔄 Demonstrating dynamic routing scenarios..."
  puts
  
  # Scenario 1: API Gateway routes to different services
  api_requests = [
    { service: 'user-service', endpoint: '/users/profile', method: 'GET' },
    { service: 'order-service', endpoint: '/orders/create', method: 'POST' },
    { service: 'payment-service', endpoint: '/payments/process', method: 'POST' }
  ]
  
  api_requests.each_with_index do |req, i|
    message = ApiRequestMessage.new(
      request_id: "REQ-#{Time.now.to_i}-#{i}",
      endpoint: req[:endpoint],
      method: req[:method],
      service_target: req[:service],
      user_id: "user_#{100 + i}"
    )
    message.to(req[:service])  # Dynamic routing
    message.publish
    
    sleep 0.1
  end
  
  puts "✅ Published 3 API requests with dynamic routing"
  puts
end

def demonstrate_database_query_routing
  puts "🗄️  Demonstrating database query routing..."
  puts
  
  queries = [
    { orm: 'user-orm', type: 'SELECT', table: 'users', time: 15 },
    { orm: 'order-orm', type: 'INSERT', table: 'orders', time: 8 },
    { orm: 'analytics-orm', type: 'UPDATE', table: 'metrics', time: 45 }
  ]
  
  queries.each_with_index do |query, i|
    message = DatabaseQueryMessage.new(
      query_id: "QRY-#{Time.now.to_i}-#{i}",
      query_type: query[:type],
      table: query[:table],
      execution_time_ms: query[:time]
    )
    message.from(query[:orm])  # Dynamic sender
    message.publish
    
    sleep 0.1  
  end
  
  puts "✅ Published 3 database queries from different ORM layers"
  puts
end

def demonstrate_log_aggregation_routing
  puts "📋 Demonstrating log aggregation routing..."
  puts
  
  log_entries = [
    { service: 'user-service', level: 'INFO', msg: 'User authentication successful' },
    { service: 'payment-service', level: 'ERROR', msg: 'Credit card validation failed' },
    { service: 'critical-service', level: 'FATAL', msg: 'Database connection lost' },
    { service: 'user-service', level: 'DEBUG', msg: 'Cache miss for user profile' }
  ]
  
  log_entries.each_with_index do |log, i|
    message = LogMessage.new(
      log_id: "LOG-#{Time.now.to_i}-#{i}",
      level: log[:level],
      service: log[:service],
      message: log[:msg],
      context: { 
        thread_id: "thread_#{i}", 
        request_id: "req_#{100 + i}"
      }
    )
    message.from(log[:service])
    message.publish
    
    sleep 0.1
  end
  
  puts "✅ Published 4 log entries from different services"
  puts
end

def demonstrate_metrics_collection
  puts "📊 Demonstrating metrics collection..."
  puts
  
  metrics = [
    { agent: 'cpu-monitor', name: 'cpu.usage.percent', value: 78.5, tags: { host: 'web-01' } },
    { agent: 'memory-monitor', name: 'memory.used.bytes', value: 2147483648, tags: { host: 'web-01' } },
    { agent: 'disk-monitor', name: 'disk.free.percent', value: 45.2, tags: { mount: '/data' } },
    { agent: 'network-monitor', name: 'network.bytes.sent', value: 1048576, tags: { interface: 'eth0' } }
  ]
  
  metrics.each_with_index do |metric, i|
    message = MetricsMessage.new(
      metric_id: "MET-#{Time.now.to_i}-#{i}",
      metric_name: metric[:name],
      value: metric[:value],
      tags: metric[:tags]
    )
    message.from(metric[:agent])
    message.publish
    
    sleep 0.1
  end
  
  puts "✅ Published 4 metrics from different monitoring agents"
  puts
end

def show_routing_patterns_summary
  puts "📋 Active Routing Patterns Summary:"
  puts "=" * 40
  puts
  
  puts "🎯 Service-to-Service Routing:"
  puts "   • api-gateway → user-service"
  puts "   • api-gateway → order-service"
  puts "   • api-gateway → payment-service"
  puts
  
  puts "🗄️  Database Query Routing:"
  puts "   • user-orm → database-service"
  puts "   • order-orm → database-service"
  puts "   • analytics-orm → database-service"
  puts
  
  puts "📋 Log Aggregation Routing:"
  puts "   • user-service → log-aggregator"
  puts "   • payment-service → log-aggregator"
  puts "   • critical-service → log-aggregator"
  puts
  
  puts "📊 Metrics Collection Routing:"
  puts "   • cpu-monitor → metrics-collector"
  puts "   • memory-monitor → metrics-collector"
  puts "   • disk-monitor → metrics-collector"
  puts "   • network-monitor → metrics-collector"
  puts
end

#==============================================================================
# Main Demonstration
#==============================================================================

begin
  puts "🔧 Checking Redis connection..."
  unless transport.connected?
    puts "❌ Redis not available. Please start Redis server:"
    puts "   brew services start redis  # macOS"
    puts "   sudo service redis start   # Linux"
    exit 1
  end
  puts "✅ Connected to Redis"
  puts
  
  # Set up advanced routing patterns
  setup_service_specific_routing(transport)
  setup_log_level_filtering(transport)
  setup_metrics_collection_routing(transport)
  
  # Subscribe message classes
  ApiRequestMessage.subscribe
  DatabaseQueryMessage.subscribe
  LogMessage.subscribe
  MetricsMessage.subscribe
  
  puts "⏳ Waiting for subscriptions to be established..."
  sleep 1
  
  # Demonstrate different routing scenarios
  demonstrate_dynamic_routing
  sleep 0.5
  
  demonstrate_database_query_routing
  sleep 0.5
  
  demonstrate_log_aggregation_routing
  sleep 0.5
  
  demonstrate_metrics_collection
  sleep 1
  
  puts "⏳ Processing messages (waiting 3 seconds)..."
  sleep 3
  
  # Show summary
  show_routing_patterns_summary
  
  # Show active pattern subscriptions
  puts "🔍 Active Pattern Subscriptions:"
  pattern_subscriptions = transport.instance_variable_get(:@pattern_subscriptions)
  if pattern_subscriptions && pattern_subscriptions.any?
    pattern_subscriptions.each_with_index do |pattern, i|
      puts "   #{i + 1}. #{pattern}"
    end
  else
    puts "   No pattern subscriptions found"
  end
  puts
  
  puts "🎉 Advanced Routing Demo completed!"
  puts
  puts "💡 Advanced Routing Benefits:"
  puts "   • Precise message targeting with multiple conditions"
  puts "   • Dynamic routing based on message content"
  puts "   • Service-specific pattern matching"
  puts "   • Complex microservices communication patterns"
  puts "   • Flexible subscription management"
  
rescue Interrupt
  puts "\n👋 Demo interrupted by user"
rescue => e
  puts "💥 Error: #{e.message}"
  puts e.backtrace[0..3]
ensure
  puts "\n🧹 Cleaning up..."
  transport&.disconnect
  puts "✅ Disconnected from Redis"
end