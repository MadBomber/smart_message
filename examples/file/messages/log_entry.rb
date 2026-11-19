# frozen_string_literal: true

# A log line that readers tail from a shared file.
class LogEntry < SmartMessage::Base
  description 'A log entry appended by a writer and tailed by readers'
  from 'log-writer'

  property :sequence, required: true
  property :level,    default: 'INFO'
  property :text,     required: true
end
