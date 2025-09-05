# Redis Queue Transport - Production Guide

This guide covers deploying Redis Queue Transport in production environments, including configuration, monitoring, scaling, and operational best practices.

## Production Architecture

### Recommended Infrastructure

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Application   │    │     Redis        │    │    Monitoring   │
│    Servers      │◄──►│    Cluster       │◄──►│     Stack       │
│                 │    │                  │    │                 │
│ • Rails Apps    │    │ • Master/Replica │    │ • Prometheus    │
│ • Workers       │    │ • Sentinel       │    │ • Grafana       │
│ • Background    │    │ • Persistence    │    │ • AlertManager  │
│   Jobs          │    │ • Memory Opt     │    │ • Logs          │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Infrastructure Components

1. **Application Layer**: Rails applications, worker processes
2. **Redis Layer**: Clustered Redis with persistence and monitoring
3. **Load Balancers**: HAProxy/nginx for application load balancing
4. **Monitoring**: Comprehensive observability stack
5. **Alerting**: Proactive issue detection and notification

## Redis Configuration

### Production Redis Settings

```ruby
# config/redis.conf
# Memory and performance optimization
maxmemory 4gb
maxmemory-policy allkeys-lru
tcp-keepalive 60
timeout 0

# Persistence for queue durability
save 900 1    # Save if at least 1 change in 15 minutes
save 300 10   # Save if at least 10 changes in 5 minutes
save 60 10000 # Save if at least 10k changes in 1 minute

# AOF for maximum durability
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Network and connection settings
tcp-backlog 511
bind 0.0.0.0
port 6379
protected-mode yes
requirepass your_secure_password

# Logging
loglevel notice
logfile /var/log/redis/redis-server.log
syslog-enabled yes

# Performance tuning
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
```

### Redis Cluster Setup

```yaml
# docker-compose.yml for Redis cluster
version: '3.8'
services:
  redis-master:
    image: redis:7-alpine
    command: redis-server /etc/redis/redis.conf
    volumes:
      - ./redis-master.conf:/etc/redis/redis.conf
      - redis-master-data:/data
    ports:
      - "6379:6379"
    networks:
      - redis-network
    
  redis-replica-1:
    image: redis:7-alpine
    command: redis-server /etc/redis/redis.conf
    volumes:
      - ./redis-replica.conf:/etc/redis/redis.conf
      - redis-replica-1-data:/data
    depends_on:
      - redis-master
    networks:
      - redis-network
      
  redis-replica-2:
    image: redis:7-alpine
    command: redis-server /etc/redis/redis.conf
    volumes:
      - ./redis-replica.conf:/etc/redis/redis.conf
      - redis-replica-2-data:/data
    depends_on:
      - redis-master
    networks:
      - redis-network
      
  redis-sentinel-1:
    image: redis:7-alpine
    command: redis-sentinel /etc/redis/sentinel.conf
    volumes:
      - ./sentinel.conf:/etc/redis/sentinel.conf
    depends_on:
      - redis-master
    networks:
      - redis-network

volumes:
  redis-master-data:
  redis-replica-1-data:
  redis-replica-2-data:

networks:
  redis-network:
    driver: bridge
```

## SmartMessage Configuration

### Production Transport Configuration

```ruby
# config/environments/production.rb
SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    # Connection settings
    url: ENV.fetch('REDIS_URL', 'redis://redis.internal:6379'),
    db: ENV.fetch('REDIS_DB', '0').to_i,
    password: ENV['REDIS_PASSWORD'],
    
    # Queue configuration
    queue_prefix: "#{Rails.application.class.module_parent_name.downcase}.#{Rails.env}",
    consumer_group: "#{Rails.application.class.module_parent_name.downcase}_workers",
    consumer_id: "#{Socket.gethostname}_#{Process.pid}",
    
    # Performance tuning
    block_time: 5000,         # 5 second blocking timeout
    max_queue_length: 100000, # Large queue capacity
    batch_size: 10,           # Process in batches
    
    # Reliability settings
    max_retries: 5,
    retry_delay: 30,          # 30 seconds between retries
    exponential_backoff: true,
    dead_letter_queue: true,
    dead_letter_prefix: 'dlq',
    
    # Connection pooling
    pool_size: ENV.fetch('REDIS_POOL_SIZE', '10').to_i,
    pool_timeout: ENV.fetch('REDIS_POOL_TIMEOUT', '5').to_i,
    
    # Circuit breaker
    circuit_breaker: true,
    failure_threshold: 10,
    recovery_timeout: 120,
    
    # Monitoring
    enable_metrics: true,
    metrics_interval: 60,
    
    # Security
    ssl_params: Rails.env.production? ? { verify_mode: OpenSSL::SSL::VERIFY_PEER } : nil
  }
end
```

