# Message Processing in SmartMessage

## Understanding the `self.process` Method

The `self.process` method in SmartMessage classes serves as the **default message handler**. It defines what should happen when a message of that type is received by a subscriber.

## Purpose of `self.process`

The `self.process` method defines **what happens when a message is received**. It's the entry point for processing incoming messages of that type.

## How it Works

### 1. Message Publishing Flow
```ruby
# Someone publishes a message
SensorDataMessage.new(device_id: "THERM-001", value: 22.5).publish
```

### 2. Subscription & Routing
```ruby
# A class subscribes to receive messages
SensorDataMessage.subscribe  # Uses default "SensorDataMessage.process"
# OR with custom method
SensorDataMessage.subscribe("MyService.custom_handler")
```

### 3. Message Processing
When a message arrives, the dispatcher calls the registered handler method with:
- `message_header` - metadata (timestamp, UUID, message class, etc.)
- `message_payload` - the serialized message data (usually JSON)

## Message Handler Options

SmartMessage supports multiple ways to handle incoming messages:

### 1. Default Handler Pattern (using `self.process`)
```ruby
class SensorDataMessage < SmartMessage::Base
  def self.process(decoded_message)
    # This gets called when a SensorDataMessage is received
    # decoded_message is already a message instance
    puts "Sensor reading: #{data['value']}"
  end
end

SensorDataMessage.subscribe  # Uses "SensorDataMessage.process"
```

### 2. Custom Method Handler Pattern
```ruby
class ThermostatService
  def self.handle_sensor_data(message_header, message_payload)
    # Custom processing logic
    # decoded_message is already a message instance
    adjust_temperature(data)
  end
end

SensorDataMessage.subscribe("ThermostatService.handle_sensor_data")
```

### 3. Block Handler Pattern (NEW)
```ruby
# Subscribe with a block - perfect for simple handlers
SensorDataMessage.subscribe do |header, payload|
  data = JSON.parse(payload)
  puts "Temperature: #{data['value']}°C from #{data['device_id']}"
  
  # You can access header information too
  puts "Received at: #{header.published_at}"
end
```

### 4. Proc/Lambda Handler Pattern (NEW)
```ruby
# Create a reusable handler
temperature_handler = proc do |header, payload|
  data = JSON.parse(payload)
  if data['value'] > 30
    puts "⚠️ High temperature alert: #{data['value']}°C"
  end
end

# Use the proc as a handler
SensorDataMessage.subscribe(temperature_handler)

# Or use a lambda
alert_handler = lambda do |header, payload|
  data = JSON.parse(payload)
  AlertService.process_sensor_data(data)
end

SensorDataMessage.subscribe(alert_handler)
```

## Real Example from IoT Code

Looking at the smart home IoT example:

```ruby
class SensorDataMessage < SmartMessage::Base
  def self.process(decoded_message)
    sensor_# decoded_message is already a message instance
    icon = case sensor_data['device_type']
           when 'thermostat' then '🌡️'
           when 'security_camera' then '📹'
           when 'door_lock' then '🚪'
           end
    
    puts "#{icon} Sensor data: #{sensor_data['device_id']} - #{sensor_data['value']}"
  end
end
```

This `process` method gets called every time a `SensorDataMessage` is published and received by a subscriber.

## Message Handler Parameters

### `message_header`
Contains metadata about the message:
```ruby
message_header.uuid           # Unique message ID
message_header.message_class  # "SensorDataMessage"
message_header.published_at   # Timestamp when published
message_header.publisher_pid  # Process ID of publisher
```

### `message_payload`
The serialized message content (typically JSON):
```ruby
# Example payload
{
  "device_id": "THERM-001",
  "device_type": "thermostat",
  "value": 22.5,
  "unit": "celsius",
  "timestamp": "2025-08-18T10:30:00Z"
}
```

## Multiple Handlers for One Message Type

A single message type can have multiple subscribers with different handlers using any combination of the handler patterns:

