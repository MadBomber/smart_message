# frozen_string_literal: true

# A general purpose message between services; its addressing is set on
# each instance.
class ServiceMessage < SmartMessage::Base
  description 'A message between two services, or a broadcast'

  property :topic, required: true
  property :body,  default: {}
end
