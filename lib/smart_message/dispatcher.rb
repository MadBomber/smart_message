# lib/smart_message/dispatcher.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage

  # The disoatcher routes incoming messages to all of the methods that
  # have been subscribed to the message.
  class Dispatcher

    def initialize
      @subscribers = Hash.new(Array.new)
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
      klass = message_header.message_class
      return nil if @subscribers[klass].empty?
      @subscribers[klass].each do |message_processor|
        # TODO: setup a thread pool and route the incoming message
        #       using individual threads.
        send(message_processor, klass, message_payload)
      end
    end


    #######################################################
    ## Class methods

    class << self
      # TODO: may want a class-level config method
    end # class << self
  end # class Dispatcher
end # module SmartMessage
