# lib/smart_message/dead_letter_queue.rb
# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'
require 'time'

module SmartMessage
  # File-based Dead Letter Queue using the JSON Lines format.
  #
  # Messages that could not be published or processed are appended here, one
  # JSON object per line, oldest first.  They can be inspected, filtered,
  # and replayed.
  #
  # Every read-modify-write runs under an exclusive lock on a sidecar
  # "<file>.lock", so several threads and several processes can share one
  # queue file.  Rewrites go to a temporary file that is then renamed over
  # the queue, so a crash never leaves a half-written queue.
  #
  # Replay never removes an entry before it has been published again: a
  # failed replay leaves the entry in the queue with its retry count raised.
  class DeadLetterQueue
    # The header message_class of a raw entry from a transport with no channels
    UNKNOWN_CLASS = 'Unknown'

    attr_reader :file_path

    @default_mutex = Mutex.new

    class << self
      # The queue at SmartMessage.configuration.dlq_path.
      def default
        @default_mutex.synchronize do
          path = File.expand_path(SmartMessage.configuration.dlq_path)
          @default_instance = new(path) unless @default_instance&.file_path == path
          @default_instance
        end
      end

      # Point the default queue at another file.
      # @return [SmartMessage::DeadLetterQueue]
      def configure_default(file_path)
        SmartMessage.configuration.dlq_path = file_path
        default
      end

      # Forget the memoized default queue (the file is left alone).
      def reset_default!
        @default_mutex.synchronize { @default_instance = nil }
      end
    end

    # @param file_path [String] the queue file; defaults to configuration.dlq_path
    def initialize(file_path = nil)
      @file_path = File.expand_path(file_path || SmartMessage.configuration.dlq_path)
      @lock_path = "#{@file_path}.lock"
      @mutex     = Mutex.new
      FileUtils.mkdir_p(File.dirname(@file_path))
    end

    #########################################################
    ## Core FIFO queue operations

    # Add a failed message to the dead letter queue.
    #
    # @param message [SmartMessage::Base] The message instance
    # @param error_info [Hash] :error, :retry_count, :transport, :stack_trace
    # @return [Hash] the stored entry
    def enqueue(message, error_info = {})
      header = message._sm_header.to_wire
      append(build_entry(
        header:         header,
        payload:        JSON.generate(Serializer::Json.jsonify(message.to_h.merge(_sm_header: header))),
        payload_format: 'json',
        error_info:     error_info
      ))
    end

    # Add a serialized payload that could not be turned into a message
    # (for example, one that failed to decode on receive).
    #
    # @param message_class [String] the class or channel it arrived for
    # @param payload [String] the serialized bytes, stored untouched
    # @param error_info [Hash] :error, :retry_count, :transport,
    #   :stack_trace, :serializer (payload format; default 'json')
    # @return [Hash] the stored entry
    def enqueue_raw(message_class:, payload:, error_info: {})
      append(build_entry(
        header:         { message_class: message_class.to_s },
        payload:        payload.to_s,
        payload_format: (error_info[:serializer] || 'json').to_s,
        error_info:     error_info
      ))
    end

    # Remove and return the oldest message from the queue.
    # Corrupt lines ahead of it are dropped and reported.
    # @return [Hash, nil] The oldest DLQ entry or nil if queue is empty
    def dequeue
      with_lock do
        lines = read_lines
        index   = lines.index { |line| parse_line(line) }
        corrupt = index || lines.size
        report_corrupt(corrupt) if corrupt.positive?

        if index.nil?
          rewrite([]) if lines.any?
          next nil
        end

        entry = parse_line(lines[index])
        rewrite(lines[(index + 1)..])
        entry
      end
    end

    # Look at the oldest message without removing it
    # @return [Hash, nil] The oldest DLQ entry or nil if queue is empty
    def peek
      entries.first
    end

    # Get the number of lines in the queue file (corrupt lines included)
    # @return [Integer]
    def size
      with_lock { read_lines.size }
    end

    def empty?
      size.zero?
    end

    # Clear all messages from the queue
    def clear
      with_lock { File.delete(@file_path) if File.exist?(@file_path) }
      nil
    end

    #########################################################
    ## Replay

    # Replay every message that is in the queue right now.
    # @param transport [SmartMessage::Transport::Base] Optional transport override
    # @return [Hash] { success:, failed:, errors: }
    def replay_all(transport = nil)
      replay_entries(entries, transport)
    end

    # Replay the oldest message.
    # @param transport [SmartMessage::Transport::Base] Optional transport override
    # @return [Hash] { success: true, message: } or { success: false, error: }
    def replay_one(transport = nil)
      entry = peek
      return { success: false, error: 'Queue is empty' } unless entry

      replay_and_settle(entry, transport)
    end

    # Replay the oldest +count+ messages.
    # @param count [Integer] Number of messages to replay
    # @param transport [SmartMessage::Transport::Base] Optional transport override
    # @return [Hash] { success:, failed:, errors: }
    def replay_batch(count = 10, transport = nil)
      replay_entries(entries.first(count), transport)
    end

    #########################################################
    ## Administrative utilities

    # Every valid entry in the queue, oldest first.
    # @return [Array<Hash>]
    def entries
      with_lock { read_lines }.filter_map { |line| parse_line(line) }
    end

    # Inspect messages in the queue without removing them
    # @param limit [Integer] Maximum number of messages to show
    # @return [Array<Hash>] Array of DLQ entries
    def inspect_messages(limit: 10)
      return [] unless limit.positive?

      entries.first(limit)
    end

    # Filter messages by message class
    # @param message_class [String] The message class name to filter by
    # @return [Array<Hash>] Filtered DLQ entries
    def filter_by_class(message_class)
      entries.select { |entry| entry.dig(:header, :message_class) == message_class.to_s }
    end

    # Filter messages by error pattern
    # @param pattern [Regexp, String] Pattern to match against error messages
    # @return [Array<Hash>] Filtered DLQ entries
    def filter_by_error_pattern(pattern)
      pattern = Regexp.new(pattern) if pattern.is_a?(String)
      entries.select { |entry| pattern.match?(entry[:error].to_s) }
    end

    # Get statistics about the dead letter queue
    # @return [Hash] { total:, by_class:, by_error:, corrupt: }
    def statistics
      lines = with_lock { read_lines }
      valid = lines.filter_map { |line| parse_line(line) }

      {
        total:    valid.size,
        by_class: valid.map { |entry| (entry.dig(:header, :message_class) || UNKNOWN_CLASS).split('::').last }.tally,
        by_error: valid.map { |entry| entry[:error] || 'Unknown error' }.tally,
        corrupt:  lines.size - valid.size
      }
    end

    # Export messages within a time range
    # @param start_time [Time] Start of time range
    # @param end_time [Time] End of time range
    # @return [Array<Hash>] DLQ entries within the time range
    def export_range(start_time, end_time)
      entries.select do |entry|
        Time.parse(entry[:timestamp].to_s).between?(start_time, end_time)
      rescue ArgumentError
        false # an entry with an unreadable timestamp is in no range
      end
    end

    private

    def logger
      SmartMessage::Logger.default
    end

    def build_entry(header:, payload:, payload_format:, error_info:)
      {
        id:             SecureRandom.uuid,
        timestamp:      Time.now.iso8601(3),
        header:         header.transform_values { |value| Serializer::Json.jsonify(value) },
        payload:        payload,
        payload_format: payload_format,
        error:          error_info[:error] || 'Unknown error',
        retry_count:    error_info[:retry_count] || 0,
        transport:      error_info[:transport],
        stack_trace:    error_info[:stack_trace]
      }
    end

    # Append one entry as one line, flushed to disk.
    def append(entry)
      line = "#{JSON.generate(entry)}\n"
      with_lock do
        File.open(@file_path, 'a') do |file|
          file.write(line)
          file.fsync
        end
      end
      entry
    end

    # Run a block while holding the queue's lock, against other threads of
    # this process and against other processes.
    def with_lock
      @mutex.synchronize do
        File.open(@lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        end
      end
    end

    # @return [Array<String>] non-blank lines, without newlines
    def read_lines
      return [] unless File.exist?(@file_path)

      File.readlines(@file_path, chomp: true).reject { |line| line.strip.empty? }
    end

    # @return [Hash, nil] the entry, or nil for a corrupt line
    def parse_line(line)
      entry = JSON.parse(line, symbolize_names: true)
      entry.is_a?(Hash) ? entry : nil
    rescue JSON::ParserError
      nil
    end

    # Replace the queue's contents atomically.  Call inside with_lock.
    def rewrite(lines)
      temp_path = "#{@file_path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
      File.open(temp_path, 'w') do |file|
        lines.each { |line| file.write("#{line}\n") }
        file.fsync
      end
      File.rename(temp_path, @file_path)
    ensure
      File.delete(temp_path) if temp_path && File.exist?(temp_path)
    end

    def report_corrupt(count)
      logger.warn { "[SmartMessage::DeadLetterQueue] Dropped #{count} corrupt line(s) from #{@file_path}" }
    end

    def replay_entries(batch, transport)
      results = { success: 0, failed: 0, errors: [] }

      batch.each do |entry|
        outcome = replay_and_settle(entry, transport)
        if outcome[:success]
          results[:success] += 1
        else
          results[:failed] += 1
          results[:errors] << outcome[:error]
        end
      end

      results
    end

    # Replay one entry, then remove it on success or mark it on failure.
    def replay_and_settle(entry, transport)
      outcome = replay_entry(entry, transport)

      if outcome[:success]
        remove_entry(entry)
      else
        mark_failed_replay(entry, outcome[:error])
      end

      outcome
    end

    # Does a stored line hold this entry?  Entries carry an id; entries
    # written by older versions are matched on their content.
    def same_entry?(line, entry)
      stored = parse_line(line)
      return false unless stored

      entry[:id] ? stored[:id] == entry[:id] : stored == entry
    end

    # Remove one entry (the first match) from the queue.
    def remove_entry(entry)
      with_lock do
        lines = read_lines
        index = lines.index { |line| same_entry?(line, entry) }
        next unless index

        lines.delete_at(index)
        rewrite(lines)
      end
    end

    # Record a failed replay on the entry, in place.
    def mark_failed_replay(entry, error)
      with_lock do
        lines = read_lines
        index = lines.index { |line| same_entry?(line, entry) }
        next unless index

        updated = entry.merge(
          error:       "Replay failed: #{error}",
          retry_count: (entry[:retry_count] || 0) + 1
        )
        lines[index] = JSON.generate(updated)
        rewrite(lines)
      end
    end

    # Rebuild the message from a DLQ entry and publish it.
    #
    # The message goes straight to the transports, not through
    # Message#publish: a failed publish there dead-letters the message,
    # which would add a second copy of an entry that is already queued.
    #
    # @param entry [Hash] The DLQ entry to replay
    # @param transport_override [SmartMessage::Transport::Base] Optional transport override
    # @return [Hash] { success: true, message: } or { success: false, error: }
    def replay_entry(entry, transport_override = nil)
      message = rebuild_message(entry)
      targets = transport_override ? [transport_override] : message.transports
      if targets.empty?
        raise Errors::TransportNotConfigured, "#{message.class.name} has no transport configured"
      end

      message.validate!
      targets.each { |target| target.publish(message) }

      { success: true, message: message }
    rescue StandardError => e
      { success: false, error: "#{e.class.name}: #{e.message}" }
    end

    # @return [SmartMessage::Base] the message stored in an entry, with its
    #   original header (same UUID)
    # @raise [SmartMessage::Errors::MessageClassMismatch] when the payload
    #   names a different class than the one the entry was stored for
    def rebuild_message(entry)
      serializer = Serializer.for(entry[:payload_format]) || Serializer::Json
      Envelope.decode(
        entry[:payload],
        serializer:      serializer.new,
        channel:         stored_class_name(entry),
        fallback_header: entry[:header]
      )
    end

    # @return [String, nil] the message class the entry was stored for, or
    #   nil when it was stored without one (a transport with no channels)
    def stored_class_name(entry)
      name = entry.dig(:header, :message_class)
      name unless name == UNKNOWN_CLASS
    end
  end
end
