# test/helpers/transport_contract.rb
# encoding: utf-8
# frozen_string_literal: true

# What every transport must do (see SmartMessage::Transport::Base).
#
# The including test class defines:
#
#   new_transport(**options)  build the transport under test, configured so
#                             that what it publishes comes back to its own
#                             subscribers
#
# and may call #track(transport) for extra transports it builds, so they
# are disconnected at teardown.
module TransportContract
  class ContractMessage < SmartMessage::Base
    from 'contract-test'
    property :value
    property :detail
  end

  class OtherMessage < SmartMessage::Base
    from 'contract-test'
    property :value
  end

  MESSAGE_CLASSES = [ContractMessage, OtherMessage].freeze

  def track(transport)
    (@tracked_transports ||= []) << transport
    transport
  end

  def transport
    @transport ||= track(new_transport)
  end

  def after_teardown
    MESSAGE_CLASSES.each do |klass|
      klass.unsubscribe! unless klass.transport_missing?
    rescue StandardError
      nil # the transport was disconnected by the test
    ensure
      klass.reset_transport
    end
    (@tracked_transports || []).each do |tracked|
      tracked.disconnect
      tracked.dispatcher.shutdown(timeout: 2)
    end
    super
  end

  # Subscribe a collecting handler and return the Queue it fills.
  def collect(klass = ContractMessage, **filters)
    received = Queue.new
    klass.subscribe(**filters) { |message| received << message }
    received
  end

  def use(a_transport = transport)
    MESSAGE_CLASSES.each { |klass| klass.transport(a_transport) }
    a_transport
  end

  # ---- the contract --------------------------------------------------------

  def test_contract_is_a_transport
    assert_kind_of SmartMessage::Transport::Base, transport
    assert_kind_of SmartMessage::Dispatcher, transport.dispatcher
    assert_kind_of SmartMessage::Serializer::Base, transport.serializer
    assert transport.connected?
  end

  def test_contract_published_message_reaches_a_subscriber_intact
    use
    received = collect
    original = ContractMessage.new(value: 42, detail: { tags: %w[a b], nested: { n: 1 } }, to: 'someone')

    result = original.publish

    assert result.success?
    wait_until(message: 'the message was not delivered') { !received.empty? }
    copy = received.pop
    assert_instance_of ContractMessage, copy
    refute_same original, copy
    assert_equal original.uuid, copy.uuid
    assert_equal 42, copy.value
    assert_equal({ tags: %w[a b], nested: { n: 1 } }, copy.detail)
    assert_equal 'contract-test', copy.from
    assert_equal 'someone', copy.to
    assert_instance_of Time, copy._sm_header.published_at
  end

  def test_contract_every_message_arrives_once_and_in_order
    use
    received = collect

    20.times { |i| ContractMessage.new(value: i).publish }

    wait_until(message: 'not every message was delivered') { received.size >= 20 }
    sleep 0.05 # anything delivered twice would show up now
    assert_equal 20, received.size
    assert_equal (0...20).to_a, Array.new(20) { received.pop.value }.sort
  end

  def test_contract_messages_go_only_to_subscribers_of_their_class
    use
    contract = collect(ContractMessage)
    other    = collect(OtherMessage)

    OtherMessage.new(value: 'other').publish
    ContractMessage.new(value: 'contract').publish

    wait_until { !contract.empty? && !other.empty? }
    sleep 0.05
    assert_equal ['contract'], Array.new(contract.size) { contract.pop.value }
    assert_equal ['other'],    Array.new(other.size) { other.pop.value }
  end

  def test_contract_unsubscribe_stops_delivery
    use
    received = collect
    ContractMessage.new(value: 1).publish
    wait_until { received.size == 1 }

    ContractMessage.unsubscribe!
    ContractMessage.new(value: 2).publish
    sleep 0.1

    assert_equal 1, received.size
    assert_empty transport.subscribers['TransportContract::ContractMessage']
  end

  def test_contract_filters_apply
    use
    received = collect(to: 'me')

    ContractMessage.new(value: 'theirs', to: 'them').publish
    ContractMessage.new(value: 'mine', to: 'me').publish

    wait_until { !received.empty? }
    sleep 0.05
    assert_equal ['mine'], Array.new(received.size) { received.pop.value }
  end

  def test_contract_publish_returns_true_and_raises_on_failure
    assert_equal true, transport.publish(ContractMessage.new(value: 1))

    broken = Class.new(SmartMessage::Serializer::Base) do
      def do_encode(_hash) = raise(TypeError, 'cannot encode')
    end
    failing = track(new_transport(serializer: broken.new))

    assert_raises(SmartMessage::Errors::SerializationError) { failing.publish(ContractMessage.new(value: 1)) }
  end

  def test_contract_disconnect_is_idempotent
    use
    collect

    transport.disconnect
    transport.disconnect
  end

  def test_contract_circuit_stats
    stats = transport.transport_circuit_stats

    assert_equal [:transport_publish], stats.keys
    assert stats[:transport_publish][:closed]
    assert_nil transport.reset_transport_circuits!
  end
end
