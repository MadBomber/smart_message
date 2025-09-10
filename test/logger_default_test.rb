# test/logger_default_test.rb
# Test suite for SmartMessage::Logger::Default

require_relative 'test_helper'
require 'fileutils'
require 'tempfile'
require 'pathname'

class LoggerDefaultTest < Minitest::Test
  
  def setup
    skip("Logger tests skipped - set SM_LOGGER_TEST=true to enable") unless ENV['SM_LOGGER_TEST'] == 'true'
    # Create a temporary directory for log files
    @temp_dir = Dir.mktmpdir('smart_message_test')
    @log_file = File.join(@temp_dir, 'test.log')
    
  end
  
  def teardown
    # Clean up temporary directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    
    # Clean up only the test log file, not the entire log directory
    test_log_file = 'log/smart_message.log'
    File.delete(test_log_file) if File.exist?(test_log_file)
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
        _logger = SmartMessage::Logger::Default.new(log_file: log_path)
        
        assert Dir.exist?(File.dirname(log_path))
      end
    end
    
    context "Ruby logger setup" do
      
      should "always use Ruby Logger (no Rails detection)" do
        logger = SmartMessage::Logger::Default.new(log_file: @log_file)
        
        # Should always use standard Ruby logger
        assert_instance_of Logger, logger.logger
      end
      
      should "use default log level of INFO" do
        logger = SmartMessage::Logger::Default.new(log_file: @log_file)
        
        assert_equal Logger::INFO, logger.level
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
        # Ensure log file doesn't exist (but don't remove entire directory)
        test_log_file = 'log/smart_message.log'
        File.delete(test_log_file) if File.exist?(test_log_file)
        Dir.rmdir('log') if Dir.exist?('log') && Dir.empty?('log')
        
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
      
    end
    
    context "integration with SmartMessage::Base" do
      
      setup do
        @log_file = File.join(@temp_dir, 'integration_test.log')
        
        # Define a test message class
        @message_class = Class.new(SmartMessage::Base) do
          from 'test-service'
          property :content
          
          def self.name
            "IntegrationTestMessage"
          end
        end
      end
      
      teardown do
        # Clean up class-level logger to prevent test pollution
        @message_class.reset_logger if @message_class
      end
      
      should "work as a logger plugin in message configuration" do
        @message_class.config do
          transport SmartMessage::Transport::StdoutTransport.new(loopback: false)
          logger SmartMessage::Logger::Default.new(log_file: @log_file)
        end
        
        assert_instance_of SmartMessage::Logger::Default, @message_class.logger
      end
      
      
      should "use global default logger when none configured" do
        # Explicitly reset logger to ensure clean state
        @message_class.reset_logger
        
        @message_class.config do
          transport SmartMessage::Transport::StdoutTransport.new(loopback: false)
          # No logger configured
        end
        
        # Should fall back to global default logger (Lumberjack)
        assert_instance_of SmartMessage::Logger::Lumberjack, @message_class.logger
        
        # Should not raise errors when no logger is explicitly configured
        message = @message_class.new(content: "test")
        # Message should be created successfully
        refute_nil message
      end
    end
    
  end
  
  # Helper classes for testing
  class TestMessage; end
  class TestTransport; end
end
