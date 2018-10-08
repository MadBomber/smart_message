# lib/smart_message/serializer/json.rb
# encoding: utf-8
# frozen_string_literal: true

require 'json'  # STDLIB

module SmartMessage::Serializer
  class JSON < Base
    def encode(message_instance)
      # TODO: is this the right place to insert an automated-invisible
      #       message header?
      message_instance.to_json
    end

    def decode(payload)
      # TODO: so how do I know to which message class this payload
      #       belongs?  The class needs to be in some kind of message
      #       header.
      a_hash = ::JSON.parse payload
    end
  end # class JSON < Base
end # module SmartMessage::Serializer
