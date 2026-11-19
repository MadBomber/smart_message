# frozen_string_literal: true

# An invoice that must be processed once, however often it is delivered.
class InvoiceMessage < SmartMessage::Base
  description 'An invoice to book; deduplicated by message UUID'
  from 'billing-service'

  property :invoice_id, required: true
  property :amount,     required: true

  ddq_size 100         # remember the last 100 UUIDs per handler
  ddq_storage :memory  # or :redis, to share the queue between processes
  enable_deduplication!

  def self.process(message)
    Example.inbox.add(:invoices, message.invoice_id)
  end
end
