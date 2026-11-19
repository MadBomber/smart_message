# frozen_string_literal: true

# Request half of a request-reply pair.  reply_to says where the answer goes.
class UserLookupRequest < SmartMessage::Base
  description 'Ask the user service for one user'
  from 'web-app'
  to 'user-service'
  reply_to 'web-app'

  property :request_id, required: true
  property :user_id,    required: true
end
