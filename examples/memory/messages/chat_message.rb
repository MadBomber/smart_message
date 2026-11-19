# frozen_string_literal: true

# One line of conversation in a chat room.
class ChatMessage < SmartMessage::Base
  description 'A chat message posted to a room'

  property :room_id,     required: true
  property :sender_name, required: true
  property :content,     required: true
  property :mentions,    default: []
end
