# frozen_string_literal: true

# A customer order sent from the order service to the payment service.
class OrderMessage < SmartMessage::Base
  description 'A customer order awaiting payment'
  from 'order-service'
  to 'payment-service'
  reply_to 'order-service'

  property :order_id,       required: true, description: 'Unique order identifier'
  property :customer_id,    required: true, description: 'Customer placing the order'
  property :amount,         required: true, description: 'Order total in dollars'
  property :payment_method, default: 'credit_card', description: 'How the customer pays'
  property :line_items,     default: [], description: 'Names of the ordered products'
end
