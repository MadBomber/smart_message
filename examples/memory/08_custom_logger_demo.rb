#!/usr/bin/env ruby
# examples/memory/08_custom_logger_demo.rb
# frozen_string_literal: true
#
# Custom loggers
#
# SmartMessage logs nothing unless a logger is configured.  A logger can be:
#
#   * any object with the standard Ruby Logger interface (Logger.new,
#     Rails.logger, ...): the framework only calls debug/info/warn/error/fatal
#     with a block
#   * a subclass of SmartMessage::Logger::Base, which adds keyword data,
#     level predicates and add(level, text)
#
# and it can be set globally (config.logger) or for one message class
# (MyMessage.logger(a_logger)).

require 'logger'
require_relative '../support/example_helper'
require_relative 'messages/order_processing_message'

# A logger that keeps its entries in memory, e.g. to assert on them in tests.
class CollectingLogger < SmartMessage::Logger::Base
  attr_reader :level

  def initialize(level: :debug)
    @entries = []
    @mutex   = Mutex.new
    self.level = level
  end

  def level=(value)
    @level = SmartMessage::Logger.severity(value)
  end

  # @return [Array<Hash>] { level:, text:, data: }
  def entries = @mutex.synchronize { @entries.dup }

  def texts = entries.map { it[:text] }

  private

  def log(severity, message, data, &block)
    return if severity < level

    entry = { level: SmartMessage::Logger::LEVELS[severity], text: resolve_message(message, &block), data: data }
    @mutex.synchronize { @entries << entry }
    nil
  end
end

def publish_order(order_id)
  OrderProcessingMessage.new(order_id: order_id).publish
  Example.wait_for_idle(OrderProcessingMessage.transport)
end

Example.title 'Custom loggers'
OrderProcessingMessage.transport(SmartMessage::Transport::MemoryTransport.new)

Example.section 'No logger configured: nothing is logged'
Example.check('the default logger is the Null logger') do
  SmartMessage::Logger.default.is_a?(SmartMessage::Logger::Null)
end

Example.section 'A global custom logger sees the whole framework'
collector = CollectingLogger.new
SmartMessage.configure { |config| config.logger = collector }
OrderProcessingMessage.subscribe
publish_order('ORD-1')
collector.texts.each { puts "  #{it}" }
Example.check('the subscription and the publish were logged') do
  collector.texts.any?(/Subscribed: OrderProcessingMessage/) &&
    collector.texts.any?(/Published: OrderProcessingMessage via MemoryTransport/)
end
Example.check('the dispatcher logged the routing at debug level') do
  collector.entries.any? { it[:level] == :debug && it[:text].include?('Routing OrderProcessingMessage') }
end

Example.section 'The richer interface: keyword data, predicates, add'
collector.warn('Stock is low', sku: 'W-1', left: 2)
collector.add(:error, 'Carrier unreachable')
Example.check('keyword data stays separate from the text') do
  collector.entries.any? { it[:text] == 'Stock is low' && it[:data] == { sku: 'W-1', left: 2 } }
end
Example.check('level predicates follow the level') do
  collector.level = :warn
  collector.warn? && !collector.info?
end

Example.section 'A standard library Logger, for one message class only'
log_path = Example.tmp_path('orders.log')
OrderProcessingMessage.logger(Logger.new(log_path, level: Logger::INFO))
publish_order('ORD-2')
log_lines = File.readlines(log_path, chomp: true).grep(/SmartMessage/)
log_lines.each { puts "  #{it}" }
Example.check('the class logger received the publish of ORD-2') do
  log_lines.any?(/INFO.*Published: OrderProcessingMessage/)
end
Example.check('the class logger is at INFO, so the Created debug line is absent') do
  log_lines.none?(/Created/)
end
Example.check('both orders reached the handler') { Example.inbox[:orders].sort == %w[ORD-1 ORD-2] }

Example.finish
