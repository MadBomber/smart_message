# frozen_string_literal: true

# Published by 15_logger_demo.rb so the framework has something to log.
class LoggedMessage < SmartMessage::Base
  description 'A message whose life cycle shows up in the log'
  from 'logger-demo'

  property :title, required: true

  def self.process(message)
    Example.inbox.add(:logged, message.title)
  end
end
