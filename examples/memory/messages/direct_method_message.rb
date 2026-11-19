# frozen_string_literal: true

# Addressing set with the class methods from, to and reply_to.
class DirectMethodMessage < SmartMessage::Base
  description 'Addressing configured with direct class methods'
  from 'service-a'
  to 'service-b'
  reply_to 'service-a-callback'

  property :body, required: true
end
