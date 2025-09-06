# Redis Queue Transport - Advanced Routing Patterns

This guide covers advanced routing patterns and use cases for the Redis Queue Transport, helping you implement sophisticated message routing architectures.

## Pattern Syntax Reference

### Wildcard Meanings

| Symbol | Matches | Examples |
|--------|---------|----------|
| `#` | Zero or more words | `#` matches `a`, `a.b`, `a.b.c` |
| `*` | Exactly one word | `*` matches `a` but not `a.b` |
| `.` | Word separator | Literal dot character |

### Pattern Structure

All patterns follow the routing key format:
```
namespace.message_type.from_uuid.to_uuid
```

Common pattern examples:
- `#.*.service_name` - All messages TO service_name
- `#.sender.*` - All messages FROM sender  
- `namespace.#.*.*` - All messages in namespace
- `#.#.#.broadcast` - All broadcast messages

## Basic Routing Patterns

### 1. Service-to-Service Communication

```ruby
# API Gateway routing requests to services
transport = SmartMessage::Transport::RedisQueueTransport.new

class ServiceRequest < SmartMessage::Base
  transport :redis_queue
  property :service, required: true
  property :operation, required: true
  property :payload, default: {}
end

# Route to user service
transport.subscribe_pattern("#.*.user_service") do |msg_class, data|
  request = JSON.parse(data)
  puts "👤 User Service: #{request['operation']}"
  
  case request['operation']
  when 'create_user'
    create_user(request['payload'])
  when 'get_user'
    get_user(request['payload']['user_id'])
  end
end

# Route to payment service
transport.subscribe_pattern("#.*.payment_service") do |msg_class, data|
  request = JSON.parse(data)
  puts "💳 Payment Service: #{request['operation']}"
  
  case request['operation']
  when 'process_payment'
    process_payment(request['payload'])
  when 'refund_payment'
    refund_payment(request['payload'])
  end
end

# API Gateway publishes requests
ServiceRequest.new(
  service: 'user_service',
  operation: 'create_user',
  payload: { name: 'John Doe', email: 'john@example.com' },
  _sm_header: { from: 'api_gateway', to: 'user_service' }
).publish
```

### 2. Event-Driven Architecture

```ruby
# Domain events with smart routing
class OrderEvent < SmartMessage::Base
  transport :redis_queue
  property :event_type, required: true
  property :order_id, required: true
  property :data, default: {}
end

# Multiple services react to order events
class InventoryService
  def self.start
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    # Listen for order events that affect inventory
    transport.subscribe_pattern("order.#.*.*") do |msg_class, data|
      event = JSON.parse(data)
      
      case event['event_type']
      when 'order_placed'
        reserve_inventory(event['order_id'], event['data']['items'])
      when 'order_cancelled'
        release_inventory(event['order_id'])
      end
    end
  end
end

class ShippingService
  def self.start
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    # Listen for paid orders
    transport.subscribe_pattern("order.#.payment_service.*") do |msg_class, data|
      event = JSON.parse(data)
      
      if event['event_type'] == 'payment_confirmed'
        schedule_shipping(event['order_id'])
      end
    end
  end
end

# Publish order events
OrderEvent.new(
  event_type: 'order_placed',
  order_id: 'ORD-123',
  data: { items: [{ sku: 'BOOK-001', qty: 2 }], customer_id: 'CUST-456' },
  _sm_header: { from: 'order_service', to: 'inventory_service' }
).publish
```

### 3. Multi-Tenant Routing

```ruby
# Tenant isolation through routing patterns
class TenantMessage < SmartMessage::Base
  transport :redis_queue
  property :tenant_id, required: true
  property :data, required: true
end

class TenantService
  def initialize(tenant_id)
    @tenant_id = tenant_id
    @transport = SmartMessage::Transport::RedisQueueTransport.new
    setup_subscriptions
  end
  
  private
  
  def setup_subscriptions
    # Only receive messages for this tenant
    pattern = "#.#{@tenant_id}_*.*"
    
    @transport.subscribe_pattern(pattern) do |msg_class, data|
      message = JSON.parse(data)
      puts "🏢 Tenant #{@tenant_id} processing: #{msg_class}"
      process_tenant_message(message)
    end
    
    # Admin broadcasts to all tenants
    @transport.subscribe_pattern("#.admin.*.broadcast") do |msg_class, data|
      message = JSON.parse(data)
      puts "📢 Admin broadcast to tenant #{@tenant_id}: #{message['subject']}"
      process_admin_broadcast(message)
    end
  end
end

# Start tenant services
tenant_1_service = TenantService.new('tenant_123')
tenant_2_service = TenantService.new('tenant_456')

# Publish tenant-specific messages
TenantMessage.new(
  tenant_id: 'tenant_123',
  data: { user_count: 50 },
  _sm_header: { from: 'tenant_123_analytics', to: 'tenant_123_dashboard' }
).publish

# Admin broadcast
AdminBroadcast.new(
  subject: 'Scheduled maintenance tonight',
  message: 'System will be down from 2-4 AM',
  _sm_header: { from: 'admin', to: 'broadcast' }
).publish
```

