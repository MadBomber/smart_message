#!/usr/bin/env ruby
# examples/memory/03_point_to_point_orders.rb
# frozen_string_literal: true
#
# Point-to-point (1-to-1) messaging: order processing
#
# The order service publishes an OrderMessage; exactly one handler, in the
# payment service, processes it and answers with a PaymentResponseMessage.
# See point_to_point_pattern.svg.

require_relative '../support/example_helper'
require_relative 'messages/order_message'
require_relative 'messages/payment_response_message'

TRANSPORT = SmartMessage::Transport::MemoryTransport.new
OrderMessage.transport(TRANSPORT)
PaymentResponseMessage.transport(TRANSPORT)

# Charges orders and reports the result to whoever asked.
module PaymentService
  LIMIT = 1_000

  module_function

  def start = OrderMessage.subscribe('PaymentService.process_order')

  def process_order(order)
    approved = order.amount <= LIMIT
    PaymentResponseMessage.new(
      order_id:   order.order_id,
      payment_id: "PAY-#{order.order_id}",
      status:     approved ? 'success' : 'declined',
      reason:     approved ? nil : "amount exceeds #{LIMIT}",
      to:         order.reply_to
    ).publish
  end
end

# Places orders and records the answers.
module OrderService
  module_function

  def start = PaymentResponseMessage.subscribe('OrderService.handle_response', to: 'order-service')

  def place_order(order_id:, amount:)
    OrderMessage.new(order_id: order_id, customer_id: 'CUST-7', amount: amount, line_items: %w[widget]).publish
  end

  def handle_response(response)
    puts "  order #{response.order_id}: #{response.status}#{" (#{response.reason})" if response.reason}"
    Example.inbox.add(:responses, response)
  end
end

Example.title 'Point-to-point order processing'
PaymentService.start
OrderService.start

orders = { 'ORD-1' => 99.99, 'ORD-2' => 1_299.0, 'ORD-3' => 450.0 }
results = orders.map { |order_id, amount| OrderService.place_order(order_id: order_id, amount: amount) }
Example.wait_for_idle(TRANSPORT)

statuses = Example.inbox[:responses].to_h { [it.order_id, it.status] }
Example.check('every publish returned a successful PublishResult') { results.all?(&:success?) }
Example.check('each order got exactly one response') do
  Example.inbox.count(:responses) == 3 && statuses.keys.sort == orders.keys
end
Example.check('the order over the limit was declined, the others charged') do
  statuses == { 'ORD-1' => 'success', 'ORD-2' => 'declined', 'ORD-3' => 'success' }
end
Example.check('responses were addressed back to the order service') do
  Example.inbox[:responses].all? { it.from == 'payment-service' && it.to == 'order-service' }
end

Example.finish
