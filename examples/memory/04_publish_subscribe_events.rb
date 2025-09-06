#!/usr/bin/env ruby
# examples/02_publish_subscribe_events.rb
#
# 1-to-Many Messaging Example: Event Notification System
#
# This example demonstrates publish-subscribe messaging where one event publisher
# sends notifications to multiple subscribers (email service, SMS service, audit logger).

require_relative '../../lib/smart_message'

puts "=== SmartMessage Example: Publish-Subscribe Event Notifications ==="
puts

# Define the User Event Message
class UserEventMessage < SmartMessage::Base
  description "Broadcasts user activity events to multiple notification services"
  
  property :event_id, 
    description: "Unique identifier for this event (e.g., EVT-1001)"
  property :event_type, 
    description: "Type of user event: 'user_registered', 'user_login', 'password_changed', etc."
  property :user_id, 
    description: "Unique identifier for the user performing the action"
  property :user_email, 
    description: "Email address of the user for notification purposes"
  property :user_name, 
    description: "Display name of the user"
  property :timestamp, 
    description: "ISO8601 timestamp when the event occurred"
  property :metadata, 
    description: "Additional event-specific data (source, location, IP, etc.)"

  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    serializer SmartMessage::Serializer::Json.new
  end

  # Default processor - just logs the event
  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    event_data = JSON.parse(message_payload)
    puts "📡 Event broadcasted: #{event_data['event_type']} for user #{event_data['user_id']}"
  end
end

# Email Notification Service
class EmailService
  def initialize
    puts "📧 EmailService: Starting up..."
    # Subscribe to user events with custom processor
    UserEventMessage.subscribe('EmailService.handle_user_event')
  end

  def self.handle_user_event(wrapper)
    service = new
    service.process_event(wrapper)
  end

  def process_event(wrapper)
    message_header, message_payload = wrapper.split
    event_data = JSON.parse(message_payload)
    
    case event_data['event_type']
    when 'user_registered'
      send_welcome_email(event_data)
    when 'password_changed'
      send_security_alert(event_data)
    when 'user_login'
      # Could send login notifications for suspicious activity
      log_email_activity("Login notification skipped for #{event_data['user_email']}")
    else
      log_email_activity("No email action for event: #{event_data['event_type']}")
    end
  end

  private

  def send_welcome_email(event_data)
    puts "📧 EmailService: Sending welcome email to #{event_data['user_email']}"
    puts "   Subject: Welcome to our platform, #{event_data['user_name']}!"
    puts "   Content: Thank you for registering..."
    simulate_email_delivery
  end

  def send_security_alert(event_data)
    puts "📧 EmailService: Sending security alert to #{event_data['user_email']}"
    puts "   Subject: Your password was changed"
    puts "   Content: If this wasn't you, please contact support..."
    simulate_email_delivery
  end

  def log_email_activity(message)
    puts "📧 EmailService: #{message}"
  end

  def simulate_email_delivery
    # Simulate email sending delay
    sleep(0.1)
    puts "   ✉️  Email queued for delivery"
  end
end

# SMS Notification Service
class SMSService
  def initialize
    puts "📱 SMSService: Starting up..."
    UserEventMessage.subscribe('SMSService.handle_user_event')
  end

  def self.handle_user_event(wrapper)
    service = new
    service.process_event(wrapper)
  end

  def process_event(wrapper)
    message_header, message_payload = wrapper.split
    event_data = JSON.parse(message_payload)
    
    case event_data['event_type']
    when 'password_changed'
      send_security_sms(event_data)
    when 'user_login'
      if suspicious_login?(event_data)
        send_login_alert(event_data)
      else
        log_sms_activity("Normal login, no SMS sent for #{event_data['user_id']}")
      end
    else
      log_sms_activity("No SMS action for event: #{event_data['event_type']}")
    end
  end

  private

  def send_security_sms(event_data)
    phone = get_user_phone(event_data['user_id'])
    puts "📱 SMSService: Sending security SMS to #{phone}"
    puts "   Message: Your password was changed. Contact support if this wasn't you."
    simulate_sms_delivery
  end

  def send_login_alert(event_data)
    phone = get_user_phone(event_data['user_id'])
    puts "📱 SMSService: Sending login alert SMS to #{phone}"
    puts "   Message: Suspicious login detected from new location."
    simulate_sms_delivery
  end

  def suspicious_login?(event_data)
    # Simulate detection logic - mark logins from 'unknown' locations as suspicious
    event_data.dig('metadata', 'location') == 'unknown'
  end

  def get_user_phone(user_id)
    "+1-555-0#{user_id.split('-').last}"
  end

  def log_sms_activity(message)
    puts "📱 SMSService: #{message}"
  end

  def simulate_sms_delivery
    sleep(0.05)
    puts "   💬 SMS sent"
  end
end

