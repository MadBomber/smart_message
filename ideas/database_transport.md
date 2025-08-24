# Database Transport Implementation Ideas

This document explores implementing database-backed transports for SmartMessage, focusing on persistent messaging, advanced routing capabilities, and high-performance batching operations.

## Overview

Database transports provide a **persistent, transactional messaging layer** that complements existing in-memory (Redis, Memory) transports. The recommended architecture uses a **hybrid approach**:

- **Database Transport**: Publish-only persistent archive (no subscriptions)
- **Redis Transport**: Real-time pub/sub processing (existing functionality)
- **Multi-Transport Publishing**: Messages published to both simultaneously

This hybrid model delivers enterprise-grade persistence with Redis-speed real-time processing, while dramatically simplifying the database transport implementation by eliminating all subscription complexity.

## Core Benefits

### 1. Reliability & Persistence
- **ACID Guarantees**: Transactional message processing with rollback capabilities
- **Message Survival**: Messages persist across application restarts and failures
- **Built-in Dead Letter Queue**: Failed messages automatically retained in database
- **Complete Audit Trail**: Every message stored with timestamps, processing status
- **Guaranteed Delivery**: Messages remain until successfully processed
- **Disaster Recovery**: Database backups include full message history

### 2. Advanced Routing Capabilities
- **SQL-based Filtering**: Complex routing rules using WHERE clauses
- **Priority Queues**: ORDER BY priority, created_at for message ordering
- **Delayed Processing**: Schedule messages for future processing with WHERE process_after < NOW()
- **Content-based Routing**: Route messages based on payload content using JSONB queries
- **Entity Targeting**: Perfect integration with FROM/TO/REPLY_TO addressing system

### 3. Performance Through Batching
- **Bulk Operations**: INSERT/UPDATE operations 100x faster than individual operations
- **Transaction Efficiency**: Process multiple messages atomically
- **Connection Pool Utilization**: Leverage database connection pooling
- **Reduced I/O Overhead**: Batch database round-trips for high-throughput scenarios

## Database Schema Design

### Core Messages Table
```sql
CREATE TABLE smart_messages (
  id BIGSERIAL PRIMARY KEY,

  -- Header fields (matches SmartMessage::Header exactly)
  uuid UUID NOT NULL UNIQUE,
  message_class VARCHAR NOT NULL,
  published_at TIMESTAMP WITH TIME ZONE NOT NULL,
  publisher_pid INTEGER NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  serializer VARCHAR,             -- Tracks serializer used for DLQ/gateway patterns

  -- Entity addressing fields (SmartMessage::Header addressing)
  from_entity VARCHAR NOT NULL,   -- Required: sender entity ID
  to_entity VARCHAR,              -- NULL = broadcast to all subscribers
  reply_to VARCHAR,               -- Optional: response routing entity

  -- Message content and processing
  payload JSONB NOT NULL,         -- Serialized message payload
  payload_format VARCHAR DEFAULT 'json', -- Format tracking for multi-serializer support

  -- Processing state tracking
  status VARCHAR DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  processed_at TIMESTAMP WITH TIME ZONE,
  processing_attempts INTEGER DEFAULT 0,
  last_error TEXT,
  last_processed_by VARCHAR,      -- Handler/processor identification

  -- Advanced features for enterprise usage
  priority INTEGER DEFAULT 0,    -- Higher numbers = higher priority
  process_after TIMESTAMP WITH TIME ZONE DEFAULT NOW(), -- Delayed processing
  expires_at TIMESTAMP WITH TIME ZONE,  -- Message expiration
  correlation_id VARCHAR,         -- Request-reply correlation

  -- Audit and compliance
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  -- Constraints
  CONSTRAINT smart_messages_uuid_key UNIQUE (uuid),
  CONSTRAINT smart_messages_version_positive CHECK (version > 0),
  CONSTRAINT smart_messages_priority_range CHECK (priority >= 0),
  CONSTRAINT smart_messages_processing_attempts_positive CHECK (processing_attempts >= 0)
);

-- Optimized performance indexes based on SmartMessage usage patterns
CREATE INDEX idx_smart_messages_processing_queue
  ON smart_messages (status, process_after, priority DESC, created_at ASC)
  WHERE status IN ('pending', 'processing');

CREATE INDEX idx_smart_messages_entity_routing
  ON smart_messages (message_class, to_entity, status);

CREATE INDEX idx_smart_messages_from_entity_audit
  ON smart_messages (from_entity, created_at DESC);

CREATE INDEX idx_smart_messages_correlation
  ON smart_messages (correlation_id)
  WHERE correlation_id IS NOT NULL;

CREATE INDEX idx_smart_messages_expiration
  ON smart_messages (expires_at)
  WHERE expires_at IS NOT NULL AND status = 'pending';

-- Partial index for active messages only (significant performance gain)
CREATE INDEX idx_smart_messages_active_by_class
  ON smart_messages (message_class, priority DESC, created_at ASC)
  WHERE status IN ('pending', 'processing');
```

