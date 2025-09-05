#!/usr/bin/env ruby
# examples/redis_queue/05_microservices.rb
# Microservices architecture with Redis Queue Transport

require_relative '../../lib/smart_message'

puts "🏗️ Redis Queue Transport - Microservices Architecture Demo"
puts "=" * 60

#==============================================================================
# Transport Configuration for Microservices
#==============================================================================

# Configure SmartMessage for microservices architecture
SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    url: 'redis://localhost:6379',
    db: 5,  # Use database 5 for microservices demo
    queue_prefix: 'microservices',
    consumer_group: 'service_workers'
  }
end

#==============================================================================
# Service Request/Response Message Classes
#==============================================================================

class ServiceRequest < SmartMessage::Base
  transport :redis_queue
  
  property :request_id, required: true
  property :service, required: true
  property :operation, required: true
  property :payload, default: {}
  property :correlation_id
  property :timestamp, default: -> { Time.now }
  
  def process
    puts "📥 Service Request: #{service}.#{operation} [#{request_id}]"
    puts "   Payload: #{payload.inspect}" if payload.any?
  end
end

class ServiceResponse < SmartMessage::Base
  transport :redis_queue
  
  property :request_id, required: true
  property :service, required: true
  property :status, required: true  # success, error, timeout
  property :result, default: {}
  property :error_message
  property :processing_time_ms
  property :timestamp, default: -> { Time.now }
  
  def process
    status_icon = case status
                 when 'success' then '✅'
                 when 'error' then '❌'
                 when 'timeout' then '⏰'
                 else '❓'
                 end
    
    puts "#{status_icon} Service Response: #{service} [#{request_id}] - #{status}"
    puts "   Result: #{result.inspect}" if result.any?
    puts "   Error: #{error_message}" if error_message
    puts "   Processing time: #{processing_time_ms}ms" if processing_time_ms
  end
end

class ServiceEvent < SmartMessage::Base
  transport :redis_queue
  
  property :event_id, required: true
  property :event_type, required: true
  property :service, required: true
  property :entity_id
  property :data, default: {}
  property :timestamp, default: -> { Time.now }
  
  def process
    puts "📡 Service Event: #{service}.#{event_type} [#{event_id}]"
    puts "   Entity: #{entity_id}" if entity_id
    puts "   Data: #{data.inspect}" if data.any?
  end
end

#==============================================================================
# Microservice Implementations
#==============================================================================

class ApiGatewayService
  def initialize(transport)
    @transport = transport
    @request_counter = 0
    setup_subscriptions
  end
  
  def setup_subscriptions
    # Listen for responses from downstream services
    @transport.where
      .to('api_gateway')
      .subscribe do |message_class, message_data|
        data = JSON.parse(message_data)
        puts "🌐 API Gateway received response from #{data['service']}: #{data['status']}"
      end
  end
  
  def handle_user_request(operation, payload = {})
    @request_counter += 1
    request_id = "REQ-#{sprintf('%06d', @request_counter)}"
    
    puts "\n🌐 API Gateway: Processing #{operation} request [#{request_id}]"
    
    # Route to appropriate service based on operation
    service = case operation
              when 'create_user', 'get_user', 'update_user' then 'user_service'
              when 'create_order', 'get_order', 'cancel_order' then 'order_service'
              when 'process_payment', 'refund_payment' then 'payment_service'
              when 'send_email', 'send_sms' then 'notification_service'
              else 'unknown_service'
              end
    
    ServiceRequest.new(
      request_id: request_id,
      service: service,
      operation: operation,
      payload: payload,
      correlation_id: SecureRandom.uuid,
      _sm_header: {
        from: 'api_gateway',
        to: service
      }
    ).publish
    
    request_id
  end
end

