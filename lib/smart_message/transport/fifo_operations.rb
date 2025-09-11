# lib/smart_message/transport/fifo_operations.rb
# encoding: utf-8
# frozen_string_literal: true

require 'rbconfig'

module SmartMessage
  module Transport
    # Module for FIFO operations, with cross-platform considerations.
    module FifoOperations
      
      private
      
      def logger
        # Ensure we have a proper logger, not just an IO object
        if @logger && @logger.respond_to?(:error) && @logger.respond_to?(:info) && @logger.respond_to?(:warn)
          return @logger
        end
        @logger = SmartMessage::Logger.default
      end
      
      public
      def configure_fifo
        unless platform_supports_fifo?
          begin
            logger.warn { "[FileTransport] FIFO not supported, falling back to regular file" }
          rescue
            # Fallback if logger is not available
          end
          @options[:file_type] = :regular
          return configure_file_output
        end
        
        create_named_pipe if @options[:create_fifo]
      end

      def create_named_pipe
        case RbConfig::CONFIG['host_os']
        when /mswin|mingw|cygwin/
          create_windows_named_pipe
        else
          File.mkfifo(@options[:file_path], @options[:fifo_permissions] || 0644)
          begin
            logger.info { "[FileTransport] Created FIFO: #{@options[:file_path]}" }
          rescue
            # Fallback if logger is not available
          end
        end
      rescue NotImplementedError
        begin
          logger.error { "[FileTransport] Named pipes not supported on this platform" }
        rescue
          # Fallback if logger is not available
        end
        raise
      rescue => e
        begin
          logger.error { "[FileTransport] Failed to create FIFO: #{e.message}" }
        rescue
          # Fallback if logger is not available
        end
        raise
      end

      def create_windows_named_pipe
        require 'win32/pipe'
        pipe_name = "\\\\.\\pipe\\#{File.basename(@options[:file_path])}"
        @windows_pipe_server = Win32::Pipe::Server.new(pipe_name)
        begin
          logger.info { "[FileTransport] Created Windows named pipe: #{pipe_name}" }
        rescue
          # Fallback if logger is not available
        end
      rescue LoadError
        raise "Windows named pipes require win32-pipe gem: gem install win32-pipe"
      rescue => e
        begin
          logger.error { "[FileTransport] Failed to create Windows named pipe: #{e.message}" }
        rescue
          # Fallback if logger is not available
        end
        raise
      end

      def platform_supports_fifo?
        case RbConfig::CONFIG['host_os']
        when /mswin|mingw|cygwin/
          defined?(Win32::Pipe)
        else
          true
        end
      end

      def write_to_fifo(serialized_message)
        handle = open_fifo_for_writing
        unless handle
          handle_fifo_write_failure(serialized_message)
          return false
        end
        
        content = prepare_file_content(serialized_message)
        handle.write(content)
        handle.flush
        true
      rescue Errno::EPIPE
        begin
          logger.warn { "[FileTransport] FIFO reader disconnected" }
        rescue
          # Fallback if logger is not available
        end
        handle_fifo_write_failure(serialized_message)
        false
      rescue => e
        begin
          logger.error { "[FileTransport] FIFO write error: #{e.message}" }
        rescue
          # Fallback if logger is not available
        end
        handle_fifo_write_failure(serialized_message)
        false
      ensure
        handle&.close
      end

      def open_fifo_for_writing
        mode = @options[:fifo_mode] == :non_blocking ? File::WRONLY | File::NONBLOCK : 'w'
        File.open(@options[:file_path], mode)
      rescue Errno::ENXIO, Errno::ENOENT
        nil
      end

      def handle_fifo_write_failure(serialized_message)
        if @options[:fallback_transport]
          begin
            @options[:fallback_transport].do_publish(@current_message_class, serialized_message)
            begin
              logger.info { "[FileTransport] Message sent to fallback transport" }
            rescue
              # Fallback if logger is not available
            end
          rescue => e
            begin
              logger.error { "[FileTransport] Fallback transport failed: #{e.message}" }
            rescue
              # Fallback if logger is not available
            end
          end
        end
      end

      def start_fifo_reader(message_class, process_method, filter_options)
        case @options[:subscription_mode]
        when :fifo_blocking
          start_blocking_fifo_reader(message_class, process_method)
        when :fifo_select
          start_select_fifo_reader(message_class, process_method)
        when :fifo_polling
          start_polling_fifo_reader(message_class, process_method)
        else
          begin
            logger.warn { "[FileTransport] Invalid FIFO subscription mode: #{@options[:subscription_mode]}" }
          rescue
            # Fallback if logger is not available
          end
        end
      end

      def start_blocking_fifo_reader(message_class, process_method)
        @fifo_reader_thread = Thread.new do
          Thread.current.name = "FileTransport-FifoReader"
          loop do
            begin
              File.open(@options[:file_path], 'r') do |fifo|
                while line = fifo.gets
                  next if line.strip.empty?
                  receive(message_class, line.strip)
                end
              end
            rescue => e
              begin
                logger.error { "[FileTransport] FIFO reader error: #{e.message}" }
              rescue
                # Fallback if logger is not available
              end
              sleep 1
            end
          end
        end
      end

      def start_select_fifo_reader(message_class, process_method)
        @fifo_select_thread = Thread.new do
          Thread.current.name = "FileTransport-FifoSelect"
          fifo = File.open(@options[:file_path], File::RDONLY | File::NONBLOCK)
          
          loop do
            ready = IO.select([fifo], nil, nil, 1.0)
            if ready
              begin
                while line = fifo.gets
                  next if line.strip.empty?
                  receive(message_class, line.strip)
                end
              rescue IO::WaitReadable
                next
              rescue => e
                begin
                  logger.error { "[FileTransport] FIFO select error: #{e.message}" }
                rescue
                  # Fallback if logger is not available
                end
              end
            end
          end
        rescue => e
          begin
            logger.error { "[FileTransport] FIFO select thread error: #{e.message}" }
          rescue
            # Fallback if logger is not available
          end
        ensure
          fifo&.close
        end
      end

      def start_polling_fifo_reader(message_class, process_method)
        @fifo_reader_thread = Thread.new do
          Thread.current.name = "FileTransport-FifoPoller"
          loop do
            begin
              File.open(@options[:file_path], File::RDONLY | File::NONBLOCK) do |fifo|
                while line = fifo.gets
                  next if line.strip.empty?
                  receive(message_class, line.strip)
                end
              end
            rescue Errno::EAGAIN
              sleep(@options[:poll_interval] || 1.0)
            rescue => e
              begin
                logger.error { "[FileTransport] FIFO polling error: #{e.message}" }
              rescue
                # Fallback if logger is not available
              end
              sleep 1
            end
          end
        end
      end

      def stop_fifo_operations
        @fifo_reader_thread&.kill
        @fifo_reader_thread&.join(2)
        @fifo_select_thread&.kill
        @fifo_select_thread&.join(2)
        @fifo_handle&.close
      end

      def fifo_active?
        @fifo_reader_thread&.alive? || @fifo_select_thread&.alive?
      end
    end
  end
end