#!/usr/bin/env ruby
# examples/multi_transport_example.rb
# frozen_string_literal: true
#
# Publishing one message on several transports
#
# transport accepts one transport or an Array.  publish tries every
# transport independently and returns a SmartMessage::PublishResult:
#
#   result.success?   every transport accepted the message
#   result.partial?   some did, some did not
#   result.failed     the outcomes that failed (outcome.transport, outcome.error)
#
# A transport that fails gets the message written to the dead letter queue
# under its name.  When every transport fails, publish raises
# SmartMessage::Errors::PublishError; the result is on error.result.

require 'stringio'
require_relative 'support/example_helper'
require_relative 'support/failing_transport'
require_relative 'messages/multi_transport_message'

def names(outcomes) = outcomes.map(&:transport_name)

Example.title 'Multiple transports'
console = StringIO.new
stdout  = SmartMessage::Transport::StdoutTransport.new(output: console)
memory  = SmartMessage::Transport::MemoryTransport.new
dlq     = SmartMessage::DeadLetterQueue.default

Example.section 'One transport'
MultiTransportMessage.transport(memory)
Example.check('the class reports a single transport') do
  MultiTransportMessage.single_transport? && MultiTransportMessage.transport.equal?(memory)
end

Example.section 'Two transports: every publish goes to both'
MultiTransportMessage.transport([stdout, memory])
MultiTransportMessage.subscribe { |message| Example.inbox.add(:received, message.content) }
result = MultiTransportMessage.new(content: 'to both', priority: 'high').publish
Example.wait_for_idle(memory, stdout)
puts "  #{result.to_h}"
Example.check('the result has one successful outcome per transport') do
  result.success? && names(result.outcomes) == %w[StdoutTransport MemoryTransport]
end
Example.check('the stdout transport wrote the message') { console.string.include?('"content":"to both"') }
Example.check('the memory transport delivered it to the subscriber') { Example.inbox[:received] == ['to both'] }

Example.section 'Instance-level override: this message goes to one transport only'
archive  = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
override = MultiTransportMessage.new(content: 'archived only')
override.transport(archive)
override.publish
Example.check('only the override transport received it') do
  archive.message_count == 1 && !console.string.include?('archived only') && override.single_transport?
end

Example.section 'Partial failure: one transport is down'
MultiTransportMessage.transport([FailingTransport.new, memory])
partial = MultiTransportMessage.new(content: 'survives an outage').publish
Example.wait_for_idle(memory)
Example.check('publish did not raise; the result is partial') do
  partial.partial? && !partial.success? && names(partial.failed) == ['FailingTransport']
end
Example.check('the error is available on the failed outcome') { partial.errors.map(&:message) == ['simulated outage'] }
Example.check('the working transport still delivered the message') { Example.inbox[:received].include?('survives an outage') }
Example.check('the failed copy is in the dead letter queue') do
  dlq.size == 1 && dlq.peek[:transport] == 'FailingTransport'
end

Example.section 'Total failure: every transport is down'
MultiTransportMessage.transport([FailingTransport.new, FailingTransport.new])
error = begin
  MultiTransportMessage.new(content: 'goes nowhere').publish
rescue SmartMessage::Errors::PublishError => e
  e
end
puts "  #{error.class}: #{error.message}"
Example.check('publish raised PublishError with both failures on error.result') do
  error.is_a?(SmartMessage::Errors::PublishError) && error.result.failure? && error.result.failed.size == 2
end
Example.check('one dead letter was written per failed transport') { dlq.size == 3 }

Example.finish
