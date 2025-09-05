# lib/smart_message/transport/redis_transport_enhanced.rb
# Enhanced Redis transport with routing intelligence similar to RabbitMQ

require_relative 'redis_transport'

module SmartMessage
  module Transport
    class RedisEnhancedTransport < RedisTransport
      
      # Enhanced publish with structured channel names
      def do_publish(message_class, serialized_message)
        # Extract routing information from message
        routing_info = extract_routing_info(serialized_message)
        
        # Build enhanced channel name with routing info
        channel = build_enhanced_channel(message_class, routing_info)
        
        begin
          # Publish to both simple channel (backwards compatibility) and enhanced channel
          @redis_pub.publish(message_class, serialized_message) # Original format
          @redis_pub.publish(channel, serialized_message)       # Enhanced format
          
          logger.debug { "[Redis Enhanced] Published to channels: #{message_class} and #{channel}" }
        rescue Redis::ConnectionError
          retry_with_reconnect('publish') do
            @redis_pub.publish(message_class, serialized_message)
            @redis_pub.publish(channel, serialized_message)
          end
        end
      end

      # Enhanced subscription with pattern support
      def subscribe_pattern(pattern)
        @mutex.synchronize do
          @pattern_subscriptions ||= Set.new
          @pattern_subscriptions.add(pattern)
          restart_subscriber if @running
        end
        
        logger.info { "[Redis Enhanced] Subscribed to pattern: #{pattern}" }
      end

      # Convenience methods similar to RabbitMQ
      def subscribe_to_recipient(recipient_id)
        pattern = "*.*.#{sanitize_for_channel(recipient_id)}"
        subscribe_pattern(pattern)
      end

      def subscribe_from_sender(sender_id) 
        pattern = "*.#{sanitize_for_channel(sender_id)}.*"
        subscribe_pattern(pattern)
      end

      def subscribe_to_type(message_type)
        base_type = message_type.to_s.gsub('::', '.').downcase
        pattern = "#{base_type}.*.*"
        subscribe_pattern(pattern)
      end

      def subscribe_to_alerts
        patterns = [
          "emergency.*.*",
          "*alert*.*.*", 
          "*alarm*.*.*",
          "*critical*.*.*"
        ]
        
        patterns.each { |pattern| subscribe_pattern(pattern) }
      end

      def subscribe_to_broadcasts
        pattern = "*.*.broadcast"
        subscribe_pattern(pattern)
      end

      # Fluent API
      def where
        RedisSubscriptionBuilder.new(self)
      end

      private

      def extract_routing_info(serialized_message)
        begin
          message_data = JSON.parse(serialized_message)
          header = message_data['_sm_header'] || {}
          
          {
            from: sanitize_for_channel(header['from'] || 'anonymous'),
            to: sanitize_for_channel(header['to'] || 'broadcast')
          }
        rescue JSON::ParserError
          logger.warn { "[Redis Enhanced] Could not parse message for routing info, using defaults" }
          { from: 'anonymous', to: 'broadcast' }
        end
      end

      def build_enhanced_channel(message_class, routing_info)
        # Format: message_type.from.to (simplified vs RabbitMQ's 4-part)
        base_channel = message_class.to_s.gsub('::', '.').downcase
        "#{base_channel}.#{routing_info[:from]}.#{routing_info[:to]}"
      end

      def sanitize_for_channel(value)
        # Redis channels can contain most characters, but standardize format
        value.to_s.gsub(/[^a-zA-Z0-9_\-]/, '_').downcase
      end

      # Override to handle both regular and pattern subscriptions
      def subscribe_to_channels
        channels = @subscribed_channels.to_a
        patterns = @pattern_subscriptions&.to_a || []
        
        return unless channels.any? || patterns.any?

        begin
          # Handle both regular subscriptions and pattern subscriptions
          if patterns.any?
            subscribe_with_patterns(channels, patterns)
          elsif channels.any?
            @redis_sub.subscribe(*channels) do |on|
              setup_subscription_handlers(on)
            end
          end
        rescue => e
          logger.error { "[Redis Enhanced] Error in subscription: #{e.class.name} - #{e.message}" }
          retry_subscriber if @running
        end
      end

      def subscribe_with_patterns(channels, patterns)
        # Redis doesn't support mixing SUBSCRIBE and PSUBSCRIBE in same connection
        # So we handle them in separate threads or use PSUBSCRIBE for everything
        
        if channels.any?
          # Convert regular channels to patterns for unified handling
          channel_patterns = channels.map { |ch| ch } # Exact match patterns
          all_patterns = patterns + channel_patterns
        else
          all_patterns = patterns
        end
        
        @redis_sub.psubscribe(*all_patterns) do |on|
          on.pmessage do |pattern, channel, serialized_message|
            begin
              # Determine message class from channel name
              message_class = extract_message_class_from_channel(channel)
              
              # Process the message if we have a handler
              if message_class && (@dispatcher.subscribers[message_class] || pattern_matches_handler?(channel))
                receive(message_class, serialized_message)
              else
                logger.debug { "[Redis Enhanced] No handler for channel: #{channel}" }
              end
            rescue => e
              logger.error { "[Redis Enhanced] Error processing pattern message: #{e.message}" }
            end
          end
          
          on.psubscribe do |pattern, subscriptions|
            logger.debug { "[Redis Enhanced] Subscribed to pattern: #{pattern} (#{subscriptions} total)" }
          end
          
          on.punsubscribe do |pattern, subscriptions| 
            logger.debug { "[Redis Enhanced] Unsubscribed from pattern: #{pattern} (#{subscriptions} total)" }
          end
        end
      end

      def setup_subscription_handlers(on)
        on.message do |channel, serialized_message|
          begin
            # Handle regular subscription
            receive(channel, serialized_message)
          rescue => e
            logger.error { "[Redis Enhanced] Error processing regular message: #{e.message}" }
          end
        end
        
        on.subscribe do |channel, subscriptions|
          logger.debug { "[Redis Enhanced] Subscribed to channel: #{channel} (#{subscriptions} total)" }
        end
        
        on.unsubscribe do |channel, subscriptions|
          logger.debug { "[Redis Enhanced] Unsubscribed from channel: #{channel} (#{subscriptions} total)" }
        end
      end

      def extract_message_class_from_channel(channel)
        # Handle both original format and enhanced format
        parts = channel.split('.')
        
        if parts.length >= 3
          # Enhanced format: message_type.from.to
          # Extract just the message type part
          message_parts = parts[0..-3] if parts.length > 3
          message_parts ||= [parts[0]]
          
          # Convert back to class name format
          message_parts.map(&:capitalize).join('::')
        else
          # Original format: just use the channel name as class
          channel
        end
      end

      def pattern_matches_handler?(channel)
        # Check if any registered patterns would match this channel
        return false unless @pattern_subscriptions
        
        @pattern_subscriptions.any? do |pattern|
          File.fnmatch(pattern, channel)
        end
      end
    end

    # Fluent API builder for Redis patterns
    class RedisSubscriptionBuilder
      def initialize(transport)
        @transport = transport
        @conditions = {}
      end

      def from(sender_id)
        @conditions[:from] = sender_id
        self
      end

      def to(recipient_id)
        @conditions[:to] = recipient_id
        self
      end

      def type(message_type)
        @conditions[:type] = message_type
        self
      end

      def build
        pattern_parts = []
        
        # Build pattern based on conditions (3-part format for Redis)
        pattern_parts << (@conditions[:type]&.to_s&.gsub('::', '.')&.downcase || '*')
        pattern_parts << (@conditions[:from] || '*')
        pattern_parts << (@conditions[:to] || '*')
        
        pattern_parts.join('.')
      end

      def subscribe
        pattern = build
        @transport.subscribe_pattern(pattern)
      end
    end
  end