# Audit Logging Service
class AuditService
  def initialize
    puts "📊 AuditService: Starting up..."
    @audit_log = []
    UserEventMessage.subscribe('AuditService.handle_user_event')
  end

  def self.handle_user_event(wrapper)
    # Use a singleton pattern for persistent audit log
    @@instance ||= new
    @@instance.process_event(wrapper)
  end

  def self.get_summary
    @@instance&.get_audit_summary || {}
  end

  def process_event(wrapper)
    message_header, message_payload = wrapper.split
    event_data = JSON.parse(message_payload)
    
    audit_entry = {
      timestamp: Time.now.iso8601,
      event_id: event_data['event_id'],
      event_type: event_data['event_type'],
      user_id: event_data['user_id'],
      processed_at: message_header.published_at
    }
    
    @audit_log << audit_entry
    puts "📊 AuditService: Logged event #{event_data['event_id']} (#{event_data['event_type']})"
    puts "   Total events logged: #{@audit_log.size}"
  end

  def get_audit_summary
    @audit_log.group_by { |entry| entry[:event_type] }
              .transform_values(&:count)
  end
end

# User Management System (Event Publisher)
class UserManager
  def initialize
    puts "👤 UserManager: Starting up..."
    @user_counter = 100
    @event_counter = 1000
  end

  def register_user(name:, email:)
    user_id = "USER-#{@user_counter += 1}"
    
    puts "\n👤 UserManager: Registering new user #{name} (#{user_id})"
    
    # Simulate user creation in database
    create_user_record(user_id, name, email)
    
    # Publish user registration event
    publish_event(
      event_type: 'user_registered',
      user_id: user_id,
      user_email: email,
      user_name: name,
      metadata: { source: 'web_registration' }
    )
    
    user_id
  end

  def user_login(user_id:, email:, location: 'known')
    puts "\n👤 UserManager: User #{user_id} logging in from #{location}"
    
    publish_event(
      event_type: 'user_login',
      user_id: user_id,
      user_email: email,
      user_name: get_user_name(user_id),
      metadata: { location: location, ip: generate_fake_ip }
    )
  end

  def change_password(user_id:, email:)
    puts "\n👤 UserManager: User #{user_id} changed password"
    
    publish_event(
      event_type: 'password_changed',
      user_id: user_id,
      user_email: email,
      user_name: get_user_name(user_id),
      metadata: { method: 'self_service' }
    )
  end

  private

  def create_user_record(user_id, name, email)
    # Simulate database insertion
    sleep(0.05)
    puts "👤 UserManager: User record created in database"
  end

  def publish_event(event_type:, user_id:, user_email:, user_name:, metadata: {})
    event = UserEventMessage.new(
      event_id: "EVT-#{@event_counter += 1}",
      event_type: event_type,
      user_id: user_id,
      user_email: user_email,
      user_name: user_name,
      timestamp: Time.now.iso8601,
      metadata: metadata,
      from: 'UserManager'
    )
    
    puts "👤 UserManager: Publishing #{event_type} event..."
    event.publish
  end

  def get_user_name(user_id)
    # Simulate database lookup
    case user_id
    when /101/ then "Alice Johnson"
    when /102/ then "Bob Smith"
    when /103/ then "Carol Williams"
    else "Unknown User"
    end
  end

  def generate_fake_ip
    "192.168.#{rand(1..254)}.#{rand(1..254)}"
  end
end

# Demo Runner
class EventNotificationDemo
  def run
    puts "🚀 Starting Event Notification Demo\n"
    
    # Start all services (these become subscribers)
    email_service = EmailService.new
    sms_service = SMSService.new
    audit_service = AuditService.new
    
    # Start the publisher
    user_manager = UserManager.new
    
    puts "\n" + "="*70
    puts "Simulating User Activities"
    puts "="*70
    
    # Simulate various user activities
    puts "\n--- Scenario 1: New User Registration ---"
    user_id_1 = user_manager.register_user(
      name: "Alice Johnson",
      email: "alice@example.com"
    )
    sleep(0.8)  # Let all services process
    
    puts "\n--- Scenario 2: Normal User Login ---"
    user_manager.user_login(
      user_id: user_id_1,
      email: "alice@example.com",
      location: "known"
    )
    sleep(0.8)
    
    puts "\n--- Scenario 3: Another User Registration ---"
    user_id_2 = user_manager.register_user(
      name: "Bob Smith", 
      email: "bob@example.com"
    )
    sleep(0.8)
    
    puts "\n--- Scenario 4: Suspicious Login ---"
    user_manager.user_login(
      user_id: user_id_2,
      email: "bob@example.com",
      location: "unknown"
    )
    sleep(0.8)
    
    puts "\n--- Scenario 5: Password Change ---"
    user_manager.change_password(
      user_id: user_id_1,
      email: "alice@example.com"
    )
    sleep(0.8)
    
    # Show audit summary
    puts "\n" + "="*70
    puts "📊 Final Audit Summary"
    puts "="*70
    summary = AuditService.get_summary
    summary.each do |event_type, count|
      puts "#{event_type}: #{count} events"
    end
    
    puts "\n✨ Demo completed!"
    puts "\nThis example demonstrated:"
    puts "• One-to-many publish-subscribe messaging pattern"
    puts "• Multiple services subscribing to the same event stream"
    puts "• Different services handling events in their own specific ways"
    puts "• Decoupled architecture where services can be added/removed independently"
    puts "• Event-driven architecture with audit logging"
  end
end

# Run the demo if this file is executed directly
if __FILE__ == $0
  demo = EventNotificationDemo.new
  demo.run
end