### Environment-Specific Settings

```ruby
# config/smartmessage.rb
class SmartMessageConfig
  ENVIRONMENT_CONFIGS = {
    development: {
      block_time: 1000,        # Fast for development
      max_queue_length: 1000,  # Small queues
      debug: true,
      pool_size: 2
    },
    
    test: {
      block_time: 100,         # Very fast for tests
      max_queue_length: 100,   # Tiny queues
      db: 15,                  # Test database
      pool_size: 1
    },
    
    staging: {
      block_time: 3000,        # Medium performance
      max_queue_length: 10000, # Medium queues
      max_retries: 3,
      pool_size: 5
    },
    
    production: {
      block_time: 5000,        # Optimized for throughput
      max_queue_length: 100000,# Large queues
      max_retries: 5,
      pool_size: 20,
      circuit_breaker: true,
      dead_letter_queue: true
    }
  }.freeze
  
  def self.configure_for_environment(env = Rails.env)
    base_config = SmartMessage.configuration.transport_options || {}
    env_config = ENVIRONMENT_CONFIGS[env.to_sym] || {}
    
    SmartMessage.configure do |config|
      config.transport_options = base_config.merge(env_config)
    end
  end
end

# Apply environment-specific configuration
SmartMessageConfig.configure_for_environment
```

## Scaling and Performance

### Horizontal Scaling

```ruby
# config/initializers/smart_message_workers.rb
class SmartMessageWorkers
  def self.start_for_environment
    worker_config = case Rails.env
                   when 'production'
                     production_workers
                   when 'staging'
                     staging_workers
                   else
                     development_workers
                   end
    
    start_workers(worker_config)
  end
  
  private
  
  def self.production_workers
    {
      # High-volume message processing
      general_workers: {
        count: ENV.fetch('GENERAL_WORKERS', '8').to_i,
        consumer_group: 'general_workers',
        patterns: ['#.*.general_service', '#.*.default']
      },
      
      # Critical business processes
      order_workers: {
        count: ENV.fetch('ORDER_WORKERS', '4').to_i,
        consumer_group: 'order_workers',
        patterns: ['order.#.*.*', '#.*.order_service']
      },
      
      # Payment processing
      payment_workers: {
        count: ENV.fetch('PAYMENT_WORKERS', '3').to_i,
        consumer_group: 'payment_workers',
        patterns: ['payment.#.*.*', '#.*.payment_service']
      },
      
      # Email and notifications
      notification_workers: {
        count: ENV.fetch('NOTIFICATION_WORKERS', '2').to_i,
        consumer_group: 'notification_workers',
        patterns: ['notification.#.*.*', '#.*.notification_service']
      },
      
      # Analytics and reporting
      analytics_workers: {
        count: ENV.fetch('ANALYTICS_WORKERS', '2').to_i,
        consumer_group: 'analytics_workers',
        patterns: ['analytics.#.*.*', '#.*.analytics_service']
      }
    }
  end
  
  def self.start_workers(worker_config)
    worker_config.each do |worker_type, config|
      Rails.logger.info "Starting #{config[:count]} #{worker_type} workers"
      
      config[:count].times do |i|
        Thread.new do
          start_worker(worker_type, i + 1, config)
        end
      end
    end
  end
  
  def self.start_worker(worker_type, worker_id, config)
    transport = SmartMessage::Transport::RedisQueueTransport.new(
      consumer_group: config[:consumer_group],
      consumer_id: "#{worker_type}_#{worker_id}_#{Socket.gethostname}"
    )
    
    config[:patterns].each do |pattern|
      transport.subscribe_pattern(pattern) do |message_class, message_data|
        Rails.logger.info "[#{worker_type}_#{worker_id}] Processing: #{message_class}"
        
        begin
          # Process message with timeout
          Timeout::timeout(30) do
            process_message(message_class, message_data)
          end
        rescue Timeout::Error
          Rails.logger.error "[#{worker_type}_#{worker_id}] Timeout processing: #{message_class}"
          raise SmartMessage::Errors::RetryableError, 'Processing timeout'
        rescue => e
          Rails.logger.error "[#{worker_type}_#{worker_id}] Error: #{e.message}"
          raise
        end
      end
    end
    
    Rails.logger.info "[#{worker_type}_#{worker_id}] Worker started"
    
    # Keep worker alive
    loop { sleep 1 }
  rescue => e
    Rails.logger.error "[#{worker_type}_#{worker_id}] Worker crashed: #{e.message}"
    # Restart worker after delay
    sleep 5
    retry
  end
end

# Auto-start workers in production
if Rails.env.production?
  Thread.new { SmartMessageWorkers.start_for_environment }
end
```

