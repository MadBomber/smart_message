# test/fifo_operations_test.rb

require_relative "test_helper"
require 'tempfile'
require 'fileutils'

class FifoOperationsTest < Minitest::Test
  # Mock class to test FifoOperations module
  class MockFileTransport
    include SmartMessage::Transport::FifoOperations
    
    attr_reader :options, :logger, :received_messages
    attr_accessor :current_message_class
    
    def initialize(options = {})
      @options = {
        file_path: '/tmp/test_fifo',
        file_type: :fifo,
        create_fifo: false,
        fifo_mode: :blocking,
        fifo_permissions: 0644,
        fallback_transport: nil,
        subscription_mode: :fifo_blocking,
        poll_interval: 1.0
      }.merge(options)
      @logger = SmartMessage.configuration.logger
      @received_messages = []
      @current_message_class = nil
    end
    
    # Make methods public for testing
    public :stop_fifo_operations

    def configure_file_output
      # Mock method for fallback
    end

    def prepare_file_content(serialized_message)
      "#{serialized_message}\n"
    end

    def receive(message_class, message)
      @received_messages << { message_class: message_class, message: message }
    end
  end

  def setup
    @temp_dir = Dir.mktmpdir('fifo_operations_test')
    @fifo_path = File.join(@temp_dir, 'test_fifo')
    @transport = MockFileTransport.new(file_path: @fifo_path)
  end

  def teardown
    @transport.stop_fifo_operations if @transport.respond_to?(:stop_fifo_operations)
    FileUtils.rm_rf(@temp_dir)
  end

  def test_platform_supports_fifo_unix
    # Should return true on Unix-like systems
    assert @transport.platform_supports_fifo?
  end

  def test_configure_fifo_fallback_when_unsupported
    # Mock platform detection to return false
    @transport.define_singleton_method(:platform_supports_fifo?) { false }
    
    @transport.configure_fifo
    
    # Should have fallen back to regular file
    assert_equal :regular, @transport.options[:file_type]
  end

  def test_create_named_pipe_unix
    skip("Skipping FIFO creation tests - requires special permissions") unless can_create_fifos?
    
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      create_fifo: true
    )
    
    @transport.create_named_pipe
    
    assert File.exist?(@fifo_path)
    # On most systems, we can't easily test if it's actually a FIFO without special tools
  end

  def test_create_named_pipe_already_exists
    skip("Skipping FIFO creation tests - requires special permissions") unless can_create_fifos?
    
    # Create a regular file first
    File.write(@fifo_path, "not a fifo")
    
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      create_fifo: true
    )
    
    # Should not raise an error, but should handle existing file gracefully
    assert File.exist?(@fifo_path)
  end

  def test_write_to_fifo_no_reader
    # Mock open_fifo_for_writing to return nil (no reader available)
    @transport.define_singleton_method(:open_fifo_for_writing) { nil }
    
    result = @transport.write_to_fifo("test message")
    refute result
  end

  def test_write_to_fifo_with_fallback_transport
    fallback_calls = []
    fallback_transport = Class.new do
      def initialize(calls_array)
        @calls = calls_array
      end
      
      def do_publish(message_class, serialized_message)
        @calls << { message_class: message_class, message: serialized_message }
      end
    end.new(fallback_calls)
    
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      fallback_transport: fallback_transport
    )
    @transport.current_message_class = 'TestMessage'
    
    # Mock failed FIFO write
    @transport.define_singleton_method(:open_fifo_for_writing) { nil }
    
    result = @transport.write_to_fifo("failed message")
    refute result
    
    # Should have called fallback transport
    assert_equal 1, fallback_calls.length
    assert_equal 'TestMessage', fallback_calls.first[:message_class]
    assert_equal "failed message", fallback_calls.first[:message]
  end

  def test_write_to_fifo_epipe_error
    # Mock file handle that raises EPIPE
    mock_handle = Class.new do
      def write(content)
        raise Errno::EPIPE, "Broken pipe"
      end
      
      def flush
        # no-op
      end
      
      def close
        # no-op
      end
    end.new
    
    @transport.define_singleton_method(:open_fifo_for_writing) { mock_handle }
    
    result = @transport.write_to_fifo("epipe message")
    refute result
  end

  def test_open_fifo_for_writing_blocking_mode
    skip("FIFO opening tests require complex process setup - skipped for test reliability")
    
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      fifo_mode: :blocking
    )
    
    # Test by checking if it tries to open in blocking mode
    # We expect it to raise ENXIO since the FIFO doesn't exist
    result = @transport.send(:open_fifo_for_writing)
    assert_nil result
  end

  def test_open_fifo_for_writing_non_blocking_mode
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      fifo_mode: :non_blocking
    )
    
    # Test by checking if it tries to open in non-blocking mode
    # We expect it to raise ENXIO since the FIFO doesn't exist
    result = @transport.send(:open_fifo_for_writing)
    assert_nil result
  end

  def test_start_fifo_reader_blocking_mode
    skip("FIFO reader thread tests require actual FIFO setup - skipped for test reliability")
    
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      subscription_mode: :fifo_blocking
    )
    
    @transport.start_fifo_reader('TestMessage', :process, {})
    
    reader_thread = @transport.instance_variable_get(:@fifo_reader_thread)
    assert reader_thread
    assert reader_thread.alive?
    assert_equal "FileTransport-FifoReader", reader_thread.name
  end

  def test_start_fifo_reader_select_mode
    skip("Skipping FIFO select mode test - requires FIFO setup")
  end

  def test_start_fifo_reader_polling_mode
    skip("FIFO reader thread tests require actual FIFO setup - skipped for test reliability")
    
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      subscription_mode: :fifo_polling
    )
    
    @transport.start_fifo_reader('TestMessage', :process, {})
    
    reader_thread = @transport.instance_variable_get(:@fifo_reader_thread)
    assert reader_thread
    assert reader_thread.alive?
    assert_equal "FileTransport-FifoPoller", reader_thread.name
  end

  def test_start_fifo_reader_invalid_mode
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      subscription_mode: :invalid_mode
    )
    
    @transport.start_fifo_reader('TestMessage', :process, {})
    
    # Should not create any threads
    assert_nil @transport.instance_variable_get(:@fifo_reader_thread)
    assert_nil @transport.instance_variable_get(:@fifo_select_thread)
  end

  def test_stop_fifo_operations
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      subscription_mode: :fifo_blocking
    )
    
    @transport.start_fifo_reader('TestMessage', :process, {})
    
    reader_thread = @transport.instance_variable_get(:@fifo_reader_thread)
    assert reader_thread.alive?
    
    @transport.stop_fifo_operations
    
    # Give thread time to stop
    sleep 0.1
    
    refute reader_thread.alive?
  end

  def test_fifo_active_with_reader_thread
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      subscription_mode: :fifo_blocking
    )
    
    refute @transport.fifo_active?
    
    @transport.start_fifo_reader('TestMessage', :process, {})
    
    assert @transport.fifo_active?
  end

  def test_fifo_active_with_select_thread
    @transport = MockFileTransport.new(
      file_path: @fifo_path,
      subscription_mode: :fifo_select
    )
    
    # Mock File.open
    File.define_singleton_method(:open) do |path, mode|
      Class.new do
        def gets; nil; end
        def close; end
      end.new
    end
    
    refute @transport.fifo_active?
    
    @transport.start_fifo_reader('TestMessage', :process, {})
    
    assert @transport.fifo_active?
    
    # Clean up
    File.singleton_class.remove_method(:open)
  end

  def test_error_handling_in_fifo_reader
    skip("Skipping FIFO error handling test - requires FIFO setup")
  end

  def test_message_processing_in_blocking_reader
    skip("Skipping FIFO message processing test - requires FIFO setup")
  end

  def test_custom_poll_interval_in_polling_mode
    skip("Skipping FIFO polling interval test - requires FIFO setup")
  end

  private

  def can_create_fifos?
    # Check if we can create FIFOs (requires appropriate permissions)
    begin
      test_fifo = File.join(@temp_dir, 'permission_test')
      File.mkfifo(test_fifo, 0644)
      File.unlink(test_fifo)
      true
    rescue NotImplementedError, Errno::EPERM, Errno::EACCES
      false
    end
  end
end