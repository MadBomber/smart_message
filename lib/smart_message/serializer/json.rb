# lib/smart_message/serializer/json.rb
# encoding: utf-8
# frozen_string_literal: true

require 'json'  # STDLIB

module SmartMessage::Serializer
  class JSON < Base
    def do_encode(message_instance)
      # Use the wrapper-aware approach: serialize only the payload portion
      # The header should remain separate and unencrypted
      message_hash = message_instance.to_h
      payload_portion = message_hash[:_sm_payload]
      ::JSON.generate(payload_portion)
    end

    def do_decode(payload)
      # TODO: so how do I know to which message class this payload
      #       belongs?  The class needs to be in some kind of message
      #       header.
      ::JSON.parse payload
    end
  end # class JSON < Base
end # module SmartMessage::Serializer
