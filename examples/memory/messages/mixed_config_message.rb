# frozen_string_literal: true

# Both styles together; a broadcast (no to) with a reply address.
class MixedConfigMessage < SmartMessage::Base
  description 'Addressing configured with a header block and a class method'

  header do
    from 'mixed-service'
  end
  reply_to 'mixed-callback'

  property :body, required: true
end