## Advanced Routing Scenarios

### 4. Priority-Based Routing

```ruby
# Priority-based message routing
class PriorityMessage < SmartMessage::Base
  transport :redis_queue
  property :priority, required: true  # critical, high, normal, low
  property :data, required: true
end

class PriorityRouter
  def self.start
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    # Route based on priority in the FROM field
    transport.subscribe_pattern("priority.#.*.*") do |msg_class, data|
      message = JSON.parse(data)
      
      target_service = case message['priority']
                      when 'critical'
                        'critical_processor'
                      when 'high'
                        'high_priority_processor'
                      else
                        'normal_processor'
                      end
      
      # Re-route to priority-specific service
      PriorityMessage.new(
        priority: message['priority'],
        data: message['data'],
        _sm_header: {
          from: 'priority_router',
          to: target_service
        }
      ).publish
    end
  end
end

# Priority-specific processors
class CriticalProcessor
  def self.start
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    transport.subscribe_pattern("#.*.critical_processor") do |msg_class, data|
      message = JSON.parse(data)
      puts "🚨 CRITICAL: Processing #{message['data']} immediately"
      # Process with highest priority
    end
  end
end

# Publish priority messages
PriorityMessage.new(
  priority: 'critical',
  data: { alert: 'System overload detected' },
  _sm_header: { from: 'monitoring', to: 'priority_router' }
).publish
```

### 5. Geographic Routing

```ruby
# Geographic region-based routing
class GeographicMessage < SmartMessage::Base
  transport :redis_queue
  property :region, required: true  # us-east, us-west, eu, asia
  property :data, required: true
end

# Regional processors
class RegionalProcessor
  def initialize(region)
    @region = region
    @transport = SmartMessage::Transport::RedisQueueTransport.new
    setup_subscriptions
  end
  
  private
  
  def setup_subscriptions
    # Process messages for this region
    pattern = "#.*.#{@region}_processor"
    
    @transport.subscribe_pattern(pattern) do |msg_class, data|
      message = JSON.parse(data)
      puts "🌍 #{@region.upcase} processing: #{message['data']}"
      process_regional_data(message['data'])
    end
    
    # Global broadcasts
    @transport.subscribe_pattern("#.*.global") do |msg_class, data|
      message = JSON.parse(data)
      puts "🌎 Global message in #{@region}: #{message['data']}"
      process_global_message(message['data'])
    end
  end
end

# Geographic router
class GeographicRouter
  def self.start
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    transport.subscribe_pattern("geo.#.*.*") do |msg_class, data|
      message = JSON.parse(data)
      
      # Route to regional processor
      target = "#{message['region']}_processor"
      
      GeographicMessage.new(
        region: message['region'],
        data: message['data'],
        _sm_header: {
          from: 'geo_router',
          to: target
        }
      ).publish
    end
  end
end

# Start regional processors
us_east = RegionalProcessor.new('us_east')
us_west = RegionalProcessor.new('us_west')
eu = RegionalProcessor.new('eu')
```

### 6. Content-Based Routing

```ruby
# Route messages based on content analysis
class ContentRouter
  def self.start
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    # Analyze incoming messages and route appropriately
    transport.subscribe_pattern("content.#.*.*") do |msg_class, data|
      message = JSON.parse(data)
      content = message['content']
      
      # Determine routing based on content
      routes = analyze_content(content)
      
      routes.each do |service|
        RoutedMessage.new(
          content: content,
          analysis_result: routes,
          _sm_header: {
            from: 'content_router',
            to: service
          }
        ).publish
      end
    end
  end
  
  private
  
  def self.analyze_content(content)
    routes = []
    
    # Text analysis routing
    if content.match?(/urgent|emergency|critical/i)
      routes << 'alert_service'
    end
    
    if content.match?(/order|purchase|buy/i)
      routes << 'sales_service'
    end
    
    if content.match?(/bug|error|issue/i)
      routes << 'support_service'
    end
    
    if content.match?/@\w+/) # Contains mentions
      routes << 'notification_service'
    end
    
    routes << 'archive_service'  # Always archive
    routes.uniq
  end
end
```

