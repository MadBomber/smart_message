# frozen_string_literal: true

# Broadcast: a sender and no recipient (to is nil).
class SystemAnnouncementMessage < SmartMessage::Base
  description 'An announcement for every service'
  from 'admin-service'

  property :text,     required: true
  property :priority, default: 'normal'
end
