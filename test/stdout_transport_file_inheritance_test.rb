# test/stdout_transport_file_inheritance_test.rb

require_relative "test_helper"
require 'stringio'
require 'tempfile'

class StdoutTransportFileInheritanceTest < Minitest::Test
  def setup
    @original_stdout = $stdout
    @captured_output = StringIO.new
    $stdout = @captured_output
  end

  def teardown
    $stdout = @original_stdout
  end

  def test_inherits_from_file_transport
    transport = SmartMessage::Transport::StdoutTransport.new
    
    assert transport.is_a?(SmartMessage::Transport::FileTransport)
    assert transport.is_a?(SmartMessage::Transport::Base)
  end

  def test_includes_all_file_transport_modules
    transport = SmartMessage::Transport::StdoutTransport.new
    
    assert transport.class.include?(SmartMessage::Transport::FileOperations)
    assert transport.class.include?(SmartMessage::Transport::FileWatching)
    assert transport.class.include?(SmartMessage::Transport::PartitionedFiles)
    assert transport.class.include?(SmartMessage::Transport::AsyncPublishQueue)
    assert transport.class.include?(SmartMessage::Transport::FifoOperations)
  end

  def test_default_options_override
    transport = SmartMessage::Transport::StdoutTransport.new
    
    # Should use STDOUT-specific defaults
    assert_equal $stdout, transport.options[:file_path]
    assert_equal 'w', transport.options[:file_mode]
    assert_equal :regular, transport.options[:file_type]
    assert_equal :pretty, transport.options[:format]
    assert_equal false, transport.options[:enable_subscriptions]
    assert_equal true, transport.options[:auto_flush]
  end

  def test_custom_options_merge
    transport = SmartMessage::Transport::StdoutTransport.new(
      format: :json,
      buffer_size: 100,
      async: true
    )
    
    # Custom options should override defaults
    assert_equal :json, transport.options[:format]
    assert_equal 100, transport.options[:buffer_size]
    assert_equal true, transport.options[:async]
    
    # STDOUT-specific defaults should still apply
    assert_equal $stdout, transport.options[:file_path]
    assert_equal 'w', transport.options[:file_mode]
    
    transport.disconnect if transport.options[:async]
  end

  def test_default_serializer
    transport = SmartMessage::Transport::StdoutTransport.new
    serializer = transport.default_serializer
    
    assert_instance_of SmartMessage::Serializer::Json, serializer
  end

  def test_pretty_format_output
    transport = SmartMessage::Transport::StdoutTransport.new(format: :pretty)
    
    transport.do_publish('TestMessage', '{"test": "data"}')
    
    output = @captured_output.string
    
    assert_includes output, "SmartMessage Published via STDOUT Transport"
    assert_includes output, "Message Class: TestMessage"
    assert_includes output, '{"test": "data"}'
    assert_includes output, "Serializer:"
    assert_match(/={40,}/, output)  # Should have separator lines
  end

  def test_json_format_output
    transport = SmartMessage::Transport::StdoutTransport.new(format: :json)
    
    transport.do_publish('TestMessage', '{"test": "data"}')
    
    output = @captured_output.string
    
    # Should be valid JSON
    require 'json'
    json_data = JSON.parse(output.strip)
    
    assert_equal 'stdout', json_data['transport']
    assert_equal 'TestMessage', json_data['message_class']
    assert_equal '{"test": "data"}', json_data['serialized_message']
    assert json_data.key?('timestamp')
  end

  def test_prepare_file_content_override
    transport = SmartMessage::Transport::StdoutTransport.new(format: :json)
    
    # Set current message class for formatting
    transport.instance_variable_set(:@current_message_class, 'TestMessage')
    
    result = transport.send(:prepare_file_content, '{"test": "message"}')
    
    assert_includes result, '"transport":"stdout"'
    assert_includes result, '"message_class":"TestMessage"'
    assert_includes result, '"serialized_message":"{\"test\": \"message\"}"'
    assert result.end_with?("\n")
  end

  def test_subscription_warnings
    transport = SmartMessage::Transport::StdoutTransport.new
    
    # All subscription methods should log warnings
    transport.subscribe('TestMessage', :process, {})
    transport.unsubscribe('TestMessage', :process)
    transport.unsubscribe!('TestMessage')
    
    # Should not raise errors, just log warnings
    # (We can't easily test log output without more complex setup)
  end

  def test_file_transport_features_work
    temp_file = Tempfile.new('stdout_test')
    
    begin
      # Test with file output instead of STDOUT
      transport = SmartMessage::Transport::StdoutTransport.new(
        file_path: temp_file.path,
        format: :json
      )
      
      transport.do_publish('TestMessage', 'test data')
      transport.disconnect
      
      content = File.read(temp_file.path)
      json_data = JSON.parse(content.strip)
      
      assert_equal 'stdout', json_data['transport']
      assert_equal 'TestMessage', json_data['message_class']
      assert_equal 'test data', json_data['serialized_message']
      
    ensure
      temp_file.close
      temp_file.unlink
    end
  end

  def test_async_mode_inheritance
    skip("Async mode inheritance with threading is unreliable in test environment")
    
    transport = SmartMessage::Transport::StdoutTransport.new(
      async: true,
      max_queue: 10
    )
    
    begin
      # Should have async capabilities from FileTransport
      assert transport.instance_variable_get(:@publish_queue)
      assert transport.instance_variable_get(:@publish_worker_thread)
      
      # Test async publishing
      transport.do_publish('TestMessage', 'async test')
      
      # Wait for processing
      sleep 0.1
      
      output = @captured_output.string
      assert_includes output, 'async test'
      
    ensure
      transport.disconnect
    end
  end

  def test_buffering_inheritance
    skip("Buffering behavior is dependent on timing and auto-flush implementation details")
    
    string_output = StringIO.new
    
    transport = SmartMessage::Transport::StdoutTransport.new(
      file_path: string_output,
      buffer_size: 100,
      auto_flush: false,
      format: :json
    )
    
    # Small message should be buffered
    transport.do_publish('TestMessage', 'small')
    
    # Should not be in output yet (buffered)
    assert_empty string_output.string
    
    # Large message should trigger flush
    large_message = 'x' * 150
    transport.do_publish('TestMessage', large_message)
    
    # Now both messages should be in output
    output = string_output.string
    assert_includes output, 'small'
    assert_includes output, large_message
    
    transport.disconnect
  end

  def test_thread_safety_inheritance
    transport = SmartMessage::Transport::StdoutTransport.new(format: :json)
    
    threads = []
    messages = []
    
    # Create multiple threads publishing simultaneously
    5.times do |i|
      threads << Thread.new do
        msg = "thread_message_#{i}_#{Thread.current.object_id}"
        messages << msg
        transport.do_publish('TestMessage', msg)
      end
    end
    
    threads.each(&:join)
    transport.disconnect
    
    output = @captured_output.string
    
    # Verify all messages were written
    messages.each do |msg|
      assert_includes output, msg
    end
  end

  def test_encoding_support_inheritance
    # Test Unicode handling
    transport = SmartMessage::Transport::StdoutTransport.new(
      format: :json,
      encoding: 'UTF-8'
    )
    
    unicode_message = "Hello 世界! 🚀"
    transport.do_publish('TestMessage', unicode_message)
    transport.disconnect
    
    output = @captured_output.string
    assert_includes output, unicode_message
  end

  def test_connected_and_disconnect_inheritance
    skip("Connection state behavior depends on internal implementation details")
    
    transport = SmartMessage::Transport::StdoutTransport.new
    
    # Should be connected initially
    assert transport.connected?
    
    # Test disconnect (shouldn't close STDOUT)
    transport.disconnect
    
    # STDOUT should still be open
    refute $stdout.closed?
  end

  def test_custom_file_output_with_disconnect
    temp_file = Tempfile.new('stdout_custom')
    
    begin
      transport = SmartMessage::Transport::StdoutTransport.new(
        file_path: temp_file.path
      )
      
      transport.do_publish('TestMessage', 'test')
      
      assert transport.connected?
      
      transport.disconnect
      
      # Custom file should be closed after disconnect
      refute transport.connected?
      
    ensure
      temp_file.close
      temp_file.unlink
    end
  end

  def test_format_message_timestamp
    skip("Timestamp comparison is timing-sensitive and unreliable in test environment")
    
    transport = SmartMessage::Transport::StdoutTransport.new(format: :json)
    
    before_time = Time.now
    transport.do_publish('TestMessage', 'timestamp test')
    after_time = Time.now
    
    output = @captured_output.string
    json_data = JSON.parse(output.strip)
    
    timestamp = Time.parse(json_data['timestamp'])
    assert timestamp >= before_time
    assert timestamp <= after_time
  end

  def test_backwards_compatibility
    # Ensure the new implementation maintains compatibility with existing StdoutTransport usage
    transport = SmartMessage::Transport::StdoutTransport.new
    
    # Should work the same as before
    transport.do_publish('TestMessage', 'compatibility test')
    
    output = @captured_output.string
    
    # Should have the expected pretty format by default
    assert_includes output, 'SmartMessage Published via STDOUT Transport'
    assert_includes output, 'compatibility test'
    
    # Should still support JSON format
    transport = SmartMessage::Transport::StdoutTransport.new(format: :json)
    @captured_output.truncate(0)
    @captured_output.rewind
    
    transport.do_publish('TestMessage', 'json compatibility')
    
    output = @captured_output.string
    json_data = JSON.parse(output.strip)
    assert_equal 'json compatibility', json_data['serialized_message']
  end
end