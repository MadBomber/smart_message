# lib/smart_message/logger/base.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage::Logger
  class Base
    # Standard logging methods that subclasses should implement
    def debug(message = nil, &block)
      raise NotImplementedError, "Subclass must implement #debug"
    end

    def info(message = nil, &block)
      raise NotImplementedError, "Subclass must implement #info"
    end

    def warn(message = nil, &block)
      raise NotImplementedError, "Subclass must implement #warn"
    end

    def error(message = nil, &block)
      raise NotImplementedError, "Subclass must implement #error"
    end

    def fatal(message = nil, &block)
      raise NotImplementedError, "Subclass must implement #fatal"
    end
  end
end # module SmartMessage::Logger