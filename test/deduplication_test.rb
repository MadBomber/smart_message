# test/deduplication_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

# Deduplication from the message class down to the handler
# (review findings R8, K5).
class DeduplicationTest < Minitest::Test
  class Deduped < SmartMessage::Base
    from 'dedup-test'
    property :value

    ddq_size 20
    enable_deduplication!
  end

  class Plain < SmartMessage::Base
    from 'dedup-test'
    property :value
  end

  def setup
    @transport = SmartMessage::Transport::MemoryTransport.new
    [Deduped, Plain].each { |klass| klass.transport(@transport) }
    @seen = Queue.new
  end

  def teardown
    [Deduped, Plain].each do |klass|
      klass.unsubscribe!
      klass.reset_transport
    end
    @transport.dispatcher.shutdown(timeout: 2)
  end

  # Deliver the same message (same UUID) again, as a redelivery would.
  def redeliver(message)
    @transport.publish(message)
    wait_for_dispatch(@transport)
  end

  # ---- settings ------------------------------------------------------------

  def test_settings_are_validated
    assert_raises(ArgumentError) { Plain.ddq_size(0) }
    assert_raises(ArgumentError) { Plain.ddq_size('10') }
    assert_raises(ArgumentError) { Plain.ddq_storage(:disk) }
    assert_raises(ArgumentError) { Plain.ddq_storage(nil) }
    refute Plain.ddq_enabled?
    assert_equal({ enabled: false }, Plain.ddq_stats)
  end

  def test_storage_options_are_kept
    klass = Class.new(SmartMessage::Base) { ddq_storage :redis, ttl: 60 }

    assert_equal :redis, klass.ddq_config[:storage]
    assert_equal({ ttl: 60 }, klass.ddq_config[:options])
  end

  def test_message_uuid
    message = Deduped.new(value: 1)

    assert_equal message._sm_header.uuid, message.uuid
  end

  # ---- behaviour -----------------------------------------------------------

  def test_a_redelivered_message_is_handled_once
    Deduped.subscribe { |message| @seen << message.value }
    message = Deduped.new(value: 1)

    3.times { redeliver(message) }

    assert_equal 1, @seen.size
  end

  def test_different_messages_are_all_handled
    Deduped.subscribe { |message| @seen << message.value }

    5.times { |i| redeliver(Deduped.new(value: i)) }

    assert_equal 5, @seen.size
  end

  def test_without_deduplication_a_redelivery_is_handled_again
    Plain.subscribe { |message| @seen << message.value }
    message = Plain.new(value: 1)

    2.times { redeliver(message) }

    assert_equal 2, @seen.size
  end

  def test_each_handler_has_its_own_queue
    first  = Queue.new
    second = Queue.new
    Deduped.subscribe { |message| first << message.value }
    message = Deduped.new(value: 1)
    redeliver(message)

    Deduped.subscribe { |message| second << message.value } # subscribes later
    redeliver(message)

    assert_equal 1, first.size,  'the first handler skips the duplicate'
    assert_equal 1, second.size, 'the new handler has not seen this message yet'
    assert_equal 2, Deduped.ddq_stats[:queues].size
  end

  def test_a_failed_handler_releases_the_message_for_redelivery
    attempts = Queue.new
    Deduped.subscribe do |message|
      attempts << message.uuid
      raise 'first attempt fails' if attempts.size == 1
    end
    message = Deduped.new(value: 1)

    redeliver(message)
    redeliver(message)
    redeliver(message)

    assert_equal 2, attempts.size, 'the failure is retried once, then the success is remembered'
    assert_equal 1, dlq.size
  end

  def test_concurrent_deliveries_of_one_message_run_the_handler_once
    Deduped.subscribe do |message|
      sleep 0.02 # still running while the other deliveries arrive
      @seen << message.value
    end
    message = Deduped.new(value: 1)
    start   = Queue.new

    threads = Array.new(12) do
      Thread.new do
        start.pop
        @transport.publish(message)
      end
    end
    12.times { start << :go }
    threads.each(&:join)
    wait_for_dispatch(@transport)

    assert_equal 1, @seen.size
  end

  def test_stats_and_clear
    handler = Deduped.subscribe { |message| @seen << message.value }
    message = Deduped.new(value: 1)
    redeliver(message)

    stats = Deduped.ddq_stats
    assert stats[:enabled]
    queue = stats[:queues].fetch("DeduplicationTest::Deduped:#{handler}")
    assert_equal 1, queue[:current_count]
    assert_equal 20, queue[:size]
    assert_equal :memory, queue[:storage_type]

    Deduped.clear_ddq!
    redeliver(message)

    assert_equal 2, @seen.size, 'after clear_ddq! the message is new again'
  end

  def test_unsubscribing_drops_the_handlers_queue
    handler = Deduped.subscribe { |message| @seen << message.value }
    redeliver(Deduped.new(value: 1))

    Deduped.unsubscribe(handler)

    assert_empty Deduped.ddq_stats[:queues]
  end

  def test_a_bad_ddq_configuration_fails_the_subscribe
    klass = Class.new(SmartMessage::Base) do
      from 'dedup-test'
      ddq_storage :redis, redis: Redis.new(url: 'redis://127.0.0.1:1', reconnect_attempts: 0, connect_timeout: 0.2)
      enable_deduplication!
    end
    self.class.const_set(:Unreachable, klass)
    klass.transport(@transport)

    assert_raises(SmartMessage::Errors::TransportError) { klass.subscribe { |_message| nil } }
    assert_empty @transport.subscribers[klass.to_s]
  ensure
    self.class.send(:remove_const, :Unreachable)
  end
end
