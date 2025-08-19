# test/transport_test.rb

require_relative "test_helper"

require 'smart_message/serializer/json'
require 'smart_message/transport'
require 'logger'

module TransportTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    from 'test-service'
    
    property :foo
    property :bar
    property :baz
    # The business logic of a smart message is located in
    # its class-level process method.
    class << self
      def process(wrapper)
        message_header = wrapper._sm_header
        message_payload = wrapper._sm_payload
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
    def test_0010_basic_transport_assignment_actions

      # Set class-level plugins to known configuration
      TransportTest::MyMessage.config do
        reset_transport
        reset_logger
        reset_serializer
      end

      assert TransportTest::MyMessage.transport_missing?
      assert TransportTest::MyMessage.logger_missing?
      assert TransportTest::MyMessage.serializer_missing?

      refute TransportTest::MyMessage.transport_configured?
      refute TransportTest::MyMessage.logger_configured?
      refute TransportTest::MyMessage.serializer_configured?


      # Setup a serializer ...
      TransportTest::MyMessage.config do
        serializer SmartMessage::Serializer::JSON.new
      end

      assert TransportTest::MyMessage.transport_missing?
      assert TransportTest::MyMessage.logger_missing?
      assert TransportTest::MyMessage.serializer_configured?

      refute TransportTest::MyMessage.transport_configured?
      refute TransportTest::MyMessage.logger_configured?
      refute TransportTest::MyMessage.serializer_missing?


      # Add in a transport ...
      TransportTest::MyMessage.config do
        transport SmartMessage::Transport::StdoutTransport.new(loopback: false)
      end

      assert_equal false, TransportTest::MyMessage.transport.loopback?

      assert TransportTest::MyMessage.transport_configured?
      assert TransportTest::MyMessage.logger_missing?
      assert TransportTest::MyMessage.serializer_configured?

      refute TransportTest::MyMessage.transport_missing?
      refute TransportTest::MyMessage.logger_configured?
      refute TransportTest::MyMessage.serializer_missing?


      # Add in a logger ...
      TransportTest::MyMessage.config do
        logger Logger.new(STDOUT)
      end

      assert TransportTest::MyMessage.transport_configured?
      assert TransportTest::MyMessage.logger_configured?
      assert TransportTest::MyMessage.serializer_configured?

      refute TransportTest::MyMessage.transport_missing?
      refute TransportTest::MyMessage.logger_missing?
      refute TransportTest::MyMessage.serializer_missing?


      assert_equal  SmartMessage::Transport::StdoutTransport,
                    TransportTest::MyMessage.transport.class

      assert_equal  SmartMessage::Serializer::JSON,
                    TransportTest::MyMessage.serializer.class

      assert_equal  Logger,
                    TransportTest::MyMessage.logger.class


      my_message        = TransportTest::MyMessage.new(foo: 'foo', bar:'bar')
      my_other_message  = TransportTest::MyOtherMessage.new(bar_two:'bar_two', baz_two: 'baz_two')

      assert_equal 'TransportTest::MyMessage',       my_message.whoami
      assert_equal 'TransportTest::MyOtherMessage',  my_other_message.whoami
      assert_equal 'TransportTest::MyMessage',       TransportTest::MyMessage.whoami
      assert_equal 'TransportTest::MyOtherMessage',  TransportTest::MyOtherMessage.whoami


    end # def test_0010_basic_transport_assignment_actions


    ##################################################################
    def test_0015_basic_transport_publish_actions

      # Set class-level plugins to known configuration
      TransportTest::MyMessage.config do
        reset_transport
        reset_logger
        reset_serializer
      end

      my_message = TransportTest::MyMessage.new(
        foo: 'one',
        bar: 'two',
        baz: 'three'
      )

      # The first step in publishing a message is to serializer it ...
      assert_raises SmartMessage::Errors::SerializerNotConfigured do
        my_message.publish
      end

      assert_equal 0, SS.get('TransportTest::MyMessage', 'publish')

      # Set class-level plugins to known configuration
      TransportTest::MyMessage.config do
        transport   SmartMessage::Transport::StdoutTransport.new(
                      loopback: false,
                      output:   'transport_test.log'
                    )
        serializer  SmartMessage::Serializer::JSON.new
      end

      assert_equal false, TransportTest::MyMessage.transport.loopback?

      my_other_message = TransportTest::MyOtherMessage.new(
        foo: 'one for the money',
        bar: 'two for the show',
        baz: 'three to get ready',
        xyzzy: 'four to go'         # not defined so ignored
      )

      my_other_message.publish


      assert_equal 1, SS.get('TransportTest::MyOtherMessage','publish')

    end # def test_0015_basic_transport_publish_actions


    ##################################################################
    def test_0020_basic_transport_subscription_management

      # Set class-level plugins to known configuration
      TransportTest::MyMessage.config do
        reset_transport
        reset_logger
        reset_serializer
      end

      assert_raises SmartMessage::Errors::TransportNotConfigured do
        TransportTest::MyMessage.subscribe
      end

      # Set class-level plugins to known configuration
      TransportTest::MyMessage.config do
        transport   SmartMessage::Transport::StdoutTransport.new(loopback: true)
        serializer  SmartMessage::Serializer::JSON.new
      end

      assert_equal true, TransportTest::MyMessage.transport.loopback?

      # clear out the subscription db because its been
      # polluted by other tests.
      TransportTest::MyMessage.transport.dispatcher.drop_all!

      # Use the defaul class-level process method
      TransportTest::MyMessage.subscribe

      message_class = 'TransportTest::MyMessage'

      assert_equal [message_class], TransportTest::MyMessage.transport.subscribers.keys

      default_process_method = message_class + '.process'

      assert_equal 1, TransportTest::MyMessage.transport.subscribers[message_class].length
      assert_equal default_process_method, TransportTest::MyMessage.transport.subscribers[message_class].first[:process_method]

      specialized_process_method = 'TransportTest::Test.specialized_process'

      # Use the class-level specialized process method
      TransportTest::MyMessage.subscribe(specialized_process_method)

      assert_equal 2, TransportTest::MyMessage.transport.subscribers[message_class].length
      process_methods = TransportTest::MyMessage.transport.subscribers[message_class].map { |sub| sub[:process_method] }
      assert_equal [default_process_method, specialized_process_method], process_methods

      # unscribe the default process_method leaving only the specialized
      # process method
      TransportTest::MyMessage.unsubscribe

      assert_equal 1, TransportTest::MyMessage.transport.subscribers[message_class].length
      assert_equal specialized_process_method, TransportTest::MyMessage.transport.subscribers[message_class].first[:process_method]

      # all the processes have been unscribed but the message key
      # still remains in the hash.
      refute TransportTest::MyMessage.transport.subscribers.empty?

      assert_equal 6, TransportTest::MyOtherMessage.fields.size

      assert_equal  [:foo, :bar, :baz, :foo_two, :bar_two, :baz_two],
                    TransportTest::MyOtherMessage.fields.to_a

      TransportTest::MyMessage.subscribe
      TransportTest::MyOtherMessage.subscribe

      assert_equal  ['TransportTest::MyMessage', 'TransportTest::MyOtherMessage'],
                    TransportTest::MyMessage.transport.subscribers.keys

      assert_equal  TransportTest::MyMessage.transport.subscribers,
                    TransportTest::MyOtherMessage.transport.subscribers

    end

  end # class TransportTest < Minitest::Test
end # module TransportTest