class UserService
  def initialize(transport)
    @transport = transport
    @users = {}  # In-memory user store for demo
    setup_subscriptions
  end
  
  def setup_subscriptions
    @transport.where
      .to('user_service')
      .subscribe do |message_class, message_data|
        handle_request(JSON.parse(message_data))
      end
  end
  
  private
  
  def handle_request(data)
    request_id = data['request_id']
    operation = data['operation']
    payload = data['payload'] || {}
    
    puts "👤 User Service: Handling #{operation} [#{request_id}]"
    
    start_time = Time.now
    result, status, error = case operation
                           when 'create_user'
                             create_user(payload)
                           when 'get_user'
                             get_user(payload['user_id'])
                           when 'update_user'
                             update_user(payload['user_id'], payload)
                           else
                             [nil, 'error', 'Unknown operation']
                           end
    end_time = Time.now
    
    # Send response back to API Gateway
    ServiceResponse.new(
      request_id: request_id,
      service: 'user_service',
      status: status,
      result: result || {},
      error_message: error,
      processing_time_ms: ((end_time - start_time) * 1000).round(2),
      _sm_header: {
        from: 'user_service',
        to: 'api_gateway'
      }
    ).publish
    
    # Emit event if successful
    if status == 'success' && operation == 'create_user'
      ServiceEvent.new(
        event_id: SecureRandom.uuid,
        event_type: 'user_created',
        service: 'user_service',
        entity_id: result[:user_id],
        data: { name: result[:name], email: result[:email] },
        _sm_header: {
          from: 'user_service',
          to: 'event_bus'
        }
      ).publish
    end
  end
  
  def create_user(payload)
    user_id = "user_#{SecureRandom.hex(4)}"
    user_data = {
      user_id: user_id,
      name: payload['name'],
      email: payload['email'],
      created_at: Time.now.iso8601
    }
    
    @users[user_id] = user_data
    [user_data, 'success', nil]
  rescue => e
    [nil, 'error', e.message]
  end
  
  def get_user(user_id)
    if user_id && @users[user_id]
      [@users[user_id], 'success', nil]
    else
      [nil, 'error', 'User not found']
    end
  end
  
  def update_user(user_id, updates)
    if user_id && @users[user_id]
      @users[user_id].merge!(updates)
      [@users[user_id], 'success', nil]
    else
      [nil, 'error', 'User not found']
    end
  end
end

class OrderService
  def initialize(transport)
    @transport = transport
    @orders = {}
    setup_subscriptions
  end
  
  def setup_subscriptions
    @transport.where
      .to('order_service')
      .subscribe do |message_class, message_data|
        handle_request(JSON.parse(message_data))
      end
  end
  
  private
  
  def handle_request(data)
    request_id = data['request_id']
    operation = data['operation']
    payload = data['payload'] || {}
    
    puts "📦 Order Service: Handling #{operation} [#{request_id}]"
    
    start_time = Time.now
    result, status, error = case operation
                           when 'create_order'
                             create_order(payload)
                           when 'get_order'
                             get_order(payload['order_id'])
                           when 'cancel_order'
                             cancel_order(payload['order_id'])
                           else
                             [nil, 'error', 'Unknown operation']
                           end
    end_time = Time.now
    
    # Send response back
    ServiceResponse.new(
      request_id: request_id,
      service: 'order_service',
      status: status,
      result: result || {},
      error_message: error,
      processing_time_ms: ((end_time - start_time) * 1000).round(2),
      _sm_header: {
        from: 'order_service',
        to: 'api_gateway'
      }
    ).publish
    
    # Emit events for successful operations
    if status == 'success'
      emit_order_event(operation, result)
    end
  end
  
  def create_order(payload)
    order_id = "order_#{SecureRandom.hex(4)}"
    order_data = {
      order_id: order_id,
      user_id: payload['user_id'],
      items: payload['items'] || [],
      total_amount: payload['total_amount'],
      status: 'pending',
      created_at: Time.now.iso8601
    }
    
    @orders[order_id] = order_data
    [order_data, 'success', nil]
  rescue => e
    [nil, 'error', e.message]
  end
  
  def get_order(order_id)
    if order_id && @orders[order_id]
      [@orders[order_id], 'success', nil]
    else
      [nil, 'error', 'Order not found']
    end
  end
  
  def cancel_order(order_id)
    if order_id && @orders[order_id]
      @orders[order_id][:status] = 'cancelled'
      [@orders[order_id], 'success', nil]
    else
      [nil, 'error', 'Order not found']
    end
  end
  
  def emit_order_event(operation, order_data)
    event_type = case operation
                when 'create_order' then 'order_created'
                when 'cancel_order' then 'order_cancelled'
                else "order_#{operation}"
                end
    
    ServiceEvent.new(
      event_id: SecureRandom.uuid,
      event_type: event_type,
      service: 'order_service',
      entity_id: order_data[:order_id],
      data: order_data,
      _sm_header: {
        from: 'order_service',
        to: 'event_bus'
      }
    ).publish
  end
