#!/usr/bin/env ruby
# examples/file/01_basic_file_transport_demo.rb
# frozen_string_literal: true
#
# FileTransport basics
#
# FileTransport appends each published message to a file, one line of JSON
# per message (JSON Lines).  Options:
#
#   file_path:          a path, or an IO to write to (required)
#   create_directories: create the file's directory (default true)
#   encoding:           file encoding (default: Ruby's default)
#   poll_interval:      \ used when subscribing;
#   read_from_end:      / see 03_file_watching_demo.rb

require 'json'
require 'stringio'
require_relative '../support/example_helper'
require_relative 'messages/log_message'
require_relative 'messages/user_action'

def parsed_lines(path) = File.readlines(path).map { JSON.parse(it, symbolize_names: true) }

Example.title 'File transport basics'

Example.section 'Publishing appends one JSON line per message'
log_path  = Example.tmp_path('logs', 'application.jsonl') # the directory does not exist yet
transport = SmartMessage::Transport::FileTransport.new(file_path: log_path)
LogMessage.transport(transport)
UserAction.transport(transport) # several message classes can share one file

LogMessage.new(level: 'INFO', text: 'Application started').publish
LogMessage.new(level: 'ERROR', text: 'Database unreachable', component: 'db').publish
UserAction.new(user_id: 'U-1', action: 'login', details: { ip: '10.0.0.7' }).publish

puts File.read(log_path)
lines = parsed_lines(log_path)
Example.check('the directory and file were created') { File.file?(log_path) && transport.path == log_path }
Example.check('three messages produced three lines') { lines.size == 3 }
Example.check('each line names its message class in the header') do
  lines.map { it[:_sm_header][:message_class] } == %w[LogMessage LogMessage UserAction]
end
Example.check('properties and defaults are stored beside the header') do
  lines[0][:component] == 'system' && lines[1][:component] == 'db' && lines[2][:details] == { ip: '10.0.0.7' }
end

Example.section 'The file is append-only: a new transport on the same path adds to it'
transport.disconnect
second = SmartMessage::Transport.create(:file, file_path: log_path) # via the registry
LogMessage.transport(second)
LogMessage.new(level: 'WARN', text: 'Disk 85% full').publish
Example.check('the file now holds four lines') { parsed_lines(log_path).size == 4 }

Example.section 'A stored line can be decoded back into a message'
restored = second.decode_message(File.readlines(log_path).last)
Example.check('decoding returns a LogMessage with the same content and UUID') do
  restored.is_a?(LogMessage) && restored.text == 'Disk 85% full' && restored.uuid == parsed_lines(log_path).last[:_sm_header][:uuid]
end

Example.section 'An invalid message never reaches the file'
Example.check('publish raises ValidationError for an unknown level') do
  LogMessage.new(level: 'CHATTY', text: 'nope').publish
  false
rescue SmartMessage::Errors::ValidationError
  true
end
Example.check('the file still holds four lines') { parsed_lines(log_path).size == 4 }

Example.section 'Publishing to an IO instead of a path'
buffer = StringIO.new
UserAction.transport(SmartMessage::Transport::FileTransport.new(file_path: buffer))
UserAction.new(user_id: 'U-2', action: 'logout').publish
Example.check('the IO received the line') { JSON.parse(buffer.string)['action'] == 'logout' }
Example.check('an IO target can be written but not subscribed to') do
  UserAction.subscribe { nil }
  false
rescue SmartMessage::Errors::TransportError
  true
end
Example.check('disconnect leaves an IO it was handed open') do
  UserAction.transport.disconnect
  !buffer.closed?
end

Example.section 'After disconnect the transport refuses to publish'
second.disconnect
error = begin
  LogMessage.new(level: 'INFO', text: 'too late').publish
rescue SmartMessage::Errors::PublishError => e
  e
end
Example.check('publish raises PublishError; connect makes the transport usable again') do
  second.connect
  error.is_a?(SmartMessage::Errors::PublishError) && LogMessage.new(level: 'INFO', text: 'back').publish.success?
end

Example.finish
