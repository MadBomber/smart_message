# Getting Started with SmartMessage

This guide will help you get up and running with SmartMessage quickly.

## Installation

Add SmartMessage to your Gemfile:

```ruby
gem 'smart_message'
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install smart_message
```

## Requirements

- Ruby >= 3.0.0
- No additional system dependencies

## Your First Message

Let's create a simple message class and see it in action:

### 1. Define a Message Class

```ruby
require 'smart_message'

class WelcomeMessage < SmartMessage::Base
  # Add a description for the message class
  description "Welcomes new users after successful signup"
  
  # Configure entity addressing (Method 1: Direct methods)
  from 'user-service'           # Required: identifies sender
  to 'notification-service'     # Optional: specific recipient
  reply_to 'user-service'       # Optional: where responses go
  
  # Alternative Method 2: Using header block
  # header do
  #   from 'user-service'
  #   to 'notification-service'
  #   reply_to 'user-service'
  # end
  
  # Define message properties
  property :user_name
  property :email
  property :signup_date

  # Configure the transport (where messages go)
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end

  # Define how to process received messages
  def self.process(decoded_message)
    # decoded_message is already a message instance
    welcome = decoded_message
    
    # Process the welcome message
    puts "🎉 Welcome #{welcome.user_name}!"
    puts "📧 Email: #{welcome.email}"
    puts "📅 Signed up: #{welcome.signup_date}"
  end
end
```

### 2. Subscribe to Messages

Before publishing, set up a subscription to receive messages. SmartMessage provides several ways to handle incoming messages:

```ruby
# 1. Default handler (uses the self.process method defined above)
WelcomeMessage.subscribe

# 2. Block handler (inline processing logic)
WelcomeMessage.subscribe do |header, payload|
  data = JSON.parse(payload)
  puts "👋 Quick welcome for #{data['user_name']}"
end

# 3. Proc handler (reusable processing logic)
welcome_processor = proc do |header, payload|
  data = JSON.parse(payload)
  EmailService.send_welcome_email(data['email'], data['user_name'])
end
WelcomeMessage.subscribe(welcome_processor)

# 4. Custom method handler
WelcomeMessage.subscribe("UserService.handle_welcome")
```

### 3. Create and Publish a Message

```ruby
# Create a new welcome message
welcome = WelcomeMessage.new(
  user_name: "Alice Johnson",
  email: "alice@example.com", 
  signup_date: Date.today.to_s
)

# Publish the message
welcome.publish
```

### 4. See It in Action

Run your script and you should see:

```
===================================================
== SmartMessage Published via STDOUT Transport
== Header: #<SmartMessage::Header:0x... @uuid="...", @message_class="WelcomeMessage", ...>
== Payload: {"user_name":"Alice Johnson","email":"alice@example.com","signup_date":"2025-08-17"}
===================================================

🎉 Welcome Alice Johnson!
📧 Email: alice@example.com
📅 Signed up: 2025-08-17
```

## Understanding What Happened

1. **Message Definition**: We created a `WelcomeMessage` class with three properties
2. **Configuration**: We configured it to use STDOUT transport with loopback enabled
3. **Subscription**: We subscribed to process incoming messages of this type
4. **Publishing**: We created an instance and published it
5. **Processing**: Because loopback is enabled, the message was immediately routed back and processed

## Key Concepts

### Properties
Messages use Hashie::Dash properties for type-safe attributes:

```ruby
class OrderMessage < SmartMessage::Base
  description "Represents customer orders for processing and fulfillment"
  
  property :order_id, required: true
  property :amount, transform_with: ->(v) { BigDecimal(v.to_s) }
  property :items, default: []
  property :created_at, default: -> { Time.now }
end
```

### Headers
Every message automatically gets a header with metadata:

```ruby
message = WelcomeMessage.new(user_name: "Bob")
puts message._sm_header.uuid          # Unique identifier
puts message._sm_header.message_class # "WelcomeMessage"
puts message._sm_header.published_at  # Timestamp when published
puts message._sm_header.publisher_pid # Process ID of publisher
puts message._sm_header.from          # 'user-service'
puts message._sm_header.to            # 'notification-service'
puts message._sm_header.reply_to      # 'user-service'
```

### Transports
Transports handle where messages go. Built-in options include:

