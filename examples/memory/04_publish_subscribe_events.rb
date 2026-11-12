#!/usr/bin/env ruby
# examples/memory/04_publish_subscribe_events.rb
# frozen_string_literal: true
#
# Publish-subscribe (1-to-many) messaging: user events
#
# One publisher, three independent subscribers.  Every subscriber gets its
# own copy of each event and decides what to do with it.
# See publish_subscribe_pattern.svg.

require_relative '../support/example_helper'
require_relative 'messages/user_event_message'

TRANSPORT = SmartMessage::Transport::MemoryTransport.new
UserEventMessage.transport(TRANSPORT)

# Welcomes new users and warns about password changes.
module EmailService
  SUBJECTS = { 'user_registered' => 'Welcome!', 'password_changed' => 'Your password was changed' }.freeze

  def self.handle_event(event)
    subject = SUBJECTS[event.event_type]
    Example.inbox.add(:email, "#{event.user_email}: #{subject}") if subject
  end
end

# Texts the user about security events only.
module SmsService
  def self.handle_event(event)
    Example.inbox.add(:sms, event.user_id) if event.event_type == 'password_changed'
  end
end

# Records everything.
module AuditService
  def self.handle_event(event)
    Example.inbox.add(:audit, event.event_type)
  end
end

def publish_event(event_type, details = {})
  UserEventMessage.new(event_type: event_type, user_id: 'U-1', user_email: 'ada@example.com', details: details).publish
end

Example.title 'Publish-subscribe user events'
%w[EmailService SmsService AuditService].each { UserEventMessage.subscribe("#{it}.handle_event") }

publish_event('user_registered', source: 'web')
publish_event('user_login', ip: '10.0.0.7')
publish_event('password_changed')
Example.wait_for_idle(TRANSPORT)

puts <<~SUMMARY
  email: #{Example.inbox[:email]}
  sms:   #{Example.inbox[:sms]}
  audit: #{Example.inbox[:audit].sort}
SUMMARY

Example.check('the class has three subscribers') { TRANSPORT.subscribers['UserEventMessage'].size == 3 }
Example.check('the audit service saw all three events') do
  Example.inbox[:audit].sort == %w[password_changed user_login user_registered]
end
Example.check('the email service sent two emails') { Example.inbox.count(:email) == 2 }
Example.check('the SMS service acted on the password change only') { Example.inbox[:sms] == ['U-1'] }

invalid = UserEventMessage.new(event_type: 'user_deleted', user_id: 'U-1', user_email: 'ada@example.com')
Example.check('an event type outside the allowed list is rejected at publish') do
  invalid.publish
  false
rescue SmartMessage::Errors::ValidationError
  true
end

Example.finish