### 7. Workflow Routing

```ruby
# Multi-step workflow routing
class WorkflowStep < SmartMessage::Base
  transport :redis_queue
  property :workflow_id, required: true
  property :step_number, required: true
  property :data, required: true
  property :next_step
end

class WorkflowEngine
  WORKFLOWS = {
    'order_processing' => [
      'validate_order',
      'check_inventory', 
      'process_payment',
      'ship_order',
      'send_confirmation'
    ],
    'user_onboarding' => [
      'verify_email',
      'setup_profile',
      'send_welcome',
      'assign_trial'
    ]
  }.freeze
  
  def self.start
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    # Listen for workflow completions
    transport.subscribe_pattern("workflow.#.*.*") do |msg_class, data|
      step = JSON.parse(data)
      advance_workflow(step)
    end
  end
  
  private
  
  def self.advance_workflow(completed_step)
    workflow_type = determine_workflow_type(completed_step['workflow_id'])
    steps = WORKFLOWS[workflow_type]
    current_index = steps.index(completed_step['step_type'])
    
    if current_index && current_index < steps.length - 1
      next_step = steps[current_index + 1]
      
      WorkflowStep.new(
        workflow_id: completed_step['workflow_id'],
        step_number: current_index + 2,
        data: completed_step['data'],
        next_step: next_step,
        _sm_header: {
          from: 'workflow_engine',
          to: "#{next_step}_service"
        }
      ).publish
    else
      # Workflow complete
      WorkflowComplete.new(
        workflow_id: completed_step['workflow_id'],
        _sm_header: {
          from: 'workflow_engine',
          to: 'workflow_monitor'
        }
      ).publish
    end
  end
end
```

## Complex Pattern Combinations

### 8. Multi-Criteria Routing

```ruby
# Complex routing with multiple criteria
class ComplexRouter
  def self.start
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    # Route based on multiple message attributes
    setup_routing_rules(transport)
  end
  
  private
  
  def self.setup_routing_rules(transport)
    # Rule 1: Critical messages from admin go to operations
    transport.subscribe_pattern("#.admin.*.#") do |msg_class, data|
      message = JSON.parse(data)
      
      if message['severity'] == 'critical'
        route_to_operations(message)
      end
    end
    
    # Rule 2: Payment messages go to compliance if amount > $10,000
    transport.subscribe_pattern("payment.#.*.*") do |msg_class, data|
      message = JSON.parse(data)
      
      if message['amount'] && message['amount'] > 10000
        route_to_compliance(message)
      end
    end
    
    # Rule 3: Messages from EU customers go to GDPR processor
    transport.subscribe_pattern("#.*.#") do |msg_class, data|
      message = JSON.parse(data)
      
      if eu_customer?(message['customer_data'])
        route_to_gdpr_processor(message)
      end
    end
    
    # Rule 4: Time-sensitive messages during business hours
    transport.subscribe_pattern("#.*.#") do |msg_class, data|
      message = JSON.parse(data)
      
      if message['time_sensitive'] && business_hours?
        route_to_priority_processor(message)
      elsif message['time_sensitive']
        route_to_delayed_processor(message)
      end
    end
  end
end
```

### 9. Fan-out and Aggregation

```ruby
# Fan-out pattern: One message to many processors
class FanOutMessage < SmartMessage::Base
  transport :redis_queue
  property :data, required: true
  property :processors, required: true  # Array of target processors
end

class FanOutRouter
  def self.start
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    transport.subscribe_pattern("fanout.#.*.*") do |msg_class, data|
      message = JSON.parse(data)
      
      # Send to each specified processor
      message['processors'].each do |processor|
        ProcessingTask.new(
          data: message['data'],
          original_message_id: message['message_id'],
          _sm_header: {
            from: 'fanout_router',
            to: processor
          }
        ).publish
      end
    end
  end
end

# Aggregation pattern: Many results back to one
class AggregationCollector
  def initialize
    @results = {}
    @transport = SmartMessage::Transport::RedisQueueTransport.new
    setup_subscriptions
  end
  
  private
  
  def setup_subscriptions
    @transport.subscribe_pattern("#.*.aggregation_collector") do |msg_class, data|
      result = JSON.parse(data)
      collect_result(result)
    end
  end
  
  def collect_result(result)
    message_id = result['original_message_id']
    @results[message_id] ||= []
    @results[message_id] << result
    
    # Check if we have all expected results
    if all_results_collected?(message_id)
      publish_aggregated_result(message_id, @results[message_id])
      @results.delete(message_id)
    end
  end
end
```

