#!/usr/bin/env ruby
# examples/memory/01_message_deduplication_demo.rb
# frozen_string_literal: true
#
# Message deduplication with the Deduplication Queue (DDQ)
#
# A class that calls enable_deduplication! gets one queue of recently seen
# message UUIDs per handler.  A second delivery of the same UUID to the same
# handler is skipped.  The queues belong to the transport's dispatcher.

require_relative '../support/example_helper'
require_relative 'messages/invoice_message'
require_relative 'messages/reminder_message'

TRANSPORT = SmartMessage::Transport::MemoryTransport.new
InvoiceMessage.transport(TRANSPORT)
ReminderMessage.transport(TRANSPORT)

# Publish the same message object (so the same UUID) +times+ times.
def deliver_repeatedly(message, times)
  times.times { message.publish }
  Example.wait_for_idle(TRANSPORT)
end

Example.title 'Message deduplication'

Example.section 'A deduplicated class handles a redelivered message once'
InvoiceMessage.subscribe # => InvoiceMessage.process
invoice = InvoiceMessage.new(invoice_id: 'INV-1', amount: 250.0)
deliver_repeatedly(invoice, 3)

handler = 'InvoiceMessage.process'
Example.check('the invoice was booked once out of three deliveries') do
  Example.inbox[:invoices] == ['INV-1']
end
Example.check('two deliveries were counted as duplicates') do
  SmartMessage::Stats.get('InvoiceMessage', handler, 'duplicate') == 2
end

Example.section 'A class without deduplication handles every delivery'
ReminderMessage.subscribe
deliver_repeatedly(ReminderMessage.new(invoice_id: 'INV-1', text: 'Payment due'), 3)
Example.check('the reminder was handled three times') { Example.inbox.count(:reminders) == 3 }
Example.check('ReminderMessage reports deduplication as off') { ReminderMessage.ddq_stats == { enabled: false } }

Example.section 'Each handler has its own queue'
InvoiceMessage.subscribe { |message| Example.inbox.add(:audit, message.invoice_id) }
deliver_repeatedly(invoice, 2)
Example.check('the new handler saw INV-1 once; the first handler skipped it again') do
  Example.inbox[:audit] == ['INV-1'] && Example.inbox[:invoices] == ['INV-1']
end

stats = InvoiceMessage.ddq_stats
puts "  ddq_config: #{InvoiceMessage.ddq_config}"
stats[:queues].each { |name, queue| puts "  #{name}: #{queue}" }
Example.check('ddq_stats lists one queue per handler, each holding one UUID') do
  stats[:enabled] && stats[:queues].size == 2 && stats[:queues].values.all? { it[:current_count] == 1 }
end

Example.section 'clear_ddq! forgets what was seen'
InvoiceMessage.clear_ddq!
deliver_repeatedly(invoice, 1)
Example.check('after clear_ddq! the same UUID is handled again') { Example.inbox.count(:invoices) == 2 }

Example.finish
