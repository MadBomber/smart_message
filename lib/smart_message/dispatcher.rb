# lib/smart_message/dispatcher.rb
# encoding: utf-8
# frozen_string_literal: true

require 'concurrent'
require_relative 'circuit_breaker'

module SmartMessage

  # The disoatcher routes incoming messages to all of the methods that
  # have been subscribed to the message.
  class Dispatcher
    include BreakerMachines::DSL

    # TODO: setup forwardable for some @router_pool methods

    def initialize(circuit_breaker_options = {})
      @subscribers = Hash.new { |h, k| h[k] = [] }
      @router_pool = Concurrent::CachedThreadPool.new

      # Configure circuit breakers
      configure_circuit_breakers(circuit_breaker_options)
      at_exit do
        shutdown_pool
      end
      
      logger.debug { "[SmartMessage::Dispatcher] Initialized with circuit breaker options: #{circuit_breaker_options}" }
    rescue => e
      logger.error { "[SmartMessage] Error in dispatcher initialization: #{e.class.name} - #{e.message}" }
      raise
    end
    
    private
    
    def logger
      @logger ||= SmartMessage::Logger.default
    end
    
    public


    def what_can_i_do?
      # TODO: Return pool methods list for debugging
      @router_pool.methods.sort
    end


    def status
      # TODO: Return proper status hash
      {
        scheduled_task_count: @router_pool.scheduled_task_count,
        completed_task_count: @router_pool.completed_task_count,
        queue_length: @router_pool.queue_length,
        length: @router_pool.length,
        running: @router_pool.running?
      }
    rescue NoMethodError
      what_can_i_do?
    end


    def pool
      @router_pool.instance_variable_get('@pool'.to_sym)
    end

    def scheduled_task_count
      @router_pool.scheduled_task_count
    end

    def worker_task_completed
      @router_pool.worker_task_completed
    end

    def completed_task_count
      @router_pool.completed_task_count
    end

    def queue_length
      @router_pool.queue_length
    end


    def  current_length
      @router_pool.length
    end


    def running?
      @router_pool.running?
    end


    def subscribers
      @subscribers
    end


    def add(message_class, process_method_as_string, filter_options = {})
      klass = String(message_class)

      # Create subscription entry with filter options
      subscription = {
        process_method: process_method_as_string,
        filters: filter_options
      }

      # Check if this exact subscription already exists
      existing_subscription = @subscribers[klass].find do |sub|
        sub[:process_method] == process_method_as_string && sub[:filters] == filter_options
      end

      unless existing_subscription
        @subscribers[klass] << subscription
      end
    end


    # drop a processer from a subscribed message
    def drop(message_class, process_method_as_string)
      klass = String(message_class)
      @subscribers[klass].reject! { |sub| sub[:process_method] == process_method_as_string }
    end


    # drop all processer from a subscribed message
    def drop_all(message_class)
      @subscribers.delete String(message_class)
    end


    # complete reset all subscriptions
    def drop_all!
      @subscribers = Hash.new { |h, k| h[k] = [] }
    end


    # Route a decoded message to appropriate message processors
    # @param decoded_message [SmartMessage::Base] The decoded message instance
    def route(decoded_message)
      message_header = decoded_message._sm_header
      message_klass = message_header.message_class
      logger.debug { "[SmartMessage::Dispatcher] Routing message #{message_klass} to #{@subscribers[message_klass]&.size || 0} subscribers" }
      logger.debug { "[SmartMessage::Dispatcher] Available subscribers: #{@subscribers.keys}" }
      return nil if @subscribers[message_klass].nil? || @subscribers[message_klass].empty?

      @subscribers[message_klass].each do |subscription|
        # Extract subscription details
        message_processor = subscription[:process_method]
        filters = subscription[:filters]

        # Check if message matches filters
        next unless message_matches_filters?(message_header, filters)

        SS.add(message_klass, message_processor, 'routed' )
        @router_pool.post do
          # Use circuit breaker to protect message processing
          circuit_result = circuit(:message_processor).wrap do
            # Check if this is a proc handler or a regular method call
            if proc_handler?(message_processor)
              # Call the proc handler via SmartMessage::Base
              SmartMessage::Base.call_proc_handler(message_processor, decoded_message)
            else
              # Method call logic with decoded message
              parts         = message_processor.split('.')
              target_klass  = parts[0]
              class_method  = parts[1]
              target_klass.constantize
                          .method(class_method)
                          .call(decoded_message)
            end
          end

          # Handle circuit breaker fallback responses
          if circuit_result.is_a?(Hash) && circuit_result[:circuit_breaker]
            handle_circuit_breaker_fallback(circuit_result, decoded_message, message_processor)
          end
        end
      end
    end

    # Get circuit breaker statistics
    # @return [Hash] Circuit breaker statistics
    def circuit_breaker_stats
      stats = {}

      begin
        if respond_to?(:circuit)
          breaker = circuit(:message_processor)
          if breaker
            stats[:message_processor] = {
              status: breaker.status,
              closed: breaker.closed?,
              open: breaker.open?,
              half_open: breaker.half_open?,
              last_error: breaker.last_error,
              opened_at: breaker.opened_at,
              stats: breaker.stats
            }
          end
        end
      rescue => e
        stats[:error] = "Failed to get circuit breaker stats: #{e.message}"
      end

      stats
    end

    # Reset circuit breakers
    # @param circuit_name [Symbol] Optional specific circuit to reset
    def reset_circuit_breakers!(circuit_name = nil)
      if circuit_name
        circuit(circuit_name)&.reset!
      else
        # Reset all known circuits
        circuit(:message_processor)&.reset!
      end
    end

    # Shutdown the router pool with timeout and fallback
    def shutdown_pool
      @router_pool.shutdown

      # Wait for graceful shutdown, force kill if timeout
      unless @router_pool.wait_for_termination(3)
        @router_pool.kill
      end
    end

    # Check if a message matches the subscription filters
    # @param message_header [SmartMessage::Header] The message header
    # @param filters [Hash] The filter criteria
    # @return [Boolean] True if the message matches all filters
    def message_matches_filters?(message_header, filters)
      # If no filters specified, accept all messages (backward compatibility)
      return true if filters.nil? || filters.empty? || filters.values.all?(&:nil?)

      # Check from filter
      if filters[:from]
        from_match = filter_value_matches?(message_header.from, filters[:from])
        return false unless from_match
      end

      # Check to/broadcast filters (OR logic between them)
      if filters[:broadcast] || filters[:to]
        broadcast_match = filters[:broadcast] && message_header.to.nil?
        to_match = filters[:to] && filter_value_matches?(message_header.to, filters[:to])

        # If either broadcast or to filter is specified, at least one must match
        combined_match = (broadcast_match || to_match)
        return false unless combined_match
      end

      true
    end

    # Check if a value matches any of the filter criteria
    # Supports both exact string matching and regex pattern matching
    # @param value [String, nil] The value to match against
    # @param filter_array [Array] Array of strings and/or regexps to match against
    # @return [Boolean] True if the value matches any filter in the array
    def filter_value_matches?(value, filter_array)
      return false if value.nil? || filter_array.nil?

      filter_array.any? do |filter|
        case filter
        when String
          filter == value
        when Regexp
          filter.match?(value)
        else
          false
        end
      end
    end

    # Check if a message processor is a proc handler
    # @param message_processor [String] The message processor identifier
    # @return [Boolean] True if this is a proc handler
    def proc_handler?(message_processor)
      SmartMessage::Base.proc_handler?(message_processor)
    end

    # Configure circuit breakers for the dispatcher
    # @param options [Hash] Circuit breaker configuration options
    def configure_circuit_breakers(options = {})
      # Ensure CircuitBreaker module is available
      return unless defined?(SmartMessage::CircuitBreaker::DEFAULT_CONFIGS)

      # Configure message processor circuit breaker
      default_config = SmartMessage::CircuitBreaker::DEFAULT_CONFIGS[:message_processor]
      return unless default_config

      processor_config = default_config.merge(options[:message_processor] || {})

      # Define the circuit using the class-level DSL
      self.class.circuit :message_processor do
        threshold failures: processor_config[:threshold][:failures],
                 within: processor_config[:threshold][:within].seconds
        reset_after processor_config[:reset_after].seconds

        # Configure storage backend
        case processor_config[:storage]
        when :redis
          # Use Redis storage if configured and available
          if defined?(SmartMessage::Transport::RedisTransport)
            begin
              redis_transport = SmartMessage::Transport::RedisTransport.new
              storage BreakerMachines::Storage::Redis.new(redis: redis_transport.redis_pub)
            rescue
              # Fall back to memory storage if Redis not available
              storage BreakerMachines::Storage::Memory.new
            end
          else
            storage BreakerMachines::Storage::Memory.new
          end
        else
          storage BreakerMachines::Storage::Memory.new
        end

        # Default fallback for message processing failures
        fallback do |exception|
          {
            circuit_breaker: {
              circuit: :message_processor,
              state: 'open',
              error: exception.message,
              error_class: exception.class.name,
              timestamp: Time.now.iso8601,
              fallback_triggered: true
            }
          }
        end
      end

    end

    # Handle circuit breaker fallback responses
    # @param circuit_result [Hash] The circuit breaker fallback result
    # @param decoded_message [SmartMessage::Base] The decoded message instance
    # @param message_processor [String] The processor that failed
    def handle_circuit_breaker_fallback(circuit_result, decoded_message, message_processor)
      message_header = decoded_message._sm_header

      # Always log circuit breaker activation for debugging
      error_msg = circuit_result[:circuit_breaker][:error]
      logger.error { "[SmartMessage::Dispatcher] Circuit breaker activated for processor: #{message_processor}" }
      logger.error { "[SmartMessage::Dispatcher] Error: #{error_msg}" }
      logger.error { "[SmartMessage::Dispatcher] Message: #{message_header.message_class} from #{message_header.from}" }

      # Send to dead letter queue
      SmartMessage::DeadLetterQueue.default.enqueue(decoded_message,
        error: circuit_result[:circuit_breaker][:error],
        retry_count: 0,
        transport: 'circuit_breaker'
      )

      # TODO: Integrate with structured logging when implemented
      # TODO: Emit metrics/events for monitoring

      # Record the failure in simple stats
      SS.add(message_header.message_class, message_processor, 'circuit_breaker_fallback')
    end


    #######################################################
    ## Class methods

    class << self
      # TODO: may want a class-level config method
    end # class << self
  end # class Dispatcher
end # module SmartMessage
