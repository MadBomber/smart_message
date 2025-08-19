# test/message_filtering_test.rb

require_relative "test_helper"

module MessageFilteringTest
  class FilterTestMessage < SmartMessage::Base
    from 'test-service'
    
    property :content
    
    class << self
      def process(message_header, message_payload)
        # Track processed messages for testing
        SS.add(whoami, 'process')
        SS.add(whoami, 'processed_messages', message_header.uuid)
      end
    end
  end

  class Test < Minitest::Test
    def setup
      SS.reset
      
      # Configure transport with loopback for testing
      FilterTestMessage.config do
        transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
        serializer SmartMessage::Serializer::JSON.new
      end
      
      # Clear any existing subscriptions
      FilterTestMessage.unsubscribe!
    end

    def test_subscribe_all_messages_backward_compatibility
      # Subscribe without filters should receive all messages
      FilterTestMessage.subscribe
      
      # Publish broadcast message
      broadcast_msg = FilterTestMessage.new(content: "broadcast")
      broadcast_msg.to(nil)
      broadcast_msg.publish
      
      # Publish directed message
      directed_msg = FilterTestMessage.new(content: "directed")
      directed_msg.to('target-service')
      directed_msg.publish
      
      # Give time for processing
      sleep(0.1)
      
      # Should have processed both messages
      assert_equal 2, SS.get('MessageFilteringTest::FilterTestMessage', 'process')
    end

    def test_subscribe_broadcast_only
      # Subscribe to broadcast messages only
      FilterTestMessage.subscribe(broadcast: true)
      
      # Publish broadcast message
      broadcast_msg = FilterTestMessage.new(content: "broadcast")
      broadcast_msg.to(nil)
      broadcast_msg.publish
      
      # Publish directed message
      directed_msg = FilterTestMessage.new(content: "directed")
      directed_msg.to('target-service')
      directed_msg.publish
      
      # Give time for processing
      sleep(0.1)
      
      # Should have processed only the broadcast message
      assert_equal 1, SS.get('MessageFilteringTest::FilterTestMessage', 'process')
    end

    def test_subscribe_to_specific_entity
      # Subscribe to messages directed to 'order-service'
      FilterTestMessage.subscribe(to: 'order-service')
      
      # Publish message to order-service
      order_msg = FilterTestMessage.new(content: "for order service")
      order_msg.to('order-service')
      order_msg.publish
      
      # Publish message to different service
      other_msg = FilterTestMessage.new(content: "for other service")
      other_msg.to('payment-service')
      other_msg.publish
      
      # Publish broadcast message
      broadcast_msg = FilterTestMessage.new(content: "broadcast")
      broadcast_msg.to(nil)
      broadcast_msg.publish
      
      # Give time for processing
      sleep(0.1)
      
      # Should have processed only the order-service message
      assert_equal 1, SS.get('MessageFilteringTest::FilterTestMessage', 'process')
    end

    def test_subscribe_from_specific_entity
      # Subscribe to messages from 'payment-service'
      FilterTestMessage.subscribe(from: 'payment-service')
      
      # Create message from payment-service
      payment_msg = FilterTestMessage.new(content: "from payment")
      payment_msg.from('payment-service')
      payment_msg.publish
      
      # Create message from other service
      other_msg = FilterTestMessage.new(content: "from other")
      other_msg.from('user-service')
      other_msg.publish
      
      # Give time for processing
      sleep(0.1)
      
      # Should have processed only the payment-service message
      assert_equal 1, SS.get('MessageFilteringTest::FilterTestMessage', 'process')
    end

    def test_subscribe_broadcast_and_directed_to_entity
      # Subscribe to broadcast messages OR messages directed to 'my-service'
      FilterTestMessage.subscribe(broadcast: true, to: 'my-service')
      
      # Publish broadcast message
      broadcast_msg = FilterTestMessage.new(content: "broadcast")
      broadcast_msg.to(nil)
      broadcast_msg.publish
      
      # Publish message to my-service
      my_msg = FilterTestMessage.new(content: "for me")
      my_msg.to('my-service')
      my_msg.publish
      
      # Publish message to other service
      other_msg = FilterTestMessage.new(content: "for other")
      other_msg.to('other-service')
      other_msg.publish
      
      # Give time for processing
      sleep(0.1)
      
      # Should have processed broadcast + my-service messages (2 total)
      assert_equal 2, SS.get('MessageFilteringTest::FilterTestMessage', 'process')
    end

    def test_subscribe_combined_filters
      # Subscribe to messages from 'admin' directed to 'my-service'
      FilterTestMessage.subscribe(from: 'admin', to: 'my-service')
      
      # Message from admin to my-service (should match)
      admin_to_me = FilterTestMessage.new(content: "admin to me")
      admin_to_me.from('admin')
      admin_to_me.to('my-service')
      admin_to_me.publish
      
      # Message from admin to other service (should not match)
      admin_to_other = FilterTestMessage.new(content: "admin to other")
      admin_to_other.from('admin')
      admin_to_other.to('other-service')
      admin_to_other.publish
      
      # Message from other to my-service (should not match)
      other_to_me = FilterTestMessage.new(content: "other to me")
      other_to_me.from('user')
      other_to_me.to('my-service')
      other_to_me.publish
      
      # Give time for processing
      sleep(0.1)
      
      # Should have processed only the admin->my-service message
      assert_equal 1, SS.get('MessageFilteringTest::FilterTestMessage', 'process')
    end

    def test_filter_arrays
      # Subscribe to messages from multiple entities
      FilterTestMessage.subscribe(from: ['admin', 'system'])
      
      # Message from admin (should match)
      admin_msg = FilterTestMessage.new(content: "from admin")
      admin_msg.from('admin')
      admin_msg.publish
      
      # Message from system (should match)
      system_msg = FilterTestMessage.new(content: "from system")
      system_msg.from('system')
      system_msg.publish
      
      # Message from user (should not match)
      user_msg = FilterTestMessage.new(content: "from user")
      user_msg.from('user')
      user_msg.publish
      
      # Give time for processing
      sleep(0.1)
      
      # Should have processed admin + system messages (2 total)
      assert_equal 2, SS.get('MessageFilteringTest::FilterTestMessage', 'process')
    end
  end
end