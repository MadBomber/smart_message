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
    RECEIVED = Queue.new

    def setup
      RECEIVED.clear
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
      
      # A class with no handlers left is no longer listed
      assert_equal 0, @dispatcher.subscribers.size
      
      assert_equal 0, @dispatcher.subscribers['DispatcherTest::MyMessage'].size
      assert          @dispatcher.subscribers['DispatcherTest::MyMessage'].empty?

      @dispatcher.drop_all(DispatcherTest::MyMessage)

      assert_equal 0, @dispatcher.subscribers.size
      assert          @dispatcher.subscribers.empty?

    end


    def test_dispatcher_routing
      # One message class with two subscribed processors
      @dispatcher.add('DispatcherTest::MyMessage', 'DispatcherTest::Test.processer_one')
      @dispatcher.add('DispatcherTest::MyMessage', 'DispatcherTest::Test.processer_two')

      assert_equal 1, @dispatcher.subscribers.size
      assert_equal 'DispatcherTest::MyMessage', @dispatcher.subscribers.keys.first
      assert_equal 2, @dispatcher.subscribers['DispatcherTest::MyMessage'].size

      @dispatcher.route(@m1)

      # Processors run on the pool; order between them is not guaranteed
      received = Array.new(2) do
        RECEIVED.pop(timeout: 5) or flunk('both processors should receive the message')
      end.sort_by(&:first)

      assert_equal %i[one two], received.map(&:first)
      received.each do |_processor, message|
        assert_equal 'DispatcherTest::MyMessage', message._sm_header.message_class
        assert_equal @m1._sm_header.uuid,         message._sm_header.uuid
        assert_equal %w[one two three],           [message.foo, message.bar, message.baz]
      end
    end


    # The business logic for a received subscribed-to message is
    # implemented as a class method; each records what it was given.
    def self.processer_one(message)
      RECEIVED << [:one, message]
    end


    def self.processer_two(message)
      RECEIVED << [:two, message]
    end

  end # class Test < Minitest::Test
end # module DispatcherTest
