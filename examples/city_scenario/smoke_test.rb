#!/usr/bin/env ruby
# examples/city_scenario/smoke_test.rb
# frozen_string_literal: true
#
# Loads every file in messages/, then for each message class builds a
# sample, validates it, publishes it over the Redis transport and waits
# for a subscriber to receive it.  Exits non-zero when anything fails.
#
#   bundle exec ruby -Ilib examples/city_scenario/smoke_test.rb
#
# The run uses its own Redis namespace and a temporary log directory, so
# it does not disturb a running city.

require 'securerandom'
require 'tmpdir'

ENV['CITY_NAMESPACE'] = "city_smoke_#{SecureRandom.hex(4)}"
ENV['CITY_LOG_DIR']   = Dir.mktmpdir('smart_message_city_smoke_')

require_relative 'common/city'
Dir[File.join(__dir__, 'messages', '*.rb')].each { |file| require file }

module SmokeTest
  NOW = Time.now.strftime('%Y-%m-%d %H:%M:%S')

  # A valid set of properties for every message class in messages/.
  SAMPLES = {
    'Emergency911Message'      => { caller_location: '123 Main Street', emergency_type: 'fire',
                                    description: 'Smoke from the roof', severity: 'high', to: '911' },
    'EmergencyResolvedMessage' => { incident_id: 'abc123', incident_type: 'kitchen fire', location: '123 Main Street',
                                    resolved_by: 'fire_department', resolution_time: NOW, duration_minutes: 0.2 },
    'FireDispatchMessage'      => { dispatch_id: 'abc123', engines_assigned: %w[Engine-1], location: '123 Main Street',
                                    fire_type: 'kitchen', timestamp: NOW, to: 'house-123-main-street' },
    'FireEmergencyMessage'     => { house_address: '123 Main Street', fire_type: 'kitchen', severity: 'small',
                                    timestamp: NOW, to: 'fire_department' },
    'HealthCheckMessage'       => { check_id: 1 },
    'HealthStatusMessage'      => { service_name: 'fire_department', check_id: 1, status: 'healthy',
                                    to: 'health-department' },
    'PoliceDispatchMessage'    => { dispatch_id: 'abc123', units_assigned: %w[Unit-101], location: '123 Main Street',
                                    incident_type: 'robbery', priority: 'high', timestamp: NOW,
                                    to: 'first-national-bank' },
    'SilentAlarmMessage'       => { bank_name: 'first-national-bank', location: '123 Main Street',
                                    alarm_type: 'robbery', timestamp: NOW, severity: 'critical',
                                    to: 'police_department' }
  }.freeze

  module_function

  # @return [Array<Class>] every message class defined by messages/*.rb
  def message_classes
    Messages.constants.sort.map { |name| Messages.const_get(name) }
            .select { |constant| constant.is_a?(Class) && constant < SmartMessage::Base }
  end

  # @return [SmartMessage::Base] an unpublished sample of +message_class+
  def sample(message_class)
    properties = SAMPLES.fetch(message_class.name.split('::').last) do
      raise KeyError, "smoke_test.rb has no sample for #{message_class}"
    end
    message_class.new(**properties, from: 'smoke-test')
  end

  # @return [Object, nil] the next item of +queue+, or nil after +timeout+ seconds
  def wait_for(queue, timeout: 5)
    queue.pop(timeout: timeout)
  end

  # Publish one sample of a message class and wait for it to come back.
  #
  # @return [String, nil] what went wrong, or nil when everything worked
  def failure_for(message_class)
    received = Thread::Queue.new
    message_class.subscribe { |message| received << message }

    message = sample(message_class)
    message.validate!
    return 'publish did not succeed' unless message.publish.success?

    echo = wait_for(received)
    return 'no subscriber received the message within 5 seconds' unless echo
    return "received #{echo.class} with a different uuid" unless echo.instance_of?(message_class) && echo.uuid == message.uuid
    return 'received properties differ from the published ones' unless echo.payload_hash == message.payload_hash

    nil
  rescue StandardError => e
    "#{e.class.name}: #{e.message}"
  ensure
    message_class.unsubscribe!
  end

  # @return [Boolean] true when every message class passed
  def run
    Common::City.setup!('smoke_test')
    classes = message_classes
    puts "Smoke test: #{classes.size} message classes over Redis (namespace #{Common::City.namespace})"

    failures = classes.filter_map do |message_class|
      failure = failure_for(message_class)
      puts "  #{failure ? 'FAIL' : 'ok  '}  #{message_class}#{": #{failure}" if failure}"
      failure
    end

    failures << 'no message classes were found' if classes.empty?
    failures.empty?
  ensure
    Common::City.teardown!
    FileUtils.remove_entry(ENV.fetch('CITY_LOG_DIR'))
  end
end

if __FILE__ == $PROGRAM_NAME
  passed = SmokeTest.run
  puts passed ? 'All message classes passed.' : 'Smoke test FAILED.'
  exit(passed ? 0 : 1)
end
