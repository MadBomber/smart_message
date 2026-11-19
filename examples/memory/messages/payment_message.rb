# frozen_string_literal: true

# A card payment to capture.
class PaymentMessage < SmartMessage::Base
  description 'A payment to capture at the payment gateway'
  from 'checkout-service'

  property :payment_id,  required: true, description: 'Unique payment identifier'
  property :amount,      required: true, description: 'Amount in dollars'
  property :customer_id, required: true, description: 'Customer making the payment'
end
