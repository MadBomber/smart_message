# test/dispatcher_test.rb


require_relative "test_helper"

module DispatcherTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
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
      skip
    end


    def processer_one(message_header, encoded_message)
      # TODO: will an assert work here?
    end


    def processer_two(message_header, encoded_message)
      # TODO: will an assert work here?
    end

  end # class Test < Minitest::Test
end # module DispatcherTest
