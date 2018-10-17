# lib/smart_message/dispatcher.rb
# encoding: utf-8
# frozen_string_literal: true

require 'concurrent'

module SmartMessage

  # The disoatcher routes incoming messages to all of the methods that
  # have been subscribed to the message.
  class Dispatcher

    def initialize
      @subscribers = Hash.new(Array.new)
      @router_pool = Concurrent::CachedThreadPool.new
      at_exit do
        print 'Sutting down the @router_pool ...'
        @router_pool.shutdown
        while @router_pool.shuttingdown?
          print '.'
          sleep 1
        end
        puts " done."
      end
    end

    def running?
      @router_pool.running?
    end

    def subscribers
      @subscribers
    end


    def add(message_class, process_method_as_string)
      klass = String(message_class)
      unless @subscribers[klass].include? process_method_as_string
        @subscribers[klass] += [process_method_as_string]
      end
    end


    # drop a processer from a subscribed message
    def drop(message_class, process_method_as_string)
      @subscribers[String(message_class)].delete process_method_as_string
    end


    # drop all processer from a subscribed message
    def drop_all(message_class)
      @subscribers.delete String(message_class)
    end


    # message_header is of class SmartMessage::Header
    # message_payload is a string buffer that is a serialized
    # SmartMessage
    def route(message_header, message_payload)
      who_called = caller
      message_klass = message_header.message_class
      return nil if @subscribers[message_klass].empty?
      @subscribers[message_klass].each do |message_processor|
        @router_pool.post do
          parts         = message_processor.split('.')
          target_klass  = parts[0]
          class_method  = parts[1]
          begin
            result = target_klass.constantize
                        .method(class_method)
                        .call(message_header, message_payload)
          rescue Exception => e
            debug_me('==== EXCEPTION ===='){[
              :e,
              :message_processor,
              :parts,
              :target_klass,
              :class_method,
              :message_header,
              :message_payload,
              :who_called
            ]}
          end
          debug_me('=== did it work? ==='){[ :result ]}
        end
      end
    end


    #######################################################
    ## Class methods

    class << self
      # TODO: may want a class-level config method
    end # class << self
  end # class Dispatcher
end # module SmartMessage
