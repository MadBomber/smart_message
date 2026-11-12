# frozen_string_literal: true

# A "/command" typed in a chat room, addressed to the bots.
class BotCommandMessage < SmartMessage::Base
  description 'A command for the chat bots'

  property :room_id,   required: true
  property :command,   required: true
  property :arguments, default: []
end
