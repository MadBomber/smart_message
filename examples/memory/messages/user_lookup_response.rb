# frozen_string_literal: true

# Reply half of a request-reply pair; its recipient is set per instance.
class UserLookupResponse < SmartMessage::Base
  description 'The user service answering a UserLookupRequest'
  from 'user-service'

  property :request_id, required: true
  property :user_name
  property :found, default: true
end
