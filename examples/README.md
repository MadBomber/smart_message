# SmartMessage Examples

This directory contains example applications that demonstrate different messaging patterns and topologies using the SmartMessage Ruby gem. Each example is a complete, runnable program that showcases real-world usage scenarios.

## Quick Start

To run any example:

```bash
cd examples
ruby 01_point_to_point_orders.rb
ruby 02_publish_subscribe_events.rb  
ruby 03_many_to_many_chat.rb
ruby 04_redis_smart_home_iot.rb
ruby 05_proc_handlers.rb
ruby 06_custom_logger_example.rb
ruby 07_error_handling_scenarios.rb
ruby 08_entity_addressing_basic.rb
ruby 08_entity_addressing_with_filtering.rb
ruby 09_dead_letter_queue_demo.rb
ruby 09_regex_filtering_microservices.rb
ruby 10_header_block_configuration.rb
ruby 10_message_deduplication.rb
ruby 11_global_configuration_example.rb
ruby show_logger.rb

# Multi-program city scenario demo
cd city_scenario
./start_demo.sh  # Starts all city services
./stop_demo.sh   # Stops all running services
```

## Examples Overview

### 1. Point-to-Point Messaging (1-to-1)
**File:** `01_point_to_point_orders.rb`

**Scenario:** E-commerce order processing system with bidirectional communication between OrderService and PaymentService.

**Key Features:**
- Request-response messaging pattern
- Error handling and payment validation
- Automatic serialization of complex business objects by transport
- Service-to-service communication

**Messages Used:**
- `OrderMessage` - Represents customer orders
- `PaymentResponseMessage` - Payment processing results

**Services:**
- `OrderService` - Creates and publishes orders
- `PaymentService` - Processes payments and sends responses

**What You'll Learn:**
- How to implement point-to-point messaging
- Bidirectional communication patterns
- Message properties and validation
- Service decoupling with SmartMessage

---

### 2. Publish-Subscribe Messaging (1-to-Many)
**File:** `02_publish_subscribe_events.rb`

**Scenario:** User management system that broadcasts events to multiple interested services (email, SMS, audit logging).

**Key Features:**
- Event-driven architecture
- Multiple subscribers to single event stream
- Different services handling events differently
- Audit logging and compliance

**Messages Used:**
- `UserEventMessage` - User lifecycle events (registration, login, password change)

**Services:**
- `UserManager` - Event publisher for user activities
- `EmailService` - Sends email notifications
- `SMSService` - Sends SMS alerts for security events
- `AuditService` - Logs all events for compliance

**What You'll Learn:**
- Event-driven system design
- Publish-subscribe patterns
- Service autonomy and specialization
- Audit and monitoring capabilities

---

### 3. Many-to-Many Messaging (Service Mesh)
**File:** `03_many_to_many_chat.rb`

**Scenario:** Distributed chat system where multiple agents (humans and bots) communicate in multiple rooms with dynamic routing.

**Key Features:**
- Complex multi-agent communication
- Dynamic subscription management
- Multiple message types and routing
- Service discovery and capabilities

**Messages Used:**
- `ChatMessage` - User and bot chat messages
- `BotCommandMessage` - Commands directed to bots
- `SystemNotificationMessage` - System events and notifications

**Services:**
- `HumanChatAgent` - Represents human users
- `BotAgent` - Automated agents with capabilities
- `RoomManager` - Manages chat rooms and membership

**What You'll Learn:**
- Many-to-many communication patterns
- Dynamic message routing
- Service capabilities and discovery
- Complex subscription management

---

### 4. Redis Transport IoT Example (Production Messaging)
**File:** `04_redis_smart_home_iot.rb`

**Scenario:** Smart home IoT dashboard with multiple device types communicating through Redis pub/sub channels, demonstrating production-ready messaging patterns.

**Key Features:**
- Real Redis pub/sub transport (falls back to memory if Redis unavailable)
- Multiple device types with realistic sensor data
- Automatic Redis channel routing using message class names
- Real-time monitoring and alerting system
- Production-ready error handling and reconnection

**Messages Used:**
- `SensorDataMessage` - IoT device sensor readings and status
- `DeviceCommandMessage` - Commands sent to control devices
- `AlertMessage` - Critical notifications and warnings
- `DashboardStatusMessage` - System-wide status updates

