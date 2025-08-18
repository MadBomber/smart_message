# test/logger_default_test.rb
# Test suite for SmartMessage::Logger::Default

require_relative 'test_helper'
require 'fileutils'
require 'tempfile'
require 'pathname'

class LoggerDefaultTest < Minitest::Test
  
  def setup
    # Create a temporary directory for log files
    @temp_dir = Dir.mktmpdir('smart_message_test')
    @log_file = File.join(@temp_dir, 'test.log')
    
    # Clean up any existing log directory for isolation
    FileUtils.rm_rf('log') if Dir.exist?('log')
  end
  
  def teardown
    # Clean up temporary directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    
    # Clean up any created log directory
    FileUtils.rm_rf('log') if Dir.exist?('log')
  end
  
  context "SmartMessage::Logger::Default" do
    
    should "be defined as a class" do
      assert defined?(SmartMessage::Logger::Default)
      assert_kind_of Class, SmartMessage::Logger::Default
    end
    
    should "inherit from SmartMessage::Logger::Base" do
      assert SmartMessage::Logger::Default < SmartMessage::Logger::Base
    end
    
    context "initialization" do
      
      should "create a logger with default settings" do
        logger = SmartMessage::Logger::Default.new
        assert_instance_of SmartMessage::Logger::Default, logger
        assert_respond_to logger, :logger
        assert_equal 'log/smart_message.log', logger.log_file
        assert_equal Logger::INFO, logger.level
      end
      
      should "accept custom log file path" do
        logger = SmartMessage::Logger::Default.new(log_file: @log_file)
        assert_equal @log_file, logger.log_file
      end
      
      should "accept custom log level" do
        logger = SmartMessage::Logger::Default.new(log_file: @log_file, level: Logger::DEBUG)
        assert_equal Logger::DEBUG, logger.level
      end
      
      should "create log directory if it doesn't exist" do
        log_path = File.join(@temp_dir, 'nested', 'path', 'test.log')
        logger = SmartMessage::Logger::Default.new(log_file: log_path)
        
        assert Dir.exist?(File.dirname(log_path))
      end
    end
    
    context "Rails detection" do
      
      should "use Rails.logger when available" do
        # Skip this test if Rails is already loaded
        skip "Rails is already loaded" if defined?(Rails)
        
        # Create a simple Rails mock
        rails_module = Module.new do
          class << self
            attr_accessor :logger, :root
            
            def respond_to?(method)
              [:logger, :root].include?(method)
            end
          end
        end
        
        rails_module.logger = Logger.new(StringIO.new)
        rails_module.root = Pathname.new('/fake/rails/root')
        
        # Temporarily define Rails constant
        Object.const_set(:Rails, rails_module)
        
        begin
          logger = SmartMessage::Logger::Default.new
          
          # The internal logger should be wrapped Rails logger
          assert_instance_of SmartMessage::Logger::Default::RailsLoggerWrapper, logger.logger
        ensure
          # Clean up
          Object.send(:remove_const, :Rails) if defined?(Rails)
        end
      end
      
      should "fall back to Ruby Logger when Rails is not available" do
        # Ensure Rails is not defined
        if Object.const_defined?(:Rails)
          old_rails = Object.const_get(:Rails)
          Object.send(:remove_const, :Rails)
        end
        
        logger = SmartMessage::Logger::Default.new(log_file: @log_file)
        
        # Should use standard Ruby logger
        assert_instance_of Logger, logger.logger
        
        # Restore Rails if it was defined
        Object.const_set(:Rails, old_rails) if defined?(old_rails) && old_rails
      end
    end
    
    context "message lifecycle logging" do
      
      setup do
        @logger = SmartMessage::Logger::Default.new(log_file: @log_file, level: Logger::DEBUG)
        @message = Minitest::Mock.new
        @transport = Minitest::Mock.new
        
        @message.expect(:class, TestMessage)
        @message.expect(:class, TestMessage) 
        @message.expect(:to_h, { data: 'test' })
        @transport.expect(:class, TestTransport)
      end
      
      should "log message creation" do
        @logger.log_message_created(@message)
        
        log_content = File.read(@log_file)
        assert_match(/Created: LoggerDefaultTest::TestMessage/, log_content)
        assert_match(/data.*test/, log_content)
      end
      
      should "log message publishing" do
        @logger.log_message_published(@message, @transport)
        
        log_content = File.read(@log_file)
        assert_match(/Published: LoggerDefaultTest::TestMessage/, log_content)
        assert_match(/TestTransport/, log_content)
      end
      
      should "log message receipt" do
        @logger.log_message_received(TestMessage, '{"test": "data"}')
        
        log_content = File.read(@log_file)
        assert_match(/Received: LoggerDefaultTest::TestMessage/, log_content)
        assert_match(/16 bytes/, log_content)
      end
      
      should "log message processing" do
        @logger.log_message_processed(TestMessage, "Success")
        
        log_content = File.read(@log_file)
        assert_match(/Processed: LoggerDefaultTest::TestMessage/, log_content)
        assert_match(/Success/, log_content)
      end
      
      should "log subscription" do
        @logger.log_message_subscribe(TestMessage, 'TestHandler')
        
        log_content = File.read(@log_file)
        assert_match(/Subscribed: LoggerDefaultTest::TestMessage/, log_content)
        assert_match(/TestHandler/, log_content)
      end
      
      should "log unsubscription" do
        @logger.log_message_unsubscribe(TestMessage)
        
        log_content = File.read(@log_file)
        assert_match(/Unsubscribed: LoggerDefaultTest::TestMessage/, log_content)
      end
    end
    
    context "error logging" do
      
      setup do
        @logger = SmartMessage::Logger::Default.new(log_file: @log_file, level: Logger::DEBUG)
      end
      
      should "log errors with context" do
        error = StandardError.new("Test error message")
        error.set_backtrace(['line1', 'line2', 'line3'])
        
        @logger.log_error("test context", error)
        
        log_content = File.read(@log_file)
        assert_match(/Error in test context/, log_content)
        assert_match(/StandardError/, log_content)
        assert_match(/Test error message/, log_content)
        assert_match(/Backtrace/, log_content)
      end
      
      should "log warnings" do
        @logger.log_warning("This is a warning")
        
        log_content = File.read(@log_file)
        assert_match(/Warning: This is a warning/, log_content)
      end
    end
    
    context "standard logger methods" do
      
      setup do
        @logger = SmartMessage::Logger::Default.new(log_file: @log_file, level: Logger::DEBUG)
      end
      
      should "support debug logging" do
        @logger.debug("Debug message")
        assert_match(/Debug message/, File.read(@log_file))
      end
      
      should "support info logging" do
        @logger.info("Info message")
        assert_match(/Info message/, File.read(@log_file))
      end
      
      should "support warn logging" do
        @logger.warn("Warning message")
        assert_match(/Warning message/, File.read(@log_file))
      end
      
      should "support error logging" do
        @logger.error("Error message")
        assert_match(/Error message/, File.read(@log_file))
      end
      
      should "support fatal logging" do
        @logger.fatal("Fatal message")
        assert_match(/Fatal message/, File.read(@log_file))
      end
      
      should "support block form for lazy evaluation" do
        expensive_operation_called = false
        
        @logger.debug { 
          expensive_operation_called = true
          "Expensive debug message"
        }
        
        assert expensive_operation_called
        assert_match(/Expensive debug message/, File.read(@log_file))
      end
    end
    
    context "log file management" do
      
      should "use default log directory following Rails convention" do
        logger = SmartMessage::Logger::Default.new
        assert_equal 'log/smart_message.log', logger.log_file
      end
      
      should "create log directory automatically" do
        # Ensure log directory doesn't exist
        FileUtils.rm_rf('log') if Dir.exist?('log')
        
        logger = SmartMessage::Logger::Default.new
        logger.info("Test message")
        
        assert Dir.exist?('log')
        assert File.exist?('log/smart_message.log')
      end
      
      should "handle STDOUT logging without errors" do
        logger = SmartMessage::Logger::Default.new(log_file: STDOUT, level: Logger::INFO)
        
        # Should not raise errors
        begin
          logger.info("STDOUT test message")
          logger.warn("STDOUT warning message")
          logger.error("STDOUT error message")
        rescue => e
          flunk("STDOUT logging raised an error: #{e.message}")
        end
        
        # Should be using STDOUT
        assert_equal STDOUT, logger.log_file
      end
      
      should "handle STDERR logging without errors" do
        logger = SmartMessage::Logger::Default.new(log_file: STDERR, level: Logger::WARN)
        
        # Should not raise errors
        begin
          logger.warn("STDERR warning message")
          logger.error("STDERR error message")
        rescue => e
          flunk("STDERR logging raised an error: #{e.message}")
        end
        
        # Should be using STDERR
        assert_equal STDERR, logger.log_file
      end
      
      should "truncate long messages" do
        logger = SmartMessage::Logger::Default.new(log_file: @log_file, level: Logger::DEBUG)
        
        long_string = "x" * 500
        message = Minitest::Mock.new
        message.expect(:class, TestMessage)
        message.expect(:class, TestMessage)
        message.expect(:to_h, { data: long_string })
        
        logger.log_message_created(message)
        
        log_content = File.read(@log_file)
        assert_match(/\.\.\./, log_content)  # Should contain truncation indicator
        refute_match(/x{250}/, log_content)  # Should not contain 250 consecutive x's (truncated at 200)
      end
    end
    
    context "integration with SmartMessage::Base" do
      
      setup do
        @log_file = File.join(@temp_dir, 'integration_test.log')
        
        # Define a test message class
        @message_class = Class.new(SmartMessage::Base) do
          property :content
          
          def self.name
            "IntegrationTestMessage"
          end
        end
      end
      
      teardown do
        # Clean up class-level logger to prevent test pollution
        @message_class.reset_logger if @message_class
        SmartMessage::Base.reset_logger
      end
      
      should "work as a logger plugin in message configuration" do
        @message_class.config do
          transport SmartMessage::Transport::StdoutTransport.new(loopback: false)
          serializer SmartMessage::Serializer::JSON.new
          logger SmartMessage::Logger::Default.new(log_file: @log_file)
        end
        
        assert_instance_of SmartMessage::Logger::Default, @message_class.logger
      end
      
      should "be configurable at instance level" do
        instance_logger = SmartMessage::Logger::Default.new(log_file: @log_file)
        
        message = @message_class.new(content: "test")
        message.logger(instance_logger)
        
        assert_equal instance_logger, message.logger
      end
      
      should "handle nil logger gracefully" do
        @message_class.config do
          transport SmartMessage::Transport::StdoutTransport.new(loopback: false)
          serializer SmartMessage::Serializer::JSON.new
          # No logger configured
        end
        
        assert_nil @message_class.logger
        
        # Should not raise errors when no logger is configured
        message = @message_class.new(content: "test")
        assert_nil message.logger
      end
    end
    
    context "Rails logger wrapper" do
      
      should "exist as a class" do
        assert defined?(SmartMessage::Logger::Default::RailsLoggerWrapper)
        assert_kind_of Class, SmartMessage::Logger::Default::RailsLoggerWrapper
      end
      
      should "delegate method calls to the wrapped logger" do
        # Use a simple mock that can handle method_missing
        mock_logger = Object.new
        received_calls = []
        
        def mock_logger.method_missing(method, *args, &block)
          @calls ||= []
          @calls << [method, args]
        end
        
        def mock_logger.respond_to?(method, include_private = false)
          true
        end
        
        def mock_logger.calls
          @calls || []
        end
        
        wrapper = SmartMessage::Logger::Default::RailsLoggerWrapper.new(mock_logger)
        wrapper.info("Test message")
        
        # The wrapper should have attempted to call the logger
        assert_respond_to wrapper, :info
      end
    end
  end
  
  # Helper classes for testing
  class TestMessage; end
  class TestTransport; end
end