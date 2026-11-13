# test/message_model_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require 'bigdecimal'

# The message keeps the data it is given, rejects what it cannot hold,
# and validates in one place (review findings M1 to M7, K7).
class MessageModelTest < Minitest::Test
  class Order < SmartMessage::Base
    from 'order-service'

    property :order_id, required: true, message: 'An order needs an id'
    property :amount, validate: ->(v) { v > 0 }, validation_message: 'Amount must be positive'
    property :items, default: []
    property :meta
  end

  # ---- reserved names (M1) -----------------------------------------------

  def test_reserved_property_names_raise_at_class_definition
    %i[from to reply_to uuid _sm_header _sm_anything publish transport validate! to_h].each do |name|
      error = assert_raises(SmartMessage::Errors::ReservedPropertyName, "property :#{name} should be rejected") do
        Class.new(SmartMessage::Base) { property name }
      end
      assert_match(/reserved/, error.message)
    end
  end

  def test_reserved_property_error_is_an_argument_error
    assert_operator SmartMessage::Errors::ReservedPropertyName, :<, ArgumentError
  end

  def test_ordinary_property_names_are_allowed
    klass = Class.new(SmartMessage::Base) do
      property :description
      property :name
      property :status
    end

    assert_equal %i[description name status], klass.fields.to_a
  end

  # ---- no caller mutation (M2) ---------------------------------------------

  def test_construction_does_not_mutate_or_share_the_callers_data
    meta   = { 'tags' => ['a'], nested: { deep: 'value' } }
    frozen = Marshal.load(Marshal.dump(meta))

    message = Order.new(order_id: 1, meta: meta)

    assert_equal frozen, meta, 'the caller hash is left exactly as it was'
    assert_instance_of Hash, meta[:nested], 'and is not extended with Hashie behaviour'

    message.meta[:nested][:deep] = 'changed'
    message.meta['tags'] << 'b'

    assert_equal frozen, meta, 'changing the message does not change the caller hash'
  end

  def test_nested_keys_keep_the_type_they_were_given
    message = Order.new(order_id: 1, meta: { 'string_key' => 1, symbol_key: 2 })

    assert_equal ['string_key', :symbol_key], message.meta.keys
  end

  def test_accepts_a_positional_hash_and_string_keys
    message = Order.new({ 'order_id' => 7, amount: 3 })

    assert_equal 7, message.order_id
    assert_equal 7, message[:order_id]
    assert_equal 7, message['order_id']
  end

  # ---- header forward compatibility (M3) -----------------------------------

  def test_header_keeps_unknown_fields_in_extensions
    header = SmartMessage::Header.new(
      'uuid' => 'u-1', 'message_class' => 'X', 'published_at' => Time.now, 'publisher_pid' => 1,
      'from' => 'svc', 'trace_id' => 'abc', 'priority' => 5
    )

    assert_equal 'u-1', header.uuid
    assert_equal({ trace_id: 'abc', priority: 5 }, header.extensions)
    assert_equal 'abc', header.to_wire[:extensions][:trace_id]
  end

  def test_header_parses_a_string_timestamp
    header = SmartMessage::Header.new(uuid: 'u', message_class: 'X', publisher_pid: 1, from: 's',
                                      published_at: '2026-01-02T03:04:05.123456+00:00')

    assert_instance_of Time, header.published_at
    assert_equal 123_456, header.published_at.usec
  end

  # ---- Marshal and dup (M4, R14) -------------------------------------------

  def test_message_survives_marshal
    message = Order.new(order_id: 1, amount: 5, items: [{ sku: 'a' }])

    copy = Marshal.load(Marshal.dump(message))

    assert_instance_of Order, copy
    assert_equal message.to_h, copy.to_h
    assert copy.valid?
  end

  def test_dup_is_a_deep_copy
    message = Order.new(order_id: 1, items: [{ sku: 'a' }], meta: { note: 'x' })

    copy = message.dup
    copy.items.first[:sku] = 'changed'
    copy.meta[:note]       = 'changed'
    copy.from              = 'someone-else'
    copy.order_id          = 2

    assert_equal 'a', message.items.first[:sku]
    assert_equal 'x', message.meta[:note]
    assert_equal 'order-service', message.from
    assert_equal 1, message.order_id
    assert_equal message.uuid, copy.uuid, 'a copy is the same message'
    refute_same message._sm_header, copy._sm_header
  end

  # ---- one validation phase (M5, M6) ---------------------------------------

  def test_missing_required_property_is_reported_not_raised_at_construction
    message = Order.new(amount: 5)

    refute message.valid?
    errors = message.validation_errors
    assert_equal [:order_id], errors.map { |error| error[:property] }
    assert_equal 'An order needs an id', errors.first[:message]
    assert_equal 'message', errors.first[:source]
  end

  def test_validate_bang_raises_validation_error_listing_every_failure
    message = Order.new(amount: -1)

    error = assert_raises(SmartMessage::Errors::ValidationError) { message.validate! }

    assert_match(/order_id: An order needs an id/, error.message)
    assert_match(/amount: Amount must be positive/, error.message)
    assert_equal %i[order_id amount], error.errors.map { |e| e[:property] }
  end

  def test_an_invalid_message_can_be_repaired
    message = Order.new(amount: 5)
    message.order_id = 9

    assert message.valid?
    assert message.validate!
  end

  def test_publish_refuses_an_invalid_message
    Order.transport(SmartMessage::Transport::MemoryTransport.new(auto_process: false))

    assert_raises(SmartMessage::Errors::ValidationError) { Order.new(amount: 5).publish }
    assert_equal 0, Order.transport.message_count
  ensure
    Order.reset_transport
  end

  def test_a_validator_that_raises_is_a_failed_validation
    message = Order.new(order_id: 1, amount: 'not a number') # String > 0 raises

    refute message.valid?
    assert_equal [:amount], message.validation_errors.map { |error| error[:property] }
  end

  def test_run_validator_supports_every_validator_kind
    message = Order.new(order_id: 1)
    run     = ->(validator, value) { message.send(:run_validator, validator, value) }

    assert run.call(->(v) { v == 1 }, 1)
    refute run.call(->(v) { v == 1 }, 2)
    assert run.call(/\Aab/, 'abc')
    refute run.call(/\Aab/, 'xbc')
    assert run.call(Integer, 1)
    refute run.call(Integer, '1')
    assert run.call(%w[a b], 'a')
    refute run.call(%w[a b], 'c')
    assert run.call(1..5, 3)
    refute run.call(1..5, 9)
    assert run.call('exact', 'exact')
    refute run.call(->(_v) { raise 'boom' }, 1)
  end

  def test_conditionally_required_property
    klass = Class.new(SmartMessage::Base) do
      from 'svc'
      property :kind
      property :reason, required: -> { kind == 'refund' }
    end

    assert klass.new(kind: 'sale').valid?
    refute klass.new(kind: 'refund').valid?
    assert klass.new(kind: 'refund', reason: 'damaged').valid?
  end

  def test_conditionally_required_property_with_a_lambda_that_takes_the_message
    klass = Class.new(SmartMessage::Base) do
      from 'svc'
      property :kind
      property :addr, required: ->(message) { message.kind == 'physical' }
    end

    assert klass.new(kind: 'digital').valid?
    refute klass.new(kind: 'physical').valid?
    assert klass.new(kind: 'physical', addr: 'Dock 4').valid?
  end

  def test_required_now_passes_the_message_only_to_a_condition_that_takes_it
    message = Order.new(order_id: 1)

    assert message.send(:required_now?, -> { order_id == 1 })
    assert message.send(:required_now?, ->(m) { m.equal?(message) })
    assert message.send(:required_now?, proc { |m| m.equal?(message) })
    refute message.send(:required_now?, ->(m) { m.order_id == 2 })
    assert message.send(:required_now?, true)
    refute message.send(:required_now?, false)
  end

  # ---- addressing lives in the header only (K7) ----------------------------

  def test_addressing_reads_and_writes_the_header
    message = Order.new(order_id: 1, to: 'warehouse')

    assert_equal 'warehouse', message.to
    message._sm_header.to = 'billing'
    assert_equal 'billing', message.to, 'writing the header directly is visible through the accessor'

    message.to = 'archive'
    assert_equal 'archive', message._sm_header.to
  end

  # ---- cleanup (M7) --------------------------------------------------------

  def test_header_dsl_with_arguments_raises
    assert_raises(ArgumentError) { Order.header(:anything) }
    assert_raises(ArgumentError) { Order.header }
  end

  def test_removed_legacy_api_is_gone
    message = Order.new(order_id: 1)

    refute_respond_to Order, :decode
    refute Order.method_defined?(:_sm_payload)
    refute Order.method_defined?(:split)
    refute SmartMessage::Errors.const_defined?(:SerializerNotConfigured)
    refute Object.const_defined?(:MilClass)
    refute Object.const_defined?(:SimpleStats)
    assert_raises(NoMethodError) { message.split }
  end

  def test_pretty_print_writes_to_the_given_io
    out = StringIO.new
    Order.new(order_id: 42, amount: 3).pretty_print(include_header: true, out: out)

    assert_match(/Header:/, out.string)
    assert_match(/order-service/, out.string)
    assert_match(/42/, out.string)
  end

  def test_pretty_print_keeps_hash_keys_that_are_not_strings_or_symbols
    out = StringIO.new
    Order.new(order_id: 1, amount: 3, meta: { 1 => 'a', nil => 'b', 'k' => 'c' }).pretty_print(out: out)

    assert_match(/"a"/, out.string)
    assert_match(/"b"/, out.string)
    assert_match(/k/, out.string)
  end
end