**Services:**
- `SmartThermostat` - Temperature monitoring and control
- `SecurityCamera` - Motion detection and recording
- `SmartDoorLock` - Access control and status monitoring
- `IoTDashboard` - Centralized monitoring and status aggregation

**What You'll Learn:**
- Production Redis transport configuration and usage
- Automatic Redis channel routing (each message type → separate channel)
- IoT device simulation and real-time data streaming
- Event-driven alert systems
- Scalable pub/sub architecture for distributed systems
- Error handling and graceful fallbacks

**Redis Channels Created:**
- `SensorDataMessage` - Device sensor readings
- `DeviceCommandMessage` - Device control commands  
- `AlertMessage` - System alerts and notifications
- `DashboardStatusMessage` - Dashboard status updates

---

### 5. Proc and Block Handler Example (Flexible Message Processing)
**File:** `05_proc_handlers.rb`

**Scenario:** Notification system demonstrating all available message handler types in SmartMessage, showcasing the flexibility of the new proc and block subscription patterns.

**Key Features:**
- Multiple handler types in a single application
- Default method handlers alongside new proc/block handlers
- Dynamic handler management (subscription and unsubscription)
- Practical comparison of different handler approaches

**Messages Used:**
- `NotificationMessage` - System notifications with type, title, message, and user info

**Handler Types Demonstrated:**
- `Default Handler` - Traditional `self.process` method
- `Block Handler` - Inline logic using `subscribe do |h,p|...end`
- `Proc Handler` - Reusable proc objects for cross-cutting concerns
- `Lambda Handler` - Strict parameter validation with functional style
- `Method Handler` - Organized service class methods

**What You'll Learn:**
- How to choose the right handler type for different use cases
- Block handlers for simple, subscription-specific logic
- Proc handlers for reusable cross-message functionality
- Lambda handlers for strict functional programming patterns
- Handler lifecycle management and cleanup
- Performance characteristics of different handler types

**Handler Patterns Shown:**
```ruby
# Default handler
class NotificationMessage < SmartMessage::Base
  def self.process(header, payload)
    # Built-in processing
  end
end

# Block handler - inline logic
NotificationMessage.subscribe do |header, payload|
  # Simple, specific processing
end

# Proc handler - reusable across message types
audit_logger = proc { |header, payload| log_audit(payload) }
NotificationMessage.subscribe(audit_logger)

# Method handler - organized service logic
NotificationMessage.subscribe("NotificationService.handle")
```

**Benefits Demonstrated:**
- **Flexibility**: Multiple ways to handle the same message type
- **Reusability**: Proc handlers can be shared across message classes
- **Maintainability**: Choose the right abstraction level for each need
- **Performance**: Understand overhead of different handler approaches

---

### 8. Entity Addressing System (Advanced Routing)
**Files:** `08_entity_addressing_basic.rb`, `08_entity_addressing_with_filtering.rb`

**Scenario:** Comprehensive demonstration of SmartMessage's entity addressing system showing point-to-point messaging, broadcast patterns, request-reply workflows, and gateway patterns.

**Key Features:**
- FROM/TO/REPLY_TO addressing fields for sophisticated routing
- Point-to-point messaging with specific entity targeting
- Broadcast messaging to all subscribers
- Request-reply patterns with response routing
- Instance-level addressing overrides
- Gateway patterns for message transformation and routing

**Messages Used:**
- `OrderMessage` - Point-to-point order processing
- `SystemAnnouncementMessage` - Broadcast announcements
- `UserLookupRequest` & `UserLookupResponse` - Request-reply pattern
- `PaymentMessage` - Instance-level addressing override
- `ExternalAPIMessage` - Gateway pattern demonstration

**Addressing Patterns Shown:**
```ruby
# Point-to-point messaging
class OrderMessage < SmartMessage::Base
  from 'order-service'        # Required: sender identity
  to 'fulfillment-service'    # Optional: specific recipient
  reply_to 'order-service'    # Optional: response routing
end

# Broadcast messaging
class AnnouncementMessage < SmartMessage::Base
  from 'admin-service'        # Required sender
  # No 'to' field = broadcast to all subscribers
end

# Instance-level override
payment = PaymentMessage.new(amount: 100.00)
payment.to('backup-gateway')  # Override destination
payment.publish
```

