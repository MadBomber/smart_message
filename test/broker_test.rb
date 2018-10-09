# test/broker_test.rb

require_relative "test_helper"

require 'smart_message/serializer/json'
require 'smart_message/broker/stdout'


module BrokerTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    property :foo
    property :bar
    property :baz
  end # class MyMessage < SmartMessage::Base

  # encapsulate the test methods
  class Test < Minitest::Test

    def test_0010_basic_broker_assignment_actions
      assert BrokerTest::MyMessage.serializer_missing?
      refute BrokerTest::MyMessage.serializer_configured?

      assert BrokerTest::MyMessage.broker_missing?
      refute BrokerTest::MyMessage.broker_configured?

      BrokerTest::MyMessage.config(
                  broker_class:     nil,
                  serializer_class: SmartMessage::Serializer::JSON.new,
                  logger_class:     nil
                )

      assert BrokerTest::MyMessage.serializer_configured?
      refute BrokerTest::MyMessage.serializer_missing?

      refute BrokerTest::MyMessage.broker_configured?
      assert BrokerTest::MyMessage.broker_missing?

      my_message = BrokerTest::MyMessage.new(
        foo: 'one',
        bar: 'two',
        baz: 'three'
      )

      debug_me{[ 'my_message.serializer', 'my_message.broker', 'my_message.logger']}

      assert_raises SmartMessage::Errors::BrokerNotConfigured do
        my_message.publish
      end

        BrokerTest::MyMessage.config(
                  broker_class:     SmartMessage::Broker::Stdout.new,
                  serializer_class: SmartMessage::Serializer::JSON.new,
                  logger_class:     nil
                )

      debug_me{['BrokerTest::MyMessage.broker']}

      assert BrokerTest::MyMessage.broker
      assert BrokerTest::MyMessage.broker_configured?
      refute BrokerTest::MyMessage.broker_missing?
      assert_equal SmartMessage::Broker::Stdout, BrokerTest::MyMessage.broker.class
    end

  end # class BrokerTest < Minitest::Test
end # module BrokerTest