```ruby
# STDOUT - for development/debugging
transport SmartMessage::Transport.create(:stdout, loopback: true)

# Memory - for testing
transport SmartMessage::Transport.create(:memory, auto_process: true)
```

### Serializers
Serializers handle message encoding/decoding:

```ruby
# JSON serialization (built-in)
serializer SmartMessage::Serializer::JSON.new
```

### Message Handlers

SmartMessage supports four types of message handlers to give you flexibility in how you process messages:

```ruby
class OrderMessage < SmartMessage::Base
  description "Handles customer order processing and fulfillment"
  
  # Define your message properties
  property :order_id
  property :amount
  
  # Default handler - processed when no custom handler specified
  def self.process(header, payload)
    puts "Default processing for order"
  end
end

# 1. Default handler (uses self.process)
OrderMessage.subscribe

# 2. Block handler - great for simple, inline logic
OrderMessage.subscribe do |header, payload|
  data = JSON.parse(payload)
  puts "Block handler: Processing order #{data['order_id']}"
end

# 3. Proc handler - reusable across message types
audit_logger = proc do |header, payload|
  puts "Audit: #{header.message_class} at #{header.published_at}"
end
OrderMessage.subscribe(audit_logger)

# 4. Method handler - organized in service classes
class OrderService
  def self.process_order(header, payload)
    puts "Service processing order"
  end
end
OrderMessage.subscribe("OrderService.process_order")
```

**When to use each type:**
- **Default**: Simple built-in processing for the message type
- **Block**: Quick inline logic specific to one subscription
- **Proc**: Reusable handlers that work across multiple message types
- **Method**: Complex business logic organized in service classes

### Entity Addressing

SmartMessage supports entity-to-entity addressing for sophisticated messaging patterns:

```ruby
# Point-to-point messaging
class PaymentMessage < SmartMessage::Base
  from 'payment-service'    # Required: sender identity
  to 'bank-gateway'         # Optional: specific recipient
  reply_to 'payment-service' # Optional: where responses go
  
  property :amount, required: true
end

# Broadcast messaging (no 'to' field)
class AnnouncementMessage < SmartMessage::Base
  from 'admin-service'      # Required sender
  # No 'to' = broadcast to all subscribers
  
  property :message, required: true
end

# Instance-level addressing override
payment = PaymentMessage.new(amount: 100.00)
payment.to('backup-gateway')  # Override destination
payment.publish
```

For more details, see [Entity Addressing](addressing.md).

## Next Steps

Now that you have the basics working, explore:

- [Architecture Overview](architecture.md) - Understand how SmartMessage works
- [Examples](examples.md) - See more practical use cases
- [Transports](transports.md) - Learn about different transport options
- [Custom Transports](custom-transports.md) - Build your own transport

## Common Patterns

### Simple Notification System

```ruby
class NotificationMessage < SmartMessage::Base
  description "Sends notifications to users via email, SMS, or push"
  
  property :recipient
  property :subject
  property :body
  property :priority, default: 'normal'

  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
    serializer SmartMessage::Serializer::JSON.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    notification = decoded_message
    
    # Send email, SMS, push notification, etc.
    send_notification(notification)
  end

  private

  def self.send_notification(notification)
    puts "Sending #{notification.priority} notification to #{notification.recipient}"
    puts "Subject: #{notification.subject}"
  end
end

# Subscribe and send
NotificationMessage.subscribe

NotificationMessage.new(
  recipient: "user@example.com",
  subject: "Welcome!",
  body: "Thanks for signing up!",
  priority: "high"
).publish
```

### Event Logging

```ruby
class EventMessage < SmartMessage::Base
  description "Logs application events for monitoring and analytics"
  
  property :event_type
  property :user_id
  property :data
  property :timestamp, default: -> { Time.now.iso8601 }

  config do
    transport SmartMessage::Transport.create(:stdout, output: 'events.log')
    serializer SmartMessage::Serializer::JSON.new
  end
end

# Log events
EventMessage.new(
  event_type: 'user_login',
  user_id: 123,
  data: { ip: '192.168.1.1', user_agent: 'Chrome' }
).publish
```

## Need Help?

- Check the [Troubleshooting Guide](troubleshooting.md)
- Review the [API Reference](api-reference.md)
- Look at more [Examples](examples.md)