#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Example demonstrating multi-transport functionality in SmartMessage
# This example shows how to configure and use multiple transports for a single message

require_relative '../lib/smart_message'

# Define a simple message class for demonstration
class MultiTransportMessage < SmartMessage::Base
  property :content, required: true
  property :priority, default: 'normal'
  
  # Configure multiple transports for this message
  transport [
    SmartMessage::Transport::StdoutTransport.new(format: :pretty),
    SmartMessage::Transport::MemoryTransport.new(auto_process: false)
  ]
end

# Example 1: Single transport (backward compatibility)
class SingleTransportMessage < SmartMessage::Base
  property :data, required: true
  
  # Single transport works exactly as before
  transport SmartMessage::Transport::StdoutTransport.new
end

puts "=== SmartMessage Multi-Transport Demo ==="
puts

# Test single transport (backward compatibility)
puts "1. Single Transport Example:"
single_msg = SingleTransportMessage.new(data: "Hello from single transport", from: "demo_app")
puts "   Transport count: #{single_msg.transports.length}"
puts "   Is single transport? #{single_msg.single_transport?}"
single_msg.publish
puts

# Test multiple transports
puts "2. Multiple Transport Example:"
multi_msg = MultiTransportMessage.new(
  content: "Hello from multiple transports!",
  priority: "high",
  from: "demo_app"
)
puts "   Transport count: #{multi_msg.transports.length}"
puts "   Is multiple transports? #{multi_msg.multiple_transports?}"
puts "   Transport classes: #{multi_msg.transports.map { |t| t.class.name.split('::').last }.join(', ')}"
puts "   Primary transport (backward compat): #{multi_msg.transport.class.name.split('::').last}"
multi_msg.publish
puts

# Test instance-level transport override
puts "3. Instance-level Transport Override:"
override_msg = MultiTransportMessage.new(content: "Override example", from: "demo_app")
override_msg.transport(SmartMessage::Transport::StdoutTransport.new(format: :json))
puts "   Override transport count: #{override_msg.transports.length}"
puts "   Override is single? #{override_msg.single_transport?}"
override_msg.publish
puts

# Test transport failure resilience
puts "4. Transport Failure Resilience:"
class FailingTransport < SmartMessage::Transport::Base
  def publish(message)
    raise StandardError, "Simulated transport failure"
  end
end

class ResilientMessage < SmartMessage::Base
  property :message, required: true
  
  transport [
    FailingTransport.new,
    SmartMessage::Transport::StdoutTransport.new(format: :compact)
  ]
end

resilient_msg = ResilientMessage.new(message: "Testing failure resilience", from: "demo_app")
puts "   Publishing with one failing transport..."
begin
  resilient_msg.publish
  puts "   ✓ Message published successfully despite transport failure"
rescue => e
  puts "   ✗ Unexpected error: #{e.message}"
end
puts

# Test all transports failing
puts "5. All Transports Failing:"
class AllFailingMessage < SmartMessage::Base
  property :data
  
  transport [
    FailingTransport.new,
    FailingTransport.new
  ]
end

failing_msg = AllFailingMessage.new(data: "This will fail", from: "demo_app")
puts "   Publishing with all transports failing..."
begin
  failing_msg.publish
  puts "   ✗ Expected failure did not occur"
rescue SmartMessage::Errors::PublishError => e
  puts "   ✓ Correctly caught PublishError: #{e.message.split(':').first}"
rescue => e
  puts "   ✗ Unexpected error type: #{e.class} - #{e.message}"
end
puts

puts "=== Demo Complete ==="