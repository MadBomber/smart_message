# frozen_string_literal: true

# A security-relevant event that must be kept on disk.
class AuditEvent < SmartMessage::Base
  description 'An audit trail entry'
  from 'audit-service'

  SEVERITIES = %w[INFO WARN CRITICAL].freeze

  property :event_type, required: true
  property :user_id,    required: true
  property :severity,   default: 'INFO', validate: SEVERITIES,
                        validation_message: "severity must be one of #{SEVERITIES.join(', ')}"
end
