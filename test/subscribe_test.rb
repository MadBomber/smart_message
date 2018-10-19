# test/subscribe_test.rb

require_relative "test_helper"

require 'smart_message/serializer/json'
require 'smart_message/broker/stdout'

module SubscribeTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    property :foo
    property :bar
    property :baz
    property :id


    # This class method is being executed inside of an
    # independant thread.
    def self.process(message_header, message_payload)
      debug_me{[ :message_header, :message_payload ]}

      SS.add(message_header.message_class, 'process')
      return 'it worked'
    end
  end # class MyMessage < SmartMessage::Base


  class Test < Minitest::Test
    def setup
      SubscribeTest::MyMessage.config do
        serializer  SmartMessage::Serializer::JSON.new
        broker      SmartMessage::Broker::Stdout.new(loopback: true, file: 'subscribe.log')
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

      # TODO: Need to find a way to wait for the background threads
      #       to all terminate.  So far nothing is working as expected.

      print "waiting: "
      # MAGIC NUMBER: 3 = current thread + 2 more threads from minitest
      #               dispatcher will create 4 additional threads to route
      #               the messages for a total of 7
      # print "for thread count to hit 7 ..."
      # while (Thread.list.size < 7)
      #   print '*'
      # end
      # puts " done."
      #
      # print 'for last thread to stop running ...'
      # while (7 == Thread.list.size) and ('run' == Thread.list.last.status)
      #   print '*'
      #   Thread.pass
      # end
      # puts ' done.'

      print 'something stupid ...'
      until SS.get('SubscribeTest::MyMessage', 'process') == how_many
        print "+"
        Thread.pass # without this many plus signs as printed
      end
      puts ' done.'

      # Thread.pass # does not work outside of the conditional loops
      # sleep 1 # works just as well as the preceeding conditional loops




      SS.to_s


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

    def self.business_logic(message_header, message_payload)

      SS.add(message_header.message_class, 'business_logic')
      return 'it worked'
    end
  end # class Test < Minitest::Test
end # module SubscribeTest
