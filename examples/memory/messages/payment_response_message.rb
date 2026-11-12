# frozen_string_literal: true

# The payment service's answer to an OrderMessage.
class PaymentResponseMessage < SmartMessage::Base
  description 'The result of charging an order'
  from 'payment-service'

  property :order_id,   required: true
  property :payment_id, required: true
  property :status,     required: true, validate: %w[success declined],
                        validation_message: 'status must be success or declined'
  property :reason
end
