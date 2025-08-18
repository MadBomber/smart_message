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
```

## Examples Overview

### 1. Point-to-Point Messaging (1-to-1)
**File:** `01_point_to_point_orders.rb`

**Scenario:** E-commerce order processing system with bidirectional communication between OrderService and PaymentService.

**Key Features:**
- Request-response messaging pattern
- Error handling and payment validation
- JSON serialization of complex business objects
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
  serializer SmartMessage::Serializer::JSON.new
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
  serializer SmartMessage::Serializer::JSON.new
end
```

**For Production Use:**
- Use production transports like Redis (see example #4), RabbitMQ, or Kafka
- Configure appropriate serializers for your data needs
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
    serializer SmartMessage::Serializer::JSON.new
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

## Production Considerations

When adapting these examples for production:

1. **Transport Selection:**
   - Use production message brokers (Redis is built-in - see example #4, RabbitMQ, Kafka)
   - Configure connection pooling and failover
   - Implement proper error handling

2. **Serialization:**
   - Choose appropriate serializers for your data
   - Consider performance and compatibility requirements
   - Handle schema evolution

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
- [Serialization Guide](../docs/serializers.md)
- [Architecture Overview](../docs/architecture.md)

## Questions and Contributions

If you have questions about these examples or want to contribute additional examples:

1. Check the main project documentation
2. Look at the test files for more usage patterns
3. Submit issues or pull requests to the main repository

These examples are designed to be educational and demonstrate best practices. Feel free to use them as starting points for your own SmartMessage-based applications!