### Vertical Scaling

```ruby
# config/initializers/performance_optimization.rb
module SmartMessageOptimization
  def self.optimize_for_production
    # Optimize Redis connection pool
    configure_connection_pool
    
    # Set up message batching
    configure_batching
    
    # Enable compression for large messages
    configure_compression
    
    # Set up performance monitoring
    configure_monitoring
  end
  
  private
  
  def self.configure_connection_pool
    SmartMessage.configure do |config|
      config.transport_options.merge!({
        pool_size: [ENV.fetch('MAX_THREADS', '20').to_i, 50].min,
        pool_timeout: 10,
        reconnect_attempts: 3,
        reconnect_delay: 1
      })
    end
  end
  
  def self.configure_batching
    # Process messages in batches for better throughput
    SmartMessage::Transport::RedisQueueTransport.class_eval do
      def process_message_batch(messages)
        messages.each do |message_class, message_data|
          begin
            receive(message_class, message_data)
          rescue => e
            Rails.logger.error "Batch processing error: #{e.message}"
          end
        end
      end
    end
  end
  
  def self.configure_compression
    # Enable compression for messages over 1KB
    SmartMessage.configure do |config|
      config.serializer_options = {
        compress_threshold: 1024,
        compression_method: :gzip
      }
    end
  end
  
  def self.configure_monitoring
    # Set up performance metrics collection
    ActiveSupport::Notifications.subscribe('smartmessage.message_processed') do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      
      # Log processing time
      Rails.logger.info "Message processed in #{event.duration}ms: #{event.payload[:message_class]}"
      
      # Send to metrics collector
      if defined?(Prometheus)
        SmartMessageMetrics.record_processing_time(event.duration, event.payload[:message_class])
      end
    end
  end
end

SmartMessageOptimization.optimize_for_production if Rails.env.production?
```

## Monitoring and Observability

### Application Monitoring

