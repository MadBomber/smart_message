# frozen_string_literal: true

# Something a user did.
class UserAction < SmartMessage::Base
  description 'A user action worth recording'
  from 'file-demo'

  property :user_id, required: true
  property :action,  required: true
  property :details, default: {}
end
