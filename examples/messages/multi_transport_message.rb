# frozen_string_literal: true

# Published by multi_transport_example.rb on several transports at once.
class MultiTransportMessage < SmartMessage::Base
  description 'A message published on more than one transport'
  from 'multi-transport-demo'

  property :content,  required: true
  property :priority, default: 'normal'
end
