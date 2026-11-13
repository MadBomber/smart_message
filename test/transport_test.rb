# test/transport_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'helpers/transport_contract'

# The transport registry, the base class, and the two in-process
# transports (review findings T4, T5, T7, T8).
class TransportRegistryTest < Minitest::Test
  def test_built_in_transports_are_registered
    assert_equal %i[memory stdout file redis], SmartMessage::Transport.available & %i[memory stdout file redis]
    assert_same SmartMessage::Transport::MemoryTransport, SmartMessage::Transport.get(:memory)
    assert_same SmartMessage::Transport::StdoutTransport, SmartMessage::Transport.get('stdout')
    assert_same SmartMessage::Transport::FileTransport,   SmartMessage::Transport.get(:file)
    assert_same SmartMessage::Transport::RedisTransport,  SmartMessage::Transport.get(:redis)
    assert_nil SmartMessage::Transport.get(:carrier_pigeon)
  end

  def test_create_builds_a_transport_with_its_options
    transport = SmartMessage::Transport.create(:memory, auto_process: false)

    assert_instance_of SmartMessage::Transport::MemoryTransport, transport
    refute transport.options[:auto_process]
  end

  def test_create_raises_for_an_unknown_transport
    error = assert_raises(ArgumentError) { SmartMessage::Transport.create(:carrier_pigeon) }

    assert_match(/Unknown transport: :carrier_pigeon/, error.message)
    assert_match(/memory/, error.message)
  end

  def test_register_accepts_only_transport_classes
    registry = SmartMessage::Transport::Registry.new
    custom   = Class.new(SmartMessage::Transport::Base)

    registry.register('custom', custom)

    assert registry.registered?(:custom)
    assert_same custom, registry.get(:custom)
    assert_includes registry.list, :custom
    assert_raises(ArgumentError) { registry.register(:bad, String) }
    assert_raises(ArgumentError) { registry.register(:bad, 'SmartMessage::Transport::MemoryTransport') }

    registry.clear
    assert_empty registry.list
  end

  def test_there_is_no_default_transport
    assert_nil SmartMessage::Transport.default

    transport = SmartMessage::Transport::MemoryTransport.new
    SmartMessage.configure { |config| config.transport = transport }

    assert_same transport, SmartMessage::Transport.default
  end
end

class TransportBaseTest < Minitest::Test
  class Sample < SmartMessage::Base
    from 'base-test'
    property :value
  end

  # Exposes #receive, which is protected
  class Inbound < SmartMessage::Transport::Base
    def do_publish(_message_class, _serialized_message) = nil
    def deliver(message_class, payload) = receive(message_class, payload)
  end

  def test_do_publish_must_be_implemented
    bare = SmartMessage::Transport::Base.new

    assert_raises(SmartMessage::Errors::NotImplemented) { bare.publish(Sample.new(value: 1)) }
    assert_kind_of StandardError, SmartMessage::Errors::NotImplemented.new
  end

  def test_options_merge_over_the_defaults
    klass = Class.new(SmartMessage::Transport::Base) do
      def default_options = { a: 1, b: 2 }
    end

    assert_equal({ a: 1, b: 3, c: 4 }, klass.new(b: 3, c: 4).options)
  end

  def test_a_dispatcher_and_serializer_can_be_supplied
    dispatcher = SmartMessage::Dispatcher.new
    serializer = SmartMessage::Serializer::Json.new

    transport = Inbound.new(dispatcher: dispatcher, serializer: serializer)

    assert_same dispatcher, transport.dispatcher
    assert_same serializer, transport.serializer
  end

  def test_an_undecodable_payload_is_dead_lettered_and_raised
    transport = Inbound.new

    assert_raises(SmartMessage::Errors::DecodeError) { transport.deliver('TransportBaseTest::Sample', '{not json') }

    assert_equal 1, dlq.size
    entry = dlq.peek
    assert_equal '{not json', entry[:payload]
    assert_equal 'TransportBaseTest::Sample', entry[:header][:message_class]
    assert_match(/DecodeError/, entry[:error])
    assert_equal 'TransportBaseTest::Inbound', entry[:transport]
  end

  def test_a_payload_for_the_wrong_channel_is_dead_lettered_and_raised
    transport = Inbound.new
    payload   = transport.encode_message(Sample.new(value: 1))

    assert_raises(SmartMessage::Errors::MessageClassMismatch) { transport.deliver('Some::Other::Class', payload) }
    assert_equal 1, dlq.size
  end

  def test_receive_without_subscribers_routes_to_nobody
    transport = Inbound.new

    assert_nil transport.deliver(nil, transport.encode_message(Sample.new(value: 1)))
    assert dlq.empty?
  end
end