### 10. Circuit Breaker Pattern with Routing

```ruby
# Route around failing services
class CircuitBreakerRouter
  def initialize
    @circuit_states = {}  # service_name => :closed | :open | :half_open
    @failure_counts = {}
    @last_failure_time = {}
    @transport = SmartMessage::Transport::RedisQueueTransport.new
    setup_routing
  end
  
  private
  
  def setup_routing
    # Monitor service health
    @transport.subscribe_pattern("health.#.*.*") do |msg_class, data|
      health_report = JSON.parse(data)
      update_circuit_state(health_report['service'], health_report['status'])
    end
    
    # Route requests based on circuit state
    @transport.subscribe_pattern("request.#.*.*") do |msg_class, data|
      request = JSON.parse(data)
      service = request['target_service']
      
      case @circuit_states[service]
      when :open
        # Route to fallback or reject
        route_to_fallback(request, service)
      when :half_open
        # Allow limited requests
        if should_allow_request?(service)
          route_to_service(request, service)
        else
          route_to_fallback(request, service)
        end
      else  # :closed (healthy)
        route_to_service(request, service)
      end
    end
  end
  
  def route_to_fallback(request, failed_service)
    fallback_service = determine_fallback(failed_service)
    
    if fallback_service
      FallbackRequest.new(
        original_service: failed_service,
        request_data: request,
        _sm_header: {
          from: 'circuit_breaker_router',
          to: fallback_service
        }
      ).publish
    else
      # No fallback available
      ErrorResponse.new(
        error: "Service #{failed_service} unavailable",
        _sm_header: {
          from: 'circuit_breaker_router',
          to: request['callback_service']
        }
      ).publish
    end
  end
end
```

## Pattern Testing and Debugging

### Pattern Validation

```ruby
# Test pattern matching
class PatternTester
  def self.test_pattern(pattern, test_keys)
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    puts "Testing pattern: #{pattern}"
    puts "-" * 40
    
    test_keys.each do |key|
      matches = transport.send(:routing_key_matches_pattern?, key, pattern)
      status = matches ? "✅ MATCH" : "❌ NO MATCH"
      puts "#{status}: #{key}"
    end
    
    transport.disconnect
  end
end

# Test cases
test_keys = [
  'order.ordermessage.api_gateway.payment_service',
  'user.usercreated.signup_service.notification_service',
  'alert.systemalert.monitoring.broadcast',
  'payment.paymentprocessed.payment_service.order_service'
]

PatternTester.test_pattern("#.*.payment_service", test_keys)
PatternTester.test_pattern("order.#.*.*", test_keys)
PatternTester.test_pattern("#.#.#.broadcast", test_keys)
```

### Pattern Performance Analysis

```ruby
# Analyze pattern matching performance
class PatternPerformance
  def self.benchmark_patterns(patterns, test_keys, iterations = 1000)
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    patterns.each do |pattern|
      start_time = Time.now
      
      iterations.times do
        test_keys.each do |key|
          transport.send(:routing_key_matches_pattern?, key, pattern)
        end
      end
      
      duration = Time.now - start_time
      total_tests = iterations * test_keys.size
      rate = total_tests / duration
      
      puts "Pattern: #{pattern}"
      puts "  Tests: #{total_tests}"
      puts "  Time: #{duration.round(4)}s"
      puts "  Rate: #{rate.round(0)} matches/sec"
      puts ""
    end
    
    transport.disconnect
  end
end

patterns = [
  "#.*.payment_service",
  "order.#.*.*",
  "#.api_gateway.*",
  "#.#.#.broadcast"
]

PatternPerformance.benchmark_patterns(patterns, test_keys)
```

### Routing Table Analysis

