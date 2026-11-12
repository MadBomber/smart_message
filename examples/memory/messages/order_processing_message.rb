# frozen_string_literal: true

# An order moving through fulfilment; used to show what the framework logs.
class OrderProcessingMessage < SmartMessage::Base
  description 'An order status change'
  from 'order-service'

  property :order_id, required: true
  property :status,   default: 'pending'

  def self.process(message)
    Example.inbox.add(:orders, message.order_id)
  end
end
