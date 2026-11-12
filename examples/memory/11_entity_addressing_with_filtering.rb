#!/usr/bin/env ruby
# examples/memory/11_entity_addressing_with_filtering.rb
# frozen_string_literal: true
#
# Subscription filters on the addressing fields
#
#   subscribe(to: 'order-service')              messages addressed to me
#   subscribe(broadcast: true)                  messages with no recipient
#   subscribe(to: 'me', broadcast: true)        either of the two
#   subscribe(from: 'admin-service')            messages from one sender
#   subscribe(from: %w[a b])                    ... or from any of several
#   subscribe(from: 'admin', to: 'me')          both must match
#
# A subscription without filters receives everything.

require_relative '../support/example_helper'
require_relative 'messages/service_message'

TRANSPORT = SmartMessage::Transport::MemoryTransport.new
ServiceMessage.transport(TRANSPORT)

# Subscribe a handler that records each topic under +name+.
def listen(name, **filters)
  ServiceMessage.subscribe(**filters) { |message| Example.inbox.add(name, message.topic) }
end

def send_message(topic, from:, to: nil)
  ServiceMessage.new(topic: topic, from: from, to: to).publish
end

Example.title 'Addressing filters'

listen(:everything)
listen(:directed,         to: 'order-service')
listen(:broadcasts,       broadcast: true)
listen(:mine_or_everyone, to: 'order-service', broadcast: true)
listen(:from_admin,       from: 'admin-service')
listen(:from_ops,         from: %w[admin-service monitoring-service])
listen(:admin_to_me,      from: 'admin-service', to: 'order-service')

send_message('restock',   from: 'inventory-service',  to: 'order-service')
send_message('refund',    from: 'admin-service',      to: 'order-service')
send_message('audit',     from: 'admin-service',      to: 'billing-service')
send_message('downtime',  from: 'admin-service')
send_message('cpu-alert', from: 'monitoring-service')
Example.wait_for_idle(TRANSPORT)

expected = {
  everything:       %w[audit cpu-alert downtime refund restock],
  directed:         %w[refund restock],
  broadcasts:       %w[cpu-alert downtime],
  mine_or_everyone: %w[cpu-alert downtime refund restock],
  from_admin:       %w[audit downtime refund],
  from_ops:         %w[audit cpu-alert downtime refund],
  admin_to_me:      %w[refund]
}

expected.each do |name, topics|
  puts "  #{name.to_s.ljust(17)} #{Example.inbox[name].sort.join(', ')}"
  Example.check("#{name} received #{topics.size} of 5 messages") { Example.inbox[name].sort == topics }
end

Example.check('a filter value must be a String, Regexp, or Array of them') do
  ServiceMessage.subscribe(to: 42) { nil }
  false
rescue ArgumentError
  true
end

Example.finish