```ruby
# app/services/smart_message_monitor.rb
class SmartMessageMonitor
  include Singleton
  
  def initialize
    @transport = SmartMessage::Transport::RedisQueueTransport.new
    @metrics = {}
    start_monitoring
  end
  
  def start_monitoring
    Thread.new { monitor_queues }
    Thread.new { monitor_workers }
    Thread.new { monitor_performance }
  end
  
  private
  
  def monitor_queues
    loop do
      stats = @transport.queue_stats
      
      stats.each do |queue_name, info|
        queue_length = info[:length]
        consumer_count = info[:consumers] || 0
        
        # Record metrics
        @metrics["queue.#{queue_name}.length"] = queue_length
        @metrics["queue.#{queue_name}.consumers"] = consumer_count
        
        # Check for alerts
        if queue_length > 1000
          alert_high_queue_length(queue_name, queue_length)
        end
        
        if queue_length > 0 && consumer_count == 0
          alert_no_consumers(queue_name, queue_length)
        end
        
        if consumer_count > 20
          alert_high_consumer_count(queue_name, consumer_count)
        end
      end
      
      # Update external metrics
      update_external_metrics(@metrics)
      
      sleep 30  # Check every 30 seconds
    end
  end
  
  def monitor_workers
    loop do
      worker_stats = collect_worker_stats
      
      worker_stats.each do |worker_type, stats|
        @metrics["workers.#{worker_type}.active"] = stats[:active]
        @metrics["workers.#{worker_type}.processing"] = stats[:processing]
        @metrics["workers.#{worker_type}.errors"] = stats[:errors]
      end
      
      sleep 60  # Check every minute
    end
  end
  
  def monitor_performance
    start_time = Time.now
    processed_messages = 0
    
    loop do
      current_processed = get_total_processed_messages
      duration = Time.now - start_time
      
      if duration >= 60  # Calculate rate every minute
        rate = (current_processed - processed_messages) / duration
        @metrics['performance.messages_per_second'] = rate
        
        processed_messages = current_processed
        start_time = Time.now
      end
      
      sleep 10
    end
  end
  
  def alert_high_queue_length(queue_name, length)
    Rails.logger.warn "HIGH QUEUE LENGTH: #{queue_name} has #{length} messages"
    
    # Send to alerting system
    if defined?(AlertManager)
      AlertManager.alert(
        severity: :warning,
        message: "Queue #{queue_name} has #{length} messages",
        tags: { queue: queue_name, type: :high_queue_length }
      )
    end
  end
  
  def alert_no_consumers(queue_name, length)
    Rails.logger.error "NO CONSUMERS: #{queue_name} has #{length} messages but no consumers"
    
    if defined?(AlertManager)
      AlertManager.alert(
        severity: :critical,
        message: "Queue #{queue_name} has no consumers but #{length} pending messages",
        tags: { queue: queue_name, type: :no_consumers }
      )
    end
  end
  
  def update_external_metrics(metrics)
    # Send to Prometheus
    if defined?(Prometheus::Client)
      metrics.each do |metric_name, value|
        Prometheus::Client.registry.get(metric_name.to_sym)&.set(value)
      end
    end
    
    # Send to StatsD
    if defined?(Statsd)
      metrics.each do |metric_name, value|
        $statsd&.gauge("smartmessage.#{metric_name}", value)
      end
    end
    
    # Send to CloudWatch
    if defined?(Aws::CloudWatch)
      # Implementation for CloudWatch metrics
    end
  end
end

# Start monitoring in production
SmartMessageMonitor.instance if Rails.env.production?
```

### Prometheus Metrics

```ruby
# lib/smart_message_metrics.rb
require 'prometheus/client'

module SmartMessageMetrics
  def self.setup_metrics
    registry = Prometheus::Client.registry
    
    @message_processing_duration = registry.histogram(
      :smartmessage_processing_duration_seconds,
      docstring: 'Time spent processing messages',
      labels: [:message_class, :worker_type]
    )
    
    @queue_length = registry.gauge(
      :smartmessage_queue_length,
      docstring: 'Current queue length',
      labels: [:queue_name, :pattern]
    )
    
    @consumer_count = registry.gauge(
      :smartmessage_consumer_count,
      docstring: 'Number of active consumers',
      labels: [:queue_name, :consumer_group]
    )
    
    @messages_processed_total = registry.counter(
      :smartmessage_messages_processed_total,
      docstring: 'Total number of messages processed',
      labels: [:message_class, :status]
    )
    
    @connection_errors_total = registry.counter(
      :smartmessage_connection_errors_total,
      docstring: 'Total number of Redis connection errors',
      labels: [:error_type]
    )
  end
  
  def self.record_processing_time(duration_seconds, message_class, worker_type = 'unknown')
    @message_processing_duration&.observe(duration_seconds, labels: {
      message_class: message_class,
      worker_type: worker_type
    })
  end
  
  def self.update_queue_length(queue_name, length, pattern = '')
    @queue_length&.set(length, labels: {
      queue_name: queue_name,
      pattern: pattern
    })
  end
  
  def self.update_consumer_count(queue_name, count, consumer_group = '')
    @consumer_count&.set(count, labels: {
      queue_name: queue_name,
      consumer_group: consumer_group
    })
  end
  
  def self.increment_messages_processed(message_class, status = 'success')
    @messages_processed_total&.increment(labels: {
      message_class: message_class,
      status: status
    })
  end
  
  def self.increment_connection_errors(error_type)
    @connection_errors_total&.increment(labels: {
      error_type: error_type
    })
  end
end

# Initialize metrics
SmartMessageMetrics.setup_metrics if defined?(Prometheus::Client)
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "id": null,
    "title": "SmartMessage Redis Queue Transport",
    "tags": ["smartmessage", "redis", "queues"],
    "timezone": "browser",
    "panels": [
      {
        "title": "Queue Lengths",
        "type": "graph",
        "targets": [
          {
            "expr": "smartmessage_queue_length",
            "legendFormat": "{{ queue_name }}"
          }
        ],
        "yAxes": [
          {
            "label": "Messages",
            "min": 0
          }
        ]
      },
      {
        "title": "Messages Processed per Second",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(smartmessage_messages_processed_total[1m])",
            "legendFormat": "{{ message_class }} ({{ status }})"
          }
        ]
      },
      {
        "title": "Processing Duration",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, smartmessage_processing_duration_seconds_bucket)",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.50, smartmessage_processing_duration_seconds_bucket)",
            "legendFormat": "50th percentile"
          }
        ]
      },
      {
        "title": "Active Consumers",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(smartmessage_consumer_count)",
            "legendFormat": "Total Consumers"
          }
        ]
      },
      {
        "title": "Connection Errors",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(smartmessage_connection_errors_total[5m])",
            "legendFormat": "{{ error_type }}"
          }
        ]
      }
    ]
  }
}
```

