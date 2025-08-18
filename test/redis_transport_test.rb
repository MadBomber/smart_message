# test/redis_transport_test.rb

require_relative "test_helper"

require 'smart_message/serializer/json'
require 'smart_message/transport'

module RedisTransportTest
  # A simple example message model for testing
  class TestMessage < SmartMessage::Base
    property :content
    property :timestamp

    class << self
      def process(message_header, message_payload)
        SS.add(whoami, 'process')
        return 'processed'
      end
    end
  end

  class AnotherTestMessage < SmartMessage::Base
    property :data

    class << self
      def process(message_header, message_payload)
        SS.add(whoami, 'process')
        return 'processed_another'
      end
    end
  end

  class Test < Minitest::Test
    def setup
      SS.reset
      skip "Redis not available" unless redis_available?
      setup_test_redis
    end

    def teardown
      cleanup_redis if redis_available?
    end

    ##################################################################
    def test_0010_redis_transport_creation_and_configuration

      transport = SmartMessage::Transport::RedisTransport.new(
        url: 'redis://localhost:6379',
        db: 15, # Use test database
        auto_subscribe: false
      )

      assert_instance_of SmartMessage::Transport::RedisTransport, transport
      assert_equal 'redis://localhost:6379', transport.options[:url]
      assert_equal 15, transport.options[:db]
      assert_equal false, transport.options[:auto_subscribe]
      assert transport.connected?

      transport.disconnect
    end

    ##################################################################
    def test_0020_redis_transport_registry_registration

      assert SmartMessage::Transport.registry.registered?(:redis)
      assert_equal SmartMessage::Transport::RedisTransport, SmartMessage::Transport.get(:redis)

      redis_transport = SmartMessage::Transport.create(:redis, 
        url: 'redis://localhost:6379',
        db: 15,
        auto_subscribe: false
      )

      assert_instance_of SmartMessage::Transport::RedisTransport, redis_transport
      redis_transport.disconnect
    end

    ##################################################################
    def test_0030_redis_transport_publish_functionality

      RedisTransportTest::TestMessage.config do
        reset_transport
        reset_logger
        reset_serializer
        
        transport SmartMessage::Transport::RedisTransport.new(
          url: 'redis://localhost:6379',
          db: 15,
          auto_subscribe: false
        )
        serializer SmartMessage::Serializer::JSON.new
      end

      message = RedisTransportTest::TestMessage.new(
        content: 'test message',
        timestamp: Time.now.to_s
      )

      # Should not raise an error
      assert message.publish

      assert_equal 1, SS.get('RedisTransportTest::TestMessage', 'publish')

      RedisTransportTest::TestMessage.transport.disconnect
    end

    ##################################################################
    def test_0040_redis_transport_subscribe_and_process

      RedisTransportTest::TestMessage.config do
        reset_transport
        reset_logger
        reset_serializer
        
        transport SmartMessage::Transport::RedisTransport.new(
          url: 'redis://localhost:6379',
          db: 15,
          auto_subscribe: true,
          debug: false
        )
        serializer SmartMessage::Serializer::JSON.new
      end

      # Clear subscription database
      RedisTransportTest::TestMessage.transport.dispatcher.drop_all!

      # Subscribe to the message
      RedisTransportTest::TestMessage.subscribe

      # Give subscriber thread time to start
      sleep(0.1)

      # Publish a message
      message = RedisTransportTest::TestMessage.new(
        content: 'subscription test',
        timestamp: Time.now.to_s
      )

      message.publish

      # Give time for message processing
      sleep(0.2)

      # Check that the message was processed
      assert_equal 1, SS.get('RedisTransportTest::TestMessage', 'publish')
      assert_equal 1, SS.get('RedisTransportTest::TestMessage', 'process')

      RedisTransportTest::TestMessage.transport.disconnect
    end

    ##################################################################
    def test_0050_redis_transport_multiple_message_types

      # Create shared transport instance
      shared_transport = SmartMessage::Transport::RedisTransport.new(
        url: 'redis://localhost:6379',
        db: 15,
        auto_subscribe: true,
        debug: false
      )

      # Configure TestMessage
      RedisTransportTest::TestMessage.config do
        reset_transport
        reset_logger
        reset_serializer
        
        transport shared_transport
        serializer SmartMessage::Serializer::JSON.new
      end

      # Configure AnotherTestMessage with same transport
      RedisTransportTest::AnotherTestMessage.config do
        reset_transport
        reset_logger
        reset_serializer
        
        transport shared_transport
        serializer SmartMessage::Serializer::JSON.new
      end

      # Clear subscription database
      shared_transport.dispatcher.drop_all!

      # Subscribe both message types
      RedisTransportTest::TestMessage.subscribe
      RedisTransportTest::AnotherTestMessage.subscribe

      # Give subscriber thread time to restart with new subscriptions
      sleep(0.1)

      # Publish messages of both types
      test_message = RedisTransportTest::TestMessage.new(
        content: 'first type',
        timestamp: Time.now.to_s
      )

      another_message = RedisTransportTest::AnotherTestMessage.new(
        data: 'second type'
      )

      test_message.publish
      another_message.publish

      # Give time for message processing
      sleep(0.2)

      # Check that both message types were processed
      assert_equal 1, SS.get('RedisTransportTest::TestMessage', 'publish')
      assert_equal 1, SS.get('RedisTransportTest::TestMessage', 'process')
      assert_equal 1, SS.get('RedisTransportTest::AnotherTestMessage', 'publish')
      assert_equal 1, SS.get('RedisTransportTest::AnotherTestMessage', 'process')

      shared_transport.disconnect
    end

    ##################################################################
    def test_0060_redis_transport_unsubscribe_functionality

      RedisTransportTest::TestMessage.config do
        reset_transport
        reset_logger
        reset_serializer
        
        transport SmartMessage::Transport::RedisTransport.new(
          url: 'redis://localhost:6379',
          db: 15,
          auto_subscribe: true,
          debug: false
        )
        serializer SmartMessage::Serializer::JSON.new
      end

      # Clear subscription database
      RedisTransportTest::TestMessage.transport.dispatcher.drop_all!

      # Subscribe and then unsubscribe
      RedisTransportTest::TestMessage.subscribe
      sleep(0.1)

      RedisTransportTest::TestMessage.unsubscribe!
      sleep(0.1)

      # Publish a message - should not be processed
      message = RedisTransportTest::TestMessage.new(
        content: 'should not be processed',
        timestamp: Time.now.to_s
      )

      message.publish
      sleep(0.2)

      # Message should be published but not processed
      assert_equal 1, SS.get('RedisTransportTest::TestMessage', 'publish')
      assert_equal 0, SS.get('RedisTransportTest::TestMessage', 'process')

      RedisTransportTest::TestMessage.transport.disconnect
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
      @redis&.flushdb # Clear test database
      @redis&.quit
    end
  end
end