# frozen_string_literal: true

# A notification for a user.  The class-level process method is the
# default handler: NotificationMessage.subscribe (no argument) calls it.
class NotificationMessage < SmartMessage::Base
  description 'A notification shown to a user'
  from 'notification-service'

  property :kind,    required: true, validate: %w[info warning error]
  property :title,   required: true
  property :user_id, required: true

  def self.process(message)
    Example.inbox.add(:default, message.title)
  end
end
