# lib/smart_message/transport/file_transport.rb
# encoding: utf-8
# frozen_string_literal: true

require 'fileutils'

module SmartMessage
  module Transport
    # Appends each published message to a file, one serialized message per
    # line (JSON Lines with the default serializer).
    #
    # Subscribing starts one background poller that tails the same file and
    # delivers each new line to the handlers of the message class named in
    # that line's header.  Several processes can share one file: writers
    # append, readers tail.
    #
    # A reader notices that the file was truncated or replaced when it
    # becomes shorter than what the reader has already consumed, and starts
    # again from the beginning.
    #
    # Options:
    #   file_path:          the file (String or Pathname), or an IO to write
    #                       to.  Required.  An IO can be published to but
    #                       not subscribed from, and is never closed.
    #   create_directories: create the file's directory (default true)
    #   encoding:           file encoding (default: Ruby's default)
    #   poll_interval:      seconds between checks for new lines (default 0.5)
    #   read_from_end:      a new subscription sees only lines written after
    #                       it started (default true); false reads the
    #                       whole file first
    class FileTransport < Base
      def default_options
        {
          file_path:          nil,
          create_directories: true,
          encoding:           nil,
          poll_interval:      0.5,
          read_from_end:      true
        }
      end

      def configure
        target = @options[:file_path]
        raise ArgumentError, "#{self.class.name} requires a file_path: option" if target.nil?

        @io_target   = target.respond_to?(:write)
        @path        = @io_target ? nil : File.expand_path(target.to_s)
        @handle      = @io_target ? target : nil
        @write_mutex = Mutex.new
        @poll_mutex  = Mutex.new
        @poller      = nil
        @closed      = false
      end

      # @return [String, nil] the absolute path, or nil when writing to an IO
      attr_reader :path

      def do_publish(_message_class, serialized_message)
        @write_mutex.synchronize do
          raise SmartMessage::Errors::TransportError, "#{self.class.name} is disconnected" if @closed

          handle = write_handle
          handle.write("#{serialized_message}\n")
          handle.flush
        end
      end

      def subscribe(message_class, process_method, filter_options = {})
        if @io_target
          raise SmartMessage::Errors::TransportError,
                "#{self.class.name} cannot subscribe when file_path is an IO; give it a path"
        end

        super
        start_poller
      end

      def unsubscribe(message_class, process_method)
        super
        stop_poller if subscribers.empty?
      end

      def unsubscribe!(message_class)
        super
        stop_poller if subscribers.empty?
      end

      def connected?
        !@closed
      end

      def connect
        @write_mutex.synchronize { @closed = false }
        start_poller unless @io_target || subscribers.empty?
      end

      # Stop the poller and close the file this transport opened.
      # Safe to call more than once.
      def disconnect
        stop_poller
        @write_mutex.synchronize do
          @closed = true
          next if @io_target

          @handle&.close unless @handle&.closed?
          @handle = nil
        end
      end

      # Read the complete lines in +path+ starting at byte +position+.
      # A trailing partial line (a writer is mid-line) is left for next time.
      #
      # @return [Array(Array<String>, Integer)] the lines, and the position
      #   to continue from
      def self.read_complete_lines(path, position, encoding: nil)
        return [[], 0] unless File.exist?(path)

        size     = File.size(path)
        position = 0 if size < position # the file was truncated or replaced
        return [[], position] if size == position

        chunk    = File.open(path, 'rb') { |file| file.seek(position) && file.read(size - position) }
        complete = chunk.rindex("\n")
        return [[], position] if complete.nil?

        text = chunk[0..complete].force_encoding(encoding || Encoding.default_external)
        [text.split("\n").reject { |line| line.strip.empty? }, position + complete + 1]
      end

      protected

      # Every reader of a shared file sees every line.  A line for a message
      # class this process has not loaded belongs to another reader, so it is
      # skipped instead of being dead-lettered by each of them.
      def dead_letter_on_receive_error?(error)
        !error.is_a?(SmartMessage::Errors::UnknownMessageClass)
      end

      private

      def write_handle
        return @handle if @handle

        FileUtils.mkdir_p(File.dirname(@path)) if @options[:create_directories]
        @handle = File.open(@path, 'a', encoding: @options[:encoding])
      end

      def start_poller
        @poll_mutex.synchronize do
          return if @poller&.alive?

          position  = @options[:read_from_end] && File.exist?(@path) ? File.size(@path) : 0
          @wakeup   = Queue.new
          @poller   = Thread.new { poll_loop(position, @wakeup) }
          @poller.name = 'SmartMessage-FilePoller'
        end
      end

      def stop_poller
        poller = @poll_mutex.synchronize do
          thread  = @poller
          @poller = nil
          @wakeup&.push(:stop)
          thread
        end
        return if poller.nil? || poller == Thread.current

        poller.join(5) || poller.kill
      end

      # Tail the file until told to stop.  The Queue doubles as the sleep
      # timer, so stopping does not wait out a poll interval.
      def poll_loop(position, wakeup)
        loop do
          position = deliver_new_lines(position)
          break if wakeup.pop(timeout: @options[:poll_interval]) == :stop
        end
      rescue StandardError => e
        logger.error { "[#{self.class.name}] Poller stopped: #{e.class.name} - #{e.message}" }
      end

      # @return [Integer] the position to continue from
      def deliver_new_lines(position)
        lines, position = self.class.read_complete_lines(@path, position, encoding: @options[:encoding])

        lines.each do |line|
          receive(nil, line)
        rescue SmartMessage::Errors::UnknownMessageClass => e
          logger.debug { "[#{self.class.name}] Skipped a line: #{e.message}" }
        rescue StandardError => e
          logger.error { "[#{self.class.name}] Could not process a line of #{@path}: #{e.class.name} - #{e.message}" }
        end

        position
      end
    end
  end
end
