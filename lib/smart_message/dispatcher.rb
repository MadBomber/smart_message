# lib/smart_message/dispatcher.rb
# encoding: utf-8
# frozen_string_literal: true

require 'concurrent'

module SmartMessage

  # The disoatcher routes incoming messages to all of the methods that
  # have been subscribed to the message.
  class Dispatcher

    # TODO: setup forwardable for some @router_pool methods

    def initialize
      @subscribers = Hash.new(Array.new)
      @router_pool = Concurrent::CachedThreadPool.new
      at_exit do
        print "Shuttingdown down the dispatcher's @router_pool ..."
        @router_pool.shutdown
        while @router_pool.shuttingdown?
          print '.'
          sleep 1
        end
        puts " done."
      end
    end


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
        @subscribers[klass] += [subscription]
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
      @subscribers = Hash.new(Array.new)
    end


    # message_header is of class SmartMessage::Header
    # message_payload is a string buffer that is a serialized
    # SmartMessage
    def route(message_header, message_payload)
      message_klass = message_header.message_class
      return nil if @subscribers[message_klass].empty?
      
      @subscribers[message_klass].each do |subscription|
        # Extract subscription details
        message_processor = subscription[:process_method]
        filters = subscription[:filters]
        
        # Check if message matches filters
        next unless message_matches_filters?(message_header, filters)
        
        SS.add(message_klass, message_processor, 'routed' )
        @router_pool.post do
          begin
            # Check if this is a proc handler or a regular method call
            if proc_handler?(message_processor)
              # Call the proc handler via SmartMessage::Base
              SmartMessage::Base.call_proc_handler(message_processor, message_header, message_payload)
            else
              # Original method call logic
              parts         = message_processor.split('.')
              target_klass  = parts[0]
              class_method  = parts[1]
              target_klass.constantize
                          .method(class_method)
                          .call(message_header, message_payload)
            end
          rescue Exception => e
            # TODO: Add proper exception logging
            # Exception details: #{e.message}
            # Processor: #{message_processor}
            puts "Error processing message: #{e.message}" if $DEBUG
          end
        end
      end
    end

    private

    # Check if a message matches the subscription filters
    # @param message_header [SmartMessage::Header] The message header
    # @param filters [Hash] The filter criteria
    # @return [Boolean] True if the message matches all filters
    def message_matches_filters?(message_header, filters)
      # If no filters specified, accept all messages (backward compatibility)
      return true if filters.nil? || filters.empty? || filters.values.all?(&:nil?)
      
      # Check from filter
      if filters[:from]
        from_match = filters[:from].include?(message_header.from)
        return false unless from_match
      end
      
      # Check to/broadcast filters (OR logic between them)
      if filters[:broadcast] || filters[:to]
        broadcast_match = filters[:broadcast] && message_header.to.nil?
        to_match = filters[:to] && filters[:to].include?(message_header.to)
        
        # If either broadcast or to filter is specified, at least one must match
        combined_match = (broadcast_match || to_match)
        return false unless combined_match
      end
      
      true
    end

    # Check if a message processor is a proc handler
    # @param message_processor [String] The message processor identifier
    # @return [Boolean] True if this is a proc handler
    def proc_handler?(message_processor)
      SmartMessage::Base.proc_handler?(message_processor)
    end


    #######################################################
    ## Class methods

    class << self
      # TODO: may want a class-level config method
    end # class << self
  end # class Dispatcher
end # module SmartMessage
