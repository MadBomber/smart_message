# frozen_string_literal: true

# A reminder without deduplication: every delivery reaches the handler.
class ReminderMessage < SmartMessage::Base
  description 'A payment reminder; not deduplicated'
  from 'billing-service'

  property :invoice_id, required: true
  property :text,       required: true

  def self.process(message)
    Example.inbox.add(:reminders, message.invoice_id)
  end
end
