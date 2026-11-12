#!/usr/bin/env ruby
# examples/memory/07_proc_handlers_demo.rb
# frozen_string_literal: true
#
# Handler types: default method, block, proc, lambda, and named method
#
#   NotificationMessage.subscribe                     # => NotificationMessage.process(message)
#   NotificationMessage.subscribe { |message| ... }   # block
#   NotificationMessage.subscribe(a_proc_or_lambda)   # any callable
#   NotificationMessage.subscribe('Service.method')   # class method, by name
#
# Every handler receives its own copy of the message.  subscribe returns the
# handler id that unsubscribe takes.

require_relative '../support/example_helper'
require_relative 'messages/notification_message'

TRANSPORT = SmartMessage::Transport::MemoryTransport.new
NotificationMessage.transport(TRANSPORT)

# A handler that lives in a service class.
module NotificationService
  def self.handle(message)
    Example.inbox.add(:service, message.title)
  end
end

def notify(kind, title)
  NotificationMessage.new(kind: kind, title: title, user_id: 'U-1').publish
  Example.wait_for_idle(TRANSPORT)
end

Example.title 'Handler types'

audit_proc   = proc { |message| Example.inbox.add(:proc, message.title) }
error_lambda = ->(message) { Example.inbox.add(:lambda, message.title) if message.kind == 'error' }

handler_ids = {
  default: NotificationMessage.subscribe,
  block:   NotificationMessage.subscribe { |message| Example.inbox.add(:block, message.title) },
  proc:    NotificationMessage.subscribe(audit_proc),
  lambda:  NotificationMessage.subscribe(error_lambda),
  service: NotificationMessage.subscribe('NotificationService.handle')
}
handler_ids.each { |kind, id| puts "  #{kind.to_s.ljust(8)} #{id}" }

notify('info', 'Welcome')
notify('error', 'Disk full')

Example.check('five handlers are subscribed') { TRANSPORT.subscribers['NotificationMessage'].size == 5 }
Example.check('default, block, proc and service handlers each saw both notifications') do
  %i[default block proc service].all? { Example.inbox[it].sort == ['Disk full', 'Welcome'] }
end
Example.check('the lambda kept only the error') { Example.inbox[:lambda] == ['Disk full'] }
Example.check('named handlers use their name as id; callables get a generated id') do
  handler_ids[:default] == 'NotificationMessage.process' &&
    handler_ids[:service] == 'NotificationService.handle' &&
    handler_ids[:block].start_with?('NotificationMessage.proc_')
end

Example.section 'Unsubscribing one handler'
NotificationMessage.unsubscribe(handler_ids[:block])
notify('warning', 'Low battery')
Example.check('the block handler saw nothing new') { Example.inbox.count(:block) == 2 }
Example.check('the other handlers still run') { Example.inbox.count(:proc) == 3 && Example.inbox.count(:default) == 3 }

Example.section 'Unsubscribing everything'
NotificationMessage.unsubscribe!
notify('info', 'Nobody listens')
Example.check('no handler is left') { TRANSPORT.subscribers['NotificationMessage'].empty? }
Example.check('nothing was delivered') { Example.inbox.count(:proc) == 3 }

Example.finish
