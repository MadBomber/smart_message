# lib/smart_message/dead_letter_queue.rb
# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'fileutils'

module SmartMessage
  # File-based Dead Letter Queue implementation using JSON Lines format
  # Provides FIFO queue operations with replay capabilities for failed messages
  class DeadLetterQueue
    attr_reader :file_path

    # Default singleton instance
    @@default_instance = nil

    def self.default
      @@default_instance ||= new
    end

    def self.configure_default(file_path)
      @@default_instance = new(file_path)
    end

    def initialize(file_path = 'dead_letters.jsonl')
      @file_path = File.expand_path(file_path)
      @mutex = Mutex.new
      ensure_directory_exists
      
      logger.debug { "[SmartMessage::DeadLetterQueue] Initialized with file path: #{@file_path}" }
    rescue => e
      logger&.error { "[SmartMessage] Error in dead letter queue initialization: #{e.class.name} - #{e.message}" }
      raise
    end
    
    private
    
    def logger
      @logger ||= SmartMessage::Logger.default
    end
    
    public

    # Core FIFO queue operations

    # Add a failed message to the dead letter queue
    # @param message [SmartMessage::Base] The message instance
    # @param error_info [Hash] Error details including :error, :retry_count, :transport, etc.
    def enqueue(message, error_info = {})
      message_header = message._sm_header
      message_payload = message.encode

      entry = {
        timestamp: Time.now.iso8601,
        header: message_header.to_hash,
        payload: message_payload,
        payload_format: error_info[:serializer] || 'json',
        error: error_info[:error] || 'Unknown error',
        retry_count: error_info[:retry_count] || 0,
        transport: error_info[:transport],
        stack_trace: error_info[:stack_trace]
      }

      @mutex.synchronize do
        File.open(@file_path, 'a') do |file|
          file.puts entry.to_json
          file.fsync  # Ensure immediate write to disk
        end
      end

      entry
    end

    # Remove and return the oldest message from the queue
    # @return [Hash, nil] The oldest DLQ entry or nil if queue is empty
    def dequeue
      @mutex.synchronize do
        return nil unless File.exist?(@file_path)

        lines = File.readlines(@file_path)
        return nil if lines.empty?

        # Get first line (oldest)
        oldest_line = lines.shift
        oldest_entry = JSON.parse(oldest_line.strip, symbolize_names: true)

        # Rewrite file without the first line
        File.open(@file_path, 'w') do |file|
          lines.each { |line| file.write(line) }
        end

        oldest_entry
      end
    rescue JSON::ParserError => e
      logger.warn { "[SmartMessage] Warning: Corrupted DLQ entry skipped: #{e.message}" }
      nil
    end

    # Look at the oldest message without removing it
    # @return [Hash, nil] The oldest DLQ entry or nil if queue is empty
    def peek
      return nil unless File.exist?(@file_path)

      File.open(@file_path, 'r') do |file|
        first_line = file.readline
        return nil if first_line.nil? || first_line.strip.empty?
        JSON.parse(first_line.strip, symbolize_names: true)
      end
    rescue EOFError, JSON::ParserError
      nil
    end

    # Get the number of messages in the queue
    # @return [Integer] Number of messages in the DLQ
    def size
      return 0 unless File.exist?(@file_path)
      File.readlines(@file_path).size
    end

    # Clear all messages from the queue
    def clear
      @mutex.synchronize do
        File.delete(@file_path) if File.exist?(@file_path)
      end
    end

    # Replay capabilities

    # Replay all messages in the queue
    # @param transport [SmartMessage::Transport::Base] Optional transport override
    # @return [Hash] Results summary
    def replay_all(transport = nil)
      results = { success: 0, failed: 0, errors: [] }

      while (entry = dequeue)
        result = replay_entry(entry, transport)
        if result[:success]
          results[:success] += 1
        else
          results[:failed] += 1
          results[:errors] << result[:error]
          # Re-enqueue failed replay attempts
          header = SmartMessage::Header.new(entry[:header])
          enqueue(header, entry[:payload],
            error: "Replay failed: #{result[:error]}",
            retry_count: (entry[:retry_count] || 0) + 1)
        end
      end

      results
    end

    # Replay the oldest message
    # @param transport [SmartMessage::Transport::Base] Optional transport override
    # @return [Hash] Result of replay attempt
    def replay_one(transport = nil)
      entry = dequeue
      return { success: false, error: 'Queue is empty' } unless entry

      replay_entry(entry, transport)
    end

    # Replay a batch of messages
    # @param count [Integer] Number of messages to replay
    # @param transport [SmartMessage::Transport::Base] Optional transport override
    # @return [Hash] Results summary
    def replay_batch(count = 10, transport = nil)
      results = { success: 0, failed: 0, errors: [] }

      count.times do
        break if size == 0

        result = replay_one(transport)
        if result[:success]
          results[:success] += 1
        else
          results[:failed] += 1
          results[:errors] << result[:error]
        end
      end

      results
    end

    # Administrative utilities

    # Inspect messages in the queue without removing them
    # @param limit [Integer] Maximum number of messages to show
    # @return [Array<Hash>] Array of DLQ entries
    def inspect_messages(limit: 10)
      count = 0
      read_entries_with_filter do |entry|
        return [] if count >= limit
        count += 1
        entry
      end
    end

    # Filter messages by message class
    # @param message_class [String] The message class name to filter by
    # @return [Array<Hash>] Filtered DLQ entries
    def filter_by_class(message_class)
      read_entries_with_filter do |entry|
        entry if entry.dig(:header, :message_class) == message_class
      end
    end

    # Filter messages by error pattern
    # @param pattern [Regexp, String] Pattern to match against error messages
    # @return [Array<Hash>] Filtered DLQ entries
    def filter_by_error_pattern(pattern)
      pattern = Regexp.new(pattern) if pattern.is_a?(String)
      
      read_entries_with_filter do |entry|
        entry if pattern.match?(entry[:error].to_s)
      end
    end

    # Get statistics about the dead letter queue
    # @return [Hash] Statistics summary
    def statistics
      stats = { total: 0, by_class: Hash.new(0), by_error: Hash.new(0) }
      
      read_entries_with_filter do |entry|
        stats[:total] += 1
        
        full_class_name = entry.dig(:header, :message_class) || 'Unknown'
        # Extract short class name (everything after the last ::)
        short_class_name = full_class_name.split('::').last || full_class_name
        stats[:by_class][short_class_name] += 1
        
        error = entry[:error] || 'Unknown error'
        stats[:by_error][error] += 1
        
        nil  # Don't collect entries, just process for side effects
      end
      
      stats
    end

    # Export messages within a time range
    # @param start_time [Time] Start of time range
    # @param end_time [Time] End of time range
    # @return [Array<Hash>] DLQ entries within the time range
    def export_range(start_time, end_time)
      read_entries_with_filter do |entry|
        begin
          timestamp = Time.parse(entry[:timestamp])
          entry if timestamp >= start_time && timestamp <= end_time
        rescue ArgumentError
          # Skip entries with invalid timestamps
          nil
        end
      end
    end

    private

    # Replay a single DLQ entry by recreating the message instance
    # @param entry [Hash] The DLQ entry to replay
    # @param transport_override [SmartMessage::Transport::Base] Optional transport override
    # @return [Hash] Result of replay attempt
    def replay_entry(entry, transport_override = nil)
      message_class_name = entry.dig(:header, :message_class)
      return { success: false, error: 'Missing message class' } unless message_class_name

      # Get the message class
      message_class = message_class_name.constantize

      # Deserialize the payload using the appropriate format
      payload_data = deserialize_payload(entry[:payload], entry[:payload_format] || 'json')
      return { success: false, error: 'Failed to deserialize payload' } unless payload_data

      # Remove the header from payload data (it's stored separately in DLQ)
      payload_data.delete(:_sm_header)

      # Create new message instance with original data
      message = message_class.new(**payload_data)

      # Restore complete header information
      restore_header_fields(message, entry[:header])

      # Override transport if provided - this must be done before publishing
      if transport_override
        message.transport(transport_override)
      end

      # Attempt to publish the message
      message.publish

      { success: true, message: message }
    rescue => e
      { success: false, error: "#{e.class.name}: #{e.message}" }
    end

    # Deserialize payload based on format
    # @param payload [String] The serialized payload
    # @param format [String] The serialization format (json, etc.)
    # @return [Hash, nil] Deserialized data or nil if failed
    def deserialize_payload(payload, format)
      case format.to_s.downcase
      when 'json'
        JSON.parse(payload, symbolize_names: true)
      else
        # For unknown formats, assume JSON as fallback but log warning
        logger.warn { "[SmartMessage] Warning: Unknown payload format '#{format}', attempting JSON" }
        JSON.parse(payload, symbolize_names: true)
      end
    rescue JSON::ParserError => e
      logger.error { "[SmartMessage] Error in payload deserialization: #{e.class.name} - #{e.message}" }
      nil
    end

    # Restore all header fields from DLQ entry
    # @param message [SmartMessage::Base] The message instance
    # @param header_data [Hash] The stored header data
    def restore_header_fields(message, header_data)
      return unless header_data
      
      # Restore all available header fields
      message._sm_header.uuid = header_data[:uuid] if header_data[:uuid]
      message._sm_header.message_class = header_data[:message_class] if header_data[:message_class]
      message._sm_header.published_at = Time.parse(header_data[:published_at]) if header_data[:published_at]
      message._sm_header.publisher_pid = header_data[:publisher_pid] if header_data[:publisher_pid]
      message._sm_header.version = header_data[:version] if header_data[:version]
      message._sm_header.from = header_data[:from] if header_data[:from]
      message._sm_header.to = header_data[:to] if header_data[:to]
      message._sm_header.reply_to = header_data[:reply_to] if header_data[:reply_to]
    rescue => e
      logger.warn { "[SmartMessage] Warning: Failed to restore some header fields: #{e.message}" }
    end

    # Generic file reading iterator with error handling
    # @param block [Proc] Block to execute for each valid entry
    # @return [Array] Results from the block
    def read_entries_with_filter(&block)
      return [] unless File.exist?(@file_path)
      
      results = []
      File.open(@file_path, 'r') do |file|
        file.each_line do |line|
          begin
            entry = JSON.parse(line.strip, symbolize_names: true)
            result = block.call(entry)
            results << result if result
          rescue JSON::ParserError
            # Skip corrupted lines
          end
        end
      end
      
      results
    end

    # Ensure the directory for the DLQ file exists
    def ensure_directory_exists
      directory = File.dirname(@file_path)
      FileUtils.mkdir_p(directory) unless Dir.exist?(directory)
    end
  end
end
