# lib/smart_message/transport/redis_transport.rb
# encoding: utf-8
# frozen_string_literal: true

require 'redis'
require 'securerandom'
require 'set'

module SmartMessage
  module Transport
    # Redis pub/sub transport for SmartMessage.
    #
    # Each message class is one Redis channel, named after the class and
    # prefixed with the namespace when one is set.
    #
    # == Delivery semantics: at most once
    #
    # Redis pub/sub does not store messages.  A message reaches the
    # subscribers connected at the moment it is published, and nobody else:
    # a process that is down, not yet subscribed, or reconnecting misses it.
    # Use a durable transport when every message must arrive.
    #
    # Redis pub/sub channels are global to the server.  The +db+ number does
    # NOT separate them, so two environments (or two test runs) on one
    # server see each other's messages unless they use different namespaces.
    #
    # Options:
    #   url:                 Redis URL (default redis://localhost:6379)
    #   db:                  database number, used for commands only (default 0)
    #   namespace:           channel prefix, "namespace:ClassName" (default none)
    #   reconnect_attempts:  retries for a lost connection (default 5)
    #   reconnect_delay:     seconds between subscriber reconnects (default 1)
    #   subscribe_timeout:   seconds to wait for Redis to confirm a
    #                        subscription (default 5)
    #
    # One connection publishes.  A second, long-lived connection subscribes;
    # it is opened by the first #subscribe and then gains and loses channels
    # with SUBSCRIBE and UNSUBSCRIBE, so no message is missed while the set
    # of subscriptions changes.
    class RedisTransport < Base
      CONTROL_SEPARATOR = "\t"

      attr_reader :redis_pub, :subscriber_thread

      def default_options
        {
          url:                'redis://localhost:6379',
          db:                 0,
          namespace:          nil,
          reconnect_attempts: 5,
          reconnect_delay:    1,
          subscribe_timeout:  5
        }
      end

      def configure
        @mutex             = Mutex.new
        @confirmed         = ConditionVariable.new
        @wanted_channels   = Set.new # channels we should be subscribed to
        @live_channels     = Set.new # channels Redis has confirmed
        @control_channel   = "__smart_message_control__:#{SecureRandom.hex(8)}"
        @subscriber_thread = nil
        @running           = false
        @closed            = false
        @redis_pub         = new_client
      end

      # The Redis channel for a message class
      def channel_for(message_class)
        @options[:namespace] ? "#{@options[:namespace]}:#{message_class}" : message_class.to_s
      end

      # The message class a Redis channel carries
      def message_class_for(channel)
        @options[:namespace] ? channel.delete_prefix("#{@options[:namespace]}:") : channel
      end

      # Publish message to the Redis channel of its message class
      def do_publish(message_class, serialized_message)
        raise SmartMessage::Errors::TransportError, "#{self.class.name} is disconnected" if @closed

        @redis_pub.publish(channel_for(message_class), serialized_message)
      end

      # Subscribe to a message class (Redis channel).  Returns once Redis
      # has confirmed the subscription.
      #
      # @raise [SmartMessage::Errors::TransportError] when Redis does not
      #   confirm within subscribe_timeout
      def subscribe(message_class, process_method, filter_options = {})
        super
        add_channel(channel_for(message_class))
      end

      # Unsubscribe from a specific message class and process method
      def unsubscribe(message_class, process_method)
        super
        remove_channel(channel_for(message_class)) if subscribers[message_class.to_s].empty?
      end

      # Unsubscribe from all process methods for a message class
      def unsubscribe!(message_class)
        super
        remove_channel(channel_for(message_class))
      end

      # @return [Array<String>] message channels Redis has confirmed
      def subscribed_channels
        @mutex.synchronize { @live_channels.to_a - [@control_channel] }
      end

      def connected?
        return false if @closed

        @redis_pub.ping == 'PONG'
      rescue StandardError
        false
      end

      # Reopen after a disconnect and resubscribe the channels that still
      # have handlers.
      def connect
        channels = @mutex.synchronize do
          if @closed
            @redis_pub = new_client
            @closed    = false
          end
          @wanted_channels.to_a
        end

        @redis_pub.ping
        channels.each { |channel| add_channel(channel) }
      end

      # Stop the subscriber and close both connections.
      # Safe to call more than once.
      def disconnect
        stop_subscriber
        @mutex.synchronize do
          next if @closed

          @closed = true
          @redis_pub.close
        end
      end

      private

      def new_client
        Redis.new(url: @options[:url], db: @options[:db], reconnect_attempts: @options[:reconnect_attempts])
      end

      #########################################################
      ## Channel bookkeeping (any thread)

      def add_channel(channel)
        @mutex.synchronize do
          raise SmartMessage::Errors::TransportError, "#{self.class.name} is disconnected" if @closed

          @wanted_channels.add(channel)
          if @running
            send_control(:subscribe, channel) unless @live_channels.include?(channel)
          else
            start_subscriber
          end

          wait_for_confirmation { @live_channels.include?(channel) } or
            raise SmartMessage::Errors::TransportError,
                  "Redis did not confirm the subscription to #{channel} within #{@options[:subscribe_timeout]}s"
        end
      end

      def remove_channel(channel)
        @mutex.synchronize do
          next unless @wanted_channels.delete?(channel)
          next unless @running

          send_control(:unsubscribe, channel)
          wait_for_confirmation { !@live_channels.include?(channel) }
        end
      end

      # Wait (holding @mutex) until the block is true or the timeout passes.
      # @return [Boolean] the block's final answer
      def wait_for_confirmation
        deadline = monotonic_now + @options[:subscribe_timeout]

        until yield
          remaining = deadline - monotonic_now
          return false if remaining <= 0 || !@running

          @confirmed.wait(@mutex, remaining)
        end
        true
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Ask the subscriber thread to change its subscriptions.  Only that
      # thread touches the subscribed connection, so the request travels to
      # it as a message on a private control channel.
      def send_control(command, channel = nil)
        @redis_pub.publish(@control_channel, [command, channel].compact.join(CONTROL_SEPARATOR))
      end

      #########################################################
      ## Subscriber thread

      # Call while holding @mutex.
      def start_subscriber
        @running           = true
        @subscriber_thread = Thread.new { subscriber_loop }
        @subscriber_thread.name = 'SmartMessage-RedisSubscriber'
      end

      def stop_subscriber
        thread = @mutex.synchronize do
          next nil unless @running

          @running = false
          begin
            send_control(:stop)
          rescue StandardError
            nil # the connection is gone; the thread is killed below
          end
          @subscriber_thread
        end
        return if thread.nil? || thread == Thread.current

        thread.join(@options[:subscribe_timeout]) || thread.kill
        @mutex.synchronize do
          @subscriber_thread = nil
          @live_channels.clear
          @confirmed.broadcast
        end
      end

      # Hold one subscribed connection open, reconnecting (and
      # resubscribing every wanted channel) when it drops.
      def subscriber_loop
        attempts = 0

        while @running
          begin
            listen { attempts = 0 }
            break # every channel was unsubscribed: a clean stop
          rescue StandardError => e
            # redis-rb raises RedisClient errors (not Redis::BaseError) from
            # inside a subscription, so every error means a lost connection.
            break unless @running

            attempts += 1
            logger.error do
              "[#{self.class.name}] Subscriber connection lost (attempt #{attempts}): #{e.class.name} - #{e.message}"
            end
            if attempts > @options[:reconnect_attempts]
              logger.error { "[#{self.class.name}] Giving up on the subscriber after #{attempts - 1} reconnects" }
              break
            end
            sleep(@options[:reconnect_delay])
          end
        end
      ensure
        @mutex.synchronize do
          @running = false
          @live_channels.clear
          @confirmed.broadcast
        end
      end

      # Subscribe and block, handling messages until every channel is gone.
      # @yield once Redis confirms the first subscription
      def listen
        connection = new_client
        channels   = @mutex.synchronize { [@control_channel, *@wanted_channels] }

        connection.subscribe(*channels) do |on|
          on.subscribe do |channel, _count|
            yield
            confirm(channel, true)
          end

          on.unsubscribe { |channel, _count| confirm(channel, false) }

          on.message do |channel, payload|
            if channel == @control_channel
              handle_control(connection, payload)
            else
              handle_message(channel, payload)
            end
          end
        end
      ensure
        connection&.close
      end

      def confirm(channel, subscribed)
        @mutex.synchronize do
          subscribed ? @live_channels.add(channel) : @live_channels.delete(channel)
          @confirmed.broadcast
        end
      end

      # Runs on the subscriber thread, inside the subscription.
      def handle_control(connection, payload)
        command, channel = payload.split(CONTROL_SEPARATOR, 2)

        case command
        when 'subscribe'   then connection.subscribe(channel)
        when 'unsubscribe' then connection.unsubscribe(channel)
        when 'stop'        then connection.unsubscribe
        end
      end

      def handle_message(channel, payload)
        receive(message_class_for(channel), payload)
      rescue SmartMessage::Errors::Error => e
        # Already logged (and dead-lettered when undecodable) by #receive;
        # keep the subscription alive for the next message.
        logger.debug { "[#{self.class.name}] Skipped a message on #{channel}: #{e.class.name}" }
      rescue StandardError => e
        # Not seen by #receive's rescue; log it so the message is not lost
        # without a trace, and keep the subscription alive.
        logger.error { "[#{self.class.name}] Skipped a message on #{channel}: #{e.class.name} - #{e.message}" }
      end
    end
  end
end
