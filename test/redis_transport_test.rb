# test/redis_transport_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'helpers/transport_contract'

# The Redis pub/sub transport, against a real server (review findings T5,
# T9, R13).  Skipped only when no server answers; every test uses its own
# namespace, so runs on a shared server cannot see each other.
class RedisTransportTest < Minitest::Test
  include TransportContract

  RT = SmartMessage::Transport::RedisTransport

  def setup
    require_redis!
  end

  def namespace
    @namespace ||= redis_namespace
  end

  def new_transport(**options)
    RT.new(url: REDIS_TEST_URL, namespace: namespace, subscribe_timeout: 3, **options)
  end

  # @return [Array<String>] ids of the pub/sub connections on the server
  def pubsub_client_ids(admin)
    admin.call('CLIENT', 'LIST', 'TYPE', 'pubsub').scan(/^id=(\d+)/).flatten
  end

  def subscriber_threads
    Thread.list.count { |thread| thread.name == 'SmartMessage-RedisSubscriber' && thread.alive? }
  end

  # ---- channels ------------------------------------------------------------

  def test_channel_names_carry_the_namespace
    assert_equal "#{namespace}:Order", transport.channel_for('Order')
    assert_equal 'Order', transport.message_class_for("#{namespace}:Order")

    bare = track(RT.new(url: REDIS_TEST_URL))
    assert_equal 'Order', bare.channel_for('Order')
    assert_equal 'Order', bare.message_class_for('Order')
  end

  def test_namespaces_do_not_see_each_other
    mine   = track(new_transport)
    theirs = track(RT.new(url: REDIS_TEST_URL, namespace: redis_namespace))
    ContractMessage.transport(mine)
    received = collect

    theirs.publish(ContractMessage.new(value: 'theirs'))
    mine.publish(ContractMessage.new(value: 'mine'))

    wait_until { !received.empty? }
    sleep 0.1
    assert_equal ['mine'], Array.new(received.size) { received.pop.value }
  end

  # ---- subscriptions -------------------------------------------------------

  def test_no_connection_thread_until_something_subscribes
    before = subscriber_threads

    idle = track(new_transport)
    idle.publish(ContractMessage.new(value: 1))

    assert_equal before, subscriber_threads
    assert_nil idle.subscriber_thread
    assert_empty idle.subscribed_channels
  end

  def test_subscribe_returns_once_redis_has_confirmed
    use
    collect

    assert_equal ["#{namespace}:TransportContract::ContractMessage"], transport.subscribed_channels
  end

  def test_a_message_published_right_after_subscribe_is_not_missed
    publisher = track(new_transport)
    ContractMessage.transport(transport)
    received = collect

    publisher.publish(ContractMessage.new(value: 'immediately')) # no sleep

    wait_until { !received.empty? }
    assert_equal 'immediately', received.pop.value
  end

  def test_adding_a_channel_keeps_the_existing_subscription_alive
    use
    first  = collect(ContractMessage)
    thread = transport.subscriber_thread

    stop      = false
    publisher = Thread.new do
      count = 0
      until stop
        ContractMessage.new(value: count += 1).publish
        sleep 0.002
      end
      count
    end
    sleep 0.05
    second = collect(OtherMessage) # changes the subscription under load
    sleep 0.05
    stop = true
    sent = publisher.value

    wait_until(message: 'messages were lost while a channel was added') { first.size == sent }
    assert_same thread, transport.subscriber_thread, 'the subscriber was not restarted'
    assert_equal 2, transport.subscribed_channels.size

    OtherMessage.new(value: 'other').publish
    wait_until { !second.empty? }
  end

  def test_unsubscribing_removes_the_channel
    use
    collect(ContractMessage)
    collect(OtherMessage)

    ContractMessage.unsubscribe!

    assert_equal ["#{namespace}:TransportContract::OtherMessage"], transport.subscribed_channels
  end

  def test_a_channel_stays_while_one_handler_remains
    use
    first = ContractMessage.subscribe { |_message| nil }
    kept  = collect

    ContractMessage.unsubscribe(first)
    assert_equal 1, transport.subscribed_channels.size

    ContractMessage.new(value: 'still delivered').publish
    wait_until { !kept.empty? }
  end

  def test_an_undecodable_payload_is_dead_lettered_and_the_subscription_survives
    use
    received = collect
    raw      = Redis.new(url: REDIS_TEST_URL)

    raw.publish(transport.channel_for('TransportContract::ContractMessage'), 'not a message')
    wait_until(message: 'the bad payload was not dead-lettered') { dlq.size == 1 }
    ContractMessage.new(value: 'after the bad payload').publish

    wait_until { !received.empty? }
    assert_equal 'after the bad payload', received.pop.value
    assert_equal 'not a message', dlq.peek[:payload]
  ensure
    raw&.close
  end

  def test_a_message_for_another_class_on_the_channel_is_rejected
    use
    received = collect
    raw      = Redis.new(url: REDIS_TEST_URL)
    forged   = transport.encode_message(OtherMessage.new(value: 'forged'))

    raw.publish(transport.channel_for('TransportContract::ContractMessage'), forged)

    wait_until { dlq.size == 1 }
    assert received.empty?
    assert_match(/MessageClassMismatch/, dlq.peek[:error])
  ensure
    raw&.close
  end

  # ---- lifecycle -----------------------------------------------------------

  def test_disconnect_stops_the_subscriber_thread
    use
    collect
    before = subscriber_threads
    thread = transport.subscriber_thread

    transport.disconnect

    refute thread.alive?
    assert_equal before - 1, subscriber_threads
    refute transport.connected?
    assert_empty transport.subscribed_channels
  end

  def test_publish_after_disconnect_fails_loudly
    use
    transport.disconnect

    error = assert_raises(SmartMessage::Errors::PublishError) { ContractMessage.new(value: 1).publish }

    assert_instance_of SmartMessage::Errors::TransportError, error.result.errors.first
    assert_equal 1, dlq.size
    assert_raises(SmartMessage::Errors::TransportError) { collect }
  end

  def test_connect_resumes_publishing_and_subscriptions
    use
    received = collect
    transport.disconnect

    transport.connect

    assert transport.connected?
    assert_equal 1, transport.subscribed_channels.size
    ContractMessage.new(value: 'after reconnect').publish
    wait_until { !received.empty? }
    assert_equal 'after reconnect', received.pop.value
  end

  def test_an_unreachable_server_fails_the_publish
    dead = use(track(RT.new(url: 'redis://127.0.0.1:1', reconnect_attempts: 0)))

    refute dead.connected?
    error = assert_raises(SmartMessage::Errors::PublishError) { ContractMessage.new(value: 1).publish }
    assert_kind_of Redis::BaseError, error.result.errors.first
    assert_equal 1, dlq.size
  end

  def test_the_subscriber_reconnects_after_its_connection_is_killed
    use(track(new_transport(reconnect_delay: 0.05)))
    admin    = Redis.new(url: REDIS_TEST_URL)
    before   = pubsub_client_ids(admin)
    received = collect
    ours     = pubsub_client_ids(admin) - before

    # Kill only the connection this test opened; the server may be shared.
    refute_empty ours
    ours.each { |id| admin.call('CLIENT', 'KILL', 'ID', id) }
    wait_until(message: 'the subscriber did not come back') do
      ContractMessage.new(value: 'ping').publish
      sleep 0.05
      !received.empty?
    end

    assert ContractMessage.transport.subscriber_thread.alive?
  ensure
    admin&.close
  end
end
