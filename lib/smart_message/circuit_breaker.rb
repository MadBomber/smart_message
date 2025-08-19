# lib/smart_message/circuit_breaker.rb
# encoding: utf-8
# frozen_string_literal: true

require 'breaker_machines'

module SmartMessage
  # Circuit breaker configuration and management for SmartMessage
  # Provides production-grade reliability patterns using BreakerMachines gem
  module CircuitBreaker
    extend self

    # Default circuit breaker configurations
    DEFAULT_CONFIGS = {
      message_processor: {
        threshold: { failures: 3, within: 60 }, # 3 failures within 1 minute
        reset_after: 30,                        # Reset after 30 seconds
        storage: :memory                        # Use memory storage by default
      },
      transport_publish: {
        threshold: { failures: 5, within: 30 }, # 5 failures within 30 seconds
        reset_after: 15,                        # Reset after 15 seconds
        storage: :memory
      },
      transport_subscribe: {
        threshold: { failures: 3, within: 60 }, # 3 failures within 1 minute
        reset_after: 45,                        # Reset after 45 seconds
        storage: :memory
      },
      serializer: {
        threshold: { failures: 5, within: 30 }, # 5 failures within 30 seconds
        reset_after: 10,                        # Reset after 10 seconds
        storage: :memory
      },
      dispatcher_shutdown: {
        threshold: { failures: 2, within: 10 }, # 2 failures within 10 seconds
        reset_after: 5,                         # Reset after 5 seconds
        storage: :memory
      }
    }.freeze

    # Configure circuit breakers for a class
    # @param target_class [Class] The class to add circuit breakers to
    # @param options [Hash] Configuration options
    def configure_for(target_class, options = {})
      target_class.include BreakerMachines::DSL
      
      # Configure each circuit breaker type
      DEFAULT_CONFIGS.each do |circuit_name, config|
        final_config = config.merge(options[circuit_name] || {})
        
        target_class.circuit circuit_name do
          threshold failures: final_config[:threshold][:failures], 
                   within: final_config[:threshold][:within].seconds
          reset_after final_config[:reset_after].seconds
          
          # Configure storage backend
          case final_config[:storage]
          when :redis
            # Use Redis storage if configured
            storage BreakerMachines::Storage::Redis.new(
              redis: SmartMessage::Transport::RedisTransport.new.redis_pub
            )
          else
            # Default to memory storage
            storage BreakerMachines::Storage::Memory.new
          end
          
          # Default fallback that logs the failure
          fallback do |exception|
            {
              circuit_breaker: {
                circuit: circuit_name,
                state: 'open',
                error: exception.message,
                timestamp: Time.now.iso8601,
                fallback_triggered: true
              }
            }
          end
        end
      end
    end

    # Create a specialized circuit breaker for entity-specific processing
    # @param target_class [Class] The class to add the circuit to
    # @param entity_id [String] The entity identifier
    # @param options [Hash] Configuration options
    def configure_entity_circuit(target_class, entity_id, options = {})
      circuit_name = "entity_#{entity_id}".to_sym
      config = DEFAULT_CONFIGS[:message_processor].merge(options)
      
      target_class.circuit circuit_name do
        threshold failures: config[:threshold][:failures], 
                 within: config[:threshold][:within].seconds
        reset_after config[:reset_after].seconds
        
        # Configure storage
        case config[:storage]
        when :redis
          storage BreakerMachines::Storage::Redis.new(
            redis: SmartMessage::Transport::RedisTransport.new.redis_pub
          )
        else
          storage BreakerMachines::Storage::Memory.new
        end
        
        # Entity-specific fallback
        fallback do |exception|
          {
            circuit_breaker: {
              circuit: circuit_name,
              entity_id: entity_id,
              state: 'open',
              error: exception.message,
              timestamp: Time.now.iso8601,
              fallback_triggered: true
            }
          }
        end
      end
      
      circuit_name
    end

    # Get circuit breaker statistics
    # @param circuit_instance [Object] Instance with circuit breakers
    # @param circuit_name [Symbol] Name of the circuit
    def stats(circuit_instance, circuit_name)
      breaker = circuit_instance.circuit(circuit_name)
      return nil unless breaker
      
      {
        name: circuit_name,
        state: breaker.state,
        failure_count: breaker.failure_count,
        last_failure_time: breaker.last_failure_time,
        next_attempt_time: breaker.next_attempt_time
      }
    end

    # Check if circuit breaker is available (closed or half-open)
    # @param circuit_instance [Object] Instance with circuit breakers
    # @param circuit_name [Symbol] Name of the circuit
    def available?(circuit_instance, circuit_name)
      breaker = circuit_instance.circuit(circuit_name)
      return true unless breaker # No circuit breaker means always available
      
      breaker.state != :open
    end

    # Manually reset a circuit breaker
    # @param circuit_instance [Object] Instance with circuit breakers
    # @param circuit_name [Symbol] Name of the circuit
    def reset!(circuit_instance, circuit_name)
      breaker = circuit_instance.circuit(circuit_name)
      breaker&.reset!
    end

    # Configure fallback handlers for different scenarios
    module Fallbacks
      # Dead letter queue fallback - stores failed messages to file-based DLQ
      def self.dead_letter_queue(dlq_instance = nil)
        proc do |exception, *args|
          # Extract message details from args if available
          message_header = args[0] if args[0].is_a?(SmartMessage::Header)
          message_payload = args[1] if args.length > 1
          
          # Use provided DLQ instance or default
          dlq = dlq_instance || SmartMessage::DeadLetterQueue.default
          
          # Store failed message in dead letter queue
          sent_to_dlq = false
          if message_header && message_payload
            begin
              dlq.enqueue(message_header, message_payload, 
                error: exception.message,
                retry_count: 0,
                serializer: 'json',  # Default to JSON, could be enhanced to detect actual serializer
                stack_trace: exception.backtrace&.join("\n")
              )
              sent_to_dlq = true
            rescue => dlq_error
              # DLQ storage failed - log but don't raise
              puts "Warning: Failed to store message in DLQ: #{dlq_error.message}" if $DEBUG
            end
          end
          
          {
            circuit_breaker: {
              circuit: :transport_publish,  # Default circuit name, overridden by specific configurations
              state: 'open',
              error: exception.message,
              sent_to_dlq: sent_to_dlq,
              timestamp: Time.now.iso8601
            }
          }
        end
      end

      # Retry with exponential backoff fallback
      def self.retry_with_backoff(max_retries: 3, base_delay: 1)
        proc do |exception, *args|
          retry_count = Thread.current[:circuit_retry_count] ||= 0
          
          if retry_count < max_retries
            Thread.current[:circuit_retry_count] += 1
            delay = base_delay * (2 ** retry_count)
            sleep(delay)
            
            # Re-raise to trigger retry
            raise exception
          else
            Thread.current[:circuit_retry_count] = nil
            
            {
              circuit_breaker: {
                state: 'open',
                error: exception.message,
                max_retries_exceeded: true,
                timestamp: Time.now.iso8601
              }
            }
          end
        end
      end

      # Graceful degradation fallback
      def self.graceful_degradation(degraded_response)
        proc do |exception|
          {
            circuit_breaker: {
              state: 'open',
              error: exception.message,
              degraded_response: degraded_response,
              timestamp: Time.now.iso8601
            }
          }
        end
      end
    end
  end
end