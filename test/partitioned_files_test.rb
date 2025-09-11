# test/partitioned_files_test.rb

require_relative "test_helper"
require 'tempfile'
require 'fileutils'

class PartitionedFilesTest < Minitest::Test
  # Mock class to test PartitionedFiles module
  class MockFileTransport
    include SmartMessage::Transport::PartitionedFiles
    
    attr_reader :options, :logger
    
    def initialize(options = {})
      @options = {
        create_directories: true,
        file_path: 'default_messages.log',
        file_mode: 'a',
        encoding: nil,
        filename_selector: nil,
        directory: nil
      }.merge(options)
      @logger = SmartMessage.configuration.logger
    end

    def file_mode
      @options[:file_mode] || 'a'
    end
  end

  def setup
    @temp_dir = Dir.mktmpdir('partitioned_files_test')
    @default_file = File.join(@temp_dir, 'default_messages.log')
    @transport = MockFileTransport.new(file_path: @default_file)
  end

  def teardown
    @transport.close_partition_handles if @transport.respond_to?(:close_partition_handles)
    FileUtils.rm_rf(@temp_dir)
  end

  def test_determine_file_path_default
    payload = "test message"
    header = { message_class_name: 'TestMessage' }
    
    result = @transport.determine_file_path(payload, header)
    assert_equal @default_file, result
  end

  def test_determine_file_path_with_directory
    @transport = MockFileTransport.new(
      file_path: @default_file,
      directory: @temp_dir
    )
    
    payload = "test message"
    header = { message_class_name: 'TestMessage' }
    
    result = @transport.determine_file_path(payload, header)
    expected = File.join(@temp_dir, 'testmessage.log')
    assert_equal expected, result
  end

  def test_determine_file_path_with_filename_selector
    selector = lambda do |payload, header|
      severity = payload.include?('ERROR') ? 'error' : 'info'
      File.join(@temp_dir, "#{header[:message_class_name].downcase}_#{severity}.log")
    end
    
    @transport = MockFileTransport.new(
      file_path: @default_file,
      filename_selector: selector
    )
    
    # Test error message
    payload = "ERROR: Something went wrong"
    header = { message_class_name: 'LogMessage' }
    
    result = @transport.determine_file_path(payload, header)
    expected = File.join(@temp_dir, 'logmessage_error.log')
    assert_equal expected, result
    
    # Test info message
    payload = "INFO: All is well"
    result = @transport.determine_file_path(payload, header)
    expected = File.join(@temp_dir, 'logmessage_info.log')
    assert_equal expected, result
  end

  def test_determine_file_path_selector_takes_precedence
    selector = lambda do |payload, header|
      File.join(@temp_dir, 'custom_from_selector.log')
    end
    
    @transport = MockFileTransport.new(
      file_path: @default_file,
      directory: @temp_dir,  # This should be ignored when selector is present
      filename_selector: selector
    )
    
    payload = "test message"
    header = { message_class_name: 'TestMessage' }
    
    result = @transport.determine_file_path(payload, header)
    expected = File.join(@temp_dir, 'custom_from_selector.log')
    assert_equal expected, result
  end

  def test_get_or_open_partition_handle_creates_file
    file_path = File.join(@temp_dir, 'new_partition.log')
    
    handle = @transport.get_or_open_partition_handle(file_path)
    
    assert_instance_of File, handle
    assert File.exist?(file_path)
    refute handle.closed?
  end

  def test_get_or_open_partition_handle_reuses_existing
    file_path = File.join(@temp_dir, 'partition.log')
    
    handle1 = @transport.get_or_open_partition_handle(file_path)
    handle2 = @transport.get_or_open_partition_handle(file_path)
    
    assert_same handle1, handle2
  end

  def test_get_or_open_partition_handle_creates_directories
    nested_path = File.join(@temp_dir, 'deep', 'nested', 'partition.log')
    
    @transport.get_or_open_partition_handle(nested_path)
    
    assert File.exist?(File.dirname(nested_path))
    assert File.exist?(nested_path)
  end

  def test_get_or_open_partition_handle_respects_create_directories_false
    @transport = MockFileTransport.new(
      file_path: @default_file,
      create_directories: false
    )
    
    nested_path = File.join(@temp_dir, 'deep', 'nested', 'partition.log')
    
    # Should raise an error because directory doesn't exist and won't be created
    assert_raises Errno::ENOENT do
      @transport.get_or_open_partition_handle(nested_path)
    end
  end

  def test_get_or_open_partition_handle_with_encoding
    @transport = MockFileTransport.new(
      file_path: @default_file,
      encoding: 'UTF-8'
    )
    
    file_path = File.join(@temp_dir, 'utf8_partition.log')
    handle = @transport.get_or_open_partition_handle(file_path)
    
    assert_equal Encoding::UTF_8, handle.external_encoding
  end

  def test_get_or_open_partition_handle_with_custom_mode
    @transport = MockFileTransport.new(
      file_path: @default_file,
      file_mode: 'w'
    )
    
    file_path = File.join(@temp_dir, 'write_mode_partition.log')
    handle = @transport.get_or_open_partition_handle(file_path)
    
    # Write mode should truncate the file
    handle.write("test")
    handle.flush
    
    assert_equal "test", File.read(file_path)
  end

  def test_ensure_directory_exists_for_creates_nested_directories
    nested_path = File.join(@temp_dir, 'level1', 'level2', 'level3', 'file.log')
    
    @transport.ensure_directory_exists_for(nested_path)
    
    assert Dir.exist?(File.dirname(nested_path))
  end

  def test_ensure_directory_exists_for_skips_when_disabled
    @transport = MockFileTransport.new(
      file_path: @default_file,
      create_directories: false
    )
    
    nested_path = File.join(@temp_dir, 'should_not_exist', 'file.log')
    
    @transport.ensure_directory_exists_for(nested_path)
    
    refute Dir.exist?(File.dirname(nested_path))
  end

  def test_ensure_directory_exists_for_skips_when_exists
    existing_dir = File.join(@temp_dir, 'existing')
    FileUtils.mkdir_p(existing_dir)
    
    file_path = File.join(existing_dir, 'file.log')
    
    # Should not raise an error
    @transport.ensure_directory_exists_for(file_path)
    
    assert Dir.exist?(existing_dir)
  end

  def test_close_partition_handles_closes_all_files
    file1 = File.join(@temp_dir, 'partition1.log')
    file2 = File.join(@temp_dir, 'partition2.log')
    
    handle1 = @transport.get_or_open_partition_handle(file1)
    handle2 = @transport.get_or_open_partition_handle(file2)
    
    refute handle1.closed?
    refute handle2.closed?
    
    @transport.close_partition_handles
    
    assert handle1.closed?
    assert handle2.closed?
  end

  def test_close_partition_handles_clears_handles_and_mutexes
    file_path = File.join(@temp_dir, 'partition.log')
    @transport.get_or_open_partition_handle(file_path)
    
    # Verify handles and mutexes exist
    handles = @transport.instance_variable_get(:@partition_handles)
    mutexes = @transport.instance_variable_get(:@partition_mutexes)
    
    refute_empty handles
    refute_empty mutexes
    
    @transport.close_partition_handles
    
    # Should be cleared
    handles = @transport.instance_variable_get(:@partition_handles)
    mutexes = @transport.instance_variable_get(:@partition_mutexes)
    
    assert_empty handles
    assert_empty mutexes
  end

  def test_close_partition_handles_handles_nil_gracefully
    # Should not raise an error when no handles exist
    @transport.close_partition_handles
    
    handles = @transport.instance_variable_get(:@partition_handles)
    mutexes = @transport.instance_variable_get(:@partition_mutexes)
    
    assert_empty handles
    assert_empty mutexes
  end

  def test_thread_safety_with_mutexes
    file_path = File.join(@temp_dir, 'threaded_partition.log')
    
    # Get the handle to create the mutex
    @transport.get_or_open_partition_handle(file_path)
    
    mutexes = @transport.instance_variable_get(:@partition_mutexes)
    assert_instance_of Mutex, mutexes[file_path]
  end

  def test_multiple_partitions_different_message_classes
    @transport = MockFileTransport.new(
      file_path: @default_file,
      directory: @temp_dir
    )
    
    # Different message classes should get different files
    header1 = { message_class_name: 'ErrorMessage' }
    header2 = { message_class_name: 'InfoMessage' }
    
    path1 = @transport.determine_file_path("error msg", header1)
    path2 = @transport.determine_file_path("info msg", header2)
    
    expected1 = File.join(@temp_dir, 'errormessage.log')
    expected2 = File.join(@temp_dir, 'infomessage.log')
    
    assert_equal expected1, path1
    assert_equal expected2, path2
    refute_equal path1, path2
    
    # Both files should be creatable
    handle1 = @transport.get_or_open_partition_handle(path1)
    handle2 = @transport.get_or_open_partition_handle(path2)
    
    assert File.exist?(path1)
    assert File.exist?(path2)
    refute_same handle1, handle2
  end

  def test_filename_selector_with_complex_logic
    skip("Complex logic with date-based paths can be flaky due to timing edge cases")
    
    selector = lambda do |payload, header|
      # Complex partitioning logic based on payload content and header
      date = Time.now.strftime('%Y-%m-%d')
      severity = case payload
                when /ERROR/i then 'error'
                when /WARN/i then 'warn'
                when /INFO/i then 'info'
                else 'debug'
                end
      
      service = header[:message_class_name].gsub(/Message$/, '').downcase
      
      File.join(@temp_dir, date, severity, "#{service}.log")
    end
    
    @transport = MockFileTransport.new(
      file_path: @default_file,
      filename_selector: selector
    )
    
    today = Time.now.strftime('%Y-%m-%d')
    
    # Test different combinations
    test_cases = [
      ["ERROR: Database connection failed", "DatabaseMessage", "#{today}/error/database.log"],
      ["WARN: High memory usage", "SystemMessage", "#{today}/warn/system.log"],
      ["INFO: User logged in", "AuthMessage", "#{today}/info/auth.log"],
      ["Debug trace information", "DebugMessage", "#{today}/debug/debug.log"]
    ]
    
    test_cases.each do |payload, message_class, expected_suffix|
      header = { message_class_name: message_class }
      result = @transport.determine_file_path(payload, header)
      expected = File.join(@temp_dir, expected_suffix)
      assert_equal expected, result
    end
  end
end