**What You'll Learn:**
- Entity-to-entity communication patterns
- Point-to-point vs broadcast messaging
- Request-reply workflows with proper response routing
- Runtime addressing configuration and overrides
- Gateway patterns for cross-system integration
- How addressing enables sophisticated routing logic

**Routing Patterns Demonstrated:**
- **Point-to-Point**: Direct entity targeting with FROM/TO
- **Broadcast**: FROM only, TO=nil for all subscribers  
- **Request-Reply**: REPLY_TO for response routing
- **Gateway**: Dynamic addressing for message transformation
- **Override**: Instance-level addressing changes

**Benefits:**
- **Flexible Routing**: Support multiple messaging patterns
- **Entity Identification**: Clear sender/recipient tracking
- **Response Management**: Structured request-reply workflows
- **Runtime Configuration**: Dynamic addressing based on conditions
- **Integration Patterns**: Gateway support for external systems

---

### 9. Dead Letter Queue & Regex Filtering
**Files:** `09_dead_letter_queue_demo.rb`, `09_regex_filtering_microservices.rb`

**Dead Letter Queue Demo:** Demonstrates handling of undeliverable messages and failed processing scenarios.

**Regex Filtering:** Shows advanced message filtering using regular expressions for microservice routing patterns.

---

### 10. Header Block Configuration & Message Deduplication
**Files:** `10_header_block_configuration.rb`, `10_message_deduplication.rb`

**Header Block Configuration:** Comprehensive demonstration of SmartMessage's flexible header configuration options, showing three different methods for setting addressing fields.

**Message Deduplication:** Shows strategies for handling duplicate messages in distributed systems.

**Key Features:**
- Direct class methods for addressing configuration
- Header block DSL for clean, grouped configuration
- Mixed approach combining both methods
- Instance-level addressing overrides with method chaining
- Setter syntax for addressing fields
- Automatic header synchronization with instance values
- Configuration checking and validation methods

**Configuration Methods Demonstrated:**
```ruby
# Method 1: Direct class methods
class DirectMethodMessage < SmartMessage::Base
  from 'service-a'
  to 'service-b'
  reply_to 'service-a-callback'
end

# Method 2: Header block DSL
class HeaderBlockMessage < SmartMessage::Base
  header do
    from 'service-x'
    to 'service-y'
    reply_to 'service-x-callback'
  end
end

# Method 3: Mixed approach
class MixedConfigMessage < SmartMessage::Base
  header do
    from 'mixed-service'
    to 'target-service'
  end
  reply_to 'mixed-callback'  # Outside block
end
```

**Instance-Level Features:**
- **Method Chaining**: `msg.from('sender').to('recipient').reply_to('callback')`
- **Setter Syntax**: `msg.from = 'sender'`, `msg.to = 'recipient'`
- **Shortcut Accessors**: `msg.from`, `msg.to`, `msg.reply_to`
- **Header Access**: `msg._sm_header.from`, `msg._sm_header.to`
- **Configuration Checks**: `msg.from_configured?`, `msg.to_missing?`
- **Reset Methods**: `msg.reset_from`, `msg.reset_to`, `msg.reset_reply_to`

**What You'll Learn:**
- How to choose the best configuration method for your use case
- Benefits of header block DSL for grouped configuration
- Dynamic addressing overrides at runtime
- Three ways to access addressing values
- How headers automatically sync with instance changes
- Configuration validation and checking methods

**Benefits:**
- **Clean Syntax**: Header block groups related configuration
- **Flexibility**: Multiple configuration approaches to suit different styles
- **Runtime Control**: Instance-level overrides for dynamic routing
- **Consistency**: Headers stay synchronized with instance values
- **Validation**: Built-in methods to check configuration state

## Message Patterns Demonstrated

### Request-Response Pattern
```ruby
# Publisher sends request
order = OrderMessage.new(customer_id: "123", amount: 99.99)
order.publish

# Subscriber processes and responds
PaymentResponseMessage.new(order_id: order.order_id, status: "success").publish
```

### Event Broadcasting Pattern
```ruby
# Single event publisher
UserEventMessage.new(event_type: "user_registered", user_id: "123").publish

# Multiple subscribers process the same event
EmailService.handle_user_event     # Sends welcome email
SMSService.handle_user_event       # No action for registration
AuditService.handle_user_event     # Logs the event
```

