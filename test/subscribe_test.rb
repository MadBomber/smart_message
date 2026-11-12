# test/subscribe_test.rb

require_relative "test_helper"

require 'smart_message/transport'

module SubscribeTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    from 'subscribe-test-service'

    property :foo
    property :bar
    property :baz
    property :id


    # This class method is being executed inside of an
    # independant thread.
    def self.process(message)
      SS.add(message._sm_header.message_class, 'process')
      return 'it worked'
    end
  end # class MyMessage < SmartMessage::Base


  class Test < Minitest::Test
    def setup
      SubscribeTest::MyMessage.config do
        transport   SmartMessage::Transport::MemoryTransport.new
      end

      @my_message = SubscribeTest::MyMessage.new(
          foo: 'foo',
          bar: 'bar',
          baz: 'baz'
        )
    end # def setup

    def test_010
      # uses the default process method
      SubscribeTest::MyMessage.subscribe('SubscribeTest::MyMessage.process')
      SubscribeTest::MyMessage.subscribe('SubscribeTest::Test.business_logic')

      @my_message.id = 42 # set to something obvious in case of error

      how_many = 2 # number of times to publish a message; tested upto 5000

      SS.reset # reset all stat counters

      # NOTE: 'times' starts at zero
      how_many.times do |message_id|
        @my_message.id = message_id
        @my_message.publish
      end

      wait_for_dispatch(SubscribeTest::MyMessage.transport)

      assert_equal how_many, SS.get('SubscribeTest::MyMessage', 'publish')

      assert_equal how_many, SS.get('SubscribeTest::MyMessage', 'process')
      assert_equal how_many, SS.get('SubscribeTest::MyMessage', 'business_logic')

      assert_equal how_many, SS.get('SubscribeTest::MyMessage',
                                    'SubscribeTest::MyMessage.process',
                                    'routed')

      assert_equal how_many, SS.get('SubscribeTest::MyMessage',
                                    'SubscribeTest::Test.business_logic',
                                    'routed')

    end

    def self.business_logic(message)
      SS.add(message._sm_header.message_class, 'business_logic')
      return 'it worked'
    end
  end # class Test < Minitest::Test
end # module SubscribeTest