class MemoryTransportTest < Minitest::Test
  include TransportContract

  def new_transport(**options)
    SmartMessage::Transport::MemoryTransport.new(**options)
  end

  def test_stores_messages_only_when_not_auto_processing
    refute new_transport.store_messages?
    assert new_transport(auto_process: false).store_messages?
    assert new_transport(store_messages: true).store_messages?
    refute new_transport(auto_process: false, store_messages: false).store_messages?
  end

  def test_max_messages_must_be_a_positive_integer
    [0, -1, nil, '5', 2.5].each do |bad|
      error = assert_raises(ArgumentError, "max_messages: #{bad.inspect}") { new_transport(max_messages: bad) }
      assert_match(/max_messages/, error.message)
    end
  end

  def test_auto_processing_does_not_grow_the_store
    use
    collect

    50.times { |i| ContractMessage.new(value: i).publish }

    assert_equal 0, transport.message_count
  end

  def test_stored_messages_are_bounded
    stored = use(track(new_transport(auto_process: false, max_messages: 3)))

    5.times { |i| ContractMessage.new(value: i).publish }

    assert_equal 3, stored.message_count
    values = stored.all_messages.map { |entry| stored.decode_message(entry[:payload]).value }
    assert_equal [2, 3, 4], values, 'the oldest messages were dropped'
    assert_equal %i[message_class payload published_at], stored.all_messages.first.keys

    stored.clear_messages
    assert_equal 0, stored.message_count
  end

  def test_process_all_delivers_each_stored_message_once
    stored   = use(track(new_transport(auto_process: false)))
    received = collect
    3.times { |i| ContractMessage.new(value: i).publish }
    assert received.empty?, 'nothing is delivered until process_all'

    assert_equal 3, stored.process_all
    assert_equal 0, stored.process_all, 'a second call has nothing left to deliver'

    wait_for_dispatch(stored)
    assert_equal 3, received.size
    assert_equal 0, stored.message_count
  end

  def test_serialization_is_on_by_default_so_type_changes_show_up
    use
    received = collect

    ContractMessage.new(value: :a_symbol).publish
    wait_until { !received.empty? }

    assert_equal 'a_symbol', received.pop.value, 'as it would over a real transport'
  end

  def test_serialize_false_hands_handlers_a_copy_of_the_object
    direct   = use(track(new_transport(serialize: false)))
    received = collect
    original = ContractMessage.new(value: :a_symbol, detail: { list: [1] })

    original.publish
    wait_until { !received.empty? }
    copy = received.pop

    assert_equal :a_symbol, copy.value
    refute_same original, copy
    copy.detail[:list] << 2
    assert_equal [1], original.detail[:list]
    assert_same direct, ContractMessage.transport
  end
end

class StdoutTransportTest < Minitest::Test
  include TransportContract

  def output
    @output ||= StringIO.new
  end

  def new_transport(**options)
    SmartMessage::Transport::StdoutTransport.new(output: output, loopback: true, **options)
  end

  def test_writes_one_line_of_json_per_message
    plain = use(track(SmartMessage::Transport::StdoutTransport.new(output: output)))

    2.times { |i| ContractMessage.new(value: i).publish }

    lines = output.string.lines
    assert_equal 2, lines.size
    assert_equal [0, 1], lines.map { |line| JSON.parse(line)['value'] }
    assert_equal 'TransportContract::ContractMessage', JSON.parse(lines.first).dig('_sm_header', 'message_class')
    assert_same plain, ContractMessage.transport
  end

  def test_without_loopback_subscribers_are_not_called
    use(track(SmartMessage::Transport::StdoutTransport.new(output: output)))
    received = collect

    ContractMessage.new(value: 1).publish
    sleep 0.05

    assert received.empty?
  end

  def test_default_output_is_the_current_stdout
    plain = track(SmartMessage::Transport::StdoutTransport.new)

    out, _err = capture_io { plain.publish(ContractMessage.new(value: 'to-stdout')) }

    assert_match(/"value":"to-stdout"/, out)
    assert_same $stdout, plain.output
  end

  def test_disconnect_never_closes_the_io
    transport.publish(ContractMessage.new(value: 1))

    transport.disconnect

    refute output.closed?
    refute $stdout.closed?
    assert transport.publish(ContractMessage.new(value: 2)), 'and the transport still works'
  end

  def test_an_io_that_fails_makes_the_publish_fail
    read_end, write_end = IO.pipe
    write_end.close
    broken = use(track(SmartMessage::Transport::StdoutTransport.new(output: write_end)))

    assert_raises(SmartMessage::Errors::PublishError) { ContractMessage.new(value: 1).publish }
    assert_equal 1, dlq.size
    assert broken.transport_circuit_stats[:transport_publish][:closed], 'one failure is below the threshold'
  ensure
    read_end&.close
  end

  def test_concurrent_publishers_do_not_interleave_lines
    plain = track(SmartMessage::Transport::StdoutTransport.new(output: output))

    Array.new(8) { |t| Thread.new { 25.times { |i| plain.publish(ContractMessage.new(value: "#{t}-#{i}", detail: 'x' * 200)) } } }.each(&:join)

    lines = output.string.lines
    assert_equal 200, lines.size
    assert_equal 200, lines.map { |line| JSON.parse(line)['value'] }.uniq.size
  end
end
