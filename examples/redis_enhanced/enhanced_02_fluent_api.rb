#!/usr/bin/env ruby
# examples/redis_queue/enhanced_02_fluent_api.rb
# Redis Enhanced Transport - Fluent API Demonstration

require_relative '../../lib/smart_message'
require 'smart_message/transport/redis_enhanced_transport'

puts "🚀 Redis Enhanced Transport - Fluent API Demo"
puts "=" * 50

# Create enhanced Redis transport instance
transport = SmartMessage::Transport::RedisEnhancedTransport.new(
  url: 'redis://localhost:6379',
  db: 3,  # Use database 3 for fluent API examples
  auto_subscribe: true
)

#==============================================================================
# Define Message Classes for Microservices Architecture
#==============================================================================

class UserRegistrationMessage < SmartMessage::Base
  from 'web-app'
  to 'user-service'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :user_id, required: true
  property :email, required: true
  property :name, required: true
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "👤 [USER SERVICE] New user registration: #{data['name']} (#{data['email']})"
    puts "   User ID: #{data['user_id']}"
    puts
  end
end

class EmailNotificationMessage < SmartMessage::Base
  from 'user-service'
  to 'notification-service'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :recipient, required: true
  property :subject, required: true
  property :body, required: true
  property :template, default: 'default'
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "📧 [NOTIFICATION SERVICE] Sending email to #{data['recipient']}"
    puts "   Subject: #{data['subject']}"
    puts "   Template: #{data['template']}"
    puts
  end
end

class AnalyticsEventMessage < SmartMessage::Base
  from 'various-services'
  to 'analytics-service'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :event_type, required: true
  property :user_id
  property :metadata, default: {}
  property :timestamp, default: -> { Time.now.iso8601 }
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "📊 [ANALYTICS] Event: #{data['event_type']}"
    puts "   User: #{data['user_id'] || 'anonymous'}"
    puts "   Timestamp: #{data['timestamp']}"
    puts "   Metadata: #{data['metadata']}"
    puts
  end
end

class AdminAlertMessage < SmartMessage::Base
  from 'monitoring'
  to 'admin-panel'
  
  transport transport
  serializer SmartMessage::Serializer::Json.new
  
  property :severity, required: true
  property :message, required: true
  property :service, required: true
  
  def self.process(wrapper)
    header, payload = wrapper.split
    data = JSON.parse(payload)
    
    puts "⚠️  [ADMIN PANEL] #{data['severity'].upcase} from #{data['service']}"
    puts "   #{data['message']}"
    puts
  end
end

#==============================================================================
# Fluent API Demonstration Functions
#==============================================================================

def demo_basic_fluent_subscriptions(transport)
  puts "🔗 Setting up fluent API subscriptions..."
  puts
  
  # Basic fluent subscriptions
  transport.where.from('web-app').subscribe
  puts "✅ Subscribed to all messages FROM 'web-app'"
  
  transport.where.to('user-service').subscribe  
  puts "✅ Subscribed to all messages TO 'user-service'"
  
  transport.where.type('EmailNotificationMessage').subscribe
  puts "✅ Subscribed to all 'EmailNotificationMessage' messages"
  puts
end

def demo_combined_fluent_subscriptions(transport)
  puts "🎯 Setting up combined fluent API subscriptions..."
  puts
  
  # Combined conditions
  transport.where
    .from('user-service')
    .to('notification-service')
    .subscribe
  puts "✅ Subscribed to messages FROM 'user-service' TO 'notification-service'"
  
  transport.where
    .type('AnalyticsEventMessage')
    .from('web-app')
    .subscribe
  puts "✅ Subscribed to 'AnalyticsEventMessage' FROM 'web-app'"
  
  # Three-way combination
  transport.where
    .type('AdminAlertMessage')
    .from('monitoring')
    .to('admin-panel')
    .subscribe
  puts "✅ Subscribed to 'AdminAlertMessage' FROM 'monitoring' TO 'admin-panel'"
  puts
end

def demo_wildcard_subscriptions(transport)
  puts "🌟 Setting up wildcard pattern subscriptions..."
  puts
  
  # Service-specific patterns
  transport.where.from('analytics-service').subscribe
  puts "✅ Subscribed to all messages from analytics service"
  
  transport.where.to('notification-service').subscribe  
  puts "✅ Subscribed to all messages to notification service"
  
  # Catch-all analytics events
  transport.where.type('AnalyticsEventMessage').subscribe
  puts "✅ Subscribed to all analytics events regardless of source/destination"
  puts
