# lib/smart_message/base.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom'   # STDLIB

require_relative './wrapper.rb'
require_relative './property_descriptions.rb'
require_relative './property_validations.rb'

module SmartMessage
  # The foundation class for the smart message
  class Base < Hashie::Dash

    # Supports multi-level plugins for transport, serializer and logger.
    # Plugins can be made at the class level and at the instance level.
    @@transport   = nil
    @@serializer  = nil
    @@logger      = nil
    
    # Class-level addressing configuration - use a registry for per-class isolation
    @@addressing_registry = {}
    
    # Registry for proc-based message handlers
    @@proc_handlers = {}
    
    # Class-level version setting
    class << self
      attr_accessor :_version
      
      def version(v = nil)
        if v.nil?
          @_version || 1  # Default to version 1 if not set
        else
          @_version = v
          
          # Set up version validation for the header
          # This ensures that the header version matches the expected class version
          @expected_header_version = v
        end
      end
      
      def expected_header_version
        @expected_header_version || 1
      end
    end

    include Hashie::Extensions::Dash::PropertyTranslation

    include SmartMessage::PropertyDescriptions
    include SmartMessage::PropertyValidations

    include Hashie::Extensions::Coercion
    include Hashie::Extensions::DeepMerge
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::IndifferentAccess
    # MergeInitializer interferes with required property validation - removed
    include Hashie::Extensions::MethodAccess

    # Common attrubutes for all messages
    # TODO: Need to change the SmartMessage::Header into a
    #       smartMessage::Wrapper concept where the message
    #       content is serialized into an element in the wrapper
    #       where the wrapper contains header/routing information
    #       in addition to the serialized message data.
    property :_sm_header

    # Constructor for a messsage definition that allows the
    # setting of initial values.
    def initialize(**props, &block)
      # instance-level over ride of class plugins
      @transport   = nil
      @serializer  = nil
      @logger      = nil
      
      # Extract addressing information from props before creating header
      addressing_props = props.extract!(:from, :to, :reply_to)
      
      # instance-level over ride of class addressing
      @from        = addressing_props[:from]
      @to          = addressing_props[:to] 
      @reply_to    = addressing_props[:reply_to]

      # Create header with version validation specific to this message class
      header = SmartMessage::Header.new(
        uuid:           SecureRandom.uuid,
        message_class:  self.class.to_s,
        published_at:   Time.now,
        publisher_pid:  Process.pid,
        version:        self.class.version,
        from:           from,
        to:             to,
        reply_to:       reply_to
      )
      
      # Set up version validation to match the expected class version
      expected_version = self.class.expected_header_version
      header.singleton_class.class_eval do
        define_method(:validate_version!) do
          unless self.version == expected_version
            raise SmartMessage::Errors::ValidationError, 
              "Header version must be #{expected_version}, got: #{self.version}"
          end
        end
      end
      
      attributes = {
        _sm_header: header
      }.merge(props)

      super(attributes, &block)
    end


    ###################################################
    ## Common instance methods
    
    # Validate that the header version matches the expected version for this class
    def validate_header_version!
      expected = self.class.expected_header_version
      actual = _sm_header.version
      unless actual == expected
        raise SmartMessage::Errors::ValidationError,
          "#{self.class.name} expects version #{expected}, but header has version #{actual}"
      end
    end

    # Override PropertyValidations validate! to include header and version validation
    def validate!
      # Validate message properties using PropertyValidations
      super
      
      # Validate header properties
      _sm_header.validate!
      
      # Validate header version matches expected class version  
      validate_header_version!
    end

    # Override PropertyValidations validation_errors to include header errors
    def validation_errors
      errors = []
      
      # Get message property validation errors using PropertyValidations
      errors.concat(super.map { |err| 
        err.merge(source: 'message') 
      })
      
      # Get header validation errors
      errors.concat(_sm_header.validation_errors.map { |err| 
        err.merge(source: 'header') 
      })
      
      # Check version mismatch
      expected = self.class.expected_header_version
      actual = _sm_header.version
      unless actual == expected
        errors << {
          property: :version,
          value: actual,
          message: "Expected version #{expected}, got: #{actual}",
          source: 'version_mismatch'
        }
      end
      
      errors
    end

    # SMELL: How does the transport know how to decode a message before
    #        it knows the message class?  We need a wrapper around
    #        the entire message in a known serialization.  That
    #        wrapper would contain two properties: _sm_header and
    #        _sm_payload

    # NOTE: to publish a message it must first be encoded using a
    #       serializer.  The receive a subscribed to message it must
    #       be decoded via a serializer from the transport to be processed.
    def encode
      raise Errors::SerializerNotConfigured if serializer_missing?

      serializer.encode(self)
    end


    # NOTE: you publish instances; but, you subscribe/unsubscribe at
    #       the class-level
    def publish
      # Validate the complete message before publishing (now uses overridden validate!)
      validate!
      
      # TODO: move all of the _sm_ property processes into the wrapper
      _sm_header.published_at   = Time.now
      _sm_header.publisher_pid  = Process.pid

      payload = encode

      raise Errors::TransportNotConfigured if transport_missing?
      transport.publish(_sm_header, payload)

      SS.add(_sm_header.message_class, 'publish')
      SS.get(_sm_header.message_class, 'publish')
    end # def publish



    #########################################################
    ## instance-level configuration

    # Configure the plugins for transport, serializer and logger
    def config(&block)
      instance_eval(&block) if block_given?
    end


    #########################################################
    ## instance-level transport configuration

    def transport(klass_or_instance = nil)
      klass_or_instance.nil? ? @transport || @@transport : @transport = klass_or_instance
    end

    def transport_configured?;  !transport.nil?;   end
    def transport_missing?;      transport.nil?;   end
    def reset_transport;        @transport = nil;  end


    #########################################################
    ## instance-level logger configuration

    def logger(klass_or_instance = nil)
      klass_or_instance.nil? ? @logger || @@logger : @logger = klass_or_instance
    end

    def logger_configured?;     !logger.nil?; end
    def logger_missing?;         logger.nil?; end
    def reset_logger;           @logger = nil;  end


    #########################################################
    ## instance-level serializer configuration

    def serializer(klass_or_instance = nil)
      klass_or_instance.nil? ? @serializer || @@serializer : @serializer = klass_or_instance
    end

    def serializer_configured?; !serializer.nil?;   end
    def serializer_missing?;     serializer.nil?;   end
    def reset_serializer;       @serializer = nil;  end


    #########################################################
    ## instance-level addressing configuration

    def from(entity_id = nil)
      if entity_id.nil?
        @from || self.class.from
      else
        @from = entity_id
        # Update the header with the new value
        _sm_header.from = entity_id if _sm_header
      end
    end
    
    def from_configured?; !from.nil?; end
    def from_missing?;     from.nil?; end
    def reset_from;       
      @from = nil
      _sm_header.from = nil if _sm_header
    end

    def to(entity_id = nil)
      if entity_id.nil?
        @to || self.class.to
      else
        @to = entity_id
        # Update the header with the new value
        _sm_header.to = entity_id if _sm_header
      end
    end
    
    def to_configured?;   !to.nil?; end
    def to_missing?;       to.nil?; end
    def reset_to;         
      @to = nil
      _sm_header.to = nil if _sm_header
    end

    def reply_to(entity_id = nil)
      if entity_id.nil?
        @reply_to || self.class.reply_to
      else
        @reply_to = entity_id
        # Update the header with the new value
        _sm_header.reply_to = entity_id if _sm_header
      end
    end
    
    def reply_to_configured?; !reply_to.nil?; end
    def reply_to_missing?;     reply_to.nil?; end
    def reset_reply_to;       
      @reply_to = nil
      _sm_header.reply_to = nil if _sm_header
    end


    #########################################################
    ## instance-level utility methods

    # return this class' name as a string
    def whoami
      self.class.to_s
    end

    # return this class' description
    def description
      self.class.description
    end


    # returns a collection of class Set that consists of
    # the symbolized values of the property names of the message
    # without the injected '_sm_' properties that support
    # the behind-the-sceens operations of SmartMessage.
    def fields
      to_h.keys
          .reject{|key| key.start_with?('_sm_')}
          .map{|key| key.to_sym}
          .to_set
    end


    ###########################################################
    ## class methods

    class << self

      #########################################################
      ## class-level description
      
      def description(desc = nil)
        if desc.nil?
          @description || "#{self.name} is a SmartMessage"
        else
          @description = desc.to_s
        end
      end

      #########################################################
      ## class-level configuration

      def config(&block)
        class_eval(&block) if block_given?
      end


      #########################################################
      ## proc handler management

      # Register a proc handler and return a unique identifier for it
      # @param message_class [String] The message class name
      # @param handler_proc [Proc] The proc to register
      # @return [String] Unique identifier for this handler
      def register_proc_handler(message_class, handler_proc)
        handler_id = "#{message_class}.proc_#{SecureRandom.hex(8)}"
        @@proc_handlers[handler_id] = handler_proc
        handler_id
      end

      # Call a registered proc handler
      # @param handler_id [String] The handler identifier
      # @param message_header [SmartMessage::Header] The message header
      # @param message_payload [String] The message payload
      def call_proc_handler(handler_id, message_header, message_payload)
        handler_proc = @@proc_handlers[handler_id]
        return unless handler_proc

        handler_proc.call(message_header, message_payload)
      end

      # Remove a proc handler from the registry
      # @param handler_id [String] The handler identifier to remove
      def unregister_proc_handler(handler_id)
        @@proc_handlers.delete(handler_id)
      end

      # Check if a handler ID refers to a proc handler
      # @param handler_id [String] The handler identifier
      # @return [Boolean] True if this is a proc handler
      def proc_handler?(handler_id)
        @@proc_handlers.key?(handler_id)
      end


      #########################################################
      ## class-level transport configuration

      def transport(klass_or_instance = nil)
        klass_or_instance.nil? ? @@transport : @@transport = klass_or_instance
      end

      def transport_configured?;  !transport.nil?;   end
      def transport_missing?;      transport.nil?;   end
      def reset_transport;       @@transport = nil;  end


      #########################################################
      ## class-level logger configuration

      def logger(klass_or_instance = nil)
        klass_or_instance.nil? ? @@logger : @@logger = klass_or_instance
      end

      def logger_configured?;     !logger.nil?;   end
      def logger_missing?;         logger.nil?;   end
      def reset_logger;          @@logger = nil;  end


      #########################################################
      ## class-level serializer configuration

      def serializer(klass_or_instance = nil)
        klass_or_instance.nil? ? @@serializer : @@serializer = klass_or_instance
      end

      def serializer_configured?; !serializer.nil?;   end
      def serializer_missing?;     serializer.nil?;   end
      def reset_serializer;      @@serializer = nil;  end


      #########################################################
      ## class-level addressing configuration
      
      # Helper method to normalize filter values (string -> array, nil -> nil)
      private def normalize_filter_value(value)
        case value
        when nil
          nil
        when String
          [value]
        when Array
          value
        else
          raise ArgumentError, "Filter value must be a String, Array, or nil, got: #{value.class}"
        end
      end
      
      # Helper method to find addressing values in the inheritance chain
      private def find_addressing_value(field)
        # Start with current class
        current_class = self
        
        while current_class && current_class.respond_to?(:name)
          class_name = current_class.name || current_class.to_s
          
          # Check registry for this class
          result = @@addressing_registry.dig(class_name, field)
          return result if result
          
          # If we have a proper name but no result, also check the to_s version
          if current_class.name
            alternative_key = current_class.to_s
            result = @@addressing_registry.dig(alternative_key, field)
            return result if result
          end
          
          # Move up the inheritance chain
          current_class = current_class.superclass
          
          # Stop if we reach SmartMessage::Base or above
          break if current_class == SmartMessage::Base || current_class.nil?
        end
        
        nil
      end

      def from(entity_id = nil)
        class_name = self.name || self.to_s
        if entity_id.nil?
          # Try to find the value, checking inheritance chain
          result = find_addressing_value(:from)
          result
        else
          @@addressing_registry[class_name] ||= {}
          @@addressing_registry[class_name][:from] = entity_id
        end
      end
      
      def from_configured?; !from.nil?; end
      def from_missing?;     from.nil?; end
      def reset_from; 
        class_name = self.name || self.to_s
        @@addressing_registry[class_name] ||= {}
        @@addressing_registry[class_name][:from] = nil
      end

      def to(entity_id = nil)
        class_name = self.name || self.to_s
        if entity_id.nil?
          # Try to find the value, checking inheritance chain
          result = find_addressing_value(:to)
          result
        else
          @@addressing_registry[class_name] ||= {}
          @@addressing_registry[class_name][:to] = entity_id
        end
      end
      
      def to_configured?;   !to.nil?; end
      def to_missing?;       to.nil?; end
      def reset_to; 
        class_name = self.name || self.to_s
        @@addressing_registry[class_name] ||= {}
        @@addressing_registry[class_name][:to] = nil
      end

      def reply_to(entity_id = nil)
        class_name = self.name || self.to_s
        if entity_id.nil?
          # Try to find the value, checking inheritance chain
          result = find_addressing_value(:reply_to)
          result
        else
          @@addressing_registry[class_name] ||= {}
          @@addressing_registry[class_name][:reply_to] = entity_id
        end
      end
      
      def reply_to_configured?; !reply_to.nil?; end
      def reply_to_missing?;     reply_to.nil?; end
      def reset_reply_to; 
        class_name = self.name || self.to_s
        @@addressing_registry[class_name] ||= {}
        @@addressing_registry[class_name][:reply_to] = nil
      end


      #########################################################
      ## class-level subscription management via the transport

      # Add this message class to the transport's catalog of
      # subscribed messages.  If the transport is missing, raise
      # an exception.
      #
      # @param process_method [String, Proc, nil] The processing method:
      #   - String: Method name like "MyService.handle_message" 
      #   - Proc: A proc/lambda that accepts (message_header, message_payload)
      #   - nil: Uses default "MessageClass.process" method
      # @param broadcast [Boolean, nil] Filter for broadcast messages (to: nil)
      # @param to [String, Array, nil] Filter for messages directed to specific entities
      # @param from [String, Array, nil] Filter for messages from specific entities
      # @param block [Proc] Alternative way to pass a processing block
      # @return [String] The identifier used for this subscription
      #
      # @example Using default handler (all messages)
      #   MyMessage.subscribe
      #
      # @example Using custom method name with filtering
      #   MyMessage.subscribe("MyService.handle_message", to: 'my-service')
      #
      # @example Using a block with broadcast filtering
      #   MyMessage.subscribe(broadcast: true) do |header, payload|
      #     data = JSON.parse(payload)
      #     puts "Received broadcast: #{data}"
      #   end
      #
      # @example Entity-specific filtering
      #   MyMessage.subscribe(to: 'order-service', from: ['payment', 'user'])
      #
      # @example Broadcast + directed messages
      #   MyMessage.subscribe(to: 'my-service', broadcast: true)
      def subscribe(process_method = nil, broadcast: nil, to: nil, from: nil, &block)
        message_class = whoami
        
        # Handle different parameter types
        if block_given?
          # Block was passed - use it as the handler
          handler_proc = block
          process_method = register_proc_handler(message_class, handler_proc)
        elsif process_method.respond_to?(:call)
          # Proc/lambda was passed as first parameter
          handler_proc = process_method
          process_method = register_proc_handler(message_class, handler_proc)
        elsif process_method.nil?
          # Use default handler
          process_method = message_class + '.process'
        end
        # If process_method is a String, use it as-is

        # Normalize string filters to arrays
        to_filter = normalize_filter_value(to)
        from_filter = normalize_filter_value(from)
        
        # Create filter options
        filter_options = {
          broadcast: broadcast,
          to: to_filter,
          from: from_filter
        }

        # TODO: Add proper logging here

        raise Errors::TransportNotConfigured if transport_missing?
        transport.subscribe(message_class, process_method, filter_options)
        
        process_method
      end


      # Remove this process_method for this message class from the
      # subscribers list.
      # @param process_method [String, nil] The processing method identifier to remove
      #   - String: Method name like "MyService.handle_message" or proc handler ID
      #   - nil: Uses default "MessageClass.process" method
      def unsubscribe(process_method = nil)
        message_class   = whoami
        process_method  = message_class + '.process' if process_method.nil?
        # TODO: Add proper logging here

        if transport_configured?
          transport.unsubscribe(message_class, process_method)
          
          # If this was a proc handler, clean it up from the registry
          if proc_handler?(process_method)
            unregister_proc_handler(process_method)
          end
        end
      end


      # Remove this message class and all of its processing methods
      # from the subscribers list.
      def unsubscribe!
        message_class   = whoami

        # TODO: Add proper logging here

        transport.unsubscribe!(message_class) if transport_configured?
      end



      #########################################################
      ## class-level utility methods

      # return this class' name as a string
      def whoami
        ancestors.first.to_s
      end

      # Return a Set of symbols representing each defined property of
      # this message class.
      def fields
        @properties.dup.delete_if{|item| item.to_s.start_with?('_sm_')}
      end

      ###################################################
      ## Business Logic resides in the #process method.

      # When a transport receives a subscribed to message it
      # creates an instance of the message and then calls
      # the process method on that instance.
      #
      # It is expected that SmartMessage classes over ride
      # the SmartMessage::Base#process method with appropriate
      # business logic to handle the received message content.
      def process(message_instance)
        raise Errors::NotImplemented
      end

    end # class << self
  end # class Base
end # module SmartMessage

require_relative 'header'
require_relative 'transport'
require_relative 'serializer'
require_relative 'logger'
