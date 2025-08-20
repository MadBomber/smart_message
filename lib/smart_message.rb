# lib/smart_message.rb
# encoding: utf-8
# frozen_string_literal: true

require 'zeitwerk'

# FIXME: handle this better
class MilClass  # IMO nil is the same as an empty String
  def to_s
    ''
  end
end

require 'active_support/core_ext/string/inflections'
require 'date'  # STDLIB
require 'hashie'         # Your friendly neighborhood hash library.

# Set up Zeitwerk autoloader
loader = Zeitwerk::Loader.for_gem
loader.tag = "smart_message"
loader.ignore("#{__dir__}/simple_stats.rb")
loader.setup

# Load simple_stats manually since it's not following the naming convention
require_relative './simple_stats'

# SmartMessage abstracts messages from the backend transport process
module SmartMessage
  class << self
    # Global configuration for SmartMessage
    # 
    # Usage:
    #   SmartMessage.configure do |config|
    #     config.logger = MyApp::Logger.new
    #     config.transport = MyApp::Transport.new
    #     config.serializer = MyApp::Serializer.new
    #   end
    def configure
      yield(configuration)
    end
    
    # Get the global configuration instance
    def configuration
      @configuration ||= Configuration.new
    end
    
    # Reset global configuration to defaults
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
  # Module definitions for Zeitwerk to populate
  module Serializer
    class << self
      def default
        # Check global configuration first, then fall back to framework default
        SmartMessage.configuration.default_serializer
      end
    end
  end

  module Logger
    class << self
      def default
        # Check global configuration first, then fall back to framework default
        SmartMessage.configuration.default_logger
      end
    end
  end
  
  module Transport
    class << self
      def default
        # Check global configuration first, then fall back to framework default
        SmartMessage.configuration.default_transport
      end
      
      def registry
        @registry ||= Registry.new
      end

      def register(name, transport_class)
        registry.register(name, transport_class)
      end

      def get(name)
        registry.get(name)
      end

      def create(name, **options)
        transport_class = get(name)
        transport_class&.new(**options)
      end

      def available
        registry.list
      end
    end
  end
end # module SmartMessage

# Don't eager load initially - let Zeitwerk handle lazy loading