end

class PaymentService
  def initialize(transport)
    @transport = transport
    @payments = {}
    setup_subscriptions
  end
  
  def setup_subscriptions
    @transport.where
      .to('payment_service')
      .subscribe do |message_class, message_data|
        handle_request(JSON.parse(message_data))
      end
  end
  
  private
  
  def handle_request(data)
    request_id = data['request_id']
    operation = data['operation']
    payload = data['payload'] || {}
    
    puts "💳 Payment Service: Handling #{operation} [#{request_id}]"
    
    start_time = Time.now
    result, status, error = case operation
                           when 'process_payment'
                             process_payment(payload)
                           when 'refund_payment'
                             refund_payment(payload['payment_id'])
                           else
                             [nil, 'error', 'Unknown operation']
                           end
    end_time = Time.now
    
    ServiceResponse.new(
      request_id: request_id,
      service: 'payment_service',
      status: status,
      result: result || {},
      error_message: error,
      processing_time_ms: ((end_time - start_time) * 1000).round(2),
      _sm_header: {
        from: 'payment_service',
        to: 'api_gateway'
      }
    ).publish
    
    if status == 'success'
      emit_payment_event(operation, result)
    end
  end
  
  def process_payment(payload)
    payment_id = "payment_#{SecureRandom.hex(4)}"
    
    # Simulate payment processing
    sleep(0.5)  # Simulate external API call
    
    # Random success/failure for demo
    if rand < 0.9  # 90% success rate
      payment_data = {
        payment_id: payment_id,
        order_id: payload['order_id'],
        amount: payload['amount'],
        currency: payload['currency'] || 'USD',
        status: 'completed',
        transaction_id: "txn_#{SecureRandom.hex(6)}",
        processed_at: Time.now.iso8601
      }
      
      @payments[payment_id] = payment_data
      [payment_data, 'success', nil]
    else
      [nil, 'error', 'Payment declined by bank']
    end
  rescue => e
    [nil, 'error', e.message]
  end
  
  def refund_payment(payment_id)
    if payment_id && @payments[payment_id]
      @payments[payment_id][:status] = 'refunded'
      @payments[payment_id][:refunded_at] = Time.now.iso8601
      [@payments[payment_id], 'success', nil]
    else
      [nil, 'error', 'Payment not found']
    end
  end
  
  def emit_payment_event(operation, payment_data)
    event_type = case operation
                when 'process_payment' then 'payment_processed'
                when 'refund_payment' then 'payment_refunded'
                else "payment_#{operation}"
                end
    
    ServiceEvent.new(
      event_id: SecureRandom.uuid,
      event_type: event_type,
      service: 'payment_service',
      entity_id: payment_data[:payment_id],
      data: payment_data,
      _sm_header: {
        from: 'payment_service',
        to: 'event_bus'
      }
    ).publish
  end
end

