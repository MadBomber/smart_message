# test/publish_test.rb

require_relative "test_helper"

require 'smart_message/serializer/json'
require 'smart_message/broker/stdout'

module PublishTest
  # A simple example message model
  class CommonMessageConfig < SmartMessage::Base
    # Defines a common message configuration
  end

  class MyMessage < CommonMessageConfig
    property :foo
    property :bar
    property :baz
    property :id

    def publish
      SS.add(whoami, 'publish')
      return id
    end

    def self.process(message_header, message_payload)
      puts "\n#{message_header.uuid}"
      puts "\t#{message_payload}"
    end
  end # class MyMessage < SmartMessage::Base

  class MyTransportMessage < CommonMessageConfig
    property :foo
    property :bar
    property :baz
    property :id

    def self.process(message_header, message_payload)
      puts "\n#{message_header.uuid}"
      puts "\t#{message_payload}"
    end
  end # class MyMessage < SmartMessage::Base




  class Test < Minitest::Test
    def setup
      PublishTest::CommonMessageConfig.config do
        serializer  SmartMessage::Serializer::JSON.new
        transport   SmartMessage::Broker::Stdout.new
      end

      # Uses the publish method defined by the message
      @my_message = PublishTest::MyMessage.new(
          foo: 'foo',
          bar: 'bar',
          baz: 'baz'
        )

      # Uses the publish method from SmartMessage::Base
      @my_transport_message = PublishTest::MyTransportMessage.new(
          foo: 'foo',
          bar: 'bar',
          baz: 'baz'
        )
    end # def setup


    def test_010_message_specific_publish_method
      PublishTest::MyMessage.subscribe

      @my_message.id  = 42
      how_many        = 10

      SS.reset('PublishTest::MyMessage', 'publish')

      how_many.times do |message_id|
        @my_message.id = message_id
        assert_equal message_id, @my_message.publish
      end

      assert_equal how_many, SS.get('PublishTest::MyMessage', 'publish')
    end


    def test_020_base_publish_method
      PublishTest::MyTransportMessage.subscribe

      @my_transport_message.id  = 42
      how_many        = 10

      SS.reset('PublishTest::MyTransportMessage', 'publish')

      how_many.times do |message_id|
        @my_transport_message.id = message_id
        # NOTE: message_id is zero-based but the count of published messages
        # is being returned.
        assert_equal message_id+1, @my_transport_message.publish
      end

      assert_equal how_many, SS.get('PublishTest::MyTransportMessage', 'publish')
    end
  end # class Test < Minitest::Test
end # module PublishTest
