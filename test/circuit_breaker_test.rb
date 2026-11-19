# test/circuit_breaker_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

# Circuit construction and helpers (review findings R6, R7, R10).
class CircuitBreakerTest < Minitest::Test
  CB = SmartMessage::CircuitBreaker

  class Sample < SmartMessage::Base
    from 'sample'
    property :value
  end

  def fast_config(failures: 2)
    { threshold: { failures: failures, within: 60 }, reset_after: 30 }
  end

  def fail_circuit(circuit, times)
    times.times { assert_raises(RuntimeError) { circuit.wrap { raise 'boom' } } }
  end

  # ---- build ---------------------------------------------------------------

  def test_a_closed_circuit_returns_the_block_value
    circuit = CB.build('ok', fast_config)

    assert_equal 42, circuit.wrap { 42 }
    assert circuit.closed?
  end

  def test_a_failing_call_raises_its_own_error_and_opens_at_the_threshold
    circuit = CB.build('failing', fast_config(failures: 2))

    fail_circuit(circuit, 1)
    assert circuit.closed?, 'one failure is below the threshold'

    fail_circuit(circuit, 1)
    assert circuit.open?

    ran = false
    assert_raises(BreakerMachines::CircuitOpenError) { circuit.wrap { ran = true } }
    refute ran, 'an open circuit does not run the block'
  end

  def test_circuits_do_not_share_state
    one = CB.build('one', fast_config(failures: 1))
    two = CB.build('one', fast_config(failures: 1)) # same name on purpose

    fail_circuit(one, 1)

    assert one.open?
    assert two.closed?
    assert_equal :ok, two.wrap { :ok }
  end

  def test_reset_closes_a_circuit
    circuit = CB.build('reset', fast_config(failures: 1))
    fail_circuit(circuit, 1)

    CB.reset!(circuit)

    assert circuit.closed?
    assert_equal 1, circuit.wrap { 1 }
  end

  def test_stats_and_available
    circuit = CB.build('stats', fast_config(failures: 1))

    assert CB.available?(circuit)
    assert_equal({ name: 'stats', state: :closed, failure_count: 0, last_error: nil },
                 CB.stats(circuit).slice(:name, :state, :failure_count, :last_error))

    fail_circuit(circuit, 1)

    refute CB.available?(circuit)
    stats = CB.stats(circuit)
    assert_equal :open, stats[:state]
    assert_equal 1, stats[:failure_count]
    assert_equal 'boom', stats[:last_error]
    assert_instance_of RuntimeError, CB.last_error_of(circuit)
  end

  # ---- configuration -------------------------------------------------------

  def test_config_for_merges_overrides_into_the_defaults
    defaults = CB::DEFAULT_CONFIGS[:transport_publish]

    assert_equal defaults, CB.config_for(:transport_publish)
    assert_equal defaults, CB.config_for(:transport_publish, {})
    assert_equal({ threshold: { failures: 9, within: 30 }, reset_after: 15 },
                 CB.config_for(:transport_publish, threshold: { failures: 9 }))
    assert_equal({ threshold: { failures: 5, within: 30 }, reset_after: 1 },
                 CB.config_for(:transport_publish, reset_after: 1))
    assert_raises(KeyError) { CB.config_for(:no_such_circuit) }
    assert_equal 5, defaults[:threshold][:failures], 'the defaults are not modified'
  end

  def test_configure_for_gives_each_instance_its_own_circuits
    klass = Class.new
    CB.configure_for(klass, message_processor: { threshold: { failures: 1 } })
    one = klass.new
    two = klass.new

    assert_raises(RuntimeError) { one.circuit(:message_processor).wrap { raise 'boom' } }

    assert one.circuit(:message_processor).open?
    assert two.circuit(:message_processor).closed?, 'another instance is not affected'
    assert one.circuit(:transport_publish).closed?, 'another circuit is not affected'
    refute CB.available?(one, :message_processor)
    assert CB.available?(two, :message_processor)
    assert_equal :open, CB.stats(one, :message_processor)[:state]

    CB.reset!(one, :message_processor)
    assert one.circuit(:message_processor).closed?
  end

  def test_configure_entity_circuit
    klass = Class.new { include BreakerMachines::DSL }

    name = CB.configure_entity_circuit(klass, 'order-service', threshold: { failures: 1 })

    assert_equal :'entity_order-service', name
    assert_equal 5, klass.new.circuit(name).wrap { 5 }
  end

  # ---- logging -------------------------------------------------------------

  def test_circuit_events_go_to_the_smart_message_logger_and_never_to_stdout
    log = StringIO.new
    SmartMessage.configure { |config| config.logger = SmartMessage::Logger::Default.new(log_file: log, level: :info) }
    events = BreakerMachines.log_events
    BreakerMachines.log_events = true

    out, err = capture_subprocess_io { fail_circuit(CB.build('announced', fast_config(failures: 1)), 1) }

    assert_empty out
    assert_empty err
    assert_instance_of CB::LogBridge, BreakerMachines.logger
    refute CB.install_log_bridge, 'a logger that is already set is left alone'
    assert_match(/Circuit 'announced' opened/, log.string)
  ensure
    BreakerMachines.log_events = events
  end

  def test_log_bridge_forwards_strings_and_blocks
    log = StringIO.new
    SmartMessage.configure { |config| config.logger = SmartMessage::Logger::Default.new(log_file: log, level: :debug) }
    bridge = CB::LogBridge.new

    assert_nil bridge.warn('a string')
    assert_nil bridge.debug { 'a block' }

    assert_match(/WARN.*a string/, log.string)
    assert_match(/DEBUG.*a block/, log.string)
  end

  # ---- retries -------------------------------------------------------------

  def test_backoff_delay_doubles_up_to_the_maximum
    assert_equal [1, 2, 4, 8, 10, 10], (0..5).map { |attempt| CB.backoff_delay(attempt, 1, 10) }
    assert_equal 0.5, CB.backoff_delay(0, 0.5, 30)
  end

  def test_with_retries_returns_as_soon_as_an_attempt_succeeds
    delays   = []
    attempts = []

    value = CB.with_retries(max_retries: 3, base_delay: 1, sleeper: ->(d) { delays << d }) do |attempt|
      attempts << attempt
      raise 'not yet' if attempt < 2

      :done
    end

    assert_equal :done, value
    assert_equal [0, 1, 2], attempts
    assert_equal [1, 2], delays
  end

  def test_with_retries_is_bounded_and_raises_the_last_error
    calls = 0

    error = assert_raises(RuntimeError) do
      CB.with_retries(max_retries: 2, sleeper: ->(_d) {}) do
        calls += 1
        raise "failure #{calls}"
      end
    end

    assert_equal 3, calls, 'one attempt plus two retries'
    assert_equal 'failure 3', error.message
  end

  def test_with_retries_only_retries_the_listed_errors
    calls = 0

    assert_raises(ArgumentError) do
      CB.with_retries(on: [IOError], sleeper: ->(_d) {}) do
        calls += 1
        raise ArgumentError, 'not retryable'
      end
    end

    assert_equal 1, calls
  end

  # ---- fallbacks -----------------------------------------------------------

  def test_fallback_result_tells_a_failure_from_a_rejection
    failure = CB::Fallbacks.result(IOError.new('down'), extra: 1)[:circuit_breaker]

    assert_equal 'closed', failure[:state]
    refute failure[:rejected]
    assert_equal 'down', failure[:error]
    assert_equal 'IOError', failure[:error_class]
    assert_equal 1, failure[:extra]

    circuit = CB.build('rejecting', fast_config(failures: 1))
    fail_circuit(circuit, 1)
    rejection = assert_raises(BreakerMachines::CircuitOpenError) { circuit.wrap { 1 } }
    rejected  = CB::Fallbacks.result(rejection)[:circuit_breaker]

    assert_equal 'open', rejected[:state]
    assert rejected[:rejected]
  end

  def test_dead_letter_queue_fallback_stores_the_message_of_the_circuit_owner
    klass = Class.new do
      include BreakerMachines::DSL

      attr_accessor :current_message

      circuit :work do
        threshold failures: 5, within: 60
        fallback SmartMessage::CircuitBreaker::Fallbacks.dead_letter_queue { current_message }
      end
    end
    worker = klass.new
    worker.current_message = Sample.new(value: 7)

    result = worker.circuit(:work).wrap { raise IOError, 'down' }

    assert result[:circuit_breaker][:sent_to_dlq]
    assert_equal 1, dlq.size
    entry = dlq.peek
    assert_equal worker.current_message.uuid, entry[:header][:uuid]
    assert_equal 'IOError: down', entry[:error]
  end

  def test_dead_letter_queue_fallback_without_a_message_stores_nothing
    fallback = CB::Fallbacks.dead_letter_queue

    result = fallback.call(IOError.new('down'))

    refute result[:circuit_breaker][:sent_to_dlq]
    assert dlq.empty?
  end

  def test_graceful_degradation_fallback
    fallback = CB::Fallbacks.graceful_degradation({ cached: true })

    result = fallback.call(IOError.new('down'))

    assert_equal({ cached: true }, result[:circuit_breaker][:degraded_response])
    assert_equal 'down', result[:circuit_breaker][:error]
  end
end