end

# Alternative: Redis Streams implementation
module SmartMessage
  module Transport
    class RedisStreamsTransport < Base
      
      def default_options
        {
          url: 'redis://localhost:6379',
          db: 0,
          stream_prefix: 'smart_message',
          consumer_group: 'smart_message_workers',
          consumer_id: Socket.gethostname + '_' + Process.pid.to_s,
          max_len: 10000,  # Trim streams to prevent unbounded growth
          block_time: 1000 # 1 second blocking read
        }
      end

      def configure
        @redis = Redis.new(url: @options[:url], db: @options[:db])
        @streams = {}
        @consumers = {}
        @running = false
      end

      def do_publish(message_class, serialized_message)
        stream_key = derive_stream_key(message_class)
        routing_info = extract_routing_info(serialized_message)
        
        @redis.xadd(
          stream_key,
          {
            data: serialized_message,
            from: routing_info[:from],
            to: routing_info[:to],
            message_class: message_class.to_s,
            timestamp: Time.now.to_f
          },
          maxlen: @options[:max_len],
          approximate: true
        )
        
        logger.debug { "[Redis Streams] Published to stream: #{stream_key}" }
      end

      def subscribe(message_class, process_method, filter_options = {})
        super(message_class, process_method, filter_options)
        
        stream_key = derive_stream_key(message_class)
        setup_consumer_group(stream_key)
        start_consumer(stream_key, message_class, filter_options)
      end

      private

      def derive_stream_key(message_class)
        "#{@options[:stream_prefix]}:#{message_class.to_s.gsub('::', ':').downcase}"
      end

      def setup_consumer_group(stream_key)
        begin
          @redis.xgroup(
            :create,
            stream_key,
            @options[:consumer_group], 
            '$',  # Start from new messages
            mkstream: true
          )
        rescue Redis::CommandError => e
          # Consumer group might already exist
          logger.debug { "[Redis Streams] Consumer group exists: #{e.message}" }
        end
      end

      def start_consumer(stream_key, message_class, filter_options)
        return if @consumers[stream_key]
        
        @consumers[stream_key] = Thread.new do
          while @running
            begin
              # Read from consumer group with blocking
              messages = @redis.xread_group(
                @options[:consumer_group],
                @options[:consumer_id],
                { stream_key => '>' },
                block: @options[:block_time],
                count: 10
              )
              
              messages&.each do |stream, stream_messages|
                stream_messages.each do |message_id, fields|
                  process_stream_message(message_id, fields, message_class, filter_options)
                end
              end
            rescue => e
              logger.error { "[Redis Streams] Consumer error: #{e.message}" }
              sleep(1)
            end
          end
        end
      end

      def process_stream_message(message_id, fields, message_class, filter_options)
        # Apply filtering based on from/to if specified
        from_filter = filter_options[:from]
        to_filter = filter_options[:to]
        
        if from_filter && fields['from'] != from_filter
          @redis.xack(@options[:stream_prefix], @options[:consumer_group], message_id)
          return
        end
        
        if to_filter && fields['to'] != to_filter  
          @redis.xack(@options[:stream_prefix], @options[:consumer_group], message_id)
          return
        end
        
        # Process the message
        begin
          receive(fields['message_class'], fields['data'])
          @redis.xack(@options[:stream_prefix], @options[:consumer_group], message_id)
        rescue => e
          logger.error { "[Redis Streams] Message processing error: #{e.message}" }
          # Message will remain unacknowledged and can be retried
        end
      end

      def extract_routing_info(serialized_message)
        begin
          message_data = JSON.parse(serialized_message)
          header = message_data['_sm_header'] || {}
          
          {
            from: header['from'] || 'anonymous',
            to: header['to'] || 'broadcast'
          }
        rescue JSON::ParserError
          { from: 'anonymous', to: 'broadcast' }
        end
      end
    end
  end
end