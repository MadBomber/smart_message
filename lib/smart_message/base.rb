# lib/smart_message/base.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom'   # STDLIB

require_relative './wrapper.rb'
require_relative './property_descriptions.rb'
require_relative './property_validations.rb'
require_relative './plugins.rb'
require_relative './addressing.rb'
require_relative './subscription.rb'
require_relative './versioning.rb'
require_relative './messaging.rb'
require_relative './utilities.rb'

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
    






    ###########################################################
    ## class methods

    class << self
      # Create message instance from wrapper object
      # Deserializes the payload using the serializer info from header
      def from_wrapper(wrapper)
        header = wrapper._sm_header
        serialized_payload = wrapper._sm_payload
        
        # Determine serializer from header
        if header.serializer
          serializer_class = Object.const_get(header.serializer)
          serializer = serializer_class.new
          
          # Deserialize payload back to message
          deserialized_data = serializer.decode(serialized_payload)
          
          # Create new message instance with the deserialized data
          # The deserialized data should be a hash that can be used to construct the message
          if deserialized_data.is_a?(Hash)
            # Extract the message properties (excluding header)
            message_props = deserialized_data.reject { |key, value| key.to_s.start_with?('_sm_') }
            # Convert string keys to symbols for compatibility with keyword arguments
            symbol_props = message_props.transform_keys(&:to_sym)
            message = self.new(**symbol_props)
            message._sm_header = header
            message
          else
            # If it's already a message object, just update the header
            deserialized_data._sm_header = header
            deserialized_data
          end
        else
          raise SmartMessage::Errors::SerializerNotConfigured,
            "Cannot deserialize wrapper: no serializer specified in header"
        end
      end
    end

  end # class Base
end # module SmartMessage

require_relative 'header'
require_relative 'transport'
require_relative 'serializer'
require_relative 'logger'
