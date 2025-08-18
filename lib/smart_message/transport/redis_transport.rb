# lib/smart_message/transport/redis_transport.rb
# encoding: utf-8
# frozen_string_literal: true

require 'redis'
require 'securerandom'
require 'set'

module SmartMessage
  module Transport
    # Redis pub/sub transport for SmartMessage
    # Uses message class name as the Redis channel name
    class RedisTransport < Base
      attr_reader :redis_pub, :redis_sub, :subscriber_thread

      def default_options
        {
          url: 'redis://localhost:6379',
          db: 0,
          auto_subscribe: true,
          reconnect_attempts: 5,
          reconnect_delay: 1
        }
      end

      def configure
        @redis_pub = Redis.new(url: @options[:url], db: @options[:db])
        @redis_sub = Redis.new(url: @options[:url], db: @options[:db])
        @subscribed_channels = Set.new
        @subscriber_thread = nil
        @running = false
        @mutex = Mutex.new
        
        start_subscriber if @options[:auto_subscribe]
      end

      # Publish message to Redis channel using message class name
      def publish(message_header, message_payload)
        channel = message_header.message_class
        
        begin
          @redis_pub.publish(channel, message_payload)
        rescue Redis::ConnectionError
          retry_with_reconnect('publish') { @redis_pub.publish(channel, message_payload) }
        end
      end

      # Subscribe to a message class (Redis channel)
      def subscribe(message_class, process_method)
        super(message_class, process_method)
        
        @mutex.synchronize do
          @subscribed_channels.add(message_class)
          restart_subscriber if @running
        end
      end

      # Unsubscribe from a specific message class and process method
      def unsubscribe(message_class, process_method)
        super(message_class, process_method)
        
        @mutex.synchronize do
          # If no more subscribers for this message class, unsubscribe from channel
          if @dispatcher.subscribers[message_class].nil? || @dispatcher.subscribers[message_class].empty?
            @subscribed_channels.delete(message_class)
            restart_subscriber if @running
          end
        end
      end

      # Unsubscribe from all process methods for a message class
      def unsubscribe!(message_class)
        super(message_class)
        
        @mutex.synchronize do
          @subscribed_channels.delete(message_class)
          restart_subscriber if @running
        end
      end

      def connected?
        begin
          @redis_pub.ping == 'PONG' && @redis_sub.ping == 'PONG'
        rescue Redis::ConnectionError
          false
        end
      end

      def connect
        @redis_pub.ping
        @redis_sub.ping
        start_subscriber unless @running
      end

      def disconnect
        stop_subscriber
        @redis_pub.quit if @redis_pub
        @redis_sub.quit if @redis_sub
      end

      private

      def start_subscriber
        return if @running
        
        @running = true
        @subscriber_thread = Thread.new do
          begin
            subscribe_to_channels
          rescue => e
            # Log error but don't crash the thread
            puts "Redis subscriber error: #{e.message}" if @options[:debug]
            retry_subscriber
          end
        end
      end

      def stop_subscriber
        @running = false
        
        if @subscriber_thread
          @subscriber_thread.kill
          @subscriber_thread.join(5) # Wait up to 5 seconds
          @subscriber_thread = nil
        end
      end

      def restart_subscriber
        stop_subscriber
        start_subscriber if @subscribed_channels.any?
      end

      def subscribe_to_channels
        return unless @subscribed_channels.any?
        
        @redis_sub.subscribe(*@subscribed_channels) do |on|
          on.message do |channel, message_payload|
            # Create a header with the channel as message_class
            message_header = SmartMessage::Header.new(
              message_class: channel,
              uuid: SecureRandom.uuid,
              published_at: Time.now,
              publisher_pid: 'redis_subscriber'
            )
            
            receive(message_header, message_payload)
          end
          
          on.subscribe do |channel, subscriptions|
            puts "Subscribed to Redis channel: #{channel} (#{subscriptions} total)" if @options[:debug]
          end
          
          on.unsubscribe do |channel, subscriptions|
            puts "Unsubscribed from Redis channel: #{channel} (#{subscriptions} total)" if @options[:debug]
          end
        end
      end

      def retry_subscriber
        return unless @running
        
        sleep(@options[:reconnect_delay])
        subscribe_to_channels if @running
      end

      def retry_with_reconnect(operation)
        attempts = 0
        begin
          yield
        rescue Redis::ConnectionError => e
          attempts += 1
          if attempts <= @options[:reconnect_attempts]
            sleep(@options[:reconnect_delay])
            # Reconnect
            @redis_pub = Redis.new(url: @options[:url], db: @options[:db])
            retry
          else
            raise e
          end
        end
      end
    end
  end
end