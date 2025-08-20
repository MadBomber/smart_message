#!/usr/bin/env ruby
# examples/11_global_configuration_example.rb
#
# Global Configuration System Example
#
# This example demonstrates how to use SmartMessage's global configuration
# system to set default logger, transport, and serializer for all message
# classes in your application.

require_relative '../lib/smart_message'

puts "=== SmartMessage Global Configuration Example ==="
puts

# Example 1: Default behavior (no configuration) - NO LOGGING
puts "1. Default Framework Behavior (NO LOGGING):"
puts "   Default Logger: #{SmartMessage::Logger.default.class}"
puts "   Default Transport: #{SmartMessage::Transport.default.class}" 
puts "   Default Serializer: #{SmartMessage::Serializer.default.class}"
puts "   Note: No logging unless explicitly configured!"
puts

# Example 2: Configure logging with string path
puts "2. Configuring Logging with String Path:"
SmartMessage.configure do |config|
  config.logger = "log/my_application.log"  # String = Lumberjack logger with this path
  config.transport = SmartMessage::Transport::StdoutTransport.new(loopback: true)
  config.serializer = SmartMessage::Serializer::Json.new
end

puts "   Configured Logger: #{SmartMessage::Logger.default.class}"
puts "   Log File: #{SmartMessage::Logger.default.log_file rescue 'N/A'}"
puts "   Configured Transport: #{SmartMessage::Transport.default.class}"
puts "   Configured Serializer: #{SmartMessage::Serializer.default.class}"
puts

# Reset for next example
SmartMessage.reset_configuration!

# Example 3: Configure with :default symbol (framework defaults)
puts "3. Configuring with :default Symbol:"
SmartMessage.configure do |config|
  config.logger = :default  # Use Lumberjack with default settings
  config.transport = SmartMessage::Transport::StdoutTransport.new(loopback: true)
  config.serializer = SmartMessage::Serializer::Json.new
end

puts "   Configured Logger: #{SmartMessage::Logger.default.class}"
puts "   Log File: #{SmartMessage::Logger.default.log_file rescue 'N/A'}"
puts "   Configured Transport: #{SmartMessage::Transport.default.class}"
puts "   Configured Serializer: #{SmartMessage::Serializer.default.class}"
puts

# Example 4: Message classes automatically use global configuration
puts "4. Message Classes Using Global Configuration:"

class NotificationMessage < SmartMessage::Base
  property :recipient
  property :message
  property :priority, default: 'normal'
  
  # No config block needed - automatically uses global configuration!
  
  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    data = JSON.parse(message_payload)
    
    priority_emoji = case data['priority']
                     when 'high' then '🔴'
                     when 'medium' then '🟡'
                     else '🟢'
                     end
    
    puts "#{priority_emoji} Notification: #{data['message']} (to: #{data['recipient']})"
  end
end

class OrderStatusMessage < SmartMessage::Base
  property :order_id
  property :status
  property :customer_id
  
  # Also uses global configuration automatically
  
  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    data = JSON.parse(message_payload)
    
    status_emoji = case data['status']
                   when 'confirmed' then '✅'
                   when 'shipped' then '📦'
                   when 'delivered' then '🎉'
                   when 'cancelled' then '❌'
                   else '⏳'
                   end
    
    puts "#{status_emoji} Order #{data['order_id']}: #{data['status']}"
  end
end

# Subscribe to messages to see them in action
NotificationMessage.subscribe
OrderStatusMessage.subscribe

puts "   Message classes configured automatically!"
puts

# Example 4: Creating and publishing messages
puts "4. Publishing Messages (using global configuration):"

notification = NotificationMessage.new(
  recipient: "admin@example.com",
  message: "System maintenance scheduled for tonight",
  priority: "high",
  from: "SystemService"
)

order_status = OrderStatusMessage.new(
  order_id: "ORD-12345",
  status: "shipped",
  customer_id: "CUST-001",
  from: "OrderService"
)

puts "\n--- Publishing Messages ---"
notification.publish
order_status.publish

# Give time for async processing
sleep(0.5)

puts

# Example 5: Individual classes can still override global configuration
puts "5. Overriding Global Configuration for Specific Classes:"

class SpecialMessage < SmartMessage::Base
  property :content
  
  # Override just the logger, keep global transport and serializer
  config do
    logger SmartMessage::Logger::Default.new(log_file: STDERR, level: Logger::WARN)
    # transport and serializer still use global configuration
  end
  
  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    data = JSON.parse(message_payload)
    puts "⭐ Special processing: #{data['content']}"
  end
end

SpecialMessage.subscribe

special = SpecialMessage.new(
  content: "This uses custom logger but global transport/serializer",
  from: "SpecialService"
)

puts "   SpecialMessage logger: #{SpecialMessage.logger.class}"
puts "   (Should be SmartMessage::Logger::Default with STDERR output)"

special.publish
sleep(0.5)

puts

# Example 6: Resetting configuration
puts "6. Resetting to Framework Defaults:"
SmartMessage.reset_configuration!

puts "   After reset:"
puts "   Logger: #{SmartMessage::Logger.default.class}"
puts "   Transport: #{SmartMessage::Transport.default.class}"
puts "   Serializer: #{SmartMessage::Serializer.default.class}"

puts "\n✨ Global Configuration Example Complete!"
puts
puts "Key Benefits:"
puts "• Set defaults once for entire application"
puts "• All message classes inherit global configuration automatically"
puts "• Individual classes can still override when needed"
puts "• Clean, centralized configuration management"
puts "• No need for repetitive config blocks in every message class"
puts "• Easy integration with Rails.logger or any other logger"
puts
puts "Configuration Options Summary:"
puts "  # No configuration = NO LOGGING (new default behavior)"
puts "  # No SmartMessage.configure block needed"
puts
puts "  # String path = Lumberjack logger with that file"
puts "  SmartMessage.configure do |config|"
puts "    config.logger = 'log/my_app.log'    # String path"
puts "  end"
puts
puts "  # STDOUT/STDERR = Lumberjack logger to console"
puts "  SmartMessage.configure do |config|"
puts "    config.logger = STDOUT              # Log to STDOUT"
puts "    config.logger = STDERR              # Log to STDERR"
puts "  end"
puts
puts "  # :default symbol = Lumberjack with framework defaults" 
puts "  SmartMessage.configure do |config|"
puts "    config.logger = :default            # Framework default (file)"
puts "  end"
puts
puts "  # Custom logger object = Use that logger"
puts "  SmartMessage.configure do |config|"
puts "    config.logger = Rails.logger        # Rails logger"
puts "    config.logger = MyApp::Logger.new   # Custom logger"
puts "  end"
puts
puts "  # Explicit nil = No logging (same as no configuration)"
puts "  SmartMessage.configure do |config|"
puts "    config.logger = nil                 # Explicit no logging"
puts "  end"

# Clean up test file
File.delete('test_config.rb') if File.exist?('test_config.rb')