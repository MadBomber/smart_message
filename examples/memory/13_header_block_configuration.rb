#!/usr/bin/env ruby
# examples/memory/13_header_block_configuration.rb
# frozen_string_literal: true
#
# Three ways to configure addressing
#
#   1. class methods:        from 'a'; to 'b'; reply_to 'c'
#   2. a header block:       header do; from 'a'; to 'b'; end
#   3. per instance:         new(from: 'a'), message.to('b'), message.to = 'b'
#
# See the three message classes in messages/ for styles 1 and 2.

require_relative '../support/example_helper'
require_relative 'messages/direct_method_message'
require_relative 'messages/header_block_message'
require_relative 'messages/mixed_config_message'

def addressing(source) = [source.from, source.to, source.reply_to]

Example.title 'Addressing configuration'

Example.section 'Class-level defaults'
[DirectMethodMessage, HeaderBlockMessage, MixedConfigMessage].each do |klass|
  puts "  #{klass.name.ljust(20)} from=#{klass.from.inspect} to=#{klass.to.inspect} reply_to=#{klass.reply_to.inspect}"
end
Example.check('direct class methods set all three fields') do
  addressing(DirectMethodMessage) == %w[service-a service-b service-a-callback]
end
Example.check('the header block sets the same three fields') do
  addressing(HeaderBlockMessage) == %w[service-x service-y service-x-callback]
end
Example.check('both styles can be mixed; an unset to means broadcast') do
  addressing(MixedConfigMessage) == ['mixed-service', nil, 'mixed-callback'] && MixedConfigMessage.to_missing?
end
Example.check('header takes a block only') do
  HeaderBlockMessage.header(from: 'nope')
  false
rescue ArgumentError
  true
end

Example.section 'A new message starts from the class defaults'
message = HeaderBlockMessage.new(body: 'hello')
Example.check('the instance and its header agree with the class') do
  addressing(message) == addressing(HeaderBlockMessage) && message._sm_header.from == 'service-x'
end

Example.section 'Instance-level overrides'
at_build = HeaderBlockMessage.new(body: 'hello', to: 'service-z')
chained  = HeaderBlockMessage.new(body: 'hello').from('sender-1').to('recipient-1').reply_to('callback-1')
message.to = 'service-q'
Example.check('constructor keywords override the defaults') { at_build.to == 'service-z' && at_build.from == 'service-x' }
Example.check('the setter methods chain') { addressing(chained) == %w[sender-1 recipient-1 callback-1] }
Example.check('assignment writes through to the header') { message._sm_header.to == 'service-q' }
Example.check('the class defaults are untouched') { addressing(HeaderBlockMessage) == %w[service-x service-y service-x-callback] }

Example.section 'Checking and resetting'
broadcast = MixedConfigMessage.new(body: 'hello')
Example.check('predicates report what is configured') do
  broadcast.from_configured? && broadcast.to_missing? && broadcast.reply_to_configured?
end
Example.check('reset_to returns an instance to its class default') do
  message.reset_to
  message.to == 'service-y'
end

Example.section 'The addressing survives a trip through a transport'
transport = SmartMessage::Transport::MemoryTransport.new
HeaderBlockMessage.transport(transport)
HeaderBlockMessage.subscribe { |received| Example.inbox.add(:received, addressing(received)) }
chained.publish
Example.wait_for_idle(transport)
Example.check('the subscriber saw the overridden addressing') do
  Example.inbox[:received] == [%w[sender-1 recipient-1 callback-1]]
end

Example.finish
