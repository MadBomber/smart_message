#!/usr/bin/env ruby
# examples/memory/06_stdout_publish_only.rb
# frozen_string_literal: true
#
# The STDOUT transport: publish only
#
# StdoutTransport writes each published message as one line of JSON.  It is
# for development, debugging, and piping messages to another program.
#
#   output:   the IO to write to (default: $stdout)
#   loopback: also deliver to this transport's own subscribers (default false)
#
# Try:  bundle exec ruby -Ilib examples/memory/06_stdout_publish_only.rb | grep _sm_header | jq .first_name

require 'json'
require 'stringio'
require_relative '../support/example_helper'
require_relative 'messages/greeting_message'

Example.title 'STDOUT transport'

Example.section 'Default: one JSON line per message on $stdout'
GreetingMessage.transport(SmartMessage::Transport::StdoutTransport.new)
result = GreetingMessage.new(first_name: 'Alice', last_name: 'Johnson').publish
Example.check('publish reports success on StdoutTransport') do
  result.success? && result.successful.map(&:transport_name) == ['StdoutTransport']
end

Example.section 'output: any IO (here a StringIO, so the lines can be checked)'
captured = StringIO.new
GreetingMessage.transport(SmartMessage::Transport::StdoutTransport.new(output: captured))
[%w[Bob Smith], %w[Carol Williams]].each do |first_name, last_name|
  GreetingMessage.new(first_name: first_name, last_name: last_name).publish
end

lines = captured.string.lines.map { JSON.parse(it, symbolize_names: true) }
puts captured.string
Example.check('two lines were written, each a complete JSON document') { lines.size == 2 }
Example.check('properties sit beside the header in a flat structure') do
  lines.first[:first_name] == 'Bob' && lines.first[:_sm_header][:message_class] == 'GreetingMessage'
end
Example.check('the header carries the sender and a UUID') do
  lines.all? { it[:_sm_header][:from] == 'stdout-demo' && it[:_sm_header][:uuid].size == 36 }
end

Example.section 'Publish only: without loopback, subscribers receive nothing'
transport = GreetingMessage.transport
GreetingMessage.subscribe { |message| Example.inbox.add(:greetings, message.first_name) }
GreetingMessage.new(first_name: 'David', last_name: 'Brown').publish
Example.wait_for_idle(transport)
Example.check('the subscriber was not called') { Example.inbox.count(:greetings).zero? }

Example.section 'The transport never closes the IO it writes to'
transport.disconnect
Example.check('the StringIO is still open after disconnect') { !captured.closed? }

Example.finish
