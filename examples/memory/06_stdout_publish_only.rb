#!/usr/bin/env ruby
# examples/memory/06_stdout_publish_only.rb
#
# STDOUT Transport Example - Publish Only
#
# This example demonstrates the STDOUT transport which is designed for
# publish-only scenarios - great for debugging, logging, or one-way
# message output without local processing.

require_relative '../../lib/smart_message'

puts "=== SmartMessage Example: STDOUT Transport (Publish Only) ==="
puts

# Configure SmartMessage for this example
SmartMessage.configure do |config|
  config.logger = STDERR  # Use STDERR for framework logs so STDOUT is clean
  config.log_level = :warn  # Reduce noise
end

# Define a Log Message for one-way output
class LogMessage < SmartMessage::Base
  description "Log entries that are output to STDOUT for external processing"

  property :level,
    description: "Log level (info, warn, error, debug)"
  property :component,
    description: "Component or service generating the log"
  property :message,
    description: "Human-readable log message"
  property :timestamp,
    default: -> { Time.now.iso8601 },
    description: "ISO8601 timestamp of when log was generated"
  property :context,
    description: "Optional additional context data"

  # Configure to use STDOUT transport (publish-only)
  config do
    transport SmartMessage::Transport::StdoutTransport.new
    from 'log-service'
  end
end

# Define a Metrics Message for monitoring systems
class MetricsMessage < SmartMessage::Base
  description "System metrics published to STDOUT for monitoring ingestion"

  property :metric_name,
    description: "Name of the metric (e.g., 'cpu_usage', 'memory_usage')"
  property :value,
    description: "Numeric value of the metric"
  property :unit,
    description: "Unit of measurement (%, MB, requests/sec, etc.)"
  property :tags,
    description: "Hash of tags for metric categorization"
  property :timestamp,
    default: -> { Time.now.to_i },
    description: "Unix timestamp of metric collection"

  config do
    transport SmartMessage::Transport::StdoutTransport.new(format: :json)  # JSON format for metrics
    from 'metrics-collector'
  end
end

# Define a Debug Message for pretty-printed output
class DebugMessage < SmartMessage::Base
  description "Debug messages with complex data structures for development"

  property :event,
    description: "Event or action being debugged"
  property :data,
    description: "Complex data structure to debug"
  property :stack_trace,
    description: "Optional stack trace for debugging"
  property :timestamp,
    default: -> { Time.now.iso8601 },
    description: "ISO8601 timestamp"

  config do
    transport SmartMessage::Transport::StdoutTransport.new(format: :pretty)  # Pretty format using amazing_print
    from 'debug-service'
  end
end

puts "📝 Publishing log messages to STDOUT..."
puts "=" * 50

# Create and publish various log messages
log_messages = [
  {
    level: "info",
    component: "user-service",
    message: "User authentication successful",
    context: { user_id: 12345, ip_address: "192.168.1.100" }
  },
  {
    level: "warn",
    component: "payment-service", 
    message: "Payment processing took longer than expected",
    context: { order_id: "ORD-001", processing_time_ms: 5500 }
  },
  {
    level: "error",
    component: "database-service",
    message: "Connection pool exhausted",
    context: { pool_size: 20, active_connections: 20, queue_length: 15 }
  }
]

log_messages.each do |log_data|
  message = LogMessage.new(**log_data)
  message.publish
  sleep(0.5)  # Small delay for readability
end

puts "\n📊 Publishing metrics to STDOUT (JSON format)..."
puts "=" * 50

# Create and publish system metrics
metrics_data = [
  {
    metric_name: "cpu_usage",
    value: 67.5,
    unit: "%",
    tags: { host: "web-01", environment: "production" }
  },
  {
    metric_name: "memory_usage", 
    value: 2048,
    unit: "MB",
    tags: { host: "web-01", environment: "production" }
  },
  {
    metric_name: "requests_per_second",
    value: 125,
    unit: "req/sec",
    tags: { service: "api-gateway", endpoint: "/api/users" }
  }
]

metrics_data.each do |metric_data|
  message = MetricsMessage.new(**metric_data)
  message.publish
  sleep(0.3)
end

puts "\n🐛 Publishing debug messages (Pretty format using amazing_print)..."
puts "=" * 50

# Create and publish debug messages with complex data
debug_data = [
  {
    event: "user_registration",
    data: {
      user: {
        id: 42,
        username: "developer",
        email: "dev@example.com",
        roles: ["admin", "developer"],
        preferences: {
          theme: "dark",
          notifications: true,
          language: "en"
        }
      },
      metadata: {
        ip: "10.0.0.1",
        user_agent: "Mozilla/5.0",
        session_id: "abc123xyz"
      }
    }
  },
  {
    event: "api_request_debug",
    data: {
      request: {
        method: "POST",
        url: "/api/v1/orders",
        headers: {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer token123"
        },
        body: {
          items: [
            { product_id: 1, quantity: 2, price: 29.99 },
            { product_id: 5, quantity: 1, price: 149.99 }
          ],
          total: 209.97
        }
      },
      response: {
        status: 201,
        data: { order_id: "ORD-2024-001", status: "pending" }
      }
    },
    stack_trace: ["app/controllers/api/orders_controller.rb:15:in `create'",
                  "actionpack/lib/action_controller/base.rb:123:in `process'"]
  }
]

debug_data.each do |debug_info|
  message = DebugMessage.new(**debug_info)
  message.publish
  sleep(0.5)
end

puts "\n" + "=" * 50
puts "🔍 Key Points About STDOUT Transport:"
puts "  ✓ Publish-only: No message processing"
puts "  ✓ Perfect for logging and debugging scenarios"
puts "  ✓ Great for integration with external systems"
puts "  ✓ Supports multiple formats: :jsonl (default), :json, :pretty"
puts "  ✓ Clean separation: output to STDOUT, logs to STDERR"
puts "  ✓ Subscription attempts are ignored with warnings"

puts "\n💡 Usage Ideas:"
puts "  • Debug message flow: ./my_app | grep 'MessageClass'"
puts "  • Feed log aggregators: ./my_app | fluentd"
puts "  • Pipe to analysis tools: ./my_app | jq '.metric_name'"
puts "  • Integration testing: capture and verify output"
puts "  • Development monitoring: real-time message visibility"

puts "\n⚠️  Note: If you need local message processing, use MemoryTransport instead!"
puts "=" * 80