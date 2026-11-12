# test/dispatcher_reliability_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

# What the dispatcher promises when handlers misbehave
# (review findings R2 to R6, R11, R12).
class DispatcherReliabilityTest < Minitest::Test
  class Event < SmartMessage::Base
    from 'reliability-test'
    property :value
    property :detail
  end

  class ClassHandler
    RECEIVED = Queue.new

    def self.process(message)
      RECEIVED << message
    end
  end

  def setup
    @log       = StringIO.new
    SmartMessage.configure { |config| config.logger = SmartMessage::Logger::Default.new(log_file: @log, level: :debug) }
    @transport = SmartMessage::Transport::MemoryTransport.new
    Event.transport(@transport)
    ClassHandler::RECEIVED.clear
  end

  def teardown
    Event.unsubscribe!
    Event.reset_transport
    @transport.dispatcher.shutdown(timeout: 2)
  end

  def dispatcher = @transport.dispatcher

  def publish(count)
    count.times { |i| Event.new(value: i).publish }
    wait_for_dispatch(@transport)
  end

  # ---- failure isolation ---------------------------------------------------

  def test_a_failing_handler_does_not_stop_the_others
    good = Queue.new
    Event.subscribe { |_message| raise 'handler is broken' }
    Event.subscribe { |message| good << message.value }

    publish(5)

    assert_equal 5, good.size, 'the healthy handler received every message'
    assert_equal 5, dlq.size, 'every message the broken handler did not process is dead-lettered'
  end

  def test_each_handler_has_its_own_circuit
    good = Queue.new
    bad  = Event.subscribe { |_message| raise 'handler is broken' }
    ok   = Event.subscribe { |message| good << message.value }

    publish(6)

    stats = dispatcher.circuit_breaker_stats
    assert stats.fetch("DispatcherReliabilityTest::Event:#{bad}")[:open], 'the broken handler tripped its circuit'
    assert stats.fetch("DispatcherReliabilityTest::Event:#{ok}")[:closed], 'the healthy handler is unaffected'
    assert_equal 6, good.size

    errors = dlq.inspect_messages(limit: 10).map { |entry| entry[:error] }
    assert_equal 3, errors.count { |error| error.start_with?('RuntimeError: handler is broken') }
    assert_equal 3, errors.count { |error| error.include?('CircuitOpenError') }, 'rejected messages are kept too'
  end

  def test_resetting_a_circuit_lets_the_handler_run_again
    calls = Queue.new
    Event.subscribe do |message|
      calls << message.value
      raise 'broken' if calls.size <= 3
    end
    publish(4)
    assert_equal 3, calls.size, 'the fourth message was rejected by the open circuit'

    dispatcher.reset_circuit_breakers!
    publish(1)

    assert_equal 4, calls.size
  end

  def test_handler_failures_are_logged_with_the_message_uuid
    Event.subscribe { |_message| raise ArgumentError, 'bad input' }
    message = Event.new(value: 1)

    message.publish
    wait_for_dispatch(@transport)

    assert_match(/Handler .* failed for DispatcherReliabilityTest::Event #{message.uuid}: ArgumentError - bad input/, @log.string)
  end

  def test_errors_that_are_not_standard_errors_are_caught_too
    Event.subscribe { |_message| raise NotImplementedError, 'not written yet' } # a ScriptError

    publish(1)

    assert_equal 1, dlq.size
    assert_match(/NotImplementedError: not written yet/, dlq.peek[:error])
    assert_equal 1, dispatcher.completed_task_count
  end

  def test_dead_letter_entries_name_the_handler
    handler = Event.subscribe { |_message| raise 'broken' }

    publish(1)

    entry = dlq.peek
    assert_equal "handler:#{handler}", entry[:transport]
    assert_match(/dispatcher_reliability_test\.rb/, entry[:stack_trace])
  end

  # ---- message isolation ---------------------------------------------------

  def test_each_handler_gets_its_own_copy
    seen = Queue.new
    Event.subscribe do |message|
      message.detail[:tags] << 'mutated'
      message.value = -1
      seen << message
    end
    Event.subscribe { |message| seen << message }
    original = Event.new(value: 1, detail: { tags: ['a'] })

    original.publish
    wait_for_dispatch(@transport)

    copies = [seen.pop, seen.pop]
    refute_same copies[0], copies[1]
    assert_equal [-1, 1], copies.map(&:value).sort
    assert_equal [['a'], %w[a mutated]], copies.map { |copy| copy.detail[:tags] }.sort
    assert_equal 1, original.value, 'the publisher keeps its own message'
    assert_equal ['a'], original.detail[:tags]
  end

  # ---- handler kinds -------------------------------------------------------

  def test_class_method_handlers_and_proc_handlers
    procs = Queue.new
    Event.subscribe('DispatcherReliabilityTest::ClassHandler.process')
    Event.subscribe(->(message) { procs << message.value })

    publish(2)

    assert_equal 2, ClassHandler::RECEIVED.size
    assert_equal 2, procs.size
  end

  def test_resolve_handler
    id = Event.subscribe { |message| message.value * 2 }

    assert_equal 6, dispatcher.resolve_handler(id).call(Event.new(value: 3))
    assert_nil dispatcher.resolve_handler('DispatcherReliabilityTest::Event.proc_0000000000000000')

    class_handler = dispatcher.resolve_handler('DispatcherReliabilityTest::ClassHandler.process')
    class_handler.call(:anything)
    assert_equal :anything, ClassHandler::RECEIVED.pop
  end

  def test_a_handler_unsubscribed_while_messages_arrive_never_raises
    received = Queue.new
    id       = Event.subscribe { |message| received << message.value }
    stop     = false

    publisher = Thread.new { Event.new(value: 1).publish until stop }
    sleep 0.05
    Event.unsubscribe(id)
    stop = true
    publisher.join
    wait_for_dispatch(@transport)

    before = received.size
    assert_operator before, :>, 0
    publish(3)
    assert_equal before, received.size, 'nothing arrives after the unsubscribe'
    assert dlq.empty?, 'and nothing failed along the way'
    assert_nil dispatcher.route(Event.new(value: 1)), 'no subscribers left'
  end

  def test_subscriptions_are_a_snapshot
    Event.subscribe { |_message| nil }
    snapshot = dispatcher.subscribers

    snapshot['DispatcherReliabilityTest::Event'] = []
    snapshot.clear

    assert_equal 1, dispatcher.subscribers['DispatcherReliabilityTest::Event'].size
    assert_empty dispatcher.subscribers['Unknown']
  end

  def test_subscribing_the_same_handler_twice_delivers_once
    2.times { Event.subscribe('DispatcherReliabilityTest::ClassHandler.process') }

    publish(1)

    assert_equal 1, ClassHandler::RECEIVED.size
  end

  def test_drop_subscriber_validates_its_argument
    assert_raises(ArgumentError) { dispatcher.drop_subscriber('X', nil) }
    assert_raises(ArgumentError) { dispatcher.drop_subscriber('X', '') }
  end

  # ---- bounded pool --------------------------------------------------------

  def test_the_pool_is_bounded_and_applies_back_pressure
    small     = SmartMessage::Dispatcher.new({}, max_threads: 2, max_queue: 2)
    transport = SmartMessage::Transport::MemoryTransport.new(dispatcher: small)
    Event.transport(transport)
    running = Concurrent::AtomicFixnum.new(0)
    peak    = Concurrent::AtomicFixnum.new(0)
    done    = Queue.new
    Event.subscribe do |message|
      now = running.increment
      peak.update { |value| [value, now].max }
      sleep 0.01
      running.decrement
      done << message.value
    end

    40.times { |i| Event.new(value: i).publish }
    wait_for_dispatch(transport)

    assert_equal 40, done.size, 'no message is dropped when the queue is full'
    assert_operator peak.value, :<=, 3, 'two pool threads plus the publisher under back pressure'
    assert_operator small.current_length, :<=, 2
  ensure
    small&.shutdown(timeout: 2)
  end

  def test_pool_size_comes_from_configuration
    SmartMessage.configure do |config|
      config.dispatcher_max_threads = 3
      config.dispatcher_max_queue   = 7
    end

    pool = SmartMessage::Dispatcher.new.instance_variable_get(:@router_pool)

    assert_equal 3, pool.max_length
    assert_equal 7, pool.max_queue
  end

  # ---- shutdown ------------------------------------------------------------

  def test_shutdown_waits_for_running_handlers
    finished = Queue.new
    Event.subscribe do |message|
      sleep 0.1
      finished << message.value
    end
    Event.new(value: 1).publish

    assert dispatcher.shutdown(timeout: 5)

    assert_equal 1, finished.size
    refute dispatcher.running?
    assert dlq.empty?
    assert dispatcher.shutdown(timeout: 1), 'shutting down twice is fine'
  end

  def test_shutdown_dead_letters_what_it_has_to_abandon
    started = Queue.new
    Event.subscribe do |_message|
      started << true
      sleep 30
    end
    message = Event.new(value: 1)
    message.publish
    started.pop

    refute dispatcher.shutdown(timeout: 0.1), 'the handler did not finish in time'

    assert_equal 1, dlq.size
    entry = dlq.peek
    assert_equal message.uuid, entry[:header][:uuid]
    assert_match(/shut down before the handler finished/, entry[:error])
    assert_match(/Shutdown interrupted .* #{message.uuid}/, @log.string)
    assert_equal 0, dispatcher.status[:in_flight]
  end

  def test_smart_message_shutdown_stops_every_dispatcher
    other = SmartMessage::Dispatcher.new

    assert_includes SmartMessage::Dispatcher.all, dispatcher
    assert_includes SmartMessage::Dispatcher.all, other

    SmartMessage.shutdown(timeout: 1)

    refute dispatcher.running?
    refute other.running?
  end

  # ---- status --------------------------------------------------------------

  def test_status_counts_work
    Event.subscribe { |_message| nil }

    publish(3)

    status = dispatcher.status
    assert_equal 3, status[:scheduled_task_count]
    assert_equal 3, status[:completed_task_count]
    assert_equal 0, status[:in_flight]
    assert status[:running]
  end

  def test_stats_count_routed_processed_and_failed
    ok  = Event.subscribe { |_message| nil }
    bad = Event.subscribe { |_message| raise 'broken' }
    [ok, bad].each { |id| %w[routed processed failed].each { |stat| SS.reset('DispatcherReliabilityTest::Event', id, stat) } }

    publish(2)

    assert_equal 2, SS.get('DispatcherReliabilityTest::Event', ok, 'routed')
    assert_equal 2, SS.get('DispatcherReliabilityTest::Event', ok, 'processed')
    assert_equal 0, SS.get('DispatcherReliabilityTest::Event', ok, 'failed')
    assert_equal 2, SS.get('DispatcherReliabilityTest::Event', bad, 'failed')
    assert_equal 0, SS.get('DispatcherReliabilityTest::Event', bad, 'processed')
  end
end
