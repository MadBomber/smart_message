# test/envelope_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require 'bigdecimal'
require 'date'

# One codec turns messages into bytes and back, and it does not trust
# what it receives (review findings T2, T6).
class EnvelopeTest < Minitest::Test
  class Reading < SmartMessage::Base
    from 'sensor'
    property :value
    property :taken_at
    property :tags
    property :detail

    coerce_key :taken_at, ->(v) { v.is_a?(String) ? Time.parse(v) : v }
  end

  class Other < SmartMessage::Base
    from 'sensor'
    property :value
  end

  class NotAMessage; end

  def setup
    @serializer = SmartMessage::Serializer::Json.new
  end

  def encode(message)
    SmartMessage::Envelope.encode(message, @serializer)
  end

  def decode(payload, **options)
    SmartMessage::Envelope.decode(payload, serializer: @serializer, **options)
  end

  # ---- round trip ----------------------------------------------------------

  def test_round_trip_rebuilds_the_same_message
    original = Reading.new(value: 21.5, tags: %w[a b], detail: { unit: 'C', nested: [{ k: 1 }] }, to: 'hub')

    copy = decode(encode(original), channel: 'EnvelopeTest::Reading')

    assert_instance_of Reading, copy
    assert_equal original.uuid, copy.uuid
    assert_equal 'hub', copy.to
    assert_equal 21.5, copy.value
    assert_equal %w[a b], copy.tags
    assert_equal({ unit: 'C', nested: [{ k: 1 }] }, copy.detail)
    assert copy.valid?
  end

  def test_header_timestamp_comes_back_as_a_time_with_microseconds
    original = Reading.new(value: 1)

    copy = decode(encode(original))

    assert_instance_of Time, copy._sm_header.published_at
    assert_in_delta original._sm_header.published_at.to_f, copy._sm_header.published_at.to_f, 0.000_002
  end

  def test_header_records_the_serializer
    original = Reading.new(value: 1)
    encode(original)

    assert_equal 'SmartMessage::Serializer::Json', original._sm_header.serializer
    assert_equal 'SmartMessage::Serializer::Json', decode(encode(original))._sm_header.serializer
  end

  def test_declared_coercion_restores_a_type
    at = Time.at(1_700_000_000, 123_456, :usec)

    copy = decode(encode(Reading.new(value: 1, taken_at: at)))

    assert_instance_of Time, copy.taken_at
    assert_equal at, copy.taken_at
  end

  def test_json_type_changes_are_the_documented_ones
    jsonify = SmartMessage::Serializer::Json.method(:jsonify)

    assert_equal 'sym', jsonify.call(:sym)
    assert_equal '2026-01-02', jsonify.call(Date.new(2026, 1, 2))
    assert_equal '1.0', jsonify.call(BigDecimal('1'))
    assert_equal({ 'a' => [1, 'b', nil, true] }, jsonify.call({ a: [1, :b, nil, true] }))
    assert_match(/\A2026-01-02T03:04:05\.000007/, jsonify.call(Time.utc(2026, 1, 2, 3, 4, 5, 7)))
  end

  def test_json_encoding_does_not_depend_on_loaded_json_extensions
    message = Reading.new(value: 1)
    payload = encode(message)

    assert_match(/"published_at":"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}/, payload)
  end

  # ---- untrusted input -----------------------------------------------------

  def test_only_declared_properties_are_passed_to_the_message
    payload = encode(Reading.new(value: 1)).sub('"value":1', '"value":1,"injected":"x","transport":"y"')

    copy = decode(payload)

    assert_equal 1, copy.value
    assert_equal %i[_sm_header value taken_at tags detail], copy.to_h.keys
  end

  def test_class_named_in_header_must_match_the_channel
    payload = encode(Other.new(value: 1))

    error = assert_raises(SmartMessage::Errors::MessageClassMismatch) do
      decode(payload, channel: 'EnvelopeTest::Reading')
    end
    assert_match(/EnvelopeTest::Reading.*EnvelopeTest::Other/, error.message)
  end

  def test_class_must_be_a_message_class
    ['EnvelopeTest::NotAMessage', 'Kernel', 'File', 'SmartMessage::Base', 'No::Such::Thing', 'system("id")', ''].each do |name|
      payload = JSON.generate(_sm_header: { uuid: 'u', message_class: name, from: 'x' }, value: 1)

      assert_raises(SmartMessage::Errors::UnknownMessageClass, SmartMessage::Errors::DecodeError,
                    "#{name.inspect} must not be instantiated") { decode(payload) }
    end
  end

  def test_resolve_message_class
    resolve = SmartMessage::Envelope.method(:resolve_message_class)
    anonymous = Class.new(SmartMessage::Base)

    assert_same Reading, resolve.call('EnvelopeTest::Reading')
    assert_same anonymous, resolve.call(anonymous.to_s)
    assert_raises(SmartMessage::Errors::UnknownMessageClass) { resolve.call('String') }
  end

  def test_payloads_that_are_not_envelopes_are_rejected
    ['not json', '[1,2]', '"text"', '{"value":1}', '{"_sm_header":{}}', '{"_sm_header":"x"}'].each do |payload|
      assert_raises(SmartMessage::Errors::DecodeError, "#{payload} is not an envelope") { decode(payload) }
    end
  end

  def test_a_message_that_cannot_be_built_is_a_decode_error
    good = encode(Reading.new(value: 1, taken_at: '2026-01-01T00:00:00Z'))

    [
      good.sub(/"published_at":"[^"]*"/, '"published_at":"yesterday-ish"'),
      good.sub(/"taken_at":"[^"]*"/, '"taken_at":"not a time"')
    ].each do |payload|
      error = assert_raises(SmartMessage::Errors::DecodeError, payload) { decode(payload) }
      assert_kind_of ArgumentError, error.cause
      assert_match(/EnvelopeTest::Reading/, error.message)
    end
  end

  def test_unknown_header_fields_survive_a_round_trip
    payload = encode(Reading.new(value: 1)).sub('"_sm_header":{', '"_sm_header":{"trace_id":"t-9",')

    copy = decode(payload)

    assert_equal 't-9', copy._sm_header.extensions[:trace_id]
    assert_equal 't-9', decode(encode(copy))._sm_header.extensions[:trace_id]
  end

  def test_fallback_header_is_used_when_the_payload_has_none
    header = Reading.new(value: 1)._sm_header.to_wire

    copy = decode('{"value":5}', fallback_header: header)

    assert_equal 5, copy.value
    assert_equal header[:uuid], copy.uuid
  end

  # ---- serializer lookup ---------------------------------------------------

  def test_serializer_lookup_by_name
    assert_same SmartMessage::Serializer::Json, SmartMessage::Serializer.for('json')
    assert_same SmartMessage::Serializer::Json, SmartMessage::Serializer.for('SmartMessage::Serializer::Json')
    assert_nil SmartMessage::Serializer.for('msgpack')
    assert_nil SmartMessage::Serializer.for(nil)
  end

  def test_serializer_base_requires_an_implementation
    bare = Class.new(SmartMessage::Serializer::Base).new

    assert_raises(SmartMessage::Errors::NotImplemented) { bare.encode({}) }
    assert_raises(SmartMessage::Errors::NotImplemented) { bare.decode('') }
  end
end
