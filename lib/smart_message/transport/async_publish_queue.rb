# lib/smart_message/transport/async_publish_queue.rb
# encoding: utf-8
# frozen_string_literal: true

require 'timeout'

module SmartMessage
  module Transport
    # Module for asynchronous publishing queue.
    module AsyncPublishQueue
      
      private
      
      def logger
        # Ensure we have a proper logger, not just an IO object
        if @logger && @logger.respond_to?(:error) && @logger.respond_to?(:info) && @logger.respond_to?(:warn)
          return @logger
        end
        @logger = SmartMessage::Logger.default
      end
      
      public
      def configure_async_publishing
        return unless @options[:async]
        
        # Ensure file configuration is set up first
        configure_file_output if respond_to?(:configure_file_output)
        
        @publish_queue = @options[:max_queue] ? SizedQueue.new(@options[:max_queue]) : Queue.new
        @queue_stats = { queued: 0, processed: 0, failed: 0, dropped: 0, blocked_count: 0, max_queue_size_reached: 0 }
        @last_warning_time = nil
        
        start_publish_worker
        start_queue_monitoring if @options[:enable_queue_monitoring]
      end

      def async_publish(message_class, serialized_message)
        check_queue_warning
        
        if queue_full?
          handle_queue_overflow(message_class, serialized_message)
          return false
        end
        
        @publish_queue << { 
          message_class: message_class, 
          serialized_message: serialized_message, 
          timestamp: Time.now, 
          retry_count: 0 
        }
        @queue_stats[:queued] += 1
        true
      rescue => e
        begin
          logger.error { "[FileTransport] Error queuing message: #{e.message}" }
        rescue
          # Fallback if logger is not available
        end
        false
      end

      def queue_full?
        @publish_queue.is_a?(SizedQueue) && @publish_queue.size >= @options[:max_queue]
      end

      def queue_usage_percentage
        return 0 unless @publish_queue.is_a?(SizedQueue)
        (@publish_queue.size.to_f / @options[:max_queue] * 100).round(1)
      end

      def publish_stats
        return {} unless @options[:async]
        @queue_stats.merge(
          current_size: @publish_queue.size,
          worker_alive: @publish_worker_thread&.alive? || false
        )
      end

      private

      def start_publish_worker
        @publish_worker_thread = Thread.new do
          Thread.current.name = "FileTransport-Publisher"
          
          loop do
            begin
              message_data = Timeout.timeout(@options[:worker_timeout] || 5) { @publish_queue.pop }
              process_queued_message(message_data)
            rescue Timeout::Error
              next
            rescue => e
              begin
                logger.error { "[FileTransport] Publish worker error: #{e.message}" }
              rescue
                # Fallback if logger is not available
              end
              sleep 1
            end
          end
        end
      end

      def process_queued_message(message_data)
        success = do_sync_publish(message_data[:message_class], message_data[:serialized_message])
        if success
          @queue_stats[:processed] += 1
        else
          handle_publish_failure(message_data)
        end
      end

      def do_sync_publish(message_class, serialized_message)
        begin
          if @options[:file_type] == :fifo
            write_to_fifo(serialized_message)
          else
            write_to_file(serialized_message)
          end
          true
        rescue => e
          begin
            logger.error { "[FileTransport] Sync write error: #{e.message}" }
          rescue
            # Fallback if logger is not available
          end
          false
        end
      end

      def handle_publish_failure(message_data)
        retry_count = message_data[:retry_count] + 1
        max_retries = @options[:max_retries] || 3
        
        if retry_count <= max_retries
          sleep_time = [2 ** retry_count, @options[:max_retry_delay] || 30].min
          Thread.new do
            sleep sleep_time
            message_data[:retry_count] = retry_count
            @publish_queue << message_data
          end
          logger.warn { "[FileTransport] Retrying message publish (attempt #{retry_count}/#{max_retries})" }
        else
          @queue_stats[:failed] += 1
          send_to_dead_letter_queue(message_data) if defined?(SmartMessage::DeadLetterQueue)
        end
      end

      def handle_queue_overflow(message_class, serialized_message)
        case @options[:queue_overflow_strategy]
        when :drop_newest
          @queue_stats[:dropped] += 1
          logger.warn { "[FileTransport] Dropping newest message - queue full (#{@publish_queue.size}/#{@options[:max_queue]})" }
        when :drop_oldest
          begin
            dropped_message = @publish_queue.pop(true)
            @publish_queue << {
              message_class: message_class,
              serialized_message: serialized_message,
              timestamp: Time.now,
              retry_count: 0
            }
            @queue_stats[:dropped] += 1
            logger.warn { "[FileTransport] Dropped oldest message to make room for new message" }
            send_to_dead_letter_queue(dropped_message) if @options[:send_dropped_to_dlq]
          rescue ThreadError
            @queue_stats[:dropped] += 1
            logger.error { "[FileTransport] Queue overflow but queue appears empty - dropping message" }
          end
        when :block
          @queue_stats[:blocked_count] += 1
          start_time = Time.now
          logger.warn { "[FileTransport] Queue full (#{@publish_queue.size}/#{@options[:max_queue]}) - blocking until space available" }
          
          @publish_queue << {
            message_class: message_class,
            serialized_message: serialized_message,
            timestamp: Time.now,
            retry_count: 0
          }
          logger.info { "[FileTransport] Queue space available after #{(Time.now - start_time).round(2)}s - message queued" }
          @queue_stats[:queued] += 1
          return true
        else
          @queue_stats[:dropped] += 1
          logger.error { "[FileTransport] Unknown overflow strategy '#{@options[:queue_overflow_strategy]}', dropping message" }
        end
        false
      end

      def send_to_dead_letter_queue(message_data)
        SmartMessage::DeadLetterQueue.default.enqueue(
          message_data[:message_class],
          message_data[:serialized_message],
          error: "Failed async publish after #{@options[:max_retries]} retries",
          transport: self.class.name,
          retry_count: message_data[:retry_count]
        )
      rescue => e
        begin
          logger.error { "[FileTransport] Failed to send to DLQ: #{e.message}" }
        rescue
          # Fallback if logger is not available
        end
      end

      def check_queue_warning
        return unless @options[:queue_warning_threshold]
        return if @options[:max_queue] == 0
        
        usage = queue_usage_percentage
        threshold = @options[:queue_warning_threshold] * 100
        
        if usage >= threshold
          now = Time.now
          if @last_warning_time.nil? || (now - @last_warning_time) > 60
            logger.warn { "[FileTransport] Publish queue is #{usage}% full (#{@publish_queue.size}/#{@options[:max_queue]})" }
            @last_warning_time = now
          end
        end
      end

      def start_queue_monitoring
        @queue_monitoring_thread = Thread.new do
          Thread.current.name = "FileTransport-QueueMonitor"
          
          loop do
            sleep 30
            
            begin
              stats = publish_stats
              usage = queue_usage_percentage
              
              logger.info do
                "[FileTransport] Queue stats: #{stats[:current_size]} messages " \
                "(#{usage}% full), processed: #{stats[:processed]}, " \
                "failed: #{stats[:failed]}, worker: #{stats[:worker_alive] ? 'alive' : 'dead'}"
              end
            rescue => e
              logger.error { "[FileTransport] Queue monitoring error: #{e.message}" }
            end
          end
        end
      end

      def stop_async_publishing
        return unless @publish_worker_thread
        
        @publish_worker_thread.kill
        @publish_worker_thread.join(@options[:shutdown_timeout] || 10)
        
        if @options[:drain_queue_on_shutdown]
          drain_publish_queue
        end
        
        @publish_worker_thread = nil
        @queue_monitoring_thread&.kill
        @queue_monitoring_thread&.join(5)
      end

      def drain_publish_queue
        begin
          logger.info { "[FileTransport] Draining #{@publish_queue.size} queued messages" }
        rescue
          # Fallback if logger is not available
        end
        
        until @publish_queue.empty?
          begin
            message_data = @publish_queue.pop(true)
            process_queued_message(message_data)
          rescue ThreadError
            break
          end
        end
        
        begin
          logger.info { "[FileTransport] Queue drained" }
        rescue
          # Fallback if logger is not available
        end
      end
    end
  end
end