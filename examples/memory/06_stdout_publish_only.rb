#!/usr/bin/env ruby
# examples/memory/06_stdout_publish_only.rb
#
# STDOUT Transport Example - Publish Only
#
# This example demonstrates the STDOUT transport with different formats
# using a single message class that can be configured with different
# transport instances.

require_relative '../../lib/smart_message'

puts "=== SmartMessage Example: STDOUT Transport Format Demonstrations ==="
puts

# Configure SmartMessage for this example
SmartMessage.configure do |config|
  config.logger = STDERR  # Use STDERR for framework logs so STDOUT is clean
  config.log_level = :warn  # Reduce noise
end

# Define a simple message class for format demonstration
class DemoMessage < SmartMessage::Base
  description "Simple demonstration message for format testing"

  property :first_name,
    description: "Person's first name"
  property :last_name,
    description: "Person's last name"

  # Default config - will be overridden with transport instance replacement
  config do
    transport SmartMessage::Transport::StdoutTransport.new
    from 'demo-service'
  end
end

puts "🎨 Example 1: Pretty Format (:pretty) - 1 message"
puts "=" * 60

# Create a simple message for pretty formatting
message_data = {
  first_name: "Alice",
  last_name: "Johnson"
}

# Replace the message's transport with :pretty format
message = DemoMessage.new(**message_data)
message.transport SmartMessage::Transport::StdoutTransport.new(format: :pretty)
message.publish

puts
puts
puts "📋 Example 2: JSONL Format (:jsonl) - 2 messages"
puts "=" * 60

# Create two simple messages for JSONL format
jsonl_messages = [
  {
    first_name: "Bob",
    last_name: "Smith"
  },
  {
    first_name: "Carol",
    last_name: "Williams"
  }
]

# Replace transport with :jsonl format and publish both messages
jsonl_messages.each do |msg_data|
  message = DemoMessage.new(**msg_data)
  message.transport SmartMessage::Transport::StdoutTransport.new(format: :jsonl)
  message.publish
end

puts
puts
puts "📊 Example 3: JSON Format (:json) - 3 messages"
puts "=" * 60

# Create three simple messages for JSON format
json_messages = [
  {
    first_name: "David",
    last_name: "Brown"
  },
  {
    first_name: "Emma",
    last_name: "Davis"
  },
  {
    first_name: "Frank",
    last_name: "Miller"
  }
]

# Replace transport with :json format and publish all three messages
json_messages.each do |msg_data|
  message = DemoMessage.new(**msg_data)
  message.transport SmartMessage::Transport::StdoutTransport.new(format: :json)
  message.publish
end

puts
puts
puts "\n🔍 Format Comparison Summary:"
puts "  🎨 :pretty - Beautiful, colorized output using amazing_print"
puts "  📋 :jsonl  - JSON Lines format, one message per line (default)"
puts "  📊 :json   - Compact JSON format without newlines"
puts
puts "💡 Usage Ideas:"
puts "  • Debug message flow: ./my_app | grep 'first_name'"
puts "  • Feed log aggregators: ./my_app | fluentd"
puts "  • Pipe to analysis tools: ./my_app | jq '.last_name'"
puts "  • Integration testing: capture and verify output"
puts "  • Development monitoring: real-time message visibility"
puts
puts "⚠️  Note: If you need local message processing, use MemoryTransport instead!"
puts "=" * 80