```ruby
# Default handler for logging
class SensorDataMessage < SmartMessage::Base
  def self.process(decoded_message)
    # decoded_message is already a message instance
    puts "📊 Sensor data logged: #{data['device_id']}"
  end
end

# Custom method handler for specific services
class ThermostatService
  def self.handle_sensor_data(message_header, message_payload)
    # decoded_message is already a message instance
    return unless data['device_type'] == 'thermostat'
    adjust_temperature(data['value'])
  end
end

# Register all handlers - mix of different types
SensorDataMessage.subscribe  # Uses default process method

SensorDataMessage.subscribe("ThermostatService.handle_sensor_data")  # Method handler

SensorDataMessage.subscribe do |header, payload|  # Block handler
  data = JSON.parse(payload)
  if data['value'] > 30
    puts "🚨 High temperature alert: #{data['value']}°C"
  end
end

# Proc handler for reusable logic
database_logger = proc do |header, payload|
  data = JSON.parse(payload)
  Database.insert(:sensor_readings, data)
end

SensorDataMessage.subscribe(database_logger)  # Proc handler
```

## Message Processing Lifecycle

1. **Message Published**: `message.publish` is called
2. **Transport Delivery**: Message is sent via configured transport (Redis, stdout, etc.)
3. **Dispatcher Routing**: Dispatcher receives message and looks up subscribers
4. **Handler Execution**: Each registered handler is called in its own thread
5. **Business Logic**: Your `process` method executes the business logic

## Threading and Concurrency

- Each message handler runs in its own thread from the dispatcher's thread pool
- Multiple handlers for the same message run concurrently
- Handlers should be thread-safe if they access shared resources

```ruby
class SensorDataMessage < SmartMessage::Base
  def self.process(decoded_message)
    # This runs in its own thread
    # Be careful with shared state
    # decoded_message is already a message instance
    
    # Thread-safe operations
    update_local_cache(data)
    
    # Avoid shared mutable state without synchronization
  end
end
```

## Error Handling in Handlers

Handlers should include proper error handling:

```ruby
class SensorDataMessage < SmartMessage::Base
  def self.process(decoded_message)
    begin
      # decoded_message is already a message instance
      
      # Validate required fields
      raise "Missing device_id" unless data['device_id']
      
      # Process the message
      process_sensor_reading(data)
      
    rescue JSON::ParserError => e
      logger.error "Invalid JSON in sensor message: #{e.message}"
    rescue => e
      logger.error "Error processing sensor data: #{e.message}"
      # Consider dead letter queue or retry logic
    end
  end
end
```

## Choosing the Right Handler Type

### When to Use Each Handler Type

**Default `self.process` method:**
- Simple message types with basic processing
- When you want a standard handler for the message class
- Good for prototyping and simple applications

**Custom method handlers (`"ClassName.method_name"`):**
- Complex business logic that belongs in a service class
- When you need testable, organized code
- Handlers that need to be called from multiple places
- Enterprise applications with well-defined service layers

**Block handlers (`subscribe do |header, payload|`):**
- Simple, one-off processing logic
- Quick prototyping and experimentation
- Inline filtering or formatting
- When the logic is specific to the subscription point

**Proc/Lambda handlers:**
- Reusable handlers across multiple message types
- Dynamic handler creation based on configuration
- Functional programming patterns
- When you need to pass handlers as parameters

### Examples of Each Use Case

```ruby
# Default - simple logging
class UserEventMessage < SmartMessage::Base
  def self.process(header, payload)
    puts "User event: #{JSON.parse(payload)['event_type']}"
  end
end

# Method handler - complex business logic
class EmailService
  def self.send_welcome_email(header, payload)
    user_data = JSON.parse(payload)
    return unless user_data['event_type'] == 'user_registered'
    
    EmailTemplate.render(:welcome, user_data)
                 .deliver_to(user_data['email'])
  end
end

UserEventMessage.subscribe("EmailService.send_welcome_email")

# Block handler - simple inline logic
UserEventMessage.subscribe do |header, payload|
  data = JSON.parse(payload)
  puts "🎉 Welcome #{data['username']}!" if data['event_type'] == 'user_registered'
end

# Proc handler - reusable across message types
audit_logger = proc do |header, payload|
  AuditLog.create(
    message_type: header.message_class,
    timestamp: header.published_at,
    data: payload
  )
end

UserEventMessage.subscribe(audit_logger)
OrderEventMessage.subscribe(audit_logger)  # Reuse the same proc
PaymentEventMessage.subscribe(audit_logger)
```

