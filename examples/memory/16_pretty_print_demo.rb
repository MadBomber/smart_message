#!/usr/bin/env ruby
# examples/memory/16_pretty_print_demo.rb
# frozen_string_literal: true
#
# pretty_print: a readable dump of a message
#
#   message.pretty_print                         content only
#   message.pretty_print(include_header: true)   header and content
#   message.pretty_print(out: io)                write somewhere else
#
# It uses the amazing_print gem when installed and Ruby's pp otherwise.
# Properties that are nil are left out.

require 'stringio'
require_relative '../support/example_helper'
require_relative 'messages/customer_order_message'

# @return [String] what pretty_print wrote, without colour codes
def rendered(message, **options)
  out = StringIO.new
  message.pretty_print(out: out, **options)
  out.string.gsub(/\e\[[\d;]*m/, '')
end

order = CustomerOrderMessage.new(
  order_id:         'ORD-2026-001',
  customer_name:    'Jane Smith',
  line_items:       [{ sku: 'KB-1', name: 'Keyboard', quantity: 1, price: 89.0 },
                     { sku: 'MS-2', name: 'Mouse', quantity: 2, price: 24.5 }],
  total_amount:     138.0,
  shipping_address: { street: '123 Main St', city: 'Springfield', zip: '62701' }
)

Example.title 'pretty_print'

Example.section 'Content only (the default)'
order.pretty_print
content = rendered(order)
Example.check('the properties are shown') { content.include?('ORD-2026-001') && content.include?('Springfield') }
Example.check('the header is not shown') { !content.include?('message_class') }
Example.check('nil properties are left out') { !content.include?('gift_note') }

Example.section 'With the header'
order.pretty_print(include_header: true)
with_header = rendered(order, include_header: true)
Example.check('the header section comes first') do
  with_header.start_with?('Header:') && with_header.index('message_class') < with_header.index('Content:')
end
Example.check('the header shows the addressing') do
  with_header.include?('order-service') && with_header.include?('fulfillment-service')
end

Example.section 'Related: plain data'
puts "  payload_hash keys: #{order.payload_hash.keys}"
Example.check('payload_hash is the content without the header') do
  order.payload_hash.keys == %i[order_id customer_name line_items total_amount shipping_address gift_note]
end
Example.check('to_h includes the header as a plain Hash') { order.to_h[:_sm_header].instance_of?(Hash) }

Example.finish