## Security

### Authentication and Authorization

```ruby
# config/initializers/redis_security.rb
class RedisSecurityConfig
  def self.configure_for_production
    SmartMessage.configure do |config|
      config.transport_options.merge!({
        # Redis authentication
        password: ENV.fetch('REDIS_PASSWORD'),
        
        # SSL/TLS encryption
        ssl: true,
        ssl_params: {
          verify_mode: OpenSSL::SSL::VERIFY_PEER,
          ca_file: ENV['REDIS_CA_CERT_PATH'],
          cert: OpenSSL::X509::Certificate.new(File.read(ENV['REDIS_CLIENT_CERT_PATH'])),
          key: OpenSSL::PKey::RSA.new(File.read(ENV['REDIS_CLIENT_KEY_PATH']))
        },
        
        # Network security
        bind: ENV.fetch('REDIS_BIND_ADDRESS', '127.0.0.1'),
        
        # Message encryption
        encrypt_messages: true,
        encryption_key: ENV.fetch('MESSAGE_ENCRYPTION_KEY')
      })
    end
  end
end

RedisSecurityConfig.configure_for_production if Rails.env.production?
```

### Message Encryption

```ruby
# lib/smart_message_encryption.rb
module SmartMessageEncryption
  def self.encrypt_message(message_data)
    key = ENV.fetch('MESSAGE_ENCRYPTION_KEY')
    cipher = OpenSSL::Cipher.new('AES-256-GCM')
    cipher.encrypt
    cipher.key = Base64.decode64(key)
    
    iv = cipher.random_iv
    encrypted_data = cipher.update(message_data) + cipher.final
    auth_tag = cipher.auth_tag
    
    Base64.encode64({
      iv: Base64.encode64(iv),
      data: Base64.encode64(encrypted_data),
      tag: Base64.encode64(auth_tag)
    }.to_json)
  end
  
  def self.decrypt_message(encrypted_message)
    key = ENV.fetch('MESSAGE_ENCRYPTION_KEY')
    parsed = JSON.parse(Base64.decode64(encrypted_message))
    
    cipher = OpenSSL::Cipher.new('AES-256-GCM')
    cipher.decrypt
    cipher.key = Base64.decode64(key)
    cipher.iv = Base64.decode64(parsed['iv'])
    cipher.auth_tag = Base64.decode64(parsed['tag'])
    
    cipher.update(Base64.decode64(parsed['data'])) + cipher.final
  end
end
```

## Deployment

### Docker Configuration

```dockerfile
# Dockerfile
FROM ruby:3.2-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Ruby dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1 && \
    bundle install --without development test

# Copy application code
COPY . .

# Create non-root user
RUN adduser --disabled-password --gecos '' appuser && \
    chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### Kubernetes Deployment

```yaml
# k8s/smartmessage-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: smartmessage-app
  labels:
    app: smartmessage-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: smartmessage-app
  template:
    metadata:
      labels:
        app: smartmessage-app
    spec:
      containers:
      - name: app
        image: smartmessage-app:latest
        ports:
        - containerPort: 3000
        env:
        - name: REDIS_URL
          value: "redis://redis-service:6379"
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: password
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: smartmessage-workers
  labels:
    app: smartmessage-workers
