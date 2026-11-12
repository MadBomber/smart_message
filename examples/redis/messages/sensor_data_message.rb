# examples/redis/messages/sensor_data_message.rb
# frozen_string_literal: true

require_relative '../../../lib/smart_message'

# A reading published by a smart home device.
class SensorDataMessage < SmartMessage::Base
  description 'Real-time sensor data from smart home IoT devices'

  DEVICE_TYPES = %w[thermostat security_camera door_lock].freeze

  property :device_id,     required: true, description: 'Device identifier, e.g. THERM-001'
  property :device_type,   required: true, validate: DEVICE_TYPES,
                           validation_message: "Device type must be one of: #{DEVICE_TYPES.join(', ')}",
                           description: "Kind of device: #{DEVICE_TYPES.join(', ')}"
  property :location,      description: 'Where the device is installed'
  property :sensor_type,   required: true, description: 'What was measured: temperature, motion, status'
  property :value,         required: true, description: 'The reading'
  property :unit,          description: 'Unit of the reading: celsius, boolean, string'
  property :battery_level, validate: 0..100, validation_message: 'Battery level must be between 0 and 100',
                           description: 'Battery charge in percent'
  property :timestamp,     default: -> { Time.now.iso8601 }, description: 'When the reading was taken (ISO 8601)'
end
