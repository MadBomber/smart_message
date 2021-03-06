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
    # The business logic of a smart message is located in
    # its class-level process method.
    class << self
      def process(message_header, message_payload)
        SS.add(whoami, 'process')
        return 'it worked'
      end # def process(message_instance)
    end # class << self
  end # class MyMessage < SmartMessage::Base

  # NOTE: That sense the base class had properties and
  #       this one adds more properties then the actual
  #       message should contain a total of six
  #       properties.
  class MyOtherMessage < MyMessage
    property :foo_two, default: 'two for foo'
    property :bar_two, default: 'two for bar'
    property :baz_two, default: 'two for baz'

    # NOTE: will use the same class process method as MyMessage
  end # class MyOtherMessage < MyMessage


  # encapsulate the test methods
  class Test < Minitest::Test

    def setup
      # c;ear all stats
      SS.reset
    end

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
        broker SmartMessage::Broker::Stdout.new(loopback: false)
      end

      assert_equal false, BrokerTest::MyMessage.broker.loopback?

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


      my_message        = BrokerTest::MyMessage.new(foo: 'foo', bar:'bar')
      my_other_message  = BrokerTest::MyOtherMessage.new(bar_two:'bar_two', baz_two: 'baz_two')

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

      assert_equal 0, SS.get('BrokerTest::MyMessage', 'publish')

      # Set class-level plugins to known configuration
      BrokerTest::MyMessage.config do
        broker      SmartMessage::Broker::Stdout.new(
                      loopback: false,
                      file:     'broker_test.log'
                    )
        serializer  SmartMessage::Serializer::JSON.new
      end

      assert_equal false, BrokerTest::MyMessage.broker.loopback?

      my_other_message = BrokerTest::MyOtherMessage.new(
        foo: 'one for the money',
        bar: 'two for the show',
        baz: 'three to get ready',
        xyzzy: 'four to go'         # not defined so ignored
      )

      my_other_message.publish


      assert_equal 1, SS.get('BrokerTest::MyOtherMessage','publish')

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
        broker      SmartMessage::Broker::Stdout.new(loopback: true)
        serializer  SmartMessage::Serializer::JSON.new
      end

      assert_equal true, BrokerTest::MyMessage.broker.loopback?

      # clear out the subscription db because its been
      # polluted by other tests.
      BrokerTest::MyMessage.broker.dispatcher.drop_all!

      # Use the defaul class-level process method
      BrokerTest::MyMessage.subscribe

      message_class = 'BrokerTest::MyMessage'

      assert_equal [message_class], BrokerTest::MyMessage.broker.subscribers.keys

      default_process_method = message_class + '.process'

      assert_equal [default_process_method], BrokerTest::MyMessage.broker.subscribers[message_class]

      specialized_process_method = 'BrokerTest::Test.specialized_process'

      # Use the class-level specialized process method
      BrokerTest::MyMessage.subscribe(specialized_process_method)

      assert_equal [default_process_method, specialized_process_method], BrokerTest::MyMessage.broker.subscribers[message_class]

      # unscribe the default process_method leaving only the specialized
      # process method
      BrokerTest::MyMessage.unsubscribe

      assert_equal [specialized_process_method], BrokerTest::MyMessage.broker.subscribers[message_class]

      # all the processes have been unscribed but the message key
      # still remains in the hash.
      refute BrokerTest::MyMessage.broker.subscribers.empty?

      assert_equal 6, BrokerTest::MyOtherMessage.fields.size

      assert_equal  [:foo, :bar, :baz, :foo_two, :bar_two, :baz_two],
                    BrokerTest::MyOtherMessage.fields.to_a

      BrokerTest::MyMessage.subscribe
      BrokerTest::MyOtherMessage.subscribe

      assert_equal  ['BrokerTest::MyMessage', 'BrokerTest::MyOtherMessage'],
                    BrokerTest::MyMessage.broker.subscribers.keys

      assert_equal  BrokerTest::MyMessage.broker.subscribers,
                    BrokerTest::MyOtherMessage.broker.subscribers

    end

  end # class BrokerTest < Minitest::Test
end # module BrokerTest
