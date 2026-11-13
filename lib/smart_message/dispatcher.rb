# lib/smart_message/dispatcher.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # The dispatcher routes incoming messages to all of the handlers that
  # have been subscribed to the message.
  #
  # Each handler runs on a bounded thread pool, gets its own copy of the
  # message, and is protected by its own circuit breaker.  A handler that
  # raises, or whose circuit is open, sends its copy of the message to the
  # dead letter queue; other handlers are not affected.
  class Dispatcher
    NO_SUBSCRIPTIONS = [].freeze

    @registry       = ObjectSpace::WeakMap.new
    @registry_mutex = Mutex.new

    class << self
      # @return [Array<SmartMessage::Dispatcher>] every dispatcher still alive
      def all
        @registry_mutex.synchronize { @registry.keys }
      end

      def register(dispatcher)
        @registry_mutex.synchronize { @registry[dispatcher] = true }
      end
    end

    # @param circuit_breaker_options [Hash] { message_processor: { threshold:
    #   { failures:, within: }, reset_after: } } overrides for handler circuits
    # @param max_threads [Integer, nil] pool size; default from configuration
    # @param max_queue [Integer, nil] tasks that may wait for a thread;
    #   default from configuration.  When the queue is full the publishing
    #   (or receiving) thread runs the handler itself, which slows it down
    #   instead of growing without bound.
    def initialize(circuit_breaker_options = {}, max_threads: nil, max_queue: nil)
      config = SmartMessage.configuration

      @subscribers     = {}.freeze
      @mutex           = Mutex.new
      @subscriber_ddqs = Concurrent::Map.new
      @circuits        = Concurrent::Map.new
      @in_flight       = Concurrent::Map.new
      @circuit_config  = CircuitBreaker.config_for(:message_processor, circuit_breaker_options[:message_processor])
      @router_pool     = Concurrent::ThreadPoolExecutor.new(
        min_threads:     0,
        max_threads:     max_threads || config.dispatcher_max_threads,
        max_queue:       max_queue || config.dispatcher_max_queue,
        fallback_policy: :caller_runs
      )

      self.class.register(self)
    end

    #########################################################
    ## Pool status

    def status
      {
        scheduled_task_count: scheduled_task_count,
        completed_task_count: completed_task_count,
        queue_length:         queue_length,
        length:               current_length,
        in_flight:            @in_flight.size,
        running:              running?
      }
    end

    def scheduled_task_count = @router_pool.scheduled_task_count
    def completed_task_count = @router_pool.completed_task_count
    def queue_length         = @router_pool.queue_length
    def current_length       = @router_pool.length
    def running?             = @router_pool.running?

    #########################################################
    ## Subscriptions

    # @return [Hash] message class name => Array of subscriptions.  A
    #   snapshot: changing it does not change the dispatcher.
    def subscribers
      Hash.new(NO_SUBSCRIPTIONS).merge!(@subscribers)
    end

    # Subscribe a handler to a message class.
    #
    # @param message_class [String, Class] The message class (name)
    # @param process_method_as_string [String] "Class.method" or a proc handler id
    # @param filter_options [Hash] :from, :to, :broadcast filters
    def add(message_class, process_method_as_string, filter_options = {})
      klass        = String(message_class)
      subscription = {
        subscriber_id:  process_method_as_string,
        process_method: process_method_as_string,
        filters:        filter_options
      }.freeze

      # A class with deduplication enabled gets its queue now, so a bad
      # DDQ configuration fails the subscribe instead of going unnoticed.
      ddq_for(klass, process_method_as_string, message_class_named(klass))

      update_subscriptions(klass) do |current|
        current.include?(subscription) ? current : current + [subscription]
      end

      logger.debug { "[SmartMessage::Dispatcher] Added subscription: #{klass} for #{process_method_as_string}" }
    end

    # Drop one handler from a message class.
    def drop(message_class, process_method_as_string, _filter_options = {})
      klass = String(message_class)

      update_subscriptions(klass) do |current|
        current.reject { |subscription| subscription[:subscriber_id] == process_method_as_string }
      end

      forget_subscriber(klass, process_method_as_string)
    end

    # Drop every subscription a handler has on a message class.
    def drop_subscriber(message_class, handler_method)
      unless handler_method.is_a?(String) && !handler_method.empty?
        raise ArgumentError, "handler_method must be a non-empty String, got: #{handler_method.inspect}"
      end

      drop(message_class, handler_method)
    end

    # Drop every handler of a message class.
    def drop_all(message_class)
      klass   = String(message_class)
      dropped = @mutex.synchronize do
        current      = @subscribers.fetch(klass, NO_SUBSCRIPTIONS)
        @subscribers = @subscribers.except(klass).freeze
        current
      end

      dropped.each { |subscription| forget_subscriber(klass, subscription[:subscriber_id]) }
    end

    # Drop every subscription.
    def drop_all!
      @mutex.synchronize { @subscribers = {}.freeze }
      @subscriber_ddqs.clear
      @circuits.clear
    end

    #########################################################
    ## Routing

    # Route a message to every subscribed handler whose filters match.
    #
    # @param message [SmartMessage::Base] The decoded message instance
    # @return [Integer, nil] how many handlers were scheduled; nil when the
    #   message class has no subscribers
    def route(message)
      header        = message._sm_header
      klass         = header.message_class
      subscriptions = @subscribers.fetch(klass, NO_SUBSCRIPTIONS)

      logger.debug { "[SmartMessage::Dispatcher] Routing #{klass} to #{subscriptions.size} subscribers" }
      return nil if subscriptions.empty?

      subscriptions.count { |subscription| schedule(subscription, message) }
    end

    # Check if a message matches the subscription filters
    # @param message_header [SmartMessage::Header] The message header
    # @param filters [Hash] The filter criteria
    # @return [Boolean] True if the message matches all filters
    def message_matches_filters?(message_header, filters)
      return false if filters[:from] && !filter_value_matches?(message_header.from, filters[:from])

      # Without a to or broadcast filter, every message is accepted
      return true unless filters[:to] || filters[:broadcast]

      # With them, at least one must match
      broadcast_match = filters[:broadcast] && message_header.to.nil?
      to_match        = filters[:to] && filter_value_matches?(message_header.to, filters[:to])
      !!(broadcast_match || to_match)
    end

    # Check if a value matches any of the filter criteria
    # @param value [String, nil] The value to match against
    # @param filter_array [Array<String, Regexp>] exact strings and patterns
    # @return [Boolean] True if the value matches any filter in the array
    def filter_value_matches?(value, filter_array)
      return false if value.nil? || filter_array.nil?

      filter_array.any? do |filter|
        case filter
        when String then filter == value
        when Regexp then filter.match?(value)
        else false
        end
      end
    end

    # Check if a message processor is a registered proc handler
    def proc_handler?(message_processor)
      SmartMessage::Base.proc_handler?(message_processor)
    end

    # Turn a handler id into something callable, now, so a later
    # unsubscribe cannot change what an already-routed message does.
    #
    # @param process_method [String] "Class.method" or a proc handler id
    # @return [#call, nil] nil when a proc handler is no longer registered
    def resolve_handler(process_method)
      return SmartMessage::Base.proc_handler(process_method) if Subscription.proc_handler_id?(process_method)

      target, method_name = process_method.to_s.split('.', 2)
      ->(message) { Object.const_get(target).method(method_name).call(message) }
    end

    #########################################################
    ## Circuit breakers

    # Get circuit breaker statistics, one entry per handler circuit.
    # @return [Hash] "MessageClass:handler" => stats
    def circuit_breaker_stats
      @circuits.each_pair.to_h do |name, breaker|
        [name, {
          status:     breaker.status_name,
          closed:     breaker.closed?,
          open:       breaker.open?,
          half_open:  breaker.half_open?,
          last_error: CircuitBreaker.last_error_of(breaker),
          stats:      breaker.stats.to_h
        }]
      end
    end

    # Close handler circuits and forget their failures.
    # @param circuit_name [String, nil] "MessageClass:handler", or nil for all
    def reset_circuit_breakers!(circuit_name = nil)
      if circuit_name
        @circuits.delete(circuit_name.to_s)
      else
        @circuits.clear
      end
      nil
    end

    # The circuit protecting one handler of one message class.
    def circuit_for(message_class, subscriber_id)
      name = subscriber_key(message_class, subscriber_id)
      @circuits.compute_if_absent(name) { CircuitBreaker.build(name, @circuit_config) }
    end

    #########################################################
    ## Deduplication queues

    # Get DDQ statistics, optionally for one message class.
    # @return [Hash] "MessageClass:handler" => stats
    def ddq_stats(message_class = nil)
      ddqs_of(message_class).to_h do |key, ddq|
        [key, ddq.stats]
      rescue StandardError => e
        [key, { error: e.message }]
      end
    end

    # Forget every UUID seen, optionally for one message class.
    def clear_ddqs(message_class = nil)
      ddqs_of(message_class).each { |_key, ddq| ddq.clear }
      nil
    end

    # The deduplication queue for one handler, created on first use.
    #
    # @param message_class_obj [Class, nil] the message class; nil when the
    #   name does not belong to a loaded message class
    # @return [SmartMessage::DDQ::Base, nil] nil when deduplication is off
    # @raise [StandardError] when the queue cannot be created
    def ddq_for(message_class, subscriber_id, message_class_obj)
      return nil unless message_class_obj.respond_to?(:ddq_enabled?) && message_class_obj.ddq_enabled?

      key = subscriber_key(message_class, subscriber_id)
      @subscriber_ddqs.compute_if_absent(key) do
        config = message_class_obj.ddq_config
        SmartMessage::DDQ.create(config[:storage], config[:size], config[:options].merge(key_prefix: "smart_message:ddq:#{key}"))
      end
    end

    #########################################################
    ## Shutdown

    # Stop accepting work and wait for running handlers.
    #
    # Handlers still running after +timeout+ seconds are killed; each of
    # their messages is logged and written to the dead letter queue.
    #
    # @param timeout [Numeric] seconds to wait
    # @return [Boolean] true when everything finished in time
    def shutdown(timeout: SmartMessage::DEFAULT_SHUTDOWN_TIMEOUT)
      return true if @router_pool.shutdown? && @in_flight.empty?

      @router_pool.shutdown
      return true if @router_pool.wait_for_termination(timeout)

      abandoned = @in_flight.values
      @router_pool.kill
      @in_flight.clear
      abandoned.each { |message, processor| record_abandoned(message, processor) }
      false
    end
    alias shutdown_pool shutdown

    private

    def logger
      SmartMessage::Logger.default
    end

    def subscriber_key(message_class, subscriber_id)
      "#{message_class}:#{subscriber_id}"
    end

    # @return [Class, nil] the loaded message class with that name
    def message_class_named(class_name)
      Envelope.resolve_message_class(class_name)
    rescue Errors::UnknownMessageClass
      nil
    end

    # Replace one class's subscription list (copy-on-write, so #route can
    # read without a lock).
    def update_subscriptions(klass)
      @mutex.synchronize do
        updated      = yield(@subscribers.fetch(klass, NO_SUBSCRIPTIONS)).freeze
        @subscribers = (updated.empty? ? @subscribers.except(klass) : @subscribers.merge(klass => updated)).freeze
      end
    end

    # Drop a handler's queue and circuit once it has no subscription left.
    def forget_subscriber(klass, subscriber_id)
      still_subscribed = @subscribers.fetch(klass, NO_SUBSCRIPTIONS).any? do |subscription|
        subscription[:subscriber_id] == subscriber_id
      end
      return if still_subscribed

      key = subscriber_key(klass, subscriber_id)
      @subscriber_ddqs.delete(key)
      @circuits.delete(key)
    end

    # The queues of one message class's own handlers.  Looked up through
    # its subscriptions rather than by key prefix, because "Order:" is also
    # a prefix of a nested class's keys ("Order::Shipped:...").
    def ddqs_of(message_class)
      return @subscriber_ddqs.each_pair.to_a if message_class.nil?

      klass = String(message_class)
      keys  = @subscribers.fetch(klass, NO_SUBSCRIPTIONS).map do |subscription|
        subscriber_key(klass, subscription[:subscriber_id])
      end

      keys.uniq.filter_map do |key|
        ddq = @subscriber_ddqs[key]
        [key, ddq] if ddq
      end
    end

    # Decide whether one subscription gets this message, and if so hand it
    # to the pool.
    #
    # @return [Boolean] true when the handler was scheduled
    def schedule(subscription, message)
      header    = message._sm_header
      klass     = header.message_class
      processor = subscription[:process_method]

      return false unless message_matches_filters?(header, subscription[:filters])

      handler = resolve_handler(processor)
      if handler.nil?
        logger.debug { "[SmartMessage::Dispatcher] Handler #{processor} is no longer registered; skipping" }
        return false
      end

      ddq = reserve_for(subscription, message)
      return false if ddq == :duplicate

      SmartMessage::Stats.add(klass, processor, 'routed')

      copy    = message.dup
      task_id = copy.object_id
      @in_flight[task_id] = [copy, processor]

      @router_pool.post do
        deliver(handler, copy, processor, ddq)
      ensure
        @in_flight.delete(task_id)
      end

      true
    end

    # Reserve the message's UUID for this handler.
    #
    # @return [SmartMessage::DDQ::Base, nil, :duplicate] the queue holding
    #   the reservation, nil when deduplication is off or unavailable, or
    #   :duplicate when this handler has already seen the message
    def reserve_for(subscription, message)
      header = message._sm_header
      ddq    = ddq_for(header.message_class, subscription[:subscriber_id], message.class)
      return nil unless ddq
      return ddq if ddq.reserve(header.uuid)

      SmartMessage::Stats.add(header.message_class, subscription[:process_method], 'duplicate')
      logger.warn do
        "[SmartMessage::Dispatcher] Skipping duplicate for #{subscription[:subscriber_id]}: #{header.uuid}"
      end
      :duplicate
    rescue StandardError => e
      logger.error do
        "[SmartMessage::Dispatcher] Deduplication unavailable for #{subscription[:subscriber_id]}: " \
          "#{e.class.name} - #{e.message}; processing without it"
      end
      nil
    end

    # Run one handler for one message.  Runs on a pool thread, so nothing
    # may escape: concurrent-ruby would discard it without a trace.
    def deliver(handler, message, processor, ddq)
      klass = message._sm_header.message_class

      circuit_for(klass, processor).wrap { handler.call(message) }
      SmartMessage::Stats.add(klass, processor, 'processed')
    rescue StandardError, ScriptError => e
      handle_failure(message, processor, ddq, e)
    end

    # A handler failed or its circuit rejected the call: release the
    # deduplication reservation and dead-letter the message.
    def handle_failure(message, processor, ddq, error)
      header = message._sm_header
      SmartMessage::Stats.add(header.message_class, processor, 'failed')

      logger.error do
        "[SmartMessage::Dispatcher] Handler #{processor} failed for #{header.message_class} " \
          "#{header.uuid}: #{error.class.name} - #{error.message}"
      end

      ddq&.release(header.uuid)
      dead_letter(message, processor, error)
    rescue StandardError => e
      logger.error do
        "[SmartMessage::Dispatcher] Could not record failure of #{processor} for " \
          "#{message._sm_header.uuid}: #{e.class.name} - #{e.message}"
      end
    end

    def dead_letter(message, processor, error)
      SmartMessage::DeadLetterQueue.default.enqueue(
        message,
        error:       "#{error.class.name}: #{error.message}",
        transport:   "handler:#{processor}",
        stack_trace: error.backtrace&.join("\n")
      )
    end

    # A handler was killed at shutdown before it finished.
    def record_abandoned(message, processor)
      logger.error do
        "[SmartMessage::Dispatcher] Shutdown interrupted #{processor} while processing " \
          "#{message._sm_header.message_class} #{message._sm_header.uuid}"
      end
      dead_letter(message, processor, Errors::Error.new('Dispatcher shut down before the handler finished'))
    rescue StandardError => e
      logger.error { "[SmartMessage::Dispatcher] Could not record abandoned message: #{e.class.name} - #{e.message}" }
    end
  end
end
