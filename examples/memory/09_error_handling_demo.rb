#!/usr/bin/env ruby
# examples/memory/09_error_handling_demo.rb
# frozen_string_literal: true
#
# Error handling: validation, versions, and configuration mistakes
#
# Nothing is validated in new.  valid?, validation_errors and validate!
# report every problem at once, and publish calls validate! first.

require_relative '../support/example_helper'
require_relative 'messages/user_registration_message'
require_relative 'messages/user_registration_message_v2'

VALID = { user_id: 'U-1', email: 'ada@example.com', age: 36, username: 'ada_l' }.freeze

# @return [Exception, nil] what the block raised
def error_from
  yield
  nil
rescue StandardError => e
  e
end

def show(error) = puts("  #{error.class}: #{error.message}")

Example.title 'Error handling'
transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
UserRegistrationMessage.transport(transport)

Example.section 'Missing required properties'
incomplete = UserRegistrationMessage.new(user_id: 'U-1')
Example.check('new does not raise for an incomplete message') { !incomplete.valid? }
Example.check('validation_errors lists every missing property') do
  incomplete.validation_errors.map { it[:property] } == %i[email age username]
end
error = error_from { incomplete.publish }
show(error)
Example.check('publish raises ValidationError with the same list on error.errors') do
  error.is_a?(SmartMessage::Errors::ValidationError) && error.errors.size == 3
end
Example.check('nothing was published') { transport.message_count.zero? }

Example.section 'Validators: regexp, range, lambda, and list'
invalid = UserRegistrationMessage.new(user_id: 'U-2', email: 'not-an-email', age: 7, username: 'x', plan: 'gold')
invalid.validation_errors.each { puts "  #{it[:property]}: #{it[:message]} (got #{it[:value].inspect})" }
Example.check('all four validators failed') do
  invalid.validation_errors.map { it[:property] } == %i[email age username plan]
end
Example.check('a corrected message is valid and publishes') do
  invalid.email    = 'bob@example.com'
  invalid.age      = 41
  invalid.username = 'bob'
  invalid.plan     = 'premium'
  invalid.valid? && invalid.publish.success?
end

Example.section 'A missing sender'
anonymous = UserRegistrationMessage.new(**VALID)
anonymous.from = nil
error = error_from { anonymous.validate! }
show(error)
Example.check('the header requires from') { error.errors.map { it[:property] } == [:from] }

Example.section 'Schema versions'
v2 = UserRegistrationMessageV2.new(**VALID, phone_number: '+15551234567')
Example.check('a V2 message carries version 2 and inherits the V1 validators') do
  v2._sm_header.version == 2 && v2.valid? && UserRegistrationMessageV2.required_property?(:email)
end
stale = UserRegistrationMessage.new(**VALID)
stale._sm_header.version = 2 # as if a newer publisher had sent it
error = error_from { stale.validate! }
show(error)
Example.check('a header version the class does not expect is a validation error') do
  error.errors.map { it[:source] } == ['version_mismatch']
end

Example.section 'Configuration mistakes'
UserRegistrationMessage.reset_transport
error = error_from { v2.publish }
show(error)
Example.check('publishing without a transport raises TransportNotConfigured') do
  error.is_a?(SmartMessage::Errors::TransportNotConfigured)
end

error = error_from { require_relative 'messages/reserved_property_message' }
show(error)
Example.check('declaring a reserved property name raises when the class is defined') do
  error.is_a?(SmartMessage::Errors::ReservedPropertyName)
end

error = error_from { SmartMessage::Transport.create(:carrier_pigeon) }
show(error)
Example.check('an unknown transport name raises ArgumentError') { error.is_a?(ArgumentError) }

Example.finish
