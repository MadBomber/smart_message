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
    # independant thread.  That means that no modification
    # to the class state will be saved at the end of the
    # thread.
    def self.process(message_header, message_payload)
      puts "\n >> HEADER: #{message_header.uuid}"
      puts "\t#{message_payload}"
      puts

      SS.add(message_header.message_class, 'process')
      return 'it worked'
    end
  end # class MyMessage < SmartMessage::Base


  class Test < Minitest::Test
    def setup
      SubscribeTest::MyMessage.config do
        serializer  SmartMessage::Serializer::JSON.new
        broker      SmartMessage::Broker::Stdout.new(loopback: true)
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

      @my_message.id = 42

      how_many = 2

      SS.reset # reset all statustic counters

      how_many.times do |message_id|
        @my_message.id = message_id
        @my_message.publish
      end

      # TODO: Need to find a way to wait for the background threads
      #       to all terminate.

      puts ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
      puts @my_message.broker.dispatcher.current_length
      puts "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"

      sleep_for = 5
      print "waiting for a #{sleep_for} seconds ..."
      sleep sleep_for
      puts 'woke up.'


      puts ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
      puts @my_message.broker.dispatcher.current_length
      puts "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"

      SS.to_s


      assert_equal how_many, SS.get('SubscribeTest::MyMessage',
                                    'publish')

      puts "waiting for thread to catch up ..."

      # puts @my_message.broker.dispatcher.status
      puts "=============================================="
      puts @my_message.broker.dispatcher.queue_length
      puts "=============================================="

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
