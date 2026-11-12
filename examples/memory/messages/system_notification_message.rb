# frozen_string_literal: true

# Room housekeeping: somebody joined or left.
class SystemNotificationMessage < SmartMessage::Base
  description 'A join/leave notice for a chat room'
  from 'room-manager'

  property :room_id,           required: true
  property :notification_type, required: true, validate: %w[user_joined user_left]
  property :content,           required: true
end
