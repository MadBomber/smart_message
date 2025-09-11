# test/file_operations_test.rb

require_relative "test_helper"
require 'tempfile'
require 'fileutils'

class FileOperationsTest < Minitest::Test
  # Mock class to test FileOperations module
  class MockFileTransport
    include SmartMessage::Transport::FileOperations
    
    attr_reader :options, :logger
    
    def initialize(options = {})
      @options = {
        file_path: 'test_messages.log',
        file_mode: 'a',
        encoding: nil,
        file_format: :lines,
        buffer_size: 0,
        flush_interval: nil,
        auto_flush: true,
        rotate_size: nil,
        rotate_time: nil,
        rotate_count: 5,
        timestamp_format: '%Y%m%d_%H%M%S',
        create_directories: true
      }.merge(options)
      @logger = SmartMessage.configuration.logger
    end

    def setup_rotation_timer
      # Mock method - no implementation needed for tests
    end
  end

  def setup
    @temp_dir = Dir.mktmpdir('file_operations_test')
    @test_file = File.join(@temp_dir, 'test_messages.log')
    @transport = MockFileTransport.new(file_path: @test_file)
  end

  def teardown
    @transport.close_file_handle if @transport.respond_to?(:close_file_handle)
    FileUtils.rm_rf(@temp_dir)
  end

  def test_configure_file_output
    @transport.configure_file_output
    
    assert File.exist?(@test_file)
    assert_instance_of File, @transport.instance_variable_get(:@file_handle)
    assert_instance_of Array, @transport.instance_variable_get(:@write_buffer)
    assert_instance_of Mutex, @transport.instance_variable_get(:@file_mutex)
  end

  def test_write_to_file_direct_mode
    @transport.configure_file_output
    @transport.write_to_file("test message")
    @transport.close_file_handle
    
    content = File.read(@test_file)
    assert_equal "test message\n", content
  end

  def test_write_to_file_buffered_mode
    @transport = MockFileTransport.new(
      file_path: @test_file,
      buffer_size: 100,
      auto_flush: false
    )
    @transport.configure_file_output
    
    @transport.write_to_file("message 1")
    @transport.write_to_file("message 2")
    
    # Should be in buffer, not yet written to file
    assert_equal "", File.read(@test_file)
    
    @transport.flush_buffer
    content = File.read(@test_file)
    assert_equal "message 1\nmessage 2\n", content
  end

  def test_file_format_lines
    @transport.configure_file_output
    @transport.write_to_file("test message")
    @transport.close_file_handle
    
    content = File.read(@test_file)
    assert_equal "test message\n", content
  end

  def test_file_format_raw
    @transport = MockFileTransport.new(
      file_path: @test_file,
      file_format: :raw
    )
    @transport.configure_file_output
    @transport.write_to_file("test message")
    @transport.close_file_handle
    
    content = File.read(@test_file)
    assert_equal "test message", content
  end

  def test_directory_creation
    nested_path = File.join(@temp_dir, 'nested', 'deep', 'messages.log')
    @transport = MockFileTransport.new(
      file_path: nested_path,
      create_directories: true
    )
    
    @transport.configure_file_output
    
    assert File.exist?(File.dirname(nested_path))
    assert File.exist?(nested_path)
  end

  def test_size_based_rotation
    # Create a small rotate size for testing
    @transport = MockFileTransport.new(
      file_path: @test_file,
      rotate_size: 50  # Very small for testing
    )
    @transport.configure_file_output
    
    # Write enough data to trigger rotation
    10.times { @transport.write_to_file("This is a test message for rotation") }
    
    @transport.close_file_handle
    
    # Check that archived files were created
    archived_files = Dir.glob(File.join(@temp_dir, "test_messages_*.log"))
    assert archived_files.length > 0, "Should have created archived files"
  end

  def test_buffer_full_triggers_flush
    @transport = MockFileTransport.new(
      file_path: @test_file,
      buffer_size: 20,  # Small buffer
      auto_flush: false
    )
    @transport.configure_file_output
    
    @transport.write_to_file("short")
    assert_equal "", File.read(@test_file)  # Should still be buffered
    
    @transport.write_to_file("this is a longer message that exceeds buffer")
    content = File.read(@test_file)
    refute_empty content  # Should have been flushed automatically
  end

  def test_flush_interval
    @transport = MockFileTransport.new(
      file_path: @test_file,
      buffer_size: 100,
      flush_interval: 0.1,  # Very short interval for testing
      auto_flush: false
    )
    @transport.configure_file_output
    
    @transport.write_to_file("test message")
    assert_equal "", File.read(@test_file)  # Should be buffered
    
    sleep 0.2  # Wait for flush interval
    @transport.write_to_file("trigger check")
    
    content = File.read(@test_file)
    refute_empty content  # Should have been flushed due to interval
  end

  def test_thread_safety
    @transport.configure_file_output
    
    threads = []
    messages = []
    
    # Create multiple threads writing simultaneously
    10.times do |i|
      threads << Thread.new do
        msg = "message_#{i}_#{Thread.current.object_id}"
        messages << msg
        @transport.write_to_file(msg)
      end
    end
    
    threads.each(&:join)
    @transport.close_file_handle
    
    content = File.read(@test_file)
    
    # Verify all messages were written
    messages.each do |msg|
      assert_includes content, msg
    end
  end

  def test_timestamped_file_path
    @transport = MockFileTransport.new(
      file_path: @test_file,
      rotate_time: :daily,
      timestamp_format: '%Y%m%d'
    )
    
    timestamped_path = @transport.send(:timestamped_file_path)
    expected_pattern = /test_messages_\d{8}\.log$/
    
    assert_match expected_pattern, timestamped_path
  end

  def test_rotation_count_cleanup
    @transport = MockFileTransport.new(
      file_path: @test_file,
      rotate_size: 30,
      rotate_count: 2  # Keep only 2 archived files
    )
    @transport.configure_file_output
    
    # Write enough to trigger multiple rotations
    20.times { @transport.write_to_file("This is a test message for rotation testing") }
    
    @transport.close_file_handle
    
    # Check that only the specified number of archived files exist
    archived_files = Dir.glob(File.join(@temp_dir, "test_messages_*.log"))
    assert archived_files.length <= 2, "Should have cleaned up old archived files"
  end

  def test_encoding_support
    @transport = MockFileTransport.new(
      file_path: @test_file,
      encoding: 'UTF-8'
    )
    @transport.configure_file_output
    
    # Write UTF-8 content
    @transport.write_to_file("Hello 世界! 🚀")
    @transport.close_file_handle
    
    content = File.read(@test_file, encoding: 'UTF-8')
    assert_equal "Hello 世界! 🚀\n", content
  end

  def test_file_handle_cleanup
    @transport.configure_file_output
    handle = @transport.instance_variable_get(:@file_handle)
    
    refute handle.closed?
    
    @transport.close_file_handle
    
    assert handle.closed?
    assert_nil @transport.instance_variable_get(:@file_handle)
  end
end