spec:
  replicas: 5
  selector:
    matchLabels:
      app: smartmessage-workers
  template:
    metadata:
      labels:
        app: smartmessage-workers
    spec:
      containers:
      - name: worker
        image: smartmessage-app:latest
        command: ["bundle", "exec", "ruby", "lib/workers/start_workers.rb"]
        env:
        - name: REDIS_URL
          value: "redis://redis-service:6379"
        - name: WORKER_TYPE
          value: "all"
        - name: GENERAL_WORKERS
          value: "2"
        - name: ORDER_WORKERS
          value: "1"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
```

### Helm Chart

```yaml
# helm/smartmessage/values.yaml
replicaCount: 3

image:
  repository: smartmessage
  tag: latest
  pullPolicy: IfNotPresent

redis:
  host: redis-service
  port: 6379
  database: 0
  auth:
    enabled: true
    password: "secure_password"

workers:
  enabled: true
  replicas: 5
  types:
    general: 2
    order: 1
    payment: 1
    notification: 1

resources:
  app:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 1Gi
      cpu: 500m
  workers:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 200m

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

monitoring:
  enabled: true
  prometheus:
    enabled: true
  grafana:
    enabled: true
  alerting:
    enabled: true

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  hosts:
    - host: smartmessage.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: smartmessage-tls
      hosts:
        - smartmessage.example.com
```

## High Availability

### Redis Sentinel Configuration

```ruby
# config/redis_sentinel.rb
class RedisSentinelConfig
  def self.configure_high_availability
    SmartMessage.configure do |config|
      config.transport_options = {
        # Sentinel configuration
        sentinels: [
          { host: 'sentinel-1.internal', port: 26379 },
          { host: 'sentinel-2.internal', port: 26379 },
          { host: 'sentinel-3.internal', port: 26379 }
        ],
        name: 'smartmessage-redis',
        password: ENV['REDIS_PASSWORD'],
        
        # Failover settings
        sentinel_timeout: 5,
        connect_timeout: 5,
        read_timeout: 5,
        write_timeout: 5,
        
        # Retry configuration
        reconnect_attempts: 5,
        reconnect_delay: 2,
        
        # Connection pool for HA
        pool_size: 20,
        pool_timeout: 10
      }
    end
  end
end

RedisSentinelConfig.configure_high_availability if Rails.env.production?
```

### Disaster Recovery

```ruby
# lib/disaster_recovery.rb
module DisasterRecovery
  class BackupManager
    def self.setup_automated_backups
      # Daily Redis backup
      whenever_schedule = <<~SCHEDULE
        # Redis backup every day at 2 AM
        0 2 * * * cd #{Rails.root} && bundle exec ruby lib/disaster_recovery/backup_redis.rb

        # Weekly full backup
        0 1 * * 0 cd #{Rails.root} && bundle exec ruby lib/disaster_recovery/full_backup.rb
      SCHEDULE
      
      File.write('config/schedule.rb', whenever_schedule)
    end
    
    def self.backup_redis_data
      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      backup_file = "backups/redis_backup_#{timestamp}.rdb"
      
      system("redis-cli --rdb #{backup_file}")
      
      # Upload to S3 or other backup storage
      if ENV['AWS_S3_BACKUP_BUCKET']
        upload_to_s3(backup_file)
      end
      
      Rails.logger.info "Redis backup completed: #{backup_file}"
    end
    
    def self.restore_from_backup(backup_file)
      Rails.logger.info "Starting Redis restore from: #{backup_file}"
      
      # Stop Redis
      system('sudo systemctl stop redis')
      
      # Replace RDB file
      system("sudo cp #{backup_file} /var/lib/redis/dump.rdb")
      system('sudo chown redis:redis /var/lib/redis/dump.rdb')
      
      # Start Redis
      system('sudo systemctl start redis')
      
      Rails.logger.info "Redis restore completed"
    end
  end
end
```

This production guide provides the foundation for deploying Redis Queue Transport in enterprise environments. Adapt the configurations based on your specific infrastructure and requirements, always testing thoroughly in staging environments before production deployment.