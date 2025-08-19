# lib/smart_message/serializer/base.rb
# encoding: utf-8
# frozen_string_literal: true

require 'json'  # STDLIB
require_relative '../circuit_breaker'

module SmartMessage::Serializer
  # the standard super class
  class Base
    include BreakerMachines::DSL
    
    # provide basic configuration
    def initialize
      configure_serializer_circuit_breakers
    end

    def encode(message_instance)
      circuit(:serializer).wrap do
        do_encode(message_instance)
      end
    rescue => e
      # Handle circuit breaker fallback
      if e.is_a?(Hash) && e[:circuit_breaker]
        handle_serializer_fallback(e, :encode, message_instance)
      else
        raise
      end
    end

    def decode(payload)
      circuit(:serializer).wrap do
        do_decode(payload)
      end
    rescue => e
      # Handle circuit breaker fallback
      if e.is_a?(Hash) && e[:circuit_breaker]
        handle_serializer_fallback(e, :decode, payload)
      else
        raise
      end
    end

    # Template methods for actual serialization (implement in subclasses)
    def do_encode(message_instance)
      # Default implementation: serialize only the payload portion for wrapper architecture
      # Subclasses can override this for specific serialization formats
      message_hash = message_instance.to_h
      payload_portion = message_hash[:_sm_payload]
      ::JSON.generate(payload_portion)
    end

    def do_decode(payload)
      raise ::SmartMessage::Errors::NotImplemented
    end

    private

    # Configure circuit breaker for serializer operations
    def configure_serializer_circuit_breakers
      serializer_config = SmartMessage::CircuitBreaker::DEFAULT_CONFIGS[:serializer]
      
      self.class.circuit :serializer do
        threshold failures: serializer_config[:threshold][:failures], 
                 within: serializer_config[:threshold][:within].seconds
        reset_after serializer_config[:reset_after].seconds
        
        storage BreakerMachines::Storage::Memory.new
        
        # Fallback for serializer failures
        fallback do |exception|
          {
            circuit_breaker: {
              circuit: :serializer,
              serializer_type: self.class.name,
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

    # Handle serializer circuit breaker fallback
    def handle_serializer_fallback(fallback_result, operation, data)
      if $DEBUG
        puts "Serializer circuit breaker activated: #{self.class.name}"
        puts "Operation: #{operation}"
        puts "Error: #{fallback_result[:circuit_breaker][:error]}"
      end
      
      # TODO: Integrate with structured logging when implemented
      
      # Return the fallback result
      fallback_result
    end
  end # class Base
end # module SmartMessage::Serializer
