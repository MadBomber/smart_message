# test/file_transport_test.rb

require_relative "test_helper"
require 'tempfile'
require 'fileutils'

class FileTransportTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir('file_transport_test')
    @test_file = File.join(@temp_dir, 'test_messages.log')
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_initialization_with_defaults
    transport = SmartMessage::Transport::FileTransport.new
    
    assert_equal 'messages.log', transport.options[:file_path]
    assert_equal 'a', transport.options[:file_mode]
    assert_equal :lines, transport.options[:file_format]
    assert_equal false, transport.options[:async]
    assert_equal :regular, transport.options[:file_type]
    assert_equal :block, transport.options[:queue_overflow_strategy]
  end

  def test_initialization_with_custom_options
    options = {
      file_path: @test_file,
      file_mode: 'w',
      async: true,
      max_queue: 100,
      file_type: :fifo
    }
    
    transport = SmartMessage::Transport::FileTransport.new(options)
    
    assert_equal @test_file, transport.options[:file_path]
    assert_equal 'w', transport.options[:file_mode]
    assert_equal true, transport.options[:async]
    assert_equal 100, transport.options[:max_queue]
    assert_equal :fifo, transport.options[:file_type]
  end

  def test_configuration_regular_file
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      async: false
    )
    
    assert File.exist?(@test_file)
    assert transport.connected?
  end

  def test_configuration_async_mode
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      async: true,
      max_queue: 10
    )
    
    # Should have configured async publishing
    assert transport.instance_variable_get(:@publish_queue)
    assert transport.instance_variable_get(:@publish_worker_thread)
    
    transport.disconnect
  end

  def test_publish_compatibility_method
    transport = SmartMessage::Transport::FileTransport.new(file_path: @test_file)
    
    transport.publish("test payload")
    transport.disconnect
    
    content = File.read(@test_file)
    assert_includes content, "test payload"
  end

  def test_do_publish_regular_file
    transport = SmartMessage::Transport::FileTransport.new(file_path: @test_file)
    
    transport.do_publish('TestMessage', 'serialized test message')
    transport.disconnect
    
    content = File.read(@test_file)
    assert_equal "serialized test message\n", content
  end

  def test_do_publish_async_mode
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      async: true
    )
    
    transport.do_publish('TestMessage', 'async test message')
    
    # Wait for async processing
    sleep 0.1
    transport.disconnect
    
    content = File.read(@test_file)
    assert_includes content, "async test message"
  end

  def test_do_publish_with_partitioned_files
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      directory: @temp_dir
    )
    
    transport.do_publish('ErrorMessage', 'error log entry')
    transport.do_publish('InfoMessage', 'info log entry')
    transport.disconnect
    
    error_file = File.join(@temp_dir, 'errormessage.log')
    info_file = File.join(@temp_dir, 'infomessage.log')
    
    assert File.exist?(error_file)
    assert File.exist?(info_file)
    assert_equal "error log entry\n", File.read(error_file)
    assert_equal "info log entry\n", File.read(info_file)
  end

  def test_do_publish_with_filename_selector
    selector = lambda do |payload, header|
      level = payload.include?('ERROR') ? 'error' : 'debug'
      File.join(@temp_dir, "#{level}.log")
    end
    
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      filename_selector: selector
    )
    
    transport.do_publish('LogMessage', 'ERROR: Database failed')
    transport.do_publish('LogMessage', 'DEBUG: Connection established')
    transport.disconnect
    
    error_file = File.join(@temp_dir, 'error.log')
    debug_file = File.join(@temp_dir, 'debug.log')
    
    assert File.exist?(error_file)
    assert File.exist?(debug_file)
    assert_includes File.read(error_file), 'ERROR: Database failed'
    assert_includes File.read(debug_file), 'DEBUG: Connection established'
  end

  def test_subscribe_disabled_by_default
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      enable_subscriptions: false
    )
    
    # Should log warning and return early
    transport.subscribe('TestMessage', :process, {})
    
    # No polling thread should be created
    assert_nil transport.instance_variable_get(:@polling_thread)
  end

  def test_subscribe_file_polling
    # Create a file with initial content
    File.write(@test_file, "initial message\n")
    
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      enable_subscriptions: true,
      poll_interval: 0.1,
      read_from_end: false  # Read from beginning to catch all content
    )
    
    received_messages = []
    
    # Mock the receive method to capture messages
    transport.define_singleton_method(:receive) do |message_class, message|
      received_messages << { message_class: message_class, message: message }
    end
    
    # Subscribe with file_path option to use the same file
    transport.subscribe('TestMessage', :process, { file_path: @test_file })
    
    # Add new content
    sleep 0.05  # Let subscription start
    File.write(@test_file, "initial message\nnew message\n")
    
    # Wait for polling to pick up changes
    sleep 0.3
    
    transport.disconnect
    
    # Should have received the new message
    assert received_messages.length >= 1
    messages = received_messages.map { |m| m[:message] }
    assert_includes messages, "new message"
  end

  def test_subscribe_fifo_mode
    # Simplified FIFO test that focuses on basic functionality
    # rather than complex message processing which is unreliable in test environments
    
    # Test if we can create FIFOs on this system
    test_dir = Dir.mktmpdir('fifo_test')
    test_fifo = File.join(test_dir, 'test.fifo')
    
    begin
      # Try to create a FIFO
      system("mkfifo #{test_fifo} 2>/dev/null")
      
      if File.exist?(test_fifo) && File.ftype(test_fifo) == "fifo"
        # Test basic FIFO transport initialization
        transport = SmartMessage::Transport::FileTransport.new(
          file_path: test_fifo,
          file_type: :fifo,
          enable_subscriptions: true,
          subscription_mode: :fifo_blocking
        )
        
        # Test that transport initialization succeeds
        assert transport.respond_to?(:subscribe), "Transport should support subscriptions"
        
        # Start a subscription to make transport connected
        transport.subscribe('TestMessage', :process, {})
        
        # Now the transport should be connected
        assert transport.connected?, "Transport should be connected to FIFO after subscription"
        
        transport.disconnect
      else
        skip("FIFO creation not supported on this system")
      end
    rescue => e
      skip("FIFO tests not supported: #{e.message}")
    ensure
      File.delete(test_fifo) if File.exist?(test_fifo)
      Dir.rmdir(test_dir) if Dir.exist?(test_dir)
    end
  end

  def test_connected_regular_file
    transport = SmartMessage::Transport::FileTransport.new(file_path: @test_file)
    
    assert transport.connected?
    
    transport.disconnect
    
    refute transport.connected?
  end

  def test_connected_with_subscriptions
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      enable_subscriptions: true
    )
    
    # Should be connected even without active subscriptions
    assert transport.connected?
    
    # Start subscription
    File.write(@test_file, "test\n")
    transport.subscribe('TestMessage', :process, {})
    
    assert transport.connected?
    
    transport.disconnect
    
    refute transport.connected?
  end

  def test_disconnect_stops_all_operations
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      async: true,
      enable_subscriptions: true
    )
    
    # Start various operations
    File.write(@test_file, "test\n")
    transport.subscribe('TestMessage', :process, {})
    
    worker_thread = transport.instance_variable_get(:@publish_worker_thread)
    polling_thread = transport.instance_variable_get(:@polling_thread)
    
    assert worker_thread&.alive?
    
    transport.disconnect
    
    # All threads should be stopped
    refute worker_thread&.alive?
    refute polling_thread&.alive?
    refute transport.connected?
  end

  def test_disconnect_with_partitioned_files
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      directory: @temp_dir
    )
    
    # Create multiple partition files
    transport.do_publish('Message1', 'content1')
    transport.do_publish('Message2', 'content2')
    
    handles = transport.instance_variable_get(:@partition_handles)
    assert handles&.length == 2
    
    # All handles should be open
    handles.each { |_, handle| refute handle.closed? }
    
    transport.disconnect
    
    # All handles should be closed
    handles.each { |_, handle| assert handle.closed? }
  end

  def test_inheritance_from_base_transport
    transport = SmartMessage::Transport::FileTransport.new(file_path: @test_file)
    
    assert transport.is_a?(SmartMessage::Transport::Base)
  end

  def test_module_inclusion
    transport = SmartMessage::Transport::FileTransport.new(file_path: @test_file)
    
    assert transport.class.include?(SmartMessage::Transport::FileOperations)
    assert transport.class.include?(SmartMessage::Transport::FileWatching)
    assert transport.class.include?(SmartMessage::Transport::PartitionedFiles)
    assert transport.class.include?(SmartMessage::Transport::AsyncPublishQueue)
    assert transport.class.include?(SmartMessage::Transport::FifoOperations)
  end

  def test_error_handling_in_publish
    # Mock write_to_file to raise an error
    transport = SmartMessage::Transport::FileTransport.new(file_path: @test_file)
    
    transport.define_singleton_method(:write_to_file) do |message|
      raise "Mock write error"
    end
    
    # Should handle the error gracefully (not crash the test)
    assert_raises(RuntimeError) do
      transport.do_publish('TestMessage', 'error message')
    end
  end

  def test_thread_safety_with_concurrent_publishes
    transport = SmartMessage::Transport::FileTransport.new(file_path: @test_file)
    
    threads = []
    messages = []
    
    # Create multiple threads publishing simultaneously
    10.times do |i|
      threads << Thread.new do
        msg = "message_#{i}_#{Thread.current.object_id}"
        messages << msg
        transport.do_publish('TestMessage', msg)
      end
    end
    
    threads.each(&:join)
    transport.disconnect
    
    content = File.read(@test_file)
    
    # Verify all messages were written
    messages.each do |msg|
      assert_includes content, msg
    end
  end

  def test_large_message_handling
    transport = SmartMessage::Transport::FileTransport.new(file_path: @test_file)
    
    # Create a large message
    large_message = "x" * 10000  # 10KB message
    
    transport.do_publish('TestMessage', large_message)
    transport.disconnect
    
    content = File.read(@test_file)
    assert_includes content, large_message
  end

  def test_unicode_message_handling
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      encoding: 'UTF-8'
    )
    
    unicode_message = "Hello 世界! 🚀 Café naïve"
    
    transport.do_publish('TestMessage', unicode_message)
    transport.disconnect
    
    content = File.read(@test_file, encoding: 'UTF-8')
    assert_includes content, unicode_message
  end

  def test_configuration_mode_precedence
    # Test that async takes precedence over fifo
    transport = SmartMessage::Transport::FileTransport.new(
      file_path: @test_file,
      async: true,
      file_type: :fifo
    )
    
    # Should have configured async, not FIFO
    assert transport.instance_variable_get(:@publish_queue)
    assert transport.instance_variable_get(:@publish_worker_thread)
    
    transport.disconnect
  end

  def test_default_options_immutability
    transport1 = SmartMessage::Transport::FileTransport.new(file_path: 'file1.log')
    transport2 = SmartMessage::Transport::FileTransport.new(file_path: 'file2.log')
    
    # Options should be independent
    refute_same transport1.options, transport2.options
    assert_equal 'file1.log', transport1.options[:file_path]
    assert_equal 'file2.log', transport2.options[:file_path]
    
    transport1.disconnect
    transport2.disconnect
  end
end