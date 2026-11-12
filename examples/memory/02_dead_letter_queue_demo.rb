#!/usr/bin/env ruby
# examples/memory/02_dead_letter_queue_demo.rb
# frozen_string_literal: true
#
# The Dead Letter Queue (DLQ)
#
# A message that could not be published, and a message whose handler
# raised, are appended to a JSON Lines file instead of being lost.  The
# entries can be inspected, filtered, and replayed.
#
# The queue file is SmartMessage.configuration.dlq_path.  The example helper
# points it at a temporary directory; an application sets it like this:
#
#   SmartMessage.configure { |config| config.dlq_path = '/var/lib/app/dead_letters.jsonl' }

require_relative '../support/example_helper'
require_relative '../support/failing_transport'
require_relative 'messages/payment_message'

# A payment gateway that can be switched off.
module Gateway
  @online = false

  class << self
    attr_accessor :online

    def capture(message)
      raise "gateway offline, cannot capture #{message.payment_id}" unless online

      Example.inbox.add(:captured, message.payment_id)
    end
  end
end

def payment(id, amount) = PaymentMessage.new(payment_id: id, amount: amount, customer_id: 'CUST-1')

memory = SmartMessage::Transport::MemoryTransport.new
dlq    = SmartMessage::DeadLetterQueue.default

PaymentMessage.transport(memory)
PaymentMessage.subscribe('Gateway.capture')

Example.title 'Dead letter queue'
puts "  queue file: #{dlq.file_path}"

Example.section 'A handler that raises sends its message to the DLQ'
payment('PAY-1', 25.0).publish
payment('PAY-2', 40.0).publish
Example.wait_for_idle(memory)
Example.check('both failed payments are in the queue') { dlq.size == 2 }
Example.check('the entry names the handler and the error') do
  entry = dlq.peek
  entry[:transport] == 'handler:Gateway.capture' && entry[:error].include?('gateway offline')
end

Example.section 'A failed publish sends the message to the DLQ and raises'
unsent = payment('PAY-3', 60.0)
unsent.transport(FailingTransport.new) # instance-level transport
error = begin
  unsent.publish
rescue SmartMessage::Errors::PublishError => e
  e
end
puts "  #{error.class}: #{error.message}"
Example.check('publish raised PublishError carrying the result') do
  error.is_a?(SmartMessage::Errors::PublishError) && error.result.failure?
end
Example.check('the unpublished payment is the third entry') { dlq.size == 3 }

Example.section 'Inspecting the queue'
statistics = dlq.statistics
puts <<~REPORT
    total:    #{statistics[:total]}
    by class: #{statistics[:by_class]}
    by error: #{statistics[:by_error].keys}
  REPORT
Example.check('statistics counts three PaymentMessage entries') do
  statistics[:total] == 3 && statistics[:by_class] == { 'PaymentMessage' => 3 }
end
Example.check('filter_by_error_pattern finds the publish failure') do
  dlq.filter_by_error_pattern(/simulated outage/).size == 1
end
Example.check('inspect_messages(limit: 2) returns the two oldest entries') do
  dlq.inspect_messages(limit: 2).map { it[:header][:uuid] } == dlq.entries.first(2).map { it[:header][:uuid] }
end

Example.section 'Replaying once the gateway is back'
Gateway.online = true
results = dlq.replay_all(memory)
Example.wait_for_idle(memory)
puts "  replay_all: #{results}"
Example.check('all three entries were replayed and removed') { results[:success] == 3 && dlq.empty? }
Example.check('the gateway captured all three payments') do
  Example.inbox[:captured].sort == %w[PAY-1 PAY-2 PAY-3]
end

Example.finish
