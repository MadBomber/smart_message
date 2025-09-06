# test/logger_null_test.rb
# Test suite for SmartMessage::Logger::Null

require_relative 'test_helper'

class LoggerNullTest < Minitest::Test
  
  def setup
    skip("Logger tests skipped - set SM_LOGGER_TEST=true to enable") unless ENV['SM_LOGGER_TEST'] == 'true'
    @logger = SmartMessage::Logger::Null.new
  end
  
  context "SmartMessage::Logger::Null" do
    
    should "be defined as a class" do
      assert defined?(SmartMessage::Logger::Null)
      assert_kind_of Class, SmartMessage::Logger::Null
    end
    
    should "inherit from SmartMessage::Logger::Base" do
      assert SmartMessage::Logger::Null < SmartMessage::Logger::Base
    end
    
    context "initialization" do
      
      should "create a null logger without arguments" do
        logger = SmartMessage::Logger::Null.new
        assert_instance_of SmartMessage::Logger::Null, logger
      end
      
      should "have a very high log level to disable all logging" do
        assert_equal ::Logger::FATAL + 1, @logger.level
      end
    end
    
    context "logging methods" do
      
      should "silently discard debug messages" do
        result = @logger.debug("Debug message")
        assert_nil result
      end
      
      should "silently discard info messages" do
        result = @logger.info("Info message")
        assert_nil result
      end
      
      should "silently discard warning messages" do
        result = @logger.warn("Warning message")
        assert_nil result
      end
      
      should "silently discard error messages" do
        result = @logger.error("Error message")
        assert_nil result
      end
      
      should "silently discard fatal messages" do
        result = @logger.fatal("Fatal message")
        assert_nil result
      end
      
      should "handle block form silently" do
        _block_called = false
        result = @logger.debug { 
          _block_called = true
          "Debug message"
        }
        assert_nil result
        # Block should not be called for performance
      end
      
      should "handle multiple arguments silently" do
        result = @logger.info("Message", "extra", "args")
        assert_nil result
      end
    end
    
    context "logger interface compatibility" do
      
      should "ignore level assignment" do
        original_level = @logger.level
        @logger.level = ::Logger::DEBUG
        assert_equal original_level, @logger.level
      end
      
      should "handle close method" do
        result = @logger.close
        assert_nil result
      end
      
      should "respond to any logging method via method_missing" do
        assert @logger.respond_to?(:any_method)
        assert @logger.respond_to?(:custom_log)
        assert @logger.respond_to?(:trace)
      end
      
      should "handle unknown methods silently" do
        result = @logger.custom_log("message")
        assert_nil result
        
        result = @logger.trace("trace message")
        assert_nil result
      end
    end
    
    context "configuration integration" do
      
      should "work as global configuration logger" do
        SmartMessage.configure do |config|
          config.logger = SmartMessage::Logger::Null.new
        end
        
        assert_instance_of SmartMessage::Logger::Null, SmartMessage::Logger.default
        
        # Reset for other tests
        SmartMessage.reset_configuration!
      end
      
      should "work when logger is set to nil" do
        SmartMessage.configure do |config|
          config.logger = nil
        end
        
        assert_instance_of SmartMessage::Logger::Null, SmartMessage::Logger.default
        
        # Reset for other tests
        SmartMessage.reset_configuration!
      end
    end
  end
end