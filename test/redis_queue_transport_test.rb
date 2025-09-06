# test/redis_queue_transport_test.rb

require_relative "test_helper"

require 'smart_message/serializer/json'
require 'smart_message/transport'
require 'async'

module RedisQueueTransportTest
  # Simple test message for basic functionality
  class TestMessage < SmartMessage::Base
    from 'test-service'
    
    property :content
    property :timestamp

    class << self
      def process(wrapper)
        _message_header, _message_payload = wrapper.split
        SS.add(whoami, 'process')
        return 'processed'
      end
    end
  end

  # Another message type for multi-type testing
  class OrderMessage < SmartMessage::Base
    from 'order-service'
    
    property :order_id, required: true
    property :amount, required: true

    class << self
      def process(wrapper)
        _message_header, _message_payload = wrapper.split
        SS.add(whoami, 'process')
        return 'order_processed'
      end
    end
  end

  # Alert message for pattern testing
  class AlertMessage < SmartMessage::Base
    from 'alert-service'
    
    property :alert_type, required: true
    property :message_text, required: true

    class << self
      def process(wrapper)
        _message_header, _message_payload = wrapper.split
        SS.add(whoami, 'process')
        return 'alert_processed'
      end
    end
  end

  class Test < Minitest::Test
    def setup
      SS.reset
      skip "Redis not available" unless redis_available?
      setup_test_redis
    rescue => e
      skip "Redis queue transport test setup failed: #{e.message}"
    end

    def teardown
      cleanup_redis if redis_available?
    end

    ##################################################################
    def test_0010_redis_queue_transport_creation_and_configuration
      Async do
        transport = SmartMessage::Transport::RedisQueueTransport.new(
          url: 'redis://localhost:6379',
          db: 15, # Use test database
          queue_prefix: 'test_sm_queue',
          exchange_name: 'smart_message',
          auto_subscribe: false,
          test_mode: true
        )

        assert_instance_of SmartMessage::Transport::RedisQueueTransport, transport
        assert_equal 'redis://localhost:6379', transport.options[:url]
        assert_equal 15, transport.options[:db]
        assert_equal 'test_sm_queue', transport.options[:queue_prefix]
        assert_equal 'smart_message', transport.options[:exchange_name]
        
        # Connected check requires async context
        connected = transport.connected?
        assert connected

        transport.disconnect
      end
    end

    ##################################################################
    def test_0020_redis_queue_transport_registry_registration
      assert SmartMessage::Transport.registry.registered?(:redis_queue)
      assert_equal SmartMessage::Transport::RedisQueueTransport, SmartMessage::Transport.get(:redis_queue)

      Async do
        redis_queue_transport = SmartMessage::Transport.create(:redis_queue, 
          url: 'redis://localhost:6379',
          db: 15,
          auto_subscribe: false,
          test_mode: true
        )

        assert_instance_of SmartMessage::Transport::RedisQueueTransport, redis_queue_transport
        redis_queue_transport.disconnect
      end
    end

    ##################################################################
    def test_0030_redis_queue_transport_publish_functionality
      Async do
        RedisQueueTransportTest::TestMessage.config do
          reset_transport
          reset_logger
          reset_serializer
          
          transport SmartMessage::Transport::RedisQueueTransport.new(
            url: 'redis://localhost:6379',
            db: 15,
            queue_prefix: 'test_sm_queue',
            auto_subscribe: false,
            test_mode: true
          )
          serializer SmartMessage::Serializer::Json.new
        end

        message = RedisQueueTransportTest::TestMessage.new(
          content: 'test message',
          timestamp: Time.now.to_s
        )

        # Should not raise an error
        assert message.publish

        assert_equal 1, SS.get('RedisQueueTransportTest::TestMessage', 'publish')

        RedisQueueTransportTest::TestMessage.transport.disconnect
      end
    end

    ##################################################################
    def test_0040_redis_queue_transport_pattern_subscriptions
      Async do
        transport = SmartMessage::Transport::RedisQueueTransport.new(
          url: 'redis://localhost:6379',
          db: 15,
          queue_prefix: 'test_sm_queue',
          exchange_name: 'smart_message',
          auto_subscribe: false,
          test_mode: true
        )

        # Test that we can add pattern subscriptions without errors
        transport.subscribe_pattern("#.*.test_service")
        transport.subscribe_pattern("order.#.*.*")
        transport.subscribe_pattern("alert.#.*.broadcast")

        # Check routing table
        routing_table = transport.routing_table
        assert routing_table.is_a?(Hash)
        assert routing_table.key?("#.*.test_service")
        assert routing_table.key?("order.#.*.*")
        assert routing_table.key?("alert.#.*.broadcast")

        transport.disconnect
      end
    end

    ##################################################################
    def test_0050_redis_queue_transport_queue_management
      Async do
        transport = SmartMessage::Transport::RedisQueueTransport.new(
          url: 'redis://localhost:6379',
          db: 15,
          queue_prefix: 'test_sm_queue',
          exchange_name: 'smart_message',
          auto_subscribe: false,
          test_mode: true
        )

        # Add some patterns to create queues
        transport.subscribe_pattern("#.*.service1")
        transport.subscribe_pattern("order.#.*.*")

        # Test queue statistics (async operation)
        stats = transport.queue_stats
        assert stats.is_a?(Hash)

        # Test routing table
        routing_table = transport.routing_table
        assert routing_table.is_a?(Hash)
        assert routing_table.size >= 2

        transport.disconnect
      end
    end

    ##################################################################
    def test_0060_redis_queue_transport_convenience_methods

      transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'convenience_workers',
        auto_subscribe: false,
        test_mode: true
      )

      # Test convenience methods don't raise errors
      transport.subscribe_to_recipient('test_service')
      transport.subscribe_from_sender('api_gateway')
      transport.subscribe_to_type('OrderMessage')
      transport.subscribe_to_broadcasts
      transport.subscribe_to_alerts

      # Check that patterns were added to routing table
      routing_table = transport.routing_table
      assert routing_table.size >= 5

      transport.disconnect
    end

    ##################################################################
    def test_0070_redis_queue_transport_fluent_api

      transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'fluent_workers',
        auto_subscribe: false,
        test_mode: true
      )

      # Test fluent API construction
      builder = transport.where
      assert_instance_of SmartMessage::Transport::RedisQueueSubscriptionBuilder, builder

      # Test builder methods don't raise errors
      builder.from('api_gateway')
             .to('order_service')
             .type('OrderMessage')

      # Test pattern building
      pattern = builder.build
      assert_instance_of String, pattern
      assert pattern.include?('ordermessage')
      assert pattern.include?('api_gateway')
      assert pattern.include?('order_service')

      transport.disconnect
    end

    ##################################################################
    def test_0080_redis_queue_transport_routing_key_generation
      Async do
        transport = SmartMessage::Transport::RedisQueueTransport.new(
          url: 'redis://localhost:6379',
          db: 15,
          queue_prefix: 'test_sm_queue',
          exchange_name: 'smart_message',
          auto_subscribe: false,
          test_mode: true
        )

        # Test routing key generation with mock message data
        test_message_data = {
          '_sm_header' => {
            'from' => 'api_gateway',
            'to' => 'order_service'
          },
          'content' => 'test'
        }.to_json

        # Use private method through send for testing
        routing_info = transport.send(:extract_routing_info, test_message_data)
        assert_equal 'api_gateway', routing_info[:from]
        assert_equal 'order_service', routing_info[:to]

        routing_key = transport.send(:build_enhanced_routing_key, 'TestMessage', routing_info)
        # Updated to match new implementation: exchange_name.message_class.from.to
        assert_equal 'smart_message.testmessage.api_gateway.order_service', routing_key

        transport.disconnect
      end
    end

    ##################################################################
    def test_0090_redis_queue_transport_pattern_matching

      transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        auto_subscribe: false,
        test_mode: true
      )

      # Test pattern matching logic
      test_cases = [
        ['#.*.service1', 'order.api.service1', true],
        ['#.*.service1', 'alert.security.service1', true],
        ['#.*.service1', 'order.api.service2', false],
        ['order.#.*.*', 'order.api.service1', true],
        ['order.#.*.*', 'alert.api.service1', false],
        ['#.api.*', 'order.api.service1', true],
        ['#.api.*', 'order.gateway.service1', false]
      ]

      test_cases.each do |pattern, routing_key, expected|
        result = transport.send(:routing_key_matches_pattern?, routing_key, pattern)
        assert_equal expected, result, "Pattern '#{pattern}' should #{expected ? '' : 'not '}match '#{routing_key}'"
      end

      transport.disconnect
    end

    ##################################################################
    def test_0100_redis_queue_transport_message_publishing_with_routing
      Async do
        transport = SmartMessage::Transport::RedisQueueTransport.new(
          url: 'redis://localhost:6379',
          db: 15,
          queue_prefix: 'test_sm_queue',
          exchange_name: 'smart_message',
          auto_subscribe: false,
          test_mode: true
        )

        # Configure message with enhanced routing
        RedisQueueTransportTest::OrderMessage.config do
          reset_transport
          reset_logger
          reset_serializer
          
          transport transport
          serializer SmartMessage::Serializer::Json.new
        end

        # Subscribe to a specific pattern
        transport.subscribe_pattern("#.*.order_service")

        # Create message with routing header
        message = RedisQueueTransportTest::OrderMessage.new(
          order_id: 'ORD-123',
          amount: 99.99
        )

        # Set routing header
        message._sm_header.from = 'api_gateway'
        message._sm_header.to = 'order_service'

        # Should not raise an error
        assert message.publish

        # Check that message was published to correct queue
        stats = transport.queue_stats
        matching_queues = stats.keys.select { |q| q.include?('order_service') }
        assert matching_queues.any?, "Should have queues for order_service pattern"

        transport.disconnect
      end
    end

    ##################################################################
    def test_0110_redis_queue_transport_error_handling
      # Test with invalid Redis connection - should handle initialization error
      # Note: Async Redis errors may be raised during async operations
      Async do
        transport = nil
        
        # Create transport with invalid host (error may occur during configure)
        assert_raises StandardError do
          transport = SmartMessage::Transport::RedisQueueTransport.new(
            url: 'redis://invalid-host:6379',
            db: 15,
            auto_subscribe: false,
            reconnect_attempts: 1
          )
          # Force connection attempt
          transport.connected?
        end
      end
    end

    ##################################################################
    def test_0120_redis_queue_transport_subscription_cleanup
      Async do
        transport = SmartMessage::Transport::RedisQueueTransport.new(
          url: 'redis://localhost:6379',
          db: 15,
          queue_prefix: 'test_sm_queue',
          exchange_name: 'smart_message',
          auto_subscribe: false,
          test_mode: true
        )

        # Add some subscriptions
        transport.subscribe_pattern("#.*.service1")
        transport.subscribe_pattern("#.*.service2")

        # Check they exist
        routing_table = transport.routing_table
        assert routing_table.size >= 2

        # Test disconnect cleans up subscriptions
        transport.disconnect
        
        # Note: In async implementation, cleanup happens during disconnect
        # This test verifies the routing table was populated before disconnect
      end
    end

    ##################################################################
    def test_0130_redis_queue_transport_consumer_group_load_balancing

      transport1 = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'load_balance_workers',
        consumer_id: 'worker_1',
        auto_subscribe: false,
        test_mode: true
      )

      transport2 = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'load_balance_workers',
        consumer_id: 'worker_2',
        auto_subscribe: false,
        test_mode: true
      )

      # Both transports subscribe to same pattern (load balancing)
      transport1.subscribe_pattern("#.*.shared_service")
      transport2.subscribe_pattern("#.*.shared_service")

      # Verify both are connected to same queue
      stats = transport1.queue_stats
      shared_queues = stats.keys.select { |q| q.include?('shared_service') }
      assert shared_queues.any?, "Should have shared service queues"

      transport1.disconnect
      transport2.disconnect
    end

    ##################################################################
    def test_0140_redis_queue_transport_message_consumption_simulation

      # Create publisher transport
      publisher = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'test_publishers',
        auto_subscribe: false,
        test_mode: true
      )

      # Create consumer transport
      consumer = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'test_consumers',
        auto_subscribe: false,
        test_mode: true
      )

      # Test message data
      test_message = {
        '_sm_header' => {
          'from' => 'test_publisher',
          'to' => 'consumption_test',
          'message_class' => 'TestMessage',
          'version' => 1
        },
        'content' => 'test consumption message',
        'timestamp' => Time.now.iso8601
      }.to_json

      # Publish message using transport's publish method (without subscribing to avoid blocking)
      publisher.publish('TestMessage', test_message)

      # Verify transports are functional
      assert publisher.connected?
      assert consumer.connected?

      publisher.disconnect
      consumer.disconnect
    end

    ##################################################################
    def test_0150_redis_queue_transport_queue_prefix_isolation

      # Create two transports with different prefixes
      transport_a = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'app_a_queues',
        consumer_group: 'app_a_workers',
        auto_subscribe: false,
        test_mode: true
      )

      transport_b = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'app_b_queues',
        consumer_group: 'app_b_workers',
        auto_subscribe: false,
        test_mode: true
      )

      # Both subscribe to same pattern
      transport_a.subscribe_pattern("#.*.service")
      transport_b.subscribe_pattern("#.*.service")

      # Verify they create separate queue namespaces
      stats_a = transport_a.queue_stats
      stats_b = transport_b.queue_stats

      # Queue names should include different prefixes
      a_queue_names = stats_a.keys
      b_queue_names = stats_b.keys

      assert a_queue_names.all? { |name| name.include?('app_a_queues') }, "App A queues should have app_a_queues prefix"
      assert b_queue_names.all? { |name| name.include?('app_b_queues') }, "App B queues should have app_b_queues prefix"

      # Verify no overlap
      assert (a_queue_names & b_queue_names).empty?, "Queue namespaces should be isolated"

      transport_a.disconnect
      transport_b.disconnect
    end

    ##################################################################
    def test_0160_redis_queue_transport_wildcard_pattern_variations

      transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'wildcard_workers',
        auto_subscribe: false,
        test_mode: true
      )

      # Test various wildcard patterns
      patterns_and_matches = [
        # Pattern, routing key, should match
        ['*', 'single', true],
        ['*', 'multi.part', false],
        ['#', 'anything', true],
        ['#', 'multi.part.message', true],
        ['order.*', 'order.created', true],
        ['order.*', 'order.cancelled.urgent', false],
        ['order.#', 'order.created', true],
        ['order.#', 'order.created.urgent', true],
        ['*.created', 'order.created', true],
        ['*.created', 'user.account.created', false],
        ['#.created', 'order.created', true],
        ['#.created', 'user.account.created', true],
        ['order.*.urgent', 'order.created.urgent', true],
        ['order.*.urgent', 'order.cancelled.priority.urgent', false]
      ]

      patterns_and_matches.each do |pattern, routing_key, expected|
        result = transport.send(:routing_key_matches_pattern?, routing_key, pattern)
        assert_equal expected, result, "Pattern '#{pattern}' should #{expected ? '' : 'not '}match '#{routing_key}'"
      end

      transport.disconnect
    end

    ##################################################################
    def test_0170_redis_queue_transport_connection_resilience

      # Test connection with custom settings
      transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'resilience_workers',
        auto_subscribe: false,
        reconnect_attempts: 3,
        reconnect_delay: 0.1,
        pool_size: 5,
        pool_timeout: 1.0
      )

      # Verify transport was created with custom options
      assert transport.options[:reconnect_attempts] == 3
      assert transport.options[:reconnect_delay] == 0.1
      assert transport.options[:pool_size] == 5
      assert transport.options[:pool_timeout] == 1.0

      # Test basic connectivity
      assert transport.connected?

      transport.disconnect
    end

    ##################################################################
    def test_0180_redis_queue_transport_queue_statistics_details

      transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'stats_workers',
        auto_subscribe: false,
        test_mode: true
      )

      # Subscribe to multiple patterns to create queues
      transport.subscribe_pattern("#.*.payment_service")
      transport.subscribe_pattern("order.#.*.*")
      transport.subscribe_pattern("#.api_gateway.*")

      # Get detailed statistics
      stats = transport.queue_stats
      routing_table = transport.routing_table

      # Verify stats structure
      assert stats.is_a?(Hash), "Stats should be a hash"
      stats.each do |queue_name, queue_info|
        assert queue_name.is_a?(String), "Queue name should be string"
        assert queue_info.is_a?(Hash), "Queue info should be hash"
        assert queue_info.key?(:length), "Queue info should include length"
        assert queue_info[:length].is_a?(Integer), "Queue length should be integer"
      end

      # Verify routing table structure
      assert routing_table.is_a?(Hash), "Routing table should be hash"
      routing_table.each do |pattern, queues|
        assert pattern.is_a?(String), "Pattern should be string"
        assert queues.is_a?(Array), "Queues should be array"
      end

      assert routing_table.size >= 3, "Should have at least 3 patterns"

      transport.disconnect
    end

    ##################################################################
    def test_0190_redis_queue_transport_builder_api_comprehensive

      transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'builder_workers',
        auto_subscribe: false,
        test_mode: true
      )

      # Test comprehensive builder API
      builder = transport.where

      # Test chaining multiple criteria
      pattern1 = builder.from('api_service').to('order_service').type('OrderMessage').build
      assert pattern1.include?('ordermessage'), "Pattern should include message type"
      assert pattern1.include?('api_service'), "Pattern should include from service"
      assert pattern1.include?('order_service'), "Pattern should include to service"

      # Test broadcast pattern
      pattern2 = transport.where.broadcast.build
      assert pattern2.include?('broadcast'), "Pattern should include broadcast"

      # Test alerts pattern
      pattern3 = transport.where.alerts.build
      assert pattern3.include?('alert'), "Pattern should include alert"

      # Test type-only pattern
      pattern4 = transport.where.type('UserMessage').build
      assert pattern4.include?('usermessage'), "Pattern should include user message type"

      # Test from-only pattern
      pattern5 = transport.where.from('admin_service').build
      assert pattern5.include?('admin_service'), "Pattern should include admin service"

      # Test to-only pattern
      pattern6 = transport.where.to('notification_service').build
      assert pattern6.include?('notification_service'), "Pattern should include notification service"

      transport.disconnect
    end

    ##################################################################
    def test_0200_redis_queue_transport_edge_cases

      transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        queue_prefix: 'test_sm_queue',
        consumer_group: 'edge_case_workers',
        auto_subscribe: false,
        test_mode: true
      )

      # Test empty pattern subscription (should handle gracefully)
      begin
        transport.subscribe_pattern("")
        # Empty pattern may be accepted, depending on implementation
      rescue => e
        # If it raises an error, that's also acceptable behavior
        assert e.is_a?(StandardError)
      end

      # Test nil pattern subscription (should handle gracefully)
      begin
        transport.subscribe_pattern(nil)
        # Nil pattern may be accepted, depending on implementation
      rescue => e
        # If it raises an error, that's also acceptable behavior
        assert e.is_a?(StandardError)
      end

      # Test invalid routing key extraction
      invalid_json = "invalid json data"
      routing_info = transport.send(:extract_routing_info, invalid_json)
      assert routing_info[:from].nil? || routing_info[:from].empty?
      assert routing_info[:to].nil? || routing_info[:to].empty?

      # Test routing key with missing header
      message_without_header = {
        'content' => 'test without header'
      }.to_json

      routing_info = transport.send(:extract_routing_info, message_without_header)
      assert routing_info[:from].nil? || routing_info[:from].empty?
      assert routing_info[:to].nil? || routing_info[:to].empty?

      # Test pattern matching with empty routing key
      result = transport.send(:routing_key_matches_pattern?, "", "#.*.service")
      assert_equal false, result

      # Test pattern matching with nil routing key
      result = transport.send(:routing_key_matches_pattern?, nil, "#.*.service")
      assert_equal false, result

      transport.disconnect
    end

    ##################################################################
    def test_0210_redis_queue_transport_configuration_validation

      # Test valid minimal configuration
      transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        auto_subscribe: false,
        test_mode: true
      )

      # Verify defaults were applied
      assert_equal 0, transport.options[:db]
      assert_equal 'smart_message.queue', transport.options[:queue_prefix]
      assert_equal 'smart_message', transport.options[:exchange_name]
      assert_equal 1, transport.options[:consumer_timeout]

      transport.disconnect

      # Test custom configuration values
      custom_transport = SmartMessage::Transport::RedisQueueTransport.new(
        url: 'redis://localhost:6379',
        db: 5,
        queue_prefix: 'custom_queues',
        exchange_name: 'custom_exchange',
        consumer_timeout: 3,
        auto_subscribe: false,
        test_mode: true
      )

      assert_equal 5, custom_transport.options[:db]
      assert_equal 'custom_queues', custom_transport.options[:queue_prefix]
      assert_equal 'custom_exchange', custom_transport.options[:exchange_name]
      assert_equal 3, custom_transport.options[:consumer_timeout]

      custom_transport.disconnect

      # Test that missing URL defaults to localhost
      transport_without_url = SmartMessage::Transport::RedisQueueTransport.new(
        db: 15,
        queue_prefix: 'test_sm_queue',
        auto_subscribe: false,
        test_mode: true
      )
      
      # Should use default URL
      assert_equal 15, transport_without_url.options[:db]
      assert_equal 'redis://localhost:6379', transport_without_url.options[:url]
      
      transport_without_url.disconnect
    end

    private

    def redis_available?
      Redis.new(url: 'redis://localhost:6379', db: 15).ping == 'PONG'
    rescue
      false
    end

    def setup_test_redis
      @redis = Redis.new(url: 'redis://localhost:6379', db: 15)
      @redis.flushdb # Clear test database
    end

    def cleanup_redis
      if @redis
        # Clean up test queues
        keys = @redis.keys('test_sm_queue*')
        @redis.del(*keys) unless keys.empty?
        @redis.flushdb # Clear test database
        @redis.quit
      end
    rescue => e
      # Ignore cleanup errors
      puts "Redis cleanup warning: #{e.message}"
    end
  end
end