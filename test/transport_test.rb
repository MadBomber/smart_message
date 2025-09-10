# test/transport_test.rb

require_relative "test_helper"

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
      def process(message)
        SS.add(whoami, 'process')
        return 'it worked'
      end # def process(message)
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
      skip("Logger configuration tests skipped - set SM_LOGGER_TEST=true to enable") unless ENV['SM_LOGGER_TEST'] == 'true'

      # Set class-level plugins to known configuration
      TransportTest::MyMessage.config do
        reset_transport
        reset_logger
      end

      assert TransportTest::MyMessage.transport_missing?
      assert TransportTest::MyMessage.logger_missing?

      refute TransportTest::MyMessage.transport_configured?
      refute TransportTest::MyMessage.logger_configured?


      # Add in a transport...
      TransportTest::MyMessage.config do
        transport SmartMessage::Transport::StdoutTransport.new
      end

      assert TransportTest::MyMessage.transport_configured?
      assert TransportTest::MyMessage.logger_missing?

      refute TransportTest::MyMessage.transport_missing?
      refute TransportTest::MyMessage.logger_configured?


      # Add in a logger ...
      TransportTest::MyMessage.config do
        logger SmartMessage::Logger::Default.new
      end

      assert TransportTest::MyMessage.transport_configured?
      assert TransportTest::MyMessage.logger_configured?

      refute TransportTest::MyMessage.transport_missing?
      refute TransportTest::MyMessage.logger_missing?


      assert_equal  SmartMessage::Transport::StdoutTransport,
                    TransportTest::MyMessage.transport.class

      assert_equal  SmartMessage::Logger::Default,
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
      end

      my_message = TransportTest::MyMessage.new(
        foo: 'one',
        bar: 'two',
        baz: 'three'
      )

      # Publishing requires a transport to be configured...
      assert_raises SmartMessage::Errors::TransportNotConfigured do
        my_message.publish
      end

      assert_equal 0, SS.get('TransportTest::MyMessage', 'publish')

      # Set class-level plugins to known configuration
      TransportTest::MyMessage.config do
        transport   SmartMessage::Transport::StdoutTransport.new(
                      output:   'transport_test.log'
                    )
      end

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
      end

      assert_raises SmartMessage::Errors::TransportNotConfigured do
        TransportTest::MyMessage.subscribe
      end

      # Set class-level plugins to known configuration  
      TransportTest::MyMessage.config do
        transport   SmartMessage::Transport::StdoutTransport.new
      end

      # clear out the subscription db because its been
      # polluted by other tests.
      TransportTest::MyMessage.transport.dispatcher.drop_all!

      # Use the default class-level process method
      # STDOUT transport is publish-only, so subscription should be ignored
      TransportTest::MyMessage.subscribe

      message_class = 'TransportTest::MyMessage'

      # STDOUT transport is publish-only - no subscribers should be added
      assert_equal [], TransportTest::MyMessage.transport.subscribers.keys

      default_process_method = message_class + '.process'

      # STDOUT transport ignores subscription attempts
      assert_equal 0, TransportTest::MyMessage.transport.subscribers[message_class].length

      specialized_process_method = 'TransportTest::Test.specialized_process'

      # Use the class-level specialized process method - should also be ignored
      TransportTest::MyMessage.subscribe(specialized_process_method)

      # Still no subscribers because STDOUT transport is publish-only
      assert_equal 0, TransportTest::MyMessage.transport.subscribers[message_class].length

      # Unsubscribe attempts should also be ignored (but won't error)
      TransportTest::MyMessage.unsubscribe

      # Still no subscribers
      assert_equal 0, TransportTest::MyMessage.transport.subscribers[message_class].length

      # STDOUT transport subscribers hash may have empty message class entries
      # but no actual subscribers for this message class
      assert_equal 0, TransportTest::MyMessage.transport.subscribers[message_class].length

      assert_equal 6, TransportTest::MyOtherMessage.fields.size

      assert_equal  [:foo, :bar, :baz, :foo_two, :bar_two, :baz_two],
                    TransportTest::MyOtherMessage.fields.to_a

      # STDOUT transport subscription attempts are ignored
      TransportTest::MyMessage.subscribe
      TransportTest::MyOtherMessage.subscribe

      # Since STDOUT transport is publish-only, expect only one entry (from earlier test)
      assert_equal  ['TransportTest::MyMessage'],
                    TransportTest::MyMessage.transport.subscribers.keys

      # Both message classes should share the same transport instance
      assert_equal  TransportTest::MyMessage.transport.subscribers,
                    TransportTest::MyOtherMessage.transport.subscribers

    end

  end # class TransportTest < Minitest::Test
end # module TransportTest