# frozen_string_literal: true

# A message with nested data, to show pretty_print.
class CustomerOrderMessage < SmartMessage::Base
  description 'An order with nested line items and a shipping address'
  from 'order-service'
  to 'fulfillment-service'

  property :order_id,         required: true
  property :customer_name,    required: true
  property :line_items,       required: true
  property :total_amount,     required: true
  property :shipping_address
  property :gift_note
end