### Subscription Registry Table
```sql
CREATE TABLE smart_subscriptions (
  id BIGSERIAL PRIMARY KEY,
  message_class VARCHAR NOT NULL,
  processor_method VARCHAR NOT NULL,

  -- Entity-aware filtering support (matches SmartMessage v0.0.6+ filtering)
  subscriber_entity_id VARCHAR,   -- The entity subscribing (for targeting)
  from_filter VARCHAR[],          -- Array of from entity patterns
  to_filter VARCHAR[],            -- Array of to entity patterns
  broadcast_filter BOOLEAN,       -- Filter for broadcast messages

  -- Filter type tracking for regex vs exact matching
  from_filter_types VARCHAR[],    -- 'exact' or 'regex' for each from_filter
  to_filter_types VARCHAR[],      -- 'exact' or 'regex' for each to_filter

  -- Subscription metadata
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_matched_at TIMESTAMP WITH TIME ZONE,
  match_count BIGINT DEFAULT 0,

  -- Deduplication settings per subscription
  ddq_enabled BOOLEAN DEFAULT true,
  ddq_size INTEGER DEFAULT 100,

  UNIQUE(message_class, processor_method, subscriber_entity_id)
);

-- Optimized indexes for subscription matching
CREATE INDEX idx_smart_subscriptions_message_routing
  ON smart_subscriptions (message_class);

CREATE INDEX idx_smart_subscriptions_entity_targeting
  ON smart_subscriptions (subscriber_entity_id, message_class);

CREATE INDEX idx_smart_subscriptions_broadcast
  ON smart_subscriptions (message_class, broadcast_filter)
  WHERE broadcast_filter = true;
```

### Deduplication Queue Table (Database-backed DDQ)
```sql
CREATE TABLE smart_ddq_entries (
  id BIGSERIAL PRIMARY KEY,
  handler_key VARCHAR NOT NULL,   -- "MessageClass:HandlerMethod" format
  message_uuid UUID NOT NULL,
  processed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  -- Circular buffer metadata
  position INTEGER NOT NULL,      -- Position in circular buffer (0 to ddq_size-1)

  UNIQUE(handler_key, position),  -- Ensures circular buffer constraint
  INDEX idx_ddq_handler_lookup (handler_key, message_uuid),
  INDEX idx_ddq_cleanup (processed_at)  -- For TTL cleanup
);

-- Partitioning by handler_key for high-throughput scenarios
-- CREATE TABLE smart_ddq_entries_handler1 PARTITION OF smart_ddq_entries FOR VALUES IN ('OrderMessage:process');
```

### Dead Letter Queue Table
```sql
CREATE TABLE smart_dead_letters (
  id BIGSERIAL PRIMARY KEY,

  -- Reference to original message
  original_message_id BIGINT REFERENCES smart_messages(id),
  original_uuid UUID NOT NULL,

  -- Failure tracking
  failed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  failure_reason VARCHAR NOT NULL,  -- 'processing_error', 'timeout', 'circuit_breaker', 'max_retries'
  error_message TEXT,
  error_details JSONB,             -- Structured error information
  stack_trace TEXT,
  retry_count INTEGER DEFAULT 0,

  -- Handler context
  failed_handler VARCHAR,          -- Which handler failed
  failed_processor VARCHAR,        -- Which processor/method failed

  -- Complete message preservation for replay
  message_class VARCHAR NOT NULL,
  from_entity VARCHAR NOT NULL,
  to_entity VARCHAR,
  reply_to VARCHAR,
  payload JSONB NOT NULL,
  payload_format VARCHAR DEFAULT 'json',

  -- Original header preservation
  original_published_at TIMESTAMP WITH TIME ZONE,
  original_publisher_pid INTEGER,
  original_version INTEGER,
  original_serializer VARCHAR,

  -- DLQ management
  replay_count INTEGER DEFAULT 0,
  last_replay_at TIMESTAMP WITH TIME ZONE,
  replay_successful BOOLEAN,

  -- Audit
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for DLQ management and analysis
CREATE INDEX idx_dead_letters_failure_analysis
  ON smart_dead_letters (message_class, failure_reason, failed_at DESC);

CREATE INDEX idx_dead_letters_replay_queue
  ON smart_dead_letters (failed_at ASC)
  WHERE replay_successful IS NULL;

CREATE INDEX idx_dead_letters_handler_errors
  ON smart_dead_letters (failed_handler, failed_at DESC);
```