class NotificationService
  def initialize(transport)
    @transport = transport
    setup_subscriptions
  end
  
  def setup_subscriptions
    # Subscribe to direct requests
    @transport.where
      .to('notification_service')
      .subscribe do |message_class, message_data|
        handle_request(JSON.parse(message_data))
      end
    
    # Subscribe to events for automatic notifications
    @transport.where
      .to('event_bus')
      .subscribe do |message_class, message_data|
        handle_event(JSON.parse(message_data)) if message_class == 'ServiceEvent'
      end
  end
  
  private
  
  def handle_request(data)
    request_id = data['request_id']
    operation = data['operation']
    payload = data['payload'] || {}
    
    puts "📧 Notification Service: Handling #{operation} [#{request_id}]"
    
    result, status, error = case operation
                           when 'send_email'
                             send_email(payload)
                           when 'send_sms'
                             send_sms(payload)
                           else
                             [nil, 'error', 'Unknown operation']
                           end
    
    ServiceResponse.new(
      request_id: request_id,
      service: 'notification_service',
      status: status,
      result: result || {},
      error_message: error,
      _sm_header: {
        from: 'notification_service',
        to: 'api_gateway'
      }
    ).publish
  end
  
  def handle_event(event_data)
    event_type = event_data['event_type']
    
    puts "📧 Notification Service: Handling event #{event_type}"
    
    case event_type
    when 'user_created'
      send_welcome_email(event_data['data'])
    when 'order_created'
      send_order_confirmation(event_data['data'])
    when 'payment_processed'
      send_payment_confirmation(event_data['data'])
    end
  end
  
  def send_email(payload)
    puts "   ✉️ Sending email to #{payload['to']}: #{payload['subject']}"
    { message_id: SecureRandom.uuid, status: 'sent' }
  rescue => e
    [nil, 'error', e.message]
  end
  
  def send_sms(payload)
    puts "   📱 Sending SMS to #{payload['phone']}: #{payload['message'][0..30]}..."
    [{ message_id: SecureRandom.uuid, status: 'sent' }, 'success', nil]
  rescue => e
    [nil, 'error', e.message]
  end
  
  def send_welcome_email(user_data)
    puts "   🎉 Sending welcome email to #{user_data['email']}"
  end
  
  def send_order_confirmation(order_data)
    puts "   📦 Sending order confirmation for #{order_data['order_id']}"
  end
  
  def send_payment_confirmation(payment_data)
    puts "   💳 Sending payment confirmation for #{payment_data['payment_id']}"
  end
end

#==============================================================================
# Service Initialization
#==============================================================================

puts "\n🔧 Initializing microservices..."

transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 5,
  queue_prefix: 'microservices',
  consumer_group: 'service_workers',
  block_time: 1000
)

# Initialize all services
api_gateway = ApiGatewayService.new(transport)
user_service = UserService.new(transport)
order_service = OrderService.new(transport)
payment_service = PaymentService.new(transport)
notification_service = NotificationService.new(transport)

# Wait for services to initialize
sleep 2

puts "✅ All microservices initialized and ready"

#==============================================================================
# End-to-End Workflow Demonstration
#==============================================================================

puts "\n🎭 Demonstrating end-to-end e-commerce workflow:"

# Workflow 1: User Registration and Welcome
puts "\n1️⃣ User Registration Workflow:"
user_req_id = api_gateway.handle_user_request('create_user', {
  'name' => 'Alice Johnson',
  'email' => 'alice@example.com'
})

sleep 2

# Workflow 2: Order Creation and Processing
puts "\n2️⃣ Order Creation Workflow:"
order_req_id = api_gateway.handle_user_request('create_order', {
  'user_id' => 'user_1234',
  'items' => [
    { 'sku' => 'BOOK-001', 'name' => 'Ruby Programming', 'price' => 29.99 },
    { 'sku' => 'BOOK-002', 'name' => 'Design Patterns', 'price' => 39.99 }
  ],
  'total_amount' => 69.98
})

sleep 2

# Workflow 3: Payment Processing
puts "\n3️⃣ Payment Processing Workflow:"
payment_req_id = api_gateway.handle_user_request('process_payment', {
  'order_id' => 'order_5678',
  'amount' => 69.98,
  'currency' => 'USD',
  'payment_method' => 'credit_card'
})

