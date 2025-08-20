# lib/smart_message/serializer/json.rb
# encoding: utf-8
# frozen_string_literal: true

require 'json'  # STDLIB

module SmartMessage::Serializer
  class Json < Base
    def do_encode(message_instance)
      # Single-tier serialization: serialize the complete message structure
      # This includes both header and payload for full message reconstruction
      message_hash = message_instance.to_h
      ::JSON.generate(message_hash)
    end

    def do_decode(payload)
      # TODO: so how do I know to which message class this payload
      #       belongs?  The class needs to be in some kind of message
      #       header.
      ::JSON.parse payload
    end
  end # class JSON < Base
end # module SmartMessage::Serializer
