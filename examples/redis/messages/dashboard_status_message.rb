# examples/redis/messages/dashboard_status_message.rb
# frozen_string_literal: true

require_relative '../../../lib/smart_message'

# A summary of the whole system, broadcast by the dashboard.
class DashboardStatusMessage < SmartMessage::Base
  description 'System-wide status summary broadcast by the dashboard'

  STATUSES = %w[normal alert].freeze

  property :system_status,  required: true, validate: STATUSES,
                            validation_message: "System status must be one of: #{STATUSES.join(', ')}",
                            description: "Overall state: #{STATUSES.join(', ')}"
  property :active_devices, required: true, description: 'Number of devices that have reported'
  property :active_alerts,  required: true, description: 'Number of alerts received'
  property :summary_stats,  default: -> { {} }, description: 'Further metrics, such as the average battery level'
  property :last_updated,   default: -> { Time.now.iso8601 }, description: 'When the summary was built (ISO 8601)'
end