## Best Practices

### 1. Keep Handlers Fast
```ruby
def self.process(decoded_message)
  # Quick validation
  # decoded_message is already a message instance
  return unless valid_message?(data)
  
  # Delegate heavy work to background jobs
  BackgroundJob.perform_async(data)
end
```

### 2. Use Descriptive Handler Names
```ruby
# Good method names
SensorDataMessage.subscribe("ThermostatService.handle_temperature_reading")
SensorDataMessage.subscribe("AlertService.monitor_for_anomalies")

# Good block handlers with comments
SensorDataMessage.subscribe do |header, payload|  # Temperature monitoring
  data = JSON.parse(payload)
  monitor_temperature_thresholds(data)
end

# Good proc handlers with descriptive variable names
temperature_validator = proc do |header, payload|
  data = JSON.parse(payload)
  validate_temperature_range(data)
end

SensorDataMessage.subscribe(temperature_validator)

# Less clear
SensorDataMessage.subscribe("Service1.method1")
SensorDataMessage.subscribe do |h, p|; process_stuff(p); end
```

### 3. Filter Messages Early
```ruby
def self.handle_thermostat_data(message_header, message_payload)
  # decoded_message is already a message instance
  
  # Filter early to avoid unnecessary processing
  return unless data['device_type'] == 'thermostat'
  return unless data['device_id']&.start_with?('THERM-')
  
  # Process only relevant messages
  adjust_temperature(data)
end
```

### 4. Include Logging and Monitoring
```ruby
def self.process(decoded_message)
  start_time = Time.now
  
  begin
    # decoded_message is already a message instance
    logger.info "Processing sensor data from #{data['device_id']}"
    
    # Business logic here
    result = process_sensor_reading(data)
    
    # Success metrics
    duration = Time.now - start_time
    metrics.histogram('message.processing.duration', duration)
    
  rescue => e
    logger.error "Failed to process sensor data: #{e.message}"
    metrics.increment('message.processing.errors')
    raise
  end
end
```

## Summary

SmartMessage provides flexible options for handling incoming messages, from simple default handlers to sophisticated proc-based solutions.

### Handler Types Summary:

1. **Default Handler** (`self.process`): Built-in method for basic message processing
2. **Method Handler** (`"Class.method"`): Organized, testable handlers in service classes  
3. **Block Handler** (`subscribe do |h,p|`): Inline logic perfect for simple processing
4. **Proc Handler** (`subscribe(proc {...})`): Reusable, composable handlers

### Key Points:

- **Flexibility**: Choose the right handler type for your use case
- **Parameters**: All handlers receive `(message_header, message_payload)`
- **Payload**: Usually JSON that needs to be parsed back into Ruby objects  
- **Multiple Handlers**: One message type can have multiple subscribers with different handler types
- **Threading**: Each handler runs in its own thread via the dispatcher's thread pool
- **Error Handling**: Include proper error handling for production reliability
- **Unsubscription**: All handler types can be unsubscribed using their returned identifiers

### Return Values:

The `subscribe` method always returns a string identifier that can be used for unsubscription:

```ruby
# All of these return identifiers for unsubscription
default_id = MyMessage.subscribe
method_id = MyMessage.subscribe("Service.handle")
block_id = MyMessage.subscribe { |h,p| puts p }
proc_id = MyMessage.subscribe(my_proc)

# Unsubscribe any handler type
MyMessage.unsubscribe(block_id)
MyMessage.unsubscribe(proc_id)
```

This enhanced subscription system provides the foundation for building sophisticated, event-driven applications while maintaining simplicity for basic use cases.