## Hybrid Architecture: Publish-Only Database + Redis Processing

### Recommended Architecture

The optimal database transport implementation uses a **publish-only pattern** combined with Redis for real-time processing:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Application   │    │  SmartMessage    │    │   Multi-Trans   │
│   Publishes     ├───►│    Message       ├───►│   Publishing    │
│   OrderMessage  │    │   Instance       │    │                 │
└─────────────────┘    └──────────────────┘    └─────────┬───────┘
                                                          │
                                          ┌───────────────┼───────────────┐
                                          │               │               │
                                          ▼               ▼               ▼
                                   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
                                   │   Database  │ │    Redis    │ │     S3      │
                                   │  (Archive)  │ │(Processing) │ │ (Compliance)│
                                   │ Publish-Only│ │   Pub/Sub   │ │Archive-Only │
                                   └─────────────┘ └─────────────┘ └─────────────┘
                                          │               │               │
                                          ▼               ▼               ▼
                                   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
                                   │   Audit     │ │ Subscribers │ │ Long-term   │
                                   │   Trails    │ │ Get Messages│ │  Storage    │
                                   │   Reports   │ │ Immediately │ │             │
                                   └─────────────┘ └─────────────┘ └─────────────┘
```

### Database Transport: Publish-Only Implementation

```ruby
class DatabaseTransport < Base
  # Database transport does NOT support subscriptions
  def subscribe(message_class, process_method, filter_options = {})
    raise NotImplementedError,
      "DatabaseTransport is publish-only. Use RedisTransport for message processing subscriptions."
  end

  # Only implement publishing for persistent archiving
  def do_publish(message_class, serialized_message)
    message_data = JSON.parse(serialized_message)
    header = message_data['header']
    payload = message_data['payload']

    # Simple INSERT - optimized for archival, not processing
    @connection_pool.with do |conn|
      conn.execute(<<~SQL, [
        header['uuid'],
        header['message_class'],
        header['published_at'],
        header['publisher_pid'],
        header['version'],
        header['serializer'],
        header['from'],
        header['to'],
        header['reply_to'],
        payload,
        'json',
        'archived'  # Status: archived, not for processing
      ])
        INSERT INTO smart_messages (
          uuid, message_class, published_at, publisher_pid, version, serializer,
          from_entity, to_entity, reply_to, payload, payload_format, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
      SQL
    end
  end

  # Simplified connection management (no complex subscription threads)
  def connected?
    @connection_pool.with { |conn| conn.execute("SELECT 1").first }
    true
  rescue
    false
  end

  def connect
    # Database connections are managed by connection pool
    # No subscription threads to start
  end

  def disconnect
    # No subscription threads to stop
    @connection_pool&.shutdown { |conn| conn.close }
  end
end
```

### Multi-Transport Message Configuration

Messages can be configured to publish to multiple transports simultaneously:

```ruby
class OrderMessage < SmartMessage::Base
  property :order_id, required: true
  property :amount, required: true
  property :customer_id, required: true

  config do
    # Multi-transport: Redis for processing + Database for archiving
    transport [
      redis_transport,      # Real-time pub/sub processing
      database_transport    # Persistent archive (publish-only)
    ]
    serializer SmartMessage::Serializer::JSON.new
  end
end

# Publishing sends to ALL configured transports
message = OrderMessage.new(order_id: "123", amount: 99.99, customer_id: "cust_456")
message.from = "order_service"
message.to = "payment_service"
message.publish  # → Redis pub/sub (immediate) + Database INSERT (archived)
```

### Environment-Specific Transport Configurations

```ruby
# config/initializers/smart_message.rb

# Development: Redis only for speed
if Rails.env.development?
  SmartMessage.configure do
    default_transport redis_transport
  end
end

# Production: Redis + Database + S3 for enterprise requirements
if Rails.env.production?
  SmartMessage.configure do
    default_transport [
      redis_transport,                              # Real-time processing
      database_transport(database_url: ENV['DATABASE_URL']), # Audit archive
      s3_transport(bucket: ENV['AUDIT_BUCKET'])     # Compliance storage
    ]
  end
end

# Testing: Memory only
if Rails.env.test?
  SmartMessage.configure do
    default_transport memory_transport
  end
end
```

### Benefits of Publish-Only Database Transport

1. **Simplified Implementation**: No subscription complexity, polling, or notification systems
2. **High Performance**: Optimized for write-heavy archival workloads
3. **Clear Separation**: Database = persistence, Redis = processing
4. **Scalability**: Database optimized for storage, Redis optimized for speed
5. **Reliability**: Every message guaranteed to be archived regardless of processing failures
6. **Compliance**: Complete audit trail with ACID guarantees
7. **Flexibility**: Add/remove archive transports without affecting processing

### Multi-Transport Publishing Logic

SmartMessage Base class handles multi-transport publishing automatically:

```ruby
# In SmartMessage::Base
def publish
  validate!

  # Support both single transport and array of transports
  transports = Array(self.class.transport)

  transports.each do |transport|
    begin
      serialized_message = serialize
      transport.publish(self.class.name, serialized_message)
    rescue => e
      # Continue publishing to other transports even if one fails
      logger.error "Failed to publish to #{transport.class.name}: #{e.message}"
      # Could integrate with circuit breaker for fallback behavior
    end
  end
end
```

This architecture provides the best of all worlds:
- **Redis speed** for real-time processing
- **Database persistence** for enterprise requirements
- **Simple implementation** with clear separation of concerns
- **Flexible configuration** for different environments

## Subscription and Notification Strategy

### Push vs Pull: Database Notification Systems

**Challenge**: Unlike Redis pub/sub which pushes messages instantly, databases require a mechanism to notify applications when new messages arrive. Traditional polling is inefficient and adds latency.

**Solution**: Use database-native push notification systems for real-time message delivery.

#### PostgreSQL LISTEN/NOTIFY (Recommended)
PostgreSQL provides a built-in pub/sub system that delivers true push notifications:

```sql
-- Database trigger to notify on new messages
CREATE OR REPLACE FUNCTION notify_new_message()
RETURNS TRIGGER AS $$
BEGIN
  -- Send notification with message details
  PERFORM pg_notify('new_smart_message', json_build_object(
    'message_id', NEW.id,
    'message_class', NEW.message_class,
    'priority', NEW.priority,
    'to_entity', NEW.to_entity
  )::text);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger fires automatically on INSERT
CREATE TRIGGER trigger_notify_new_message
  AFTER INSERT ON smart_messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_new_message();
```

```ruby
class DatabaseTransport < Base
  def start_postgres_listener
    @notification_thread = Thread.new do
      @connection_pool.with do |conn|
        # Subscribe to database notifications
        conn.execute("LISTEN new_smart_message")

        loop do
          # Block until notification received (no polling!)
          conn.raw_connection.wait_for_notify do |channel, pid, payload|
            handle_notification(payload)
          end
        end
      end
    end
  end

  private

  def handle_notification(payload)
    message_info = JSON.parse(payload)
    message_id = message_info['message_id']

    # Fetch specific message and process immediately
    message_data = fetch_message_by_id(message_id)
    if message_data
      # Convert to SmartMessage format and route
      receive(message_data['message_class'], reconstruct_serialized_message(message_data))

      # Mark as processing to prevent duplicate handling
      mark_message_processing(message_id)
    end
  end

  def fetch_message_by_id(message_id)
    @connection_pool.with do |conn|
      conn.execute(<<~SQL, [message_id]).first
        SELECT * FROM smart_messages
        WHERE id = $1 AND status = 'pending'
      SQL
    end
  end
end
```

#### MySQL/Other Databases (Polling Fallback)
For databases without native push notifications:

```ruby
def start_polling_subscriber
  @polling_thread = Thread.new do
    loop do
      poll_for_messages
      sleep(@options[:poll_interval] || 1) # Default 1 second
    end
  end
end

def poll_for_messages
  messages = retrieve_pending_messages(limit: @options[:batch_size] || 100)

  messages.each do |message_data|
    receive(message_data['message_class'], reconstruct_serialized_message(message_data))
    mark_message_processing(message_data['id'])
  end
end
```

#### Hybrid Detection Strategy
```ruby
def initialize(**options)
  super
  @notification_method = detect_notification_method
  configure_subscriber
end

private

def detect_notification_method
  case @connection_adapter_name
  when /postgresql/i
    :listen_notify
  when /mysql/i
    :polling  # Could add MySQL events or external triggers
  when /sqlite/i
    :polling  # Limited to single-process anyway
  else
    :polling
  end
end

def start_subscriber
  case @notification_method
  when :listen_notify
    start_postgres_listener
  else
    start_polling_subscriber
  end
end
```

### Performance Comparison

| Method | Latency | CPU Usage | Database Support | Complexity |
|--------|---------|-----------|------------------|------------|
| **PostgreSQL LISTEN/NOTIFY** | ~1ms | Very Low | PostgreSQL | Medium |
| **MySQL Events** | ~1s | Low | MySQL | Medium |
| **Polling (1s interval)** | ~500ms avg | Medium | All | Low |
| **Polling (100ms interval)** | ~50ms avg | High | All | Low |

### Benefits of PostgreSQL LISTEN/NOTIFY

- **Real-time Delivery**: Sub-millisecond notification latency
- **Zero Polling Overhead**: No constant database queries
- **Connection Resilience**: Automatic reconnection and notification replay
- **Scalable**: Multiple subscribers can listen to same channel
- **Native Integration**: Built into PostgreSQL, no external dependencies
- **Filtered Notifications**: Can include message metadata in notification payload

This approach gives database transport **the same real-time characteristics as Redis pub/sub** while maintaining all the persistence, ACID guarantees, and enterprise features that databases provide.

## Implementation Architecture

### Transport Class Structure
```ruby
module SmartMessage
  module Transport
    class DatabaseTransport < Base
      attr_reader :connection_pool, :batch_processor

      def initialize(**options)
        super
        @connection_pool = setup_connection_pool
        @batch_processor = BatchProcessor.new(self)
        @pending_messages = Queue.new
        setup_batch_timer if options[:enable_batching]
      end

      # Individual message publishing (immediate)
      def publish(message_header, message_payload)
        if @options[:enable_batching]
          @pending_messages << [message_header, message_payload]
        else
          publish_single(message_header, message_payload)
        end
      end

      # Batch publishing for high-throughput scenarios
      def publish_batch(messages)
        @connection_pool.with do |conn|
          conn.transaction do
            insert_data = messages.map { |header, payload| prepare_message_data(header, payload) }
            conn.execute(batch_insert_sql, insert_data.flatten)
          end
        end
      end

      # Message retrieval with advanced routing
      def retrieve_messages(entity_id: nil, limit: 100)
        @connection_pool.with do |conn|
          conn.execute(retrieval_sql, [entity_id, entity_id, Time.current, limit])
        end
      end

      private

      def retrieval_sql
        <<~SQL
          SELECT id, uuid, from_entity, to_entity, reply_to, message_class,
                 payload, published_at, priority
          FROM smart_messages
          WHERE processed_at IS NULL
            AND process_after <= $3
            AND (to_entity = $1 OR to_entity IS NULL OR $2 IS NULL)
          ORDER BY priority DESC, published_at ASC
          LIMIT $4
        SQL
      end
    end
  end
end
```

### Batch Processing System
```ruby
class BatchProcessor
  def initialize(transport)
    @transport = transport
    @batch = []
    @mutex = Mutex.new
    @batch_size = transport.options[:batch_size] || 100
    @batch_timeout = transport.options[:batch_timeout] || 5.seconds
  end

  def add_message(header, payload)
    @mutex.synchronize do
      @batch << [header, payload]
      flush_if_ready
    end
  end

  def flush_if_ready
    if @batch.size >= @batch_size
      flush_batch
    end
  end

  def flush_batch
    return if @batch.empty?

    batch_to_process = @batch.dup
    @batch.clear

    @transport.publish_batch(batch_to_process)
  end
end
```

## Advanced Routing Queries

### Entity-Specific and Broadcast Messaging
```sql
-- Retrieve messages for specific entity or broadcast messages
SELECT * FROM smart_messages
WHERE processed_at IS NULL
  AND (to_entity = 'user_123' OR to_entity IS NULL)
  AND process_after <= NOW()
ORDER BY priority DESC, published_at ASC;
```

### Priority-Based Processing
```sql
-- High priority messages first, then by publish time
SELECT * FROM smart_messages
WHERE processed_at IS NULL
  AND message_class = 'OrderProcessingMessage'
ORDER BY priority DESC, published_at ASC
LIMIT 50;
```

### Content-Based Routing
```sql
-- Route based on payload content using JSONB operators
SELECT * FROM smart_messages
WHERE processed_at IS NULL
  AND message_class = 'NotificationMessage'
  AND payload->>'urgency' = 'high'
  AND payload->'recipient'->>'region' = 'us-west';
```

### Delayed Processing
```sql
-- Messages scheduled for future processing
SELECT * FROM smart_messages
WHERE processed_at IS NULL
  AND process_after <= NOW()
ORDER BY process_after ASC, priority DESC;
```

## Integration with SmartMessage Improvements

### 1. Message Wrapper Enhancement Integration
The database schema naturally supports the proposed addressing system:
```ruby
# Publishing with addressing
message = OrderMessage.new(order_id: "123", amount: 99.99)
message.from = "order_service"
message.to = "payment_service"  # Specific targeting
message.reply_to = "order_service"
message.publish

# Broadcast (to_entity = NULL)
broadcast = SystemAlert.new(message: "Maintenance starting")
broadcast.from = "admin_service"
# No .to specified = broadcast
broadcast.publish
```

### 2. Circuit Breaker Integration
```ruby
class DatabaseTransport < Base
  include BreakerMachines::DSL

  circuit :database_publish do
    threshold failures: 5, within: 2.minutes
    reset_after 30.seconds
    fallback { |error| handle_publish_failure(error) }
  end

  def publish(message_header, message_payload)
    circuit(:database_publish).wrap do
      # Database publishing logic
    end
  end
end
```

### 3. Dead Letter Queue Integration
```ruby
def mark_message_failed(message_id, error)
  @connection_pool.with do |conn|
    conn.transaction do
      # Move to dead letter queue
      conn.execute(insert_dead_letter_sql, [message_id, error.message])

      # Update original message
      conn.execute(
        "UPDATE smart_messages SET processed_at = NOW(), last_error = $1 WHERE id = $2",
        [error.message, message_id]
      )
    end
  end
end
```

### 4. Ractor-Based Processing Integration
```ruby
class DatabaseMessageProcessor
  def initialize(database_transport)
    @transport = database_transport
    @ractor_pool = RactorPool.new(size: 4)
  end

  def process_messages
    messages = @transport.retrieve_messages(limit: 100)

    messages.each do |message_data|
      @ractor_pool.post(message_data) do |data|
        # Process in isolated Ractor
        process_single_message(data)
      end
    end
  end
end
```

## Performance Characteristics

### Benchmarking Scenarios

**Single Message Operations:**
- Individual INSERT: ~1-2ms per message
- Individual SELECT: ~0.5-1ms per message
- Network latency typically dominates

**Batch Operations:**
- Batch INSERT (100 messages): ~10-20ms total (10-20x improvement)
- Bulk UPDATE (marking processed): ~5-10ms for 100 messages
- Transaction overhead amortized across batch

**Query Performance:**
- Indexed entity routing: Sub-millisecond
- Priority ordering: ~1-2ms for large queues
- JSONB content filtering: ~2-5ms depending on complexity

### Scalability Considerations
- **Read Replicas**: Route message retrieval to read replicas
- **Partitioning**: Partition by message_class or date for large volumes
- **Archival**: Move old processed messages to archive tables
- **Connection Pooling**: Scale with database connection limits

## Configuration Options

```ruby
# Database transport configuration
database_transport = SmartMessage::Transport.create(:database,
  # Database connection
  database_url: ENV['DATABASE_URL'],
  connection_pool_size: 10,

  # Batching configuration
  enable_batching: true,
  batch_size: 100,
  batch_timeout: 5.seconds,

  # Processing options
  default_priority: 0,
  enable_delayed_processing: true,

  # Reliability options
  max_processing_attempts: 3,
  dead_letter_queue_enabled: true,

  # Performance options
  retrieval_limit: 100,
  enable_content_routing: true
)
```

## Use Cases

### 1. Financial Transactions
- **ACID Requirements**: Transaction messages must be durable
- **Audit Trail**: Regulatory compliance requires complete history
- **Guaranteed Delivery**: Payment processing cannot lose messages
- **Priority Processing**: High-value transactions get priority

### 2. Order Processing Systems
- **State Persistence**: Order state changes must survive failures
- **Entity Routing**: Messages targeted to specific services
- **Delayed Processing**: Scheduled order fulfillment
- **Batch Efficiency**: High-volume order processing

### 3. Notification Systems
- **Content Routing**: Different notification types to different handlers
- **Priority Levels**: Urgent notifications processed first
- **Delivery Guarantees**: Critical notifications must be delivered
- **Scheduling**: Time-based notification delivery

### 4. Enterprise Integration
- **Multiple Systems**: Database provides universal messaging layer
- **Gateway Patterns**: Transform messages between different formats
- **Monitoring**: Complete visibility into message flow
- **Compliance**: Audit trails for regulatory requirements

## Migration Strategy

### Phase 1: Basic Implementation
1. Create database schema
2. Implement basic DatabaseTransport class
3. Add to transport registry
4. Create basic publish/subscribe functionality

### Phase 2: Addressing Integration
1. Add FROM/TO/REPLY_TO fields to schema
2. Implement entity-specific routing
3. Update dispatcher to handle database retrieval
4. Add broadcast vs targeted message support

### Phase 3: Advanced Features
1. Implement batch processing
2. Add priority and delayed processing
3. Create dead letter queue functionality
4. Add content-based routing

### Phase 4: Performance & Reliability
1. Optimize queries and indexes
2. Add connection pooling
3. Implement circuit breakers
4. Add monitoring and metrics

## Testing Strategy

### Unit Tests
```ruby
RSpec.describe SmartMessage::Transport::DatabaseTransport do
  let(:transport) { described_class.new(database_url: test_db_url) }

  describe '#publish' do
    it 'stores message in database' do
      header = create_header(from: 'service_a', to: 'service_b')
      payload = '{"test": true}'

      transport.publish(header, payload)

      message = SmartMessage::DatabaseMessage.last
      expect(message.from_entity).to eq('service_a')
      expect(message.to_entity).to eq('service_b')
      expect(message.payload).to eq('{"test": true}')
    end
  end

  describe '#retrieve_messages' do
    it 'returns messages for specific entity' do
      create_message(to_entity: 'service_a')
      create_message(to_entity: 'service_b')
      create_message(to_entity: nil) # broadcast

      messages = transport.retrieve_messages(entity_id: 'service_a')

      expect(messages.count).to eq(2) # targeted + broadcast
    end
  end
end
```

### Integration Tests
```ruby
RSpec.describe 'Database Transport Integration' do
  it 'handles complete message lifecycle' do
    # Setup message class with database transport
    class TestMessage < SmartMessage::Base
      property :data

      config do
        transport database_transport
        serializer SmartMessage::Serializer::JSON.new
      end

      def self.process(header, payload)
        # Processing logic
      end
    end

    # Subscribe
    TestMessage.subscribe

    # Publish
    message = TestMessage.new(data: 'test')
    message.from = 'test_service'
    message.publish

    # Verify storage and processing
    expect(SmartMessage::DatabaseMessage.count).to eq(1)

    # Simulate processing
    transport.process_pending_messages

    db_message = SmartMessage::DatabaseMessage.last
    expect(db_message.processed_at).not_to be_nil
  end
end
```

## Conclusion

Database transports represent a **significant architectural enhancement** to SmartMessage, enabling:

1. **Enterprise-grade reliability** through persistence and ACID guarantees
2. **Advanced routing capabilities** through SQL-based filtering and entity targeting
3. **High-performance batching** for throughput-intensive applications
4. **Complete observability** through built-in audit trails and message history
5. **Natural integration** with other planned improvements (addressing, circuit breakers, Ractors)

This positions SmartMessage as a production-ready messaging framework capable of handling mission-critical applications while maintaining the simplicity and elegance of the current API.

The database transport complements rather than replaces existing transports - Redis for speed, Memory for testing, Database for reliability and persistence.
