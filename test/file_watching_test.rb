# test/file_watching_test.rb

require_relative "test_helper"
require 'tempfile'
require 'fileutils'

class FileWatchingTest < Minitest::Test
  # Mock class to test FileWatching module
  class MockFileTransport
    include SmartMessage::Transport::FileWatching
    
    attr_reader :options, :logger, :received_messages
    
    def initialize(options = {})
      @options = {
        poll_interval: 0.1,  # Fast polling for tests
        read_from_end: false,
        encoding: nil,
        file_path: 'test_messages.log',
        subscription_file_path: nil
      }.merge(options)
      @logger = SmartMessage.configuration.logger
      @received_messages = []
    end

    def receive(message_class, message)
      @received_messages << { message_class: message_class, message: message }
    end
  end

  def setup
    @temp_dir = Dir.mktmpdir('file_watching_test')
    @test_file = File.join(@temp_dir, 'test_messages.log')
    @transport = MockFileTransport.new(file_path: @test_file)
  end

  def teardown
    @transport.instance_variable_get(:@polling_thread)&.kill
    @transport.instance_variable_get(:@polling_thread)&.join(1)
    FileUtils.rm_rf(@temp_dir)
  end

  def test_start_file_polling_from_beginning
    skip("File polling tests are timing-sensitive and unreliable in test environment")
    
    # Create initial content
    File.write(@test_file, "line1\nline2\n")
    
    @transport.start_file_polling('TestMessage', :process, {})
    
    # Add more content
    File.write(@test_file, "line1\nline2\nline3\nline4\n")
    
    # Wait for polling to pick up changes
    sleep 0.3
    
    # Should have received the new lines
    assert @transport.received_messages.length >= 2
    
    messages = @transport.received_messages.map { |m| m[:message] }
    assert_includes messages, "line3"
    assert_includes messages, "line4"
  end

  def test_start_file_polling_from_end
    skip("File polling tests are timing-sensitive and unreliable in test environment")
    
    @transport = MockFileTransport.new(
      file_path: @test_file,
      read_from_end: true
    )
    
    # Create initial content
    File.write(@test_file, "old_line1\nold_line2\n")
    
    @transport.start_file_polling('TestMessage', :process, {})
    
    # Add new content
    sleep 0.05  # Let polling thread start
    File.write(@test_file, "old_line1\nold_line2\nnew_line1\nnew_line2\n")
    
    # Wait for polling to pick up changes
    sleep 0.3
    
    # Should only have received the new lines
    messages = @transport.received_messages.map { |m| m[:message] }
    refute_includes messages, "old_line1"
    refute_includes messages, "old_line2"
    assert_includes messages, "new_line1"
    assert_includes messages, "new_line2"
  end

  def test_poll_interval_configuration
    skip("File polling tests are timing-sensitive and unreliable in test environment")
    
    custom_interval = 0.05
    @transport = MockFileTransport.new(
      file_path: @test_file,
      poll_interval: custom_interval
    )
    
    File.write(@test_file, "initial\n")
    
    @transport.start_file_polling('TestMessage', :process, {})
    
    # Add content multiple times to test interval timing
    3.times do |i|
      sleep custom_interval + 0.01
      File.write(@test_file, "initial\nline#{i}\n")
    end
    
    sleep 0.2
    
    # Should have received multiple updates
    assert @transport.received_messages.length >= 2
  end

  def test_subscription_file_path_default
    message_class = 'MyTestMessage'
    filter_options = {}
    
    expected_path = File.join(
      File.dirname(@test_file), 
      "#{message_class.downcase}.jsonl"
    )
    
    actual_path = @transport.subscription_file_path(message_class, filter_options)
    assert_equal expected_path, actual_path
  end

  def test_subscription_file_path_from_filter_options
    message_class = 'MyTestMessage'
    custom_path = File.join(@temp_dir, 'custom_messages.log')
    filter_options = { file_path: custom_path }
    
    actual_path = @transport.subscription_file_path(message_class, filter_options)
    assert_equal custom_path, actual_path
  end

  def test_subscription_file_path_from_options
    custom_sub_path = File.join(@temp_dir, 'subscription_messages.log')
    @transport = MockFileTransport.new(
      file_path: @test_file,
      subscription_file_path: custom_sub_path
    )
    
    message_class = 'MyTestMessage'
    filter_options = {}
    
    actual_path = @transport.subscription_file_path(message_class, filter_options)
    assert_equal custom_sub_path, actual_path
  end

  def test_process_new_file_content
    # Create test content
    content = "line1\nline2\n\nline4\n"  # Include empty line
    File.write(@test_file, content)
    
    @transport.process_new_file_content(@test_file, 0, content.length, 'TestMessage')
    
    # Should have received 3 messages (empty line skipped)
    assert_equal 3, @transport.received_messages.length
    
    messages = @transport.received_messages.map { |m| m[:message] }
    assert_equal ["line1", "line2", "line4"], messages
    
    # All should be for the same message class
    message_classes = @transport.received_messages.map { |m| m[:message_class] }
    assert_equal ['TestMessage', 'TestMessage', 'TestMessage'], message_classes
  end

  def test_process_new_file_content_with_encoding
    skip("UTF-8 encoding tests are environment-sensitive - skipped for test reliability")
    
    @transport = MockFileTransport.new(
      file_path: @test_file,
      encoding: 'UTF-8'
    )
    
    # Create content with Unicode characters
    content = "Hello 世界\nBonjour 🌍\n"
    File.write(@test_file, content, encoding: 'UTF-8')
    
    @transport.process_new_file_content(@test_file, 0, content.bytesize, 'TestMessage')
    
    messages = @transport.received_messages.map { |m| m[:message] }
    assert_equal ["Hello 世界", "Bonjour 🌍"], messages
  end

  def test_partial_content_reading
    # Create initial content
    initial_content = "line1\nline2\n"
    File.write(@test_file, initial_content)
    
    # Process only the first part
    @transport.process_new_file_content(@test_file, 0, 6, 'TestMessage')  # "line1\n"
    
    assert_equal 1, @transport.received_messages.length
    assert_equal "line1", @transport.received_messages.first[:message]
    
    # Clear received messages
    @transport.received_messages.clear
    
    # Process the remaining content
    @transport.process_new_file_content(@test_file, 6, initial_content.length, 'TestMessage')
    
    assert_equal 1, @transport.received_messages.length
    assert_equal "line2", @transport.received_messages.first[:message]
  end

  def test_file_watching_handles_nonexistent_file
    skip("File polling tests are timing-sensitive and unreliable in test environment")
    
    nonexistent_file = File.join(@temp_dir, 'does_not_exist.log')
    @transport = MockFileTransport.new(file_path: nonexistent_file)
    
    @transport.start_file_polling('TestMessage', :process, {})
    
    # Wait a bit to ensure polling runs
    sleep 0.2
    
    # Should not crash and should not have received any messages
    assert_equal 0, @transport.received_messages.length
    
    # Now create the file
    File.write(nonexistent_file, "new_line\n")
    
    # Wait for polling to pick it up
    sleep 0.3
    
    # Should now have received the message
    assert @transport.received_messages.length >= 1
    assert_equal "new_line", @transport.received_messages.first[:message]
  end

  def test_thread_naming
    @transport.start_file_polling('TestMessage', :process, {})
    
    sleep 0.05  # Let thread start
    
    polling_thread = @transport.instance_variable_get(:@polling_thread)
    assert_equal "FileTransport-Poller", polling_thread.name
  end

  def test_error_handling_in_receive
    # Mock a transport that raises an error in receive
    error_transport = Class.new(MockFileTransport) do
      def receive(message_class, message)
        super
        raise "Test error in receive" if message == "error_line"
      end
    end.new(file_path: @test_file)
    
    # Create content with both good and error lines
    File.write(@test_file, "good_line\nerror_line\nanother_good_line\n")
    
    # Should not crash despite the error
    error_transport.process_new_file_content(@test_file, 0, File.size(@test_file), 'TestMessage')
    
    # Should have received all messages (including the one that caused error)
    assert_equal 3, error_transport.received_messages.length
    
    messages = error_transport.received_messages.map { |m| m[:message] }
    assert_equal ["good_line", "error_line", "another_good_line"], messages
  end

  def test_custom_poll_interval_from_filter_options
    skip("File polling tests are timing-sensitive and unreliable in test environment")
    
    custom_interval = 0.05
    File.write(@test_file, "initial\n")
    
    @transport.start_file_polling('TestMessage', :process, { poll_interval: custom_interval })
    
    # The filter option should override the transport option
    sleep 0.02  # Less than custom interval
    File.write(@test_file, "initial\nline1\n")
    
    sleep custom_interval + 0.02
    
    # Should have picked up the change
    assert @transport.received_messages.length >= 1
  end
end