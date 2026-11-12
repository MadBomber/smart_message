# frozen_string_literal: true

# Something happened to a user account.  Published once, received by
# every interested service.
class UserEventMessage < SmartMessage::Base
  description 'A user account lifecycle event'
  from 'user-manager'

  EVENT_TYPES = %w[user_registered user_login password_changed].freeze

  property :event_type, required: true, validate: EVENT_TYPES,
                        validation_message: "event_type must be one of #{EVENT_TYPES.join(', ')}"
  property :user_id,    required: true
  property :user_email, required: true
  property :details,    default: {}
end
