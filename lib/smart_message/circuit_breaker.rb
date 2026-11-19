# lib/smart_message/circuit_breaker.rb
# encoding: utf-8
# frozen_string_literal: true

require 'breaker_machines'

module SmartMessage
  # Circuit breaker construction and helpers, built on the BreakerMachines gem.
  #
  # SmartMessage keeps one circuit per transport instance (publishing) and
  # one per handler per message class (processing).  Each circuit has its
  # own in-memory storage, so a failure in one never opens another.
  #
  # A circuit built here has no fallback: a failing call raises its own
  # error, and a call rejected by an open circuit raises
  # BreakerMachines::CircuitOpenError.  Callers decide what to do with it.
  module CircuitBreaker
    extend self

    # Sends what BreakerMachines logs (circuit opened, closed, half-opened)
    # to the SmartMessage logger, so it follows the same configuration as
    # everything else: nothing is written unless a logger is configured.
    # Without this BreakerMachines writes to $stdout.
    class LogBridge
      %i[debug info warn error fatal].each do |level|
        define_method(level) do |message = nil, &block|
          SmartMessage::Logger.default.public_send(level) { block ? block.call : message }
          nil
        end
      end
    end

    # Install the LogBridge unless the application gave BreakerMachines a
    # logger of its own.
    #
    # @return [Boolean] true when the bridge was installed
    def install_log_bridge
      return false if BreakerMachines.instance_variable_get(:@logger)

      BreakerMachines.logger = LogBridge.new
      true
    end

    # Default circuit breaker configurations
    DEFAULT_CONFIGS = {
      message_processor: {
        threshold: { failures: 3, within: 60 }, # 3 failures within 1 minute
        reset_after: 30                         # try again after 30 seconds
      },
      transport_publish: {
        threshold: { failures: 5, within: 30 }, # 5 failures within 30 seconds
        reset_after: 15                         # try again after 15 seconds
      }
    }.freeze

    # Build a standalone circuit with its own storage.
    #
    # @param name [String, Symbol] circuit name, used in logs and stats
    # @param config [Hash] { threshold: { failures:, within: }, reset_after: }
    # @return [BreakerMachines::Circuit]
    def build(name, config = DEFAULT_CONFIGS[:message_processor])
      BreakerMachines::Circuit.new(
        name,
        failure_threshold: config.dig(:threshold, :failures),
        failure_window:    config.dig(:threshold, :within),
        reset_timeout:     config[:reset_after],
        storage:           BreakerMachines::Storage::Memory.new
      )
    end

    # Merge caller overrides into one of the DEFAULT_CONFIGS.
    #
    # @param kind [Symbol] a key of DEFAULT_CONFIGS
    # @param overrides [Hash, nil]
    def config_for(kind, overrides = nil)
      defaults = DEFAULT_CONFIGS.fetch(kind)
      return defaults if overrides.nil? || overrides.empty?

      defaults.merge(overrides) do |key, default, override|
        key == :threshold ? default.merge(override) : override
      end
    end

    # Add the default circuits to a class that wants to use the
    # BreakerMachines DSL (circuit(:name).wrap { ... }) directly.
    #
    # @param target_class [Class] The class to add circuit breakers to
    # @param options [Hash] per-circuit overrides keyed by circuit name
    def configure_for(target_class, options = {})
      target_class.include BreakerMachines::DSL

      DEFAULT_CONFIGS.each_key do |circuit_name|
        define_circuit(target_class, circuit_name, config_for(circuit_name, options[circuit_name]))
      end
    end

    # Create a circuit for entity-specific processing on a DSL class.
    #
    # @param target_class [Class] The class to add the circuit to
    # @param entity_id [String] The entity identifier
    # @param options [Hash] overrides for the :message_processor defaults
    # @return [Symbol] the circuit name
    def configure_entity_circuit(target_class, entity_id, options = {})
      circuit_name = :"entity_#{entity_id}"
      define_circuit(target_class, circuit_name, config_for(:message_processor, options))
      circuit_name
    end

    # Describe a circuit.
    #
    # @overload stats(circuit)
    #   @param circuit [BreakerMachines::Circuit]
    # @overload stats(circuit_instance, circuit_name)
    #   @param circuit_instance [Object] an object that includes BreakerMachines::DSL
    #   @param circuit_name [Symbol]
    # @return [Hash, nil]
    def stats(circuit_or_owner, circuit_name = nil)
      breaker = resolve(circuit_or_owner, circuit_name)
      return nil unless breaker

      numbers = breaker.stats
      {
        name:            breaker.name,
        state:           numbers.state,
        failure_count:   numbers.failure_count,
        success_count:   numbers.success_count,
        last_failure_at: numbers.last_failure_at,
        opened_at:       numbers.opened_at,
        last_error:      last_error_of(breaker)&.message
      }
    end

    # Check if a circuit will accept calls (closed or half-open).
    # No circuit means always available.
    def available?(circuit_or_owner, circuit_name = nil)
      breaker = resolve(circuit_or_owner, circuit_name)
      breaker.nil? || !breaker.open?
    end

    # Manually close a circuit and forget its failures.
    def reset!(circuit_or_owner, circuit_name = nil)
      resolve(circuit_or_owner, circuit_name)&.hard_reset!
    end

    # Run a block, retrying on failure with exponential backoff.
    #
    # This is a plain bounded loop.  Put it around a circuit-protected
    # call, not inside one, so each attempt counts against the circuit.
    #
    # @param max_retries [Integer] retries after the first attempt
    # @param base_delay [Numeric] seconds before the first retry; doubles each time
    # @param max_delay [Numeric] upper bound for one delay
    # @param on [Array<Class>] exception classes worth retrying
    # @param sleeper [#call] how to wait (injectable for tests)
    # @yieldparam attempt [Integer] 0 for the first attempt
    # @return the block's value
    # @raise the last error when every attempt fails
    def with_retries(max_retries: 3, base_delay: 1, max_delay: 30, on: [StandardError], sleeper: Kernel.method(:sleep))
      attempt = 0
      begin
        yield attempt
      rescue *on
        raise if attempt >= max_retries

        sleeper.call(backoff_delay(attempt, base_delay, max_delay))
        attempt += 1
        retry
      end
    end

    # @return [Numeric] the delay before retry number +attempt+ (0-based)
    def backoff_delay(attempt, base_delay, max_delay)
      [base_delay * (2**attempt), max_delay].min
    end

    # Fallback procs for classes that use the BreakerMachines DSL directly:
    #
    #   circuit :payments do
    #     fallback SmartMessage::CircuitBreaker::Fallbacks.dead_letter_queue { current_message }
    #   end
    #
    # BreakerMachines calls a fallback with the error only, evaluated on the
    # object that owns the circuit.
    module Fallbacks
      # The Hash every fallback returns.
      #
      # @param exception [Exception] what BreakerMachines passed to the fallback
      # @return [Hash] { circuit_breaker: { state:, rejected:, error:, ... } }
      def self.result(exception, **extra)
        rejected = exception.is_a?(BreakerMachines::CircuitOpenError)
        {
          circuit_breaker: {
            state:       rejected ? 'open' : 'closed',
            rejected:    rejected,
            error:       exception.message,
            error_class: exception.class.name,
            timestamp:   Time.now.iso8601
          }.merge(extra)
        }
      end

      # Store the failed message in the dead letter queue.
      #
      # @param dlq_instance [SmartMessage::DeadLetterQueue, nil] default: the default DLQ
      # @yieldreturn [SmartMessage::Base, nil] the message being processed;
      #   the block is evaluated on the circuit's owner
      def self.dead_letter_queue(dlq_instance = nil, &message_source)
        proc do |exception|
          message = message_source && instance_exec(&message_source)
          sent    = false

          if message
            (dlq_instance || SmartMessage::DeadLetterQueue.default).enqueue(
              message,
              error:       "#{exception.class.name}: #{exception.message}",
              stack_trace: exception.backtrace&.join("\n")
            )
            sent = true
          end

          SmartMessage::CircuitBreaker::Fallbacks.result(exception, sent_to_dlq: sent)
        end
      end

      # Return a canned response instead of failing.
      def self.graceful_degradation(degraded_response)
        proc do |exception|
          SmartMessage::CircuitBreaker::Fallbacks.result(exception, degraded_response: degraded_response)
        end
      end
    end

    # The last error a circuit recorded, or nil.
    def last_error_of(breaker)
      error = breaker.last_error
      error.respond_to?(:value) ? error.value : error
    end

    private

    def resolve(circuit_or_owner, circuit_name)
      return circuit_or_owner if circuit_name.nil?

      circuit_or_owner.circuit(circuit_name)
    end

    def define_circuit(target_class, circuit_name, config)
      target_class.circuit circuit_name do
        threshold failures: config[:threshold][:failures], within: config[:threshold][:within]
        reset_after config[:reset_after]
        # no storage: BreakerMachines then gives each instance its own
      end
    end
  end
end

SmartMessage::CircuitBreaker.install_log_bridge