end

def publish_sample_workflow
  puts "📤 Publishing sample microservices workflow..."
  puts
  
  # 1. User registration from web app
  registration = UserRegistrationMessage.new(
    user_id: 'user_12345',
    email: 'john.doe@example.com',
    name: 'John Doe'
  )
  registration.publish
  
  sleep 0.1 # Small delay to see message processing order
  
  # 2. Welcome email notification
  welcome_email = EmailNotificationMessage.new(
    recipient: 'john.doe@example.com',
    subject: 'Welcome to Our Platform!',
    body: 'Thank you for joining us, John!',
    template: 'welcome'
  )
  welcome_email.publish
  
  sleep 0.1
  
  # 3. Analytics event from user service
  analytics = AnalyticsEventMessage.new(
    event_type: 'user_registered',
    user_id: 'user_12345',
    metadata: { 
      source: 'web_signup',
      referrer: 'google_ads',
      campaign: 'spring_2024'
    }
  )
  analytics.from('user-service')  # Override default 'from'
  analytics.publish
  
  sleep 0.1
  
  # 4. Another analytics event from web-app
  web_analytics = AnalyticsEventMessage.new(
    event_type: 'signup_completed',
    user_id: 'user_12345',
    metadata: { 
      page: '/signup/complete',
      time_spent: 45
    }
  )
  web_analytics.from('web-app')
  web_analytics.publish
  
  sleep 0.1
  
  # 5. Admin alert from monitoring
  admin_alert = AdminAlertMessage.new(
    severity: 'info',
    message: 'New user registration completed successfully',
    service: 'user-service'
  )
  admin_alert.publish
  
  puts "✅ Published complete user registration workflow (5 messages)"
  puts
end

def demonstrate_pattern_building(transport)
  puts "🔨 Demonstrating pattern building..."
  puts
  
  # Show how patterns are built
  builder = transport.where.from('web-app').to('user-service').type('UserRegistrationMessage')
  pattern = builder.build
  puts "Pattern for web-app → user-service UserRegistrationMessage:"
  puts "   #{pattern}"
  puts
  
  builder2 = transport.where.type('AnalyticsEventMessage')
  pattern2 = builder2.build
  puts "Pattern for any AnalyticsEventMessage:"
  puts "   #{pattern2}"
  puts
  
  builder3 = transport.where.from('monitoring')
  pattern3 = builder3.build
  puts "Pattern for any message from monitoring:"
  puts "   #{pattern3}"
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
  
  # Demonstrate pattern building first
  demonstrate_pattern_building(transport)
  
  # Set up various fluent API subscriptions
  demo_basic_fluent_subscriptions(transport)
  demo_combined_fluent_subscriptions(transport)
  demo_wildcard_subscriptions(transport)
  
  # Subscribe message classes to their handlers
  UserRegistrationMessage.subscribe
  EmailNotificationMessage.subscribe
  AnalyticsEventMessage.subscribe
  AdminAlertMessage.subscribe
  
  puts "⏳ Waiting for subscriptions to be established..."
  sleep 1
  
  # Publish sample workflow
  publish_sample_workflow
  
  puts "⏳ Processing messages (waiting 3 seconds)..."
  sleep 3
  
  # Show active patterns
  puts "📋 Active Pattern Subscriptions:"
  pattern_subscriptions = transport.instance_variable_get(:@pattern_subscriptions)
  if pattern_subscriptions && pattern_subscriptions.any?
    pattern_subscriptions.each_with_index do |pattern, i|
      puts "   #{i + 1}. #{pattern}"
    end
  else
    puts "   No pattern subscriptions found"
  end
  puts
  
  puts "🎉 Fluent API Demo completed!"
  puts "💡 Key takeaways:"
  puts "   • Fluent API makes complex subscriptions readable"
  puts "   • Combine .from(), .to(), and .type() for precise routing"
  puts "   • Patterns are built as: type.from.to with wildcards (*)"
  puts "   • Each .subscribe() call adds a new pattern to the transport"
  
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