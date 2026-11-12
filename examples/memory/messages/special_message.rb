# frozen_string_literal: true

# Gets a transport of its own in 14_global_configuration_demo.rb, which
# takes precedence over the global one.
class SpecialMessage < SmartMessage::Base
  description 'A message whose class overrides the global transport'
  from 'special-service'

  property :content, required: true

  def self.process(message)
    Example.inbox.add(:special, message.content)
  end
end
