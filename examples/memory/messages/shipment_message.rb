# frozen_string_literal: true

# Point-to-point: one sender, one named recipient.
class ShipmentMessage < SmartMessage::Base
  description 'An order to ship, addressed to the fulfilment service'
  from 'order-service'
  to 'fulfillment-service'

  property :order_id, required: true
  property :address,  required: true
end
