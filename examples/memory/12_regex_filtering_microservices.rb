#!/usr/bin/env ruby
# examples/memory/12_regex_filtering_microservices.rb
# frozen_string_literal: true
#
# Regular expressions in subscription filters
#
# from: and to: accept a Regexp, or an Array mixing exact Strings and
# Regexps.  With entity ids that follow a naming convention this routes
# by environment ("prod-...") or by service family ("payment-...").

require_relative '../support/example_helper'
require_relative 'messages/microservice_message'

TRANSPORT = SmartMessage::Transport::MemoryTransport.new
MicroserviceMessage.transport(TRANSPORT)

FILTERS = {
  payment_family:   { from: /\Apayment-/ },
  non_production:   { to: /\A(dev|staging)-/ },
  production_or_me: { to: [/\Aprod-/, 'audit-log'] },
  admin_or_system:  { from: ['admin', /\Asystem-/] },
  payments_to_prod: { from: /\Apayment-/, to: /\Aprod-/ },
  alerts:           { from: /-monitor\z/, broadcast: true }
}.freeze

TRAFFIC = [
  { action: 'charge',  from: 'payment-gateway',   to: 'prod-orders' },
  { action: 'refund',  from: 'payment-processor', to: 'staging-orders' },
  { action: 'deploy',  from: 'admin',             to: 'dev-api' },
  { action: 'archive', from: 'system-cron',       to: 'audit-log' },
  { action: 'cpu',     from: 'system-monitor',    to: nil },
  { action: 'signup',  from: 'web-frontend',      to: 'prod-users' }
].freeze

EXPECTED = {
  payment_family:   %w[charge refund],
  non_production:   %w[deploy refund],
  production_or_me: %w[archive charge signup],
  admin_or_system:  %w[archive cpu deploy],
  payments_to_prod: %w[charge],
  alerts:           %w[cpu]
}.freeze

Example.title 'Regex filtering'

FILTERS.each do |name, filters|
  MicroserviceMessage.subscribe(**filters) { |message| Example.inbox.add(name, message.action) }
end
TRAFFIC.each { MicroserviceMessage.new(**it).publish }
Example.wait_for_idle(TRANSPORT)

EXPECTED.each do |name, actions|
  puts "  #{name.to_s.ljust(17)} #{FILTERS[name].inspect.ljust(46)} => #{Example.inbox[name].sort.join(', ')}"
  Example.check("#{name} matched #{actions.join(' and ')}") { Example.inbox[name].sort == actions }
end

Example.finish