```ruby
# Analyze routing efficiency
class RoutingAnalyzer
  def self.analyze(transport)
    routing_table = transport.routing_table
    
    puts "📊 Routing Table Analysis"
    puts "=" * 30
    
    # Pattern complexity analysis
    simple_patterns = 0
    wildcard_patterns = 0
    complex_patterns = 0
    
    routing_table.each do |pattern, queues|
      if pattern.include?('#') || pattern.include?('*')
        if pattern.count('#') + pattern.count('*') > 2
          complex_patterns += 1
        else
          wildcard_patterns += 1
        end
      else
        simple_patterns += 1
      end
    end
    
    puts "Pattern Types:"
    puts "  Simple: #{simple_patterns}"
    puts "  Wildcard: #{wildcard_patterns}"
    puts "  Complex: #{complex_patterns}"
    puts ""
    
    # Queue distribution
    queue_counts = routing_table.values.map(&:size)
    avg_queues = queue_counts.sum.to_f / queue_counts.size
    
    puts "Queue Distribution:"
    puts "  Total patterns: #{routing_table.size}"
    puts "  Total queues: #{queue_counts.sum}"
    puts "  Avg queues/pattern: #{avg_queues.round(2)}"
    puts "  Max queues/pattern: #{queue_counts.max}"
    puts ""
    
    # Potential overlaps
    overlapping_patterns = find_overlapping_patterns(routing_table.keys)
    if overlapping_patterns.any?
      puts "⚠️ Potentially overlapping patterns:"
      overlapping_patterns.each do |pair|
        puts "  #{pair[0]} ↔ #{pair[1]}"
      end
    else
      puts "✅ No overlapping patterns detected"
    end
  end
  
  private
  
  def self.find_overlapping_patterns(patterns)
    overlaps = []
    
    patterns.combination(2) do |p1, p2|
      if patterns_might_overlap?(p1, p2)
        overlaps << [p1, p2]
      end
    end
    
    overlaps
  end
  
  def self.patterns_might_overlap?(p1, p2)
    # Simple heuristic - both have wildcards in same positions
    p1_parts = p1.split('.')
    p2_parts = p2.split('.')
    
    return false if p1_parts.size != p2_parts.size
    
    p1_parts.zip(p2_parts).any? do |part1, part2|
      (part1 == '#' || part1 == '*') && (part2 == '#' || part2 == '*')
    end
  end
end

# Analyze current routing
transport = SmartMessage::Transport::RedisQueueTransport.new
RoutingAnalyzer.analyze(transport)
```

## Best Practices for Pattern Design

### 1. Pattern Hierarchy

```ruby
# Organize patterns from specific to general
patterns = [
  "emergency.alert.security.critical",    # Most specific
  "emergency.alert.security.*",           # Department-specific
  "emergency.alert.*.*",                  # Alert type-specific
  "emergency.#.*.*",                      # Emergency namespace
  "#.#.#.critical",                       # Priority-specific
  "#.#.#.broadcast"                       # Broadcast messages
]
```

### 2. Naming Conventions

```ruby
# Use consistent naming patterns
PATTERN_CONVENTIONS = {
  # Service routing
  service_inbound: "#.*.{service_name}",
  service_outbound: "#{service_name}.#.*.*",
  
  # Event routing
  domain_events: "#{domain}.#.*.*",
  global_events: "#.#.#.broadcast",
  
  # Priority routing
  critical_messages: "#.#.#.critical",
  urgent_messages: "#.#.#.urgent",
  
  # Geographic routing
  regional_messages: "#.*.{region}_*",
  global_messages: "#.*.global"
}.freeze
```

### 3. Pattern Documentation

```ruby
# Document your routing patterns
class RoutingDocumentation
  PATTERNS = {
    "#.*.payment_service" => {
      description: "All messages directed to payment service",
      use_case: "Payment processing requests from any source",
      examples: [
        "order.paymentrequest.api_gateway.payment_service",
        "refund.refundrequest.customer_service.payment_service"
      ],
      performance: "High volume - ensure adequate consumers"
    },
    
    "emergency.#.*.*" => {
      description: "All emergency messages regardless of routing",
      use_case: "Emergency monitoring and logging",
      examples: [
        "emergency.fire.building_sensor.fire_department",
        "emergency.medical.mobile_app.ambulance_service"
      ],
      performance: "Critical - requires immediate processing"
    }
  }.freeze
  
  def self.document_pattern(pattern)
    info = PATTERNS[pattern]
    return unless info
    
    puts "Pattern: #{pattern}"
    puts "Description: #{info[:description]}"
    puts "Use Case: #{info[:use_case]}"
    puts "Examples:"
    info[:examples].each { |ex| puts "  - #{ex}" }
    puts "Performance Notes: #{info[:performance]}"
    puts ""
  end
end
```

Advanced routing patterns enable sophisticated message architectures that can adapt to complex business requirements while maintaining high performance and reliability. Use these patterns as building blocks to create messaging systems that scale with your application's needs.