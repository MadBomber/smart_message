# frozen_string_literal: true

# Addressing set with the header block DSL.
class HeaderBlockMessage < SmartMessage::Base
  description 'Addressing configured with a header block'

  header do
    from 'service-x'
    to 'service-y'
    reply_to 'service-x-callback'
  end

  property :body, required: true
end
