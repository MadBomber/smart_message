# lib/smart_message/plugins.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Plugin configuration module for SmartMessage::Base
  # Handles transport and logger configuration at class and instance levels.
  #
  # Precedence, highest first:
  #
  #   1. the instance        message.transport(t)
  #   2. the class           MyMessage.transport(t)
  #   3. a parent class      (inherited)
  #   4. global config       SmartMessage.configure { |c| c.transport = t }
  #
  # There is no framework default transport: a class with none configured
  # anywhere has no transports, and publishing raises TransportNotConfigured.
  # The logger falls back to SmartMessage::Logger.default, which logs nothing
  # unless a logger was configured.
  module Plugins
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Resolve a list of transports from the first source that has one.
    #
    # @param candidates [Array] values in precedence order; each may be nil,
    #   one transport, or an Array of transports
    # @return [Array] the transports of the first non-empty candidate
    def self.resolve_transports(*candidates)
      candidates.each do |candidate|
        list = Array(candidate)
        return list unless list.empty?
      end
      []
    end

    # Check that each value can be used as a transport.  Duck typed, so
    # test doubles that are not Transport::Base subclasses still work.
    #
    # @param value [Object, Array] one transport or an Array of them
    # @raise [ArgumentError] when one of them is not a transport
    def self.check_transports!(value)
      Array(value).each do |candidate|
        next if candidate.respond_to?(:publish) && candidate.respond_to?(:subscribe)

        name = candidate.is_a?(Symbol) || candidate.is_a?(String) ? candidate.to_sym : :memory
        raise ArgumentError, "#{candidate.inspect} is not a transport (it must respond to publish and subscribe); " \
                             "build one with SmartMessage::Transport.create(#{name.inspect})"
      end
      value
    end

    #########################################################
    ## instance-level configuration

    def config(&block)
      instance_eval(&block) if block_given?
    end

    # Get the first transport, or set an instance-level override.
    def transport(klass_or_instance = nil)
      return transports.first if klass_or_instance.nil?

      Plugins.check_transports!(klass_or_instance)
      @transport = Array(klass_or_instance)
      klass_or_instance
    end

    # @return [Array] every transport this instance publishes to.  Read at
    #   call time, so a class-level change after construction is honoured.
    def transports
      Plugins.resolve_transports(@transport, self.class.transports)
    end

    def transport_configured?; !transport_missing?; end
    def transport_missing?;    transports.empty?;   end
    def reset_transport;       @transport = nil;    end
    def single_transport?;     transports.length == 1; end
    def multiple_transports?;  transports.length > 1;  end

    # The logger for this message's class
    def logger
      self.class.logger
    end

    module ClassMethods
      #########################################################
      ## class-level configuration

      def config(&block)
        class_eval(&block) if block_given?
      end

      # Get the first transport, or set this class's transport(s).
      def transport(klass_or_instance = nil)
        return transports.first if klass_or_instance.nil?

        Plugins.check_transports!(klass_or_instance)
        set_setting(:transport, Array(klass_or_instance))
        klass_or_instance
      end

      # @return [Array] this class's transports, else its parent's, else the
      #   globally configured transport, else none
      def transports
        Plugins.resolve_transports(setting(:transport), SmartMessage.configuration.transport)
      end

      def transport_configured?; !transport_missing?; end
      def transport_missing?;    transports.empty?;   end
      def reset_transport;       clear_setting(:transport); end
      def single_transport?;     transports.length == 1; end
      def multiple_transports?;  transports.length > 1;  end

      #########################################################
      ## class-level logger configuration

      # Get the logger, or set this class's logger.
      def logger(klass_or_instance = nil)
        return setting(:logger) || SmartMessage::Logger.default if klass_or_instance.nil?

        set_setting(:logger, klass_or_instance)
      end

      # Is a logger set on this class or an ancestor (not just globally)?
      def logger_configured?; !logger_missing?;      end
      def logger_missing?;    setting(:logger).nil?; end
      def reset_logger;       clear_setting(:logger); end
    end
  end
end