### Dynamic Subscription Pattern
```ruby
# Agents can join/leave message streams dynamically
alice.join_room('general')         # Start receiving messages
alice.leave_room('general')        # Stop receiving messages
```

## Transport Configurations

Most examples use `StdoutTransport` with loopback enabled for demonstration purposes:

```ruby
config do
  transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
end
```

**Exception:** The IoT example (`04_redis_smart_home_iot.rb`) uses real Redis transport:

```ruby
config do
  transport SmartMessage::Transport.create(:redis,
    url: 'redis://localhost:6379',
    db: 1,
    auto_subscribe: true
  )
end
```

**For Production Use:**
- Use production transports like Redis (see example #4), RabbitMQ, or Kafka
- Transports handle serialization automatically
- Add proper error handling and logging
- Implement monitoring and metrics

## Advanced Features Shown

### Message Properties and Headers
```ruby
property :order_id
property :amount
property :currency, default: 'USD'
property :items
```

### Custom Message Processing
```ruby
def self.process(message_header, message_payload)
  # Custom business logic here
  data = JSON.parse(message_payload)
  handle_business_logic(data)
end
```

### Service-Specific Subscriptions
```ruby
# Subscribe with custom processor method
OrderMessage.subscribe('PaymentService.process_order')
```

### Message Metadata and Context
```ruby
metadata: { 
  source: 'web_registration',
  ip_address: request.ip,
  user_agent: request.user_agent
}
```

## Common Patterns

### Service Registration Pattern
```ruby
class MyService
  def initialize
    MessageType.subscribe('MyService.handle_message')
  end
  
  def self.handle_message(header, payload)
    service = new
    service.process_message(header, payload)
  end
end
```

### Message Filtering Pattern
```ruby
def handle_message(header, payload)
  data = JSON.parse(payload)
  
  # Only process messages for rooms we're in
  return unless @active_rooms.include?(data['room_id'])
  
  # Process the message
  process_filtered_message(data)
end
```

### Response Pattern
```ruby
def process_request(request_data)
  # Process the request
  result = perform_business_logic(request_data)
  
  # Send response
  ResponseMessage.new(
    request_id: request_data['id'],
    status: result.success? ? 'success' : 'error',
    data: result.data
  ).publish
end
```

## Testing the Examples

Each example includes:
- Comprehensive output showing message flow
- Error scenarios and handling
- Multiple service interactions
- Clear demonstration of the messaging pattern

### Running Examples

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Run individual examples:**
   ```bash
   ruby examples/01_point_to_point_orders.rb
   ruby examples/02_publish_subscribe_events.rb
   ruby examples/03_many_to_many_chat.rb
   ruby examples/04_redis_smart_home_iot.rb  # Requires Redis server
   ```

3. **Expected output:**
   Each example produces verbose output showing:
   - Service startup messages
   - Message publishing and receiving
   - Business logic execution
   - System notifications and responses

## Extending the Examples

### Adding New Services
```ruby
class MyNewService
  def initialize
    MyMessageType.subscribe('MyNewService.handle_message')
  end
  
  def self.handle_message(header, payload)
    # Process messages here
  end
end
```

### Creating New Message Types
```ruby
class MyCustomMessage < SmartMessage::Base
  property :custom_field
  property :another_field
  
  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
  end
end
```

### Implementing New Transports
```ruby
class MyCustomTransport < SmartMessage::Transport::Base
  def publish(message_header, message_payload)
    # Custom transport logic
  end
end
```

---

### City Emergency Services Scenario (Multi-Service Demo)
**Directory:** `city_scenario/`

**Scenario:** Complete city emergency services simulation demonstrating complex multi-service messaging patterns with health monitoring, emergency dispatch, and coordinated response systems.

**Key Features:**
- Multiple independent services communicating through SmartMessage
- Emergency 911 dispatch center routing calls to appropriate departments
- Fire and Police departments responding to different emergency types
- Houses generating fire emergencies and banks triggering silent alarms
- Health monitoring system checking all services periodically
- Common mixins for shared functionality (logging, health monitoring)
- Redis-based transport for production-ready messaging

**Services Included:**
- `emergency_dispatch_center.rb` - 911 call center routing emergencies
- `fire_department.rb` - Responds to fires, medical, rescue, and hazmat calls
- `police_department.rb` - Handles crime, accidents, and silent alarms
- `health_department.rb` - Monitors health status of all city services
- `house.rb` - Simulates residential fire emergencies
- `local_bank.rb` - Triggers silent alarms for security incidents
- `citizen.rb` - Generates 911 emergency calls

**Messages Used:**
- `Emergency911Message` - 911 emergency calls with caller details
- `FireEmergencyMessage` - Fire-specific emergency notifications
- `FireDispatchMessage` - Fire department dispatch responses
- `SilentAlarmMessage` - Bank security alerts to police
- `PoliceDispatchMessage` - Police unit dispatch notifications
- `EmergencyResolvedMessage` - Incident resolution notifications
- `HealthCheckMessage` - Service health check broadcasts
- `HealthStatusMessage` - Service health status responses

**Common Modules:**
- `Common::HealthMonitor` - Standardized health monitoring for all services
- `Common::Logger` - Centralized logging configuration

**What You'll Learn:**
- Building complex multi-service systems with SmartMessage
- Emergency dispatch routing patterns
- Service health monitoring and status reporting
- Message filtering and selective subscription
- Production-ready Redis transport configuration
- Extracting common functionality into mixins
- Coordinated response patterns between services
- Real-time event simulation and processing

**Running the Demo:**
```bash
cd examples/city_scenario

# Start all services (opens multiple terminal windows)
./start_demo.sh

# Monitor Redis message flow (optional)
ruby redis_monitor.rb

# View Redis statistics (optional)
ruby redis_stats.rb

# Stop all services
./stop_demo.sh
```

**Architecture Highlights:**
- **Dispatch Routing**: 911 center analyzes calls and routes to appropriate departments
- **Service Specialization**: Each department handles specific emergency types
- **Broadcast Health Checks**: Health department monitors all services simultaneously
- **Selective Subscriptions**: Services only receive relevant messages using filters
- **Incident Lifecycle**: Complete tracking from emergency to resolution
- **Production Patterns**: Demonstrates patterns suitable for production systems

---

### Show Logger Demonstration
**File:** `show_logger.rb`

**Scenario:** Comprehensive demonstration of SmartMessage's enhanced logging capabilities, showing how applications can use the SmartMessage logger directly and configure various Lumberjack options.

**Key Features:**
- Colorized console output for different log levels
- JSON and text log formatting
- File-based logging with rolling (size and date-based)
- Application logger patterns and direct logger usage
- Multiple logger configurations
- Integration with SmartMessage classes

**What You'll Learn:**
- How to configure SmartMessage's global logger settings
- Different log output formats (text vs JSON)
- Colorized logging for console output
- File rolling strategies for production use
- How to use the SmartMessage logger directly in applications
- Best practices for structured logging
- Integration patterns between application code and SmartMessage classes

**Demonstrates:**
- `SmartMessage.configure` block usage for logger configuration
- `log_level`, `log_format`, `log_colorize`, and `log_options` settings
- Direct access to `SmartMessage.configuration.default_logger`
- Creating multiple logger instances with different configurations
- Practical application patterns using the logger

## Production Considerations

When adapting these examples for production:

1. **Transport Selection:**
   - Use production message brokers (Redis is built-in - see example #4, RabbitMQ, Kafka)
   - Configure connection pooling and failover
   - Implement proper error handling

2. **Serialization:**
   - Transports handle serialization automatically
   - Choose transports based on serialization requirements
   - Handle schema evolution at the message level

3. **Monitoring:**
   - Add logging and metrics
   - Implement health checks
   - Monitor message throughput and latency

4. **Security:**
   - Implement message encryption if needed
   - Add authentication and authorization
   - Validate message integrity

5. **Scaling:**
   - Configure multiple service instances
   - Implement load balancing
   - Plan for horizontal scaling

## Additional Resources

- [SmartMessage Documentation](../docs/README.md)
- [Transport Layer Guide](../docs/transports.md)
- [Serialization Guide](../docs/serializers.md) (Note: Serialization is now handled by transports)
- [Architecture Overview](../docs/architecture.md)

## Questions and Contributions

If you have questions about these examples or want to contribute additional examples:

1. Check the main project documentation
2. Look at the test files for more usage patterns
3. Submit issues or pull requests to the main repository

These examples are designed to be educational and demonstrate best practices. Feel free to use them as starting points for your own SmartMessage-based applications!