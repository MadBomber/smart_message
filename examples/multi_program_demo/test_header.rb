#!/usr/bin/env ruby

require_relative 'messages/health_check_message'

puts "Creating message with from/to in constructor..."
health_check = Messages::HealthCheckMessage.new(
  timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
  check_id: 'test-123',
  from: 'health-department',
  to: nil
)

puts "Calling validate!..."
health_check.validate!

puts "✓ Validation passed!"
puts "Header from: #{health_check._sm_header.from}"
puts "Header to: #{health_check._sm_header.to}"