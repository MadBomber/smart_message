# frozen_string_literal: true

# Declares no transport of its own: it uses whatever
# SmartMessage.configure set globally.
class OrderStatusMessage < SmartMessage::Base
  description 'An order status update using the global transport'
  from 'order-service'

  property :order_id, required: true
  property :status,   required: true

  def self.process(message)
    Example.inbox.add(:global, message.order_id)
  end
end
