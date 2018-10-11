# test/broker_test.rb

require_relative "test_helper"

require 'smart_message/serializer/json'
require 'smart_message/broker/stdout'
require 'logger'

module BrokerTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    property :foo
    property :bar
    property :baz
  end # class MyMessage < SmartMessage::Base

  # NOTE: That sense the base class had properties and
  #       this one adds more properties then the actual
  #       message should contain a total of six
  #       properties.
  class MyOtherMessage < MyMessage
    property :foo_two, default: 'two for foo'
    property :bar_two, default: 'two for bar'
    property :baz_two, default: 'two for baz'
  end # class MyOtherMessage < MyMessage


  # encapsulate the test methods
  class Test < Minitest::Test

    ##################################################################
    def test_0010_basic_broker_assignment_actions

      # Set class-level plugins to known configuration
      BrokerTest::MyMessage.config do
        reset_broker
        reset_logger
        reset_serializer
      end

      assert BrokerTest::MyMessage.broker_missing?
      assert BrokerTest::MyMessage.logger_missing?
      assert BrokerTest::MyMessage.serializer_missing?

      refute BrokerTest::MyMessage.broker_configured?
      refute BrokerTest::MyMessage.logger_configured?
      refute BrokerTest::MyMessage.serializer_configured?


      # Setup a serializer ...
      BrokerTest::MyMessage.config do
        serializer SmartMessage::Serializer::JSON.new
      end

      assert BrokerTest::MyMessage.broker_missing?
      assert BrokerTest::MyMessage.logger_missing?
      assert BrokerTest::MyMessage.serializer_configured?

      refute BrokerTest::MyMessage.broker_configured?
      refute BrokerTest::MyMessage.logger_configured?
      refute BrokerTest::MyMessage.serializer_missing?


      # Add in a broker ...
      BrokerTest::MyMessage.config do
        broker SmartMessage::Broker::Stdout.new
      end

      assert BrokerTest::MyMessage.broker_configured?
      assert BrokerTest::MyMessage.logger_missing?
      assert BrokerTest::MyMessage.serializer_configured?

      refute BrokerTest::MyMessage.broker_missing?
      refute BrokerTest::MyMessage.logger_configured?
      refute BrokerTest::MyMessage.serializer_missing?


      # Add in a logger ...
      BrokerTest::MyMessage.config do
        logger Logger.new(STDOUT)
      end

      assert BrokerTest::MyMessage.broker_configured?
      assert BrokerTest::MyMessage.logger_configured?
      assert BrokerTest::MyMessage.serializer_configured?

      refute BrokerTest::MyMessage.broker_missing?
      refute BrokerTest::MyMessage.logger_missing?
      refute BrokerTest::MyMessage.serializer_missing?



      assert_equal  SmartMessage::Broker::Stdout,
                    BrokerTest::MyMessage.broker.class

      assert_equal  SmartMessage::Serializer::JSON,
                    BrokerTest::MyMessage.serializer.class

      assert_equal  Logger,
                    BrokerTest::MyMessage.logger.class


      my_message        = BrokerTest::MyMessage
      my_other_message  = BrokerTest::MyOtherMessage

      assert_equal 'BrokerTest::MyMessage',       my_message.whoami
      assert_equal 'BrokerTest::MyOtherMessage',  my_other_message.whoami
      assert_equal 'BrokerTest::MyMessage',       BrokerTest::MyMessage.whoami
      assert_equal 'BrokerTest::MyOtherMessage',  BrokerTest::MyOtherMessage.whoami


    end # def test_0010_basic_broker_assignment_actions


    ##################################################################
    def test_0015_basic_broker_publish_actions

      # Set class-level plugins to known configuration
      BrokerTest::MyMessage.config do
        reset_broker
        reset_logger
        reset_serializer
      end

      my_message = BrokerTest::MyMessage.new(
        foo: 'one',
        bar: 'two',
        baz: 'three'
      )

      # The first step in publishing a message is to serializer it ...
      assert_raises SmartMessage::Errors::SerializerNotConfigured do
        my_message.publish
      end

      # Set class-level plugins to known configuration
      BrokerTest::MyMessage.config do
        broker      SmartMessage::Broker::Stdout.new
        serializer  SmartMessage::Serializer::JSON.new
      end


      my_other_message = BrokerTest::MyMessage.new(
        foo: 'one for the money',
        bar: 'two for the show',
        baz: 'three to get ready',
        xyzzy: 'four to go'         # not defined so ignored
      )

      # TODO: How do I know that the publich was completed successfully
      #       beyound a raised exception?  Should the publish method return
      #       something like a boolean maybe?  Or the encoded message payload?
      my_other_message.publish


    end # def test_0015_basic_broker_publish_actions


    ##################################################################
    def test_0020_basic_broker_subscription_management

      # Set class-level plugins to known configuration
      BrokerTest::MyMessage.config do
        reset_broker
        reset_logger
        reset_serializer
      end

      assert_raises SmartMessage::Errors::BrokerNotConfigured do
        BrokerTest::MyMessage.subscribe
      end

      # Set class-level plugins to known configuration
      BrokerTest::MyMessage.config do
        broker      SmartMessage::Broker::Stdout.new
        serializer  SmartMessage::Serializer::JSON.new
      end

      BrokerTest::MyMessage.subscribe

      assert_equal ['BrokerTest::MyMessage'], BrokerTest::MyMessage.broker.subscribers

      BrokerTest::MyMessage.unsubscribe

      assert_equal [], BrokerTest::MyMessage.broker.subscribers

      assert BrokerTest::MyMessage.broker.subscribers.empty?

      assert_equal 6, BrokerTest::MyOtherMessage.fields.size

      assert_equal  [:foo, :bar, :baz, :foo_two, :bar_two, :baz_two],
                    BrokerTest::MyOtherMessage.fields.to_a

      BrokerTest::MyMessage.subscribe
      BrokerTest::MyOtherMessage.subscribe

      assert_equal  ['BrokerTest::MyMessage', 'BrokerTest::MyOtherMessage'],
                    BrokerTest::MyMessage.broker.subscribers

      assert_equal  BrokerTest::MyMessage.broker.subscribers,
                    BrokerTest::MyOtherMessage.broker.subscribers

    end

  end # class BrokerTest < Minitest::Test
end # module BrokerTest
