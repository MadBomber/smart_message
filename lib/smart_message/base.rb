# lib/smart_message/base.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom'   # STDLIB

require_relative './property_descriptions.rb'
require_relative './property_validations.rb'
require_relative './plugins.rb'
require_relative './addressing.rb'
require_relative './subscription.rb'
require_relative './versioning.rb'
require_relative './messaging.rb'
require_relative './utilities.rb'
require_relative './deduplication.rb'

module SmartMessage
  # The foundation class for the smart message
  class Base < Hashie::Dash
    include Hashie::Extensions::Dash::PropertyTranslation

    include SmartMessage::PropertyDescriptions
    include SmartMessage::PropertyValidations
    include SmartMessage::Plugins
    include SmartMessage::Addressing
    include SmartMessage::Subscription
    include SmartMessage::Versioning
    include SmartMessage::Messaging
    include SmartMessage::Utilities
    include SmartMessage::Deduplication

    include Hashie::Extensions::Coercion
    include Hashie::Extensions::DeepMerge
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::IndifferentAccess
    # MergeInitializer interferes with required property validation - removed
    include Hashie::Extensions::MethodAccess

    # Common attrubutes for all messages
    # TODO: This comment is now obsolete - the flat message structure 
    #       has been implemented where header and message properties
    #       exist at the same level in a flat structure.
    property :_sm_header

    # Constructor for a messsage definition that allows the
    # setting of initial values.
    def initialize(**props, &block)
      # instance-level override of class plugins  
      # Don't use fallback defaults here - let the methods handle fallbacks when actually used
      @transport   = (self.class.class_variable_get(:@@transport) rescue nil)

      # Check if we're reconstructing from serialized data (complete header provided)
      if props[:_sm_header]
        # Deserialization path: use provided header and payload
        existing_header = props[:_sm_header]
        
        # Convert to Header object if it's a hash (from deserialization)
        if existing_header.is_a?(Hash)
          # Convert string keys to symbols
          header_hash = existing_header.transform_keys(&:to_sym)
          header = SmartMessage::Header.new(**header_hash)
        else
          header = existing_header
        end
        
        # Extract addressing from header for instance variables
        @from = header.from
        @to = header.to
        @reply_to = header.reply_to
        
        # Extract payload properties directly from props (flat structure)
        payload_props = props.except(:_sm_header)
        
        attributes = {
          _sm_header: header
        }.merge(payload_props)
      else
        # Normal creation path: create new header
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

        attributes = {
          _sm_header: header
        }.merge(props)
      end

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

      super(attributes, &block)

      # Log message creation
      (self.class.logger || SmartMessage::Logger.default).debug { "[SmartMessage] Created: #{self.class.name}" }
    rescue => e
      (self.class.logger || SmartMessage::Logger.default).error { "[SmartMessage] Error in message initialization: #{e.class.name} - #{e.message}" }
      raise
    end

    # Backward compatibility method for proc handlers that expect _sm_payload as JSON string
    # In the new single-tier approach, this recreates the expected format
    def _sm_payload
      require 'json'
      
      # Extract payload properties (non-header properties)
      payload_props = self.class.properties.each_with_object({}) do |prop, hash|
        next if prop == :_sm_header
        hash[prop.to_s] = self[prop]  # Access property value
      end
      
      JSON.generate(payload_props)
    end

    # Backward compatibility method for handlers that expect message.split
    # Returns [header, payload_json] in the old two-tier format
    def split
      [_sm_header, _sm_payload]
    end


    ###################################################
    ## Common instance methods







    # Convert message to hash for serialization
    def to_hash
      # Get all properties and their values
      hash = {}
      self.class.properties.each do |prop|
        hash[prop] = self[prop]
      end
      hash
    end

    ###########################################################
    ## class methods

    class << self
      # Decode a complete serialized message back to a message instance
      # Note: This method is no longer used with transport-based serialization
      # Transports handle decoding and create message instances directly
      # @param serialized_message [String] The serialized message content
      # @return [SmartMessage::Base] The decoded message instance
      def decode(serialized_message)
        begin
          (self.logger || SmartMessage::Logger.default).info { "[SmartMessage] Received: #{self.name} (#{serialized_message.bytesize} bytes)" }

          # This method is deprecated - transports now handle serialization
          # For backward compatibility, try to decode as JSON
          require 'json'
          deserialized_data = JSON.parse(serialized_message)

          # Create new message instance with the complete deserialized data
          if deserialized_data.is_a?(Hash)
            # Convert string keys to symbols for compatibility with keyword arguments
            symbol_props = deserialized_data.transform_keys(&:to_sym)
            
            message = self.new(**symbol_props)

            (self.logger || SmartMessage::Logger.default).debug { "[SmartMessage] Deserialized message: #{self.name}" }
            message
          else
            # If it's already a message object, return it
            (self.logger || SmartMessage::Logger.default).debug { "[SmartMessage] Returning existing message object: #{self.name}" }
            deserialized_data
          end
        rescue => e
          (self.logger || SmartMessage::Logger.default).error { "[SmartMessage] Error in message deserialization: #{e.class.name} - #{e.message}" }
          raise
        end
      end
    end

  end # class Base
end # module SmartMessage

# Zeitwerk will handle autoloading of these modules
