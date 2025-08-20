# test/dispatcher_test.rb


require_relative "test_helper"

module DispatcherTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    from 'test-service'
    
    property :foo
    property :bar
    property :baz
  end # class MyMessage < SmartMessage::Base


  class Test < Minitest::Test
    def setup
      @dispatcher = SmartMessage::Dispatcher.new

      @m1 = DispatcherTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )

      @m2 = DispatcherTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )
    end

    def test_dispatcher_admin
      refute_nil  @dispatcher
      assert      @dispatcher.running?, '@router_pool should be ready to process messages'

      assert      @dispatcher.subscribers.empty?

      @dispatcher.add('DispatcherTest::MyMessage', 'DispatcherTest::Test.processer_one')

      assert_equal 1, @dispatcher.subscribers.size
      assert_equal 'DispatcherTest::MyMessage', @dispatcher.subscribers.keys.first
      assert_equal 1, @dispatcher.subscribers['DispatcherTest::MyMessage'].size

      @dispatcher.add(DispatcherTest::MyMessage, 'DispatcherTest::Test.processer_two')

      assert_equal 1, @dispatcher.subscribers.size
      assert_equal 'DispatcherTest::MyMessage', @dispatcher.subscribers.keys.first
      assert_equal 2, @dispatcher.subscribers['DispatcherTest::MyMessage'].size

      @dispatcher.drop('DispatcherTest::MyMessage', 'DispatcherTest::Test.processer_one')

      assert_equal 1, @dispatcher.subscribers.size
      assert_equal 'DispatcherTest::MyMessage', @dispatcher.subscribers.keys.first

      @dispatcher.drop('DispatcherTest::MyMessage', 'DispatcherTest::Test.processer_two')

      assert_equal 1, @dispatcher.subscribers.size
      assert_equal 'DispatcherTest::MyMessage', @dispatcher.subscribers.keys.first

      assert_equal 0, @dispatcher.subscribers['DispatcherTest::MyMessage'].size
      assert          @dispatcher.subscribers['DispatcherTest::MyMessage'].empty?

      @dispatcher.drop_all(DispatcherTest::MyMessage)

      assert_equal 0, @dispatcher.subscribers.size
      assert          @dispatcher.subscribers.empty?

    end


    def test_dispatcher_routing
      # simulate the subscription of a single message class with two
      # business-logic received message processors.
      @dispatcher.add('DispatcherTest::MyMessage', 'DispatcherTest::Test.processer_one')
      @dispatcher.add('DispatcherTest::MyMessage', 'DispatcherTest::Test.processer_two')

      # verify that we have a single message class and to subscribed-to
      # class methods that will receive the message.
      assert_equal 1, @dispatcher.subscribers.size
      assert_equal 'DispatcherTest::MyMessage', @dispatcher.subscribers.keys.first
      assert_equal 2, @dispatcher.subscribers['DispatcherTest::MyMessage'].size

      # simulate the reception of a specific and route it to all of its
      # subscribed-to processes.
      @dispatcher.route(@m1)

      # NOTE: this shows that the messages are not being "processed"
      #       in the order that they were published.
      # TODO: Consider a buffered queue if the order of message processing
      #       is important.
      # 100.times do |msg_count|
      #   @dispatcher.route(@m1._sm_header, msg_count.to_s)
      # end
    end


    # The business logic for process a received subscribed-to message
    # is implemented as a class method.
    def self.processer_one(wrapper)
      message_header, encoded_message = wrapper.split
      debug_me(' = ONE ='){[ :message_header, :encoded_message]}
      unless 'DispatcherTest::MyMessage' == message_header.message_class
        puts "ERROR:  Expected DispatcherTest::MyMessage"
        puts "        not #{message_header.message_class}"
      end
      puts "INFO: " + encoded_message
      puts
      return 'it worked'
    end


    def self.processer_two(wrapper)
      message_header, encoded_message = wrapper.split
      debug_me(' == TWO =='){[ :message_header, :encoded_message]}
      unless 'DispatcherTest::MyMessage' == message_header.message_class
        puts "ERROR:  Expected DispatcherTest::MyMessage"
        puts "        not #{message_header.message_class}"
      end
      puts "INFO: " + encoded_message
      puts
      return 'it worked'
    end

  end # class Test < Minitest::Test
end # module DispatcherTest
