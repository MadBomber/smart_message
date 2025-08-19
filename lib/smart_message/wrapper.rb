# lib/smart_message/wrapper.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom'   # STDLIB
require_relative './header.rb'

module SmartMessage
  module Wrapper
    # Every smart message has a common wrapper format that contains
    # information used to support the dispatching of subscribed
    # messages upon receipt from a transport as well as the serialized
    # payload.
    #
    # The wrapper consolidates header and payload into a single object
    # for cleaner method signatures throughout the SmartMessage dataflow.
    class Base < Hashie::Dash
      include Hashie::Extensions::IndifferentAccess
      include Hashie::Extensions::MethodAccess
      include Hashie::Extensions::DeepMerge

      # Core wrapper properties
      # Using '_sm_' prefix to avoid collision with user message definitions
      property :_sm_header,
        required: true,
        description: "SmartMessage header containing routing and metadata information"
      
      property :_sm_payload,
        required: true, 
        description: "Serialized message payload containing the business data"

      # Create wrapper from header and payload
      def initialize(header: nil, payload: nil, **props, &block)
        # Handle different initialization patterns
        if header && payload
          attributes = {
            _sm_header: header,
            _sm_payload: payload
          }
        else
          # Create default header if not provided
          default_header = SmartMessage::Header.new(
            uuid:           SecureRandom.uuid,
            message_class:  'SmartMessage::Wrapper::Base',
            published_at:   Time.now,
            publisher_pid:  Process.pid,
            version:        1
          )
          
          attributes = {
            _sm_header: default_header,
            _sm_payload: nil
          }.merge(props)
        end

        super(attributes, &block)
      end

      # Convenience accessors for header and payload
      def header
        _sm_header
      end

      def payload
        _sm_payload
      end

      # Check if this is a broadcast message (to field is nil)
      def broadcast?
        _sm_header.to.nil?
      end

      # Check if this is a directed message (to field is present) 
      def directed?
        !broadcast?
      end

      # Get message class from header
      def message_class
        _sm_header.message_class
      end

      # Get sender from header
      def from
        _sm_header.from
      end

      # Get recipient from header
      def to
        _sm_header.to
      end

      # Get reply destination from header
      def reply_to
        _sm_header.reply_to
      end

      # Get message version from header
      def version
        _sm_header.version
      end

      # Get UUID from header
      def uuid
        _sm_header.uuid
      end

      # Convert wrapper to hash for serialization/transport
      def to_hash
        {
          '_sm_header' => _sm_header.to_hash,
          '_sm_payload' => _sm_payload
        }
      end

      alias_method :to_h, :to_hash

      # Outer-level JSON serialization for the wrapper
      # This is level 2 serialization - always JSON for routing/monitoring
      def to_json(*args)
        require 'json'
        to_hash.to_json(*args)
      end
    end
  end
end