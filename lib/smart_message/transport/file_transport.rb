# lib/smart_message/transport/file_transport.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'file_operations'
require_relative 'file_watching'
require_relative 'partitioned_files'
require_relative 'async_publish_queue'
require_relative 'fifo_operations'

module SmartMessage
  module Transport
    class FileTransport < Base
      include FileOperations
      include FileWatching
      include PartitionedFiles
      include AsyncPublishQueue
      include FifoOperations

      # @param path [String, IO, Pathname] file path or IO-like object
      # @param mode [String] file open mode ("a" for append, etc.)
      # @param encoding [String, nil] file encoding
      def initialize(options = {})
        @current_message_class = nil
        super(**options)
      end

      def default_options
        {
          file_path: 'messages.log',
          file_mode: 'a',
          encoding: nil,
          file_format: :lines,
          buffer_size: 0,
          flush_interval: nil,
          auto_flush: true,
          rotate_size: nil,
          rotate_time: nil,
          rotate_count: 5,
          timestamp_format: '%Y%m%d_%H%M%S',
          create_directories: true,
          async: false,
          max_queue: nil,
          drop_when_full: false,
          queue_overflow_strategy: :block,
          max_retries: 3,
          max_retry_delay: 30,
          worker_timeout: 5,
          shutdown_timeout: 10,
          queue_warning_threshold: 0.8,
          enable_queue_monitoring: true,
          drain_queue_on_shutdown: true,
          send_dropped_to_dlq: false,
          read_from_end: true,
          poll_interval: 1.0,
          file_type: :regular,
          create_fifo: false,
          fifo_mode: :blocking,
          fifo_permissions: 0644,
          fallback_transport: nil,
          enable_subscriptions: false,
          subscription_mode: :polling,
          filename_selector: nil,
          directory: nil,
          subscription_file_path: nil
        }
      end

      def configure
        # Call parent configuration first
        super if defined?(super)
        
        # Then configure our file-specific features
        if @options[:async]
          configure_async_publishing
        elsif @options[:file_type] == :fifo
          configure_fifo
        else
          configure_file_output
        end
      end

      def publish(payload)
        do_publish(nil, payload)
      end

      def do_publish(message_class, serialized_message)
        @current_message_class = message_class
        if @options[:async]
          async_publish(message_class, serialized_message)
        else
          if @options[:filename_selector] || @options[:directory]
            header = { message_class_name: message_class.to_s }
            path = determine_file_path(serialized_message, header)
            @file_handle = get_or_open_partition_handle(path)
            write_to_file(serialized_message)
          elsif @options[:file_type] == :fifo
            write_to_fifo(serialized_message)
          else
            write_to_file(serialized_message)
          end
        end
      end

      def subscribe(message_class, process_method, filter_options = {})
        unless @options[:enable_subscriptions]
          logger.warn { "[FileTransport] Subscriptions disabled - set enable_subscriptions: true" }
          return
        end

        if @options[:file_type] == :fifo
          start_fifo_reader(message_class, process_method, filter_options)
        else
          start_file_polling(message_class, process_method, filter_options)
        end

        super(message_class, process_method, filter_options)
      end

      def connected?
        case @options[:file_type]
        when :fifo
          subscription_active? || fifo_active?
        else
          (@file_handle && !@file_handle.closed?) || subscription_active?
        end
      end

      def disconnect
        stop_file_subscriptions
        stop_fifo_operations if @options[:file_type] == :fifo
        stop_async_publishing if @options[:async]
        close_partition_handles if @options[:filename_selector] || @options[:directory]
        close_file_handle
      end

      private

      def subscription_active?
        @polling_thread&.alive? || fifo_active?
      end

      def stop_file_subscriptions
        @polling_thread&.kill
        @polling_thread&.join(5)
      end
    end
  end
end