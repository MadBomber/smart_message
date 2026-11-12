#!/usr/bin/env ruby
# examples/file/04_multi_transport_file_demo.rb
# frozen_string_literal: true
#
# FileTransport together with other transports
#
# A message class (or one message) may have several transports.  publish
# tries each one and returns a PublishResult with one outcome per transport.
# Typical uses with a file:
#
#   * archive: process in memory and keep a copy on disk
#   * fan-out: write the same message to several files
#   * routing: choose the file per message

require 'json'
require_relative '../support/example_helper'
require_relative 'messages/audit_event'
require_relative 'messages/system_metric'

def file_transport(name) = SmartMessage::Transport::FileTransport.new(file_path: Example.tmp_path(name))

def line_count(transport) = File.exist?(transport.path) ? File.readlines(transport.path).size : 0

def stored(transport, field) = File.readlines(transport.path).map { JSON.parse(it)[field] }

Example.title 'File transport with other transports'

Example.section 'Archive: handle in memory, keep a copy on disk'
memory  = SmartMessage::Transport::MemoryTransport.new
archive = file_transport('audit_archive.jsonl')
AuditEvent.transport([memory, archive])
AuditEvent.subscribe { |event| Example.inbox.add(:audit, event.event_type) }
# The subscription is registered on both transports, so the archive file is
# tailed as well; only lines written from now on are delivered from it.

result = AuditEvent.new(event_type: 'login', user_id: 'U-1').publish
Example.wait_until { Example.inbox.count(:audit) == 2 }
Example.check('publish succeeded on both transports') do
  result.success? && result.outcomes.map(&:transport_name) == %w[MemoryTransport FileTransport]
end
Example.check('the event is on disk') { stored(archive, 'event_type') == ['login'] }
Example.check('the handler ran once per transport that delivered the event') { Example.inbox[:audit] == %w[login login] }
AuditEvent.unsubscribe!

Example.section 'Fan-out: one metric, two files'
primary = file_transport('metrics_primary.jsonl')
backup  = file_transport('metrics_backup.jsonl')
SystemMetric.transport([primary, backup])
[['cpu', 71.5, '%'], ['memory', 12.4, 'GB']].each do |metric_name, value, unit|
  SystemMetric.new(metric_name: metric_name, value: value, unit: unit, host: 'web-1').publish
end
Example.check('both files hold both metrics') do
  stored(primary, 'metric_name') == %w[cpu memory] && File.read(primary.path) == File.read(backup.path)
end

Example.section 'Partial failure: one file is unavailable'
backup.disconnect
partial = SystemMetric.new(metric_name: 'disk', value: 83, unit: '%', host: 'web-1').publish
puts "  #{partial.to_h}"
Example.check('the result is partial: primary succeeded, backup failed') do
  partial.partial? && partial.successful.map(&:transport) == [primary] && partial.failed.map(&:transport) == [backup]
end
Example.check('the primary file has the metric; the backup does not') { line_count(primary) == 3 && line_count(backup) == 2 }
Example.check('the copy that could not be written is in the dead letter queue') do
  entry = SmartMessage::DeadLetterQueue.default.peek
  entry[:transport] == 'SmartMessage::Transport::FileTransport' && entry[:error].include?('disconnected')
end

Example.section 'Routing: choose the file per message'
routes = { 'INFO' => file_transport('audit_info.jsonl'), 'CRITICAL' => file_transport('audit_critical.jsonl') }
events = [%w[login INFO], %w[logout INFO], %w[privilege_escalation CRITICAL]]
events.each do |event_type, severity|
  event = AuditEvent.new(event_type: event_type, user_id: 'U-1', severity: severity)
  event.transport(routes.fetch(severity)) # an instance-level transport replaces the class's
  event.publish
end
Example.check('routine events went to the info file') { stored(routes['INFO'], 'event_type') == %w[login logout] }
Example.check('the critical event went to its own file') do
  stored(routes['CRITICAL'], 'event_type') == ['privilege_escalation']
end
Example.check('routed events bypassed the class-level archive') { line_count(archive) == 1 }

Example.finish
