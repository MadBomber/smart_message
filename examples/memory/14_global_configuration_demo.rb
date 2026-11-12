#!/usr/bin/env ruby
# examples/memory/14_global_configuration_demo.rb
# frozen_string_literal: true
#
# Global configuration
#
# SmartMessage.configure sets what every message class uses unless the
# class sets its own: the transport, the logger, the dead letter queue
# file, and the dispatcher limits.  There is no default transport and no
# logging until something is configured.

require_relative '../support/example_helper'
require_relative 'messages/order_status_message'
require_relative 'messages/special_message'

def order_status = OrderStatusMessage.new(order_id: 'ORD-1', status: 'shipped')

Example.title 'Global configuration'

Example.section 'Nothing configured'
error = begin
  order_status.publish
rescue SmartMessage::Errors::TransportNotConfigured => e
  e
end
puts "  #{error.class}: #{error.message}"
Example.check('publishing without any transport raises TransportNotConfigured') { !error.nil? }
Example.check('no logger is configured') { !SmartMessage.configuration.logger_configured? }

Example.section 'SmartMessage.configure'
log_path         = Example.tmp_path('log', 'application.log')
global_transport = SmartMessage::Transport::MemoryTransport.new

SmartMessage.configure do |config|
  config.transport              = global_transport
  config.logger                 = log_path # a path, STDOUT/STDERR, :default, or a logger object
  config.log_level              = :info
  config.dlq_path               = Example.tmp_path('app_dead_letters.jsonl')
  config.dispatcher_max_threads = 4
  config.shutdown_timeout       = 2
end

OrderStatusMessage.subscribe
order_status.publish
Example.wait_for_idle(global_transport)

Example.check('a class without its own transport uses the global one') do
  OrderStatusMessage.transport.equal?(global_transport) && Example.inbox[:global] == ['ORD-1']
end
Example.check('the dead letter queue follows config.dlq_path') do
  SmartMessage::DeadLetterQueue.default.file_path == Example.tmp_path('app_dead_letters.jsonl')
end
SmartMessage::Logger.default.close # flush the log file before reading it
Example.check('the configured log file received the publish') do
  File.read(log_path).include?('Published: OrderStatusMessage via MemoryTransport')
end

Example.section 'A class-level transport takes precedence'
special_transport = SmartMessage::Transport::MemoryTransport.new
SpecialMessage.transport(special_transport)
SpecialMessage.subscribe
SpecialMessage.new(content: 'handled apart').publish
Example.wait_for_idle(special_transport)
Example.check('SpecialMessage used its own transport') do
  SpecialMessage.transport.equal?(special_transport) && Example.inbox[:special] == ['handled apart']
end
Example.check('the global transport never saw SpecialMessage') do
  global_transport.subscribers.keys == ['OrderStatusMessage']
end

Example.section 'An instance-level transport takes precedence over both'
captured = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
one_off  = SpecialMessage.new(content: 'captured')
one_off.transport(captured)
one_off.publish
Example.check('only the instance used the third transport') do
  captured.message_count == 1 && Example.inbox.count(:special) == 1
end

Example.section 'Resetting'
SpecialMessage.reset_transport
Example.check('reset_transport falls back to the global transport') { SpecialMessage.transport.equal?(global_transport) }
SmartMessage.reset_configuration!
Example.isolate_dead_letters # reset restored the default DLQ path
Example.check('reset_configuration! removes the global transport') { OrderStatusMessage.transport_missing? }

Example.finish
