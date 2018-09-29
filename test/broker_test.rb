# test/broker_test.rb

require_relative "test_helper"

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
      assert BrokerTest::MyMessage.broker_missing?

      my_message = BrokerTest::MyMessage.new(
        foo: 'one',
        bar: 'two',
        baz: 'three'
      )

      assert_raises SmartMessage::Errors::NoBrokerConfigured do
        my_message.publish
      end

      BrokerTest::MyMessage.config SmartMessage::StdoutBroker
      debug_me{['BrokerTest::MyMessage.broker']}
      assert BrokerTest::MyMessage.broker
      assert BrokerTest::MyMessage.broker_configured?
      assert_equal SmartMessage::StdoutBroker, BrokerTest::MyMessage.broker
    end

  end # class BrokerTest < Minitest::Test
end # module BrokerTest
