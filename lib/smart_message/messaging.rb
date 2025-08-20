# lib/smart_message/messaging.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Messaging module for SmartMessage::Base
  # Handles message encoding and publishing operations
  module Messaging
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

    # Convert message to hash with _sm_header and _sm_payload structure
    # This is the foundation for wrapper architecture
    def to_h
      # Update header with serializer info before converting
      _sm_header.serializer = serializer.class.to_s if serializer_configured?
      
      {
        :_sm_header => header_hash_with_symbols,
        :_sm_payload => payload_hash_with_symbols
      }
    end


    # NOTE: you publish instances; but, you subscribe/unsubscribe at
    #       the class-level
    def publish
      begin
        # Validate the complete message before publishing (now uses overridden validate!)
        validate!
        
        # Update header with current publication info
        _sm_header.published_at   = Time.now
        _sm_header.publisher_pid  = Process.pid
        _sm_header.serializer     = serializer.class.to_s if serializer_configured?

        # Single-tier serialization: serialize entire message with designated serializer
        serialized_message = encode
        
        raise Errors::TransportNotConfigured if transport_missing?
        
        # Transport receives the message class name (for channel routing) and serialized message
        (self.class.logger || SmartMessage::Logger.default).debug { "[SmartMessage::Messaging] About to call transport.publish" }
        transport.publish(_sm_header.message_class, serialized_message)
        (self.class.logger || SmartMessage::Logger.default).debug { "[SmartMessage::Messaging] transport.publish completed" }
        
        # Log the message publish
        (self.class.logger || SmartMessage::Logger.default).info { "[SmartMessage] Published: #{self.class.name} via #{transport.class.name.split('::').last}" }

        SS.add(_sm_header.message_class, 'publish')
        SS.get(_sm_header.message_class, 'publish')
      rescue => e
        (self.class.logger || SmartMessage::Logger.default).error { "[SmartMessage] Error in message publishing: #{e.class.name} - #{e.message}" }
        raise
      end
    end # def publish

    private

    # Convert header to hash with symbol keys
    def header_hash_with_symbols
      _sm_header.to_hash.transform_keys(&:to_sym)
    end
    
    # Extract all non-header properties into a hash with symbol keys
    # Performs deep symbolization on nested structures
    def payload_hash_with_symbols
      self.class.properties.each_with_object({}) do |prop, hash|
        next if prop == :_sm_header
        hash[prop.to_sym] = deep_symbolize_keys(self[prop])
      end
    end

    # Recursively convert all string keys to symbols in nested hashes and arrays
    def deep_symbolize_keys(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = deep_symbolize_keys(value)
        end
      when Array
        obj.map { |item| deep_symbolize_keys(item) }
      else
        obj
      end
    end
  end
end