# examples/redis/messages/device_command_message.rb
# frozen_string_literal: true

require_relative '../../../lib/smart_message'

# A command for one device.  The target device is the message's +to+
# address, so each device subscribes with `to: its_own_id`.
class DeviceCommandMessage < SmartMessage::Base
  description 'A command sent to one smart home device'

  COMMANDS = %w[set_temperature start_recording stop_recording lock unlock get_status].freeze

  property :command,      required: true, validate: COMMANDS,
                          validation_message: "Command must be one of: #{COMMANDS.join(', ')}",
                          description: "What the device should do: #{COMMANDS.join(', ')}"
  property :parameters,   default: -> { {} }, description: 'Command-specific parameters'
  property :requested_by, description: 'The user, schedule, or automation that asked for this'
  property :timestamp,    default: -> { Time.now.iso8601 }, description: 'When the command was issued (ISO 8601)'
end