sleep 3

# Workflow 4: Notification Sending
puts "\n4️⃣ Direct Notification Workflow:"
notification_req_id = api_gateway.handle_user_request('send_email', {
  'to' => 'customer@example.com',
  'subject' => 'Your order has been shipped!',
  'template' => 'shipping_notification'
})

sleep 2

#==============================================================================
# Complex Multi-Service Scenarios
#==============================================================================

puts "\n🔄 Complex multi-service scenarios:"

# Scenario 1: Parallel service calls
puts "\n📡 Scenario 1: Parallel service operations"
requests = [
  api_gateway.handle_user_request('get_user', { 'user_id' => 'user_1234' }),
  api_gateway.handle_user_request('get_order', { 'order_id' => 'order_5678' }),
  api_gateway.handle_user_request('send_sms', { 'phone' => '+1234567890', 'message' => 'Your order is ready!' })
]

puts "   Parallel requests: #{requests.join(', ')}"

sleep 3

# Scenario 2: Service dependency chain
puts "\n🔗 Scenario 2: Service dependency chain"
puts "   Creating user → Creating order → Processing payment → Sending confirmation"

# Step 1: Create user
user_req = api_gateway.handle_user_request('create_user', {
  'name' => 'Bob Smith',
  'email' => 'bob@example.com'
})

sleep 1

# Step 2: Create order for user
order_req = api_gateway.handle_user_request('create_order', {
  'user_id' => 'user_' + SecureRandom.hex(4),
  'items' => [{ 'sku' => 'GADGET-001', 'name' => 'Smart Watch', 'price' => 199.99 }],
  'total_amount' => 199.99
})

sleep 1

# Step 3: Process payment
payment_req = api_gateway.handle_user_request('process_payment', {
  'order_id' => 'order_' + SecureRandom.hex(4),
  'amount' => 199.99,
  'payment_method' => 'paypal'
})

sleep 2

# Scenario 3: Error handling and compensation
puts "\n⚠️ Scenario 3: Error handling demonstration"
error_req = api_gateway.handle_user_request('get_user', { 'user_id' => 'nonexistent_user' })

sleep 2

#==============================================================================
# Service Statistics and Monitoring
#==============================================================================

puts "\n📊 Microservices Architecture Statistics:"

# Show queue statistics
stats = transport.queue_stats
puts "\nService queue lengths:"
service_queues = stats.select { |name, _| name.include?('_service') }
service_queues.each do |queue_name, info|
  service_name = queue_name.split('.').last.gsub('_', ' ').titleize
  puts "  #{service_name}: #{info[:length]} pending requests"
end

# Show routing patterns
routing_table = transport.routing_table
puts "\nActive service routing patterns:"
routing_table.each do |pattern, queues|
  puts "  Pattern: '#{pattern}' → #{queues.size} queue(s)"
end

puts "\nTotal active queues: #{stats.size}"
total_messages = stats.values.sum { |info| info[:length] }
puts "Total pending messages: #{total_messages}"

# Cleanup
transport.disconnect

puts "\n🏗️ Microservices architecture demonstration completed!"

puts "\n💡 Microservices Patterns Demonstrated:"
puts "   ✓ Service-to-service communication"
puts "   ✓ Request/response pattern"
puts "   ✓ Event-driven architecture"
puts "   ✓ Asynchronous message processing"
puts "   ✓ Service isolation and independence"
puts "   ✓ Centralized API Gateway pattern"
puts "   ✓ Event bus for cross-service notifications"
puts "   ✓ Error handling and fault tolerance"

puts "\n🚀 Key Architecture Benefits:"
puts "   • Loose coupling between services"
puts "   • High-performance async communication"
puts "   • Scalable service-specific queues"
puts "   • Event-driven reactive patterns"
puts "   • Built-in message persistence"
puts "   • Service discovery via routing patterns"
puts "   • Comprehensive monitoring and observability"