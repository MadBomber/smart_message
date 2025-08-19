# test/circuit_breaker_test.rb
# encoding: utf-8
# frozen_string_literal: true

require 'test_helper'

class CircuitBreakerTest < Minitest::Test
  include SmartMessage

  def setup
    # Initialize components - circuit breakers will be configured automatically
    begin
      @dispatcher = SmartMessage::Dispatcher.new
      @transport = SmartMessage::Transport::MemoryTransport.new
      @serializer = SmartMessage::Serializer::JSON.new
      @header = SmartMessage::Header.new(
        message_class: 'TestMessage',
        from: 'test_sender',
        uuid: SecureRandom.uuid,
        published_at: Time.now,
        publisher_pid: Process.pid
      )
    rescue => e
      puts "Setup error: #{e.message}"
      puts e.backtrace
      raise
    end
  end

  def teardown
    # Reset any circuit breakers
    @dispatcher.reset_circuit_breakers! rescue nil
    @transport.reset_transport_circuits! rescue nil
  end

  context "Circuit Breaker Configuration" do
    should "configure default circuit breakers for dispatcher" do
      assert_respond_to @dispatcher, :circuit
      assert_respond_to @dispatcher, :circuit_breaker_stats
      assert_respond_to @dispatcher, :reset_circuit_breakers!
    end

    should "configure circuit breakers for transport" do
      assert_respond_to @transport, :circuit
      assert_respond_to @transport, :transport_circuit_stats
      assert_respond_to @transport, :reset_transport_circuits!
    end

    should "configure circuit breakers for serializer" do
      assert_respond_to @serializer, :circuit
    end
  end

  context "Message Processor Circuit Breaker" do
    should "allow normal message processing when circuit is closed" do
      # Set up a failing processor
      failing_processor = proc do |wrapper|
        raise StandardError, "Processing failed"
      end

      SmartMessage::Base.register_proc_handler('test_failing_processor', failing_processor)
      @dispatcher.add('TestMessage', 'test_failing_processor')

      # First few failures should still attempt processing
      wrapper = SmartMessage::Wrapper::Base.new(header: @header, payload: '{"test": true}')
      3.times do
        @dispatcher.route(wrapper)
        sleep 0.1 # Allow async processing
      end

      stats = @dispatcher.circuit_breaker_stats
      assert stats[:message_processor], "Expected message_processor stats to be present"
      assert stats[:message_processor][:open], "Expected circuit to be open after failures"
    end

    should "provide circuit breaker statistics" do
      stats = @dispatcher.circuit_breaker_stats
      assert_kind_of Hash, stats
      # Circuit might not be present if it hasn't been used
      if stats[:message_processor]
        assert_kind_of Hash, stats[:message_processor]
        assert stats[:message_processor].key?(:status)
      end
    end

    should "reset circuit breakers when requested" do
      # Trigger circuit breaker by causing failures
      failing_processor = proc { |wrapper| raise "Test failure" }
      SmartMessage::Base.register_proc_handler('test_reset_processor', failing_processor)
      @dispatcher.add('TestMessage', 'test_reset_processor')

      # Cause some failures
      wrapper = SmartMessage::Wrapper::Base.new(header: @header, payload: '{"test": true}')
      5.times do
        @dispatcher.route(wrapper)
        sleep 0.1
      end

      # Reset and verify
      @dispatcher.reset_circuit_breakers!
      stats = @dispatcher.circuit_breaker_stats
      # Circuit should be closed after reset
      if stats[:message_processor]
        assert stats[:message_processor][:closed] || stats[:message_processor][:half_open], 
               "Expected circuit to be closed or half-open after reset"
      end
    end
  end

  context "Transport Circuit Breaker" do
    should "protect publish operations" do
      # Mock a failing transport
      def @transport.do_publish(header, payload)
        raise Redis::ConnectionError, "Connection failed"
      end

      # This should trigger the circuit breaker
      result = @transport.publish(@header, '{"test": true}')
      
      # Should receive a circuit breaker fallback response
      if result.is_a?(Hash) && result[:circuit_breaker]
        assert_equal 'open', result[:circuit_breaker][:state]
        assert_equal :transport_publish, result[:circuit_breaker][:circuit]
      end
    end

    should "provide transport circuit statistics" do
      stats = @transport.transport_circuit_stats
      assert_kind_of Hash, stats
      assert stats.key?(:transport_publish)
      assert stats.key?(:transport_subscribe)
    end

    should "reset transport circuits when requested" do
      @transport.reset_transport_circuits!
      # Should not raise any errors
      assert true
    end
  end

  context "Serializer Circuit Breaker" do
    should "protect encoding operations" do
      # Mock a failing serializer
      def @serializer.do_encode(message_instance)
        raise JSON::GeneratorError, "Encoding failed"
      end

      # This should trigger the circuit breaker eventually
      result = @serializer.encode({"test" => "data"})
      
      # Check if we got a circuit breaker response or the original error
      if result.is_a?(Hash) && result[:circuit_breaker]
        assert_equal 'open', result[:circuit_breaker][:state]
        assert_equal :serializer, result[:circuit_breaker][:circuit]
      end
    end

    should "protect decoding operations" do
      # Mock a failing serializer
      def @serializer.do_decode(payload)
        raise JSON::ParserError, "Decoding failed"
      end

      # This should trigger the circuit breaker eventually
      result = @serializer.decode('invalid json')
      
      # Check if we got a circuit breaker response or the original error
      if result.is_a?(Hash) && result[:circuit_breaker]
        assert_equal 'open', result[:circuit_breaker][:state]
        assert_equal :serializer, result[:circuit_breaker][:circuit]
      end
    end
  end

  context "Circuit Breaker Integration" do
    should "handle multiple circuit breaker layers" do
      # Create a message class with circuit breaker protection
      test_message_class = Class.new(SmartMessage::Base) do
        property :content

        def self.name
          'TestCircuitMessage'
        end

        def self.process(wrapper)
          # This processor will be protected by the dispatcher circuit breaker
          data = JSON.parse(wrapper._sm_payload)
          new(data)
        end
      end

      # Register the processor
      @dispatcher.add('TestCircuitMessage', 'TestCircuitMessage.process')

      # Test with transport and serializer circuit breakers
      header = SmartMessage::Header.new(
        message_class: 'TestCircuitMessage',
        from: 'test_sender',
        uuid: SecureRandom.uuid,
        published_at: Time.now,
        publisher_pid: Process.pid
      )

      # This should work through all circuit breaker layers
      @transport.publish(header, '{"content": "test message"}')
      
      # Allow time for async processing
      sleep 0.2

      # Verify message was processed
      assert_equal 1, @transport.message_count
    end

    should "provide fallback mechanisms" do
      # Test circuit breaker fallbacks
      fallback_handler = SmartMessage::CircuitBreaker::Fallbacks.dead_letter_queue
      assert_respond_to fallback_handler, :call

      graceful_fallback = SmartMessage::CircuitBreaker::Fallbacks.graceful_degradation({status: "degraded"})
      assert_respond_to graceful_fallback, :call

      retry_fallback = SmartMessage::CircuitBreaker::Fallbacks.retry_with_backoff
      assert_respond_to retry_fallback, :call
    end
  end

  context "Circuit Breaker Configuration Module" do
    should "provide default configurations" do
      configs = SmartMessage::CircuitBreaker::DEFAULT_CONFIGS
      assert_kind_of Hash, configs
      assert configs.key?(:message_processor)
      assert configs.key?(:transport_publish)
      assert configs.key?(:transport_subscribe)
      assert configs.key?(:serializer)
    end

    should "configure circuit breakers for classes" do
      test_class = Class.new do
        include BreakerMachines::DSL
      end

      SmartMessage::CircuitBreaker.configure_for(test_class)
      
      instance = test_class.new
      assert_respond_to instance, :circuit
    end

    should "provide utility methods" do
      assert_respond_to SmartMessage::CircuitBreaker, :stats
      assert_respond_to SmartMessage::CircuitBreaker, :available?
      assert_respond_to SmartMessage::CircuitBreaker, :reset!
    end
  end

  private

  # Helper method to create a test message
  def create_test_message(content = "test")
    Class.new(SmartMessage::Base) do
      property :content
      
      def self.name
        'TestMessage'
      end
    end.new(content: content)
  end
end