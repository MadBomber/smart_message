#!/usr/bin/env ruby
# examples/memory/10_entity_addressing_basic.rb
# frozen_string_literal: true
#
# Entity addressing: from, to and reply_to
#
#   from      who sent it (required)
#   to        the recipient; nil means broadcast
#   reply_to  where an answer should go
#
# A class sets defaults; an instance can override them.  The values travel
# in the message header.

require_relative '../support/example_helper'
require_relative 'messages/shipment_message'
require_relative 'messages/system_announcement_message'
require_relative 'messages/user_lookup_request'
require_relative 'messages/user_lookup_response'

TRANSPORT = SmartMessage::Transport::MemoryTransport.new
[ShipmentMessage, SystemAnnouncementMessage, UserLookupRequest, UserLookupResponse].each { it.transport(TRANSPORT) }

# Answers lookups, sending each answer to the request's reply_to.
module UserService
  USERS = { 'U-1' => 'Ada Lovelace' }.freeze

  def self.lookup(request)
    name = USERS[request.user_id]
    UserLookupResponse.new(request_id: request.request_id, user_name: name, found: !name.nil?, to: request.reply_to).publish
  end
end

def addressing(message) = [message.from, message.to, message.reply_to]

Example.title 'Entity addressing'

Example.section 'Point-to-point: class defaults name sender and recipient'
ShipmentMessage.subscribe { |message| Example.inbox.add(:shipments, addressing(message)) }
ShipmentMessage.new(order_id: 'ORD-1', address: '1 Main St').publish

Example.section 'Instance override: same class, different recipient'
rerouted = ShipmentMessage.new(order_id: 'ORD-2', address: '2 Side St', to: 'backup-warehouse')
rerouted.publish

Example.section 'Broadcast: no recipient'
SystemAnnouncementMessage.subscribe { |message| Example.inbox.add(:announcements, addressing(message)) }
SystemAnnouncementMessage.new(text: 'Maintenance at 02:00').publish

Example.section 'Request-reply: the answer goes to reply_to'
UserLookupRequest.subscribe('UserService.lookup')
UserLookupResponse.subscribe { |message| Example.inbox.add(:replies, message) }
UserLookupRequest.new(request_id: 'REQ-1', user_id: 'U-1').publish
UserLookupRequest.new(request_id: 'REQ-2', user_id: 'U-404', reply_to: 'audit-service').publish

Example.wait_for_idle(TRANSPORT)

Example.check('the first shipment used the class defaults') do
  Example.inbox[:shipments].include?(['order-service', 'fulfillment-service', nil])
end
Example.check('the second shipment went to the overridden recipient') do
  Example.inbox[:shipments].include?(['order-service', 'backup-warehouse', nil])
end
Example.check('the override did not change the class default') { ShipmentMessage.to == 'fulfillment-service' }
Example.check('the announcement is a broadcast: to is nil') do
  Example.inbox[:announcements] == [['admin-service', nil, nil]]
end

replies = Example.inbox[:replies].to_h { [it.request_id, it] }
replies.each_value { puts "  #{it.request_id}: #{it.from} -> #{it.to} found=#{it.found} #{it.user_name}" }
Example.check('REQ-1 was answered to the requester (web-app)') do
  replies['REQ-1'].to == 'web-app' && replies['REQ-1'].user_name == 'Ada Lovelace'
end
Example.check('REQ-2 was answered to its own reply_to (audit-service)') do
  replies['REQ-2'].to == 'audit-service' && replies['REQ-2'].found == false
end

Example.finish
