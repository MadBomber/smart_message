# lib/smart_message/transport/file_operations.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # Module for shared file operations, including buffering, rotation, and basic I/O.
    module FileOperations
      def configure_file_output
        ensure_directory_exists if @options[:create_directories]
        @file_handle = open_file_handle
        @write_buffer = []
        @last_flush = Time.now
        setup_rotation_timer if rotation_enabled?
        @file_mutex = Mutex.new  # For thread-safety
      end

      def write_to_file(serialized_message)
        content = prepare_file_content(serialized_message)
        
        @file_mutex.synchronize do
          if buffered_mode?
            buffer_write(content)
          else
            direct_write(content)
          end
          
          rotate_file_if_needed
        end
      end

      def flush_buffer
        return if @write_buffer.empty?
        
        # Only synchronize if we're not already holding the lock
        if @file_mutex.owned?
          @file_handle.write(@write_buffer.join)
          @file_handle.flush
          @write_buffer.clear
          @last_flush = Time.now
        else
          @file_mutex.synchronize do
            @file_handle.write(@write_buffer.join)
            @file_handle.flush
            @write_buffer.clear
            @last_flush = Time.now
          end
        end
      end

      def close_file_handle
        flush_buffer if buffered_mode?
        if @file_mutex
          @file_mutex.synchronize do
            @file_handle&.flush unless @file_handle&.closed?
            @file_handle&.close unless @file_handle&.closed?
            @file_handle = nil
          end
        else
          @file_handle&.flush unless @file_handle&.closed?
          @file_handle&.close unless @file_handle&.closed?
          @file_handle = nil
        end
      end

      private

      def prepare_file_content(serialized_message)
        case @options[:format] || @options[:file_format] || :jsonl
        when :json, :raw
          serialized_message
        when :jsonl, :lines
          "#{serialized_message}\n"
        when :pretty
          begin
            require 'amazing_print'
            # Use the serializer to decode back to the original data structure
            if @serializer.respond_to?(:decode)
              data = @serializer.decode(serialized_message)
              data.ai + "\n"
            else
              # Fallback: try to parse as JSON
              begin
                require 'json'
                data = JSON.parse(serialized_message)
                data.ai + "\n"
              rescue JSON::ParserError
                # If not JSON, pretty print the raw string
                serialized_message.ai + "\n"
              end
            end
          rescue LoadError
            # Fallback if amazing_print not available
            "#{serialized_message}\n"
          rescue => e
            # Handle any other errors (like circuit breaker issues)
            "#{serialized_message}\n"
          end
        else
          "#{serialized_message}\n"  # default to jsonl
        end
      end

      def open_file_handle
        # Return IO objects directly, don't try to open them
        return @options[:file_path] if @options[:file_path].respond_to?(:write)
        # Open file handle for string paths
        File.open(current_file_path, file_mode, encoding: @options[:encoding])
      end

      def ensure_directory_exists
        return unless @options[:create_directories]
        return if @options[:file_path].respond_to?(:write)  # Skip for IO objects
        
        dir = File.dirname(current_file_path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def current_file_path
        if rotation_enabled? && time_based_rotation?
          timestamped_file_path
        else
          @options[:file_path]
        end
      end

      def file_mode
        @options[:file_mode] || 'a'  # append by default
      end

      def buffered_mode?
        @options[:buffer_size] && @options[:buffer_size] > 0
      end

      def buffer_write(content)
        @write_buffer << content
        
        if buffer_full? || flush_interval_exceeded?
          flush_buffer
        end
      end

      def direct_write(content)
        return unless @file_handle
        @file_handle.write(content)
        @file_handle.flush if @options[:auto_flush]
      end

      def buffer_full?
        @write_buffer.join.bytesize >= @options[:buffer_size]
      end

      def flush_interval_exceeded?
        @options[:flush_interval] && 
          (Time.now - @last_flush) >= @options[:flush_interval]
      end

      def rotation_enabled?
        @options[:rotate_size] || @options[:rotate_time]
      end

      def time_based_rotation?
        @options[:rotate_time]
      end

      def should_rotate?
        size_rotation_needed? || time_rotation_needed?
      end

      def size_rotation_needed?
        @options[:rotate_size] && 
          File.exist?(current_file_path) && File.size(current_file_path) >= @options[:rotate_size]
      end

      def time_rotation_needed?
        return false unless @options[:rotate_time]
        
        case @options[:rotate_time]
        when :hourly
          Time.now.min == 0 && Time.now.sec == 0
        when :daily
          Time.now.hour == 0 && Time.now.min == 0 && Time.now.sec == 0
        else
          false
        end
      end

      def rotate_file_if_needed
        return unless should_rotate?
        
        close_current_file
        archive_current_file
        @file_handle = open_file_handle
      end

      def close_current_file
        flush_buffer if buffered_mode?
        @file_handle&.close
        @file_handle = nil
      end

      def archive_current_file
        return unless File.exist?(current_file_path)
        
        timestamp = Time.now.strftime(@options[:timestamp_format] || '%Y%m%d_%H%M%S')
        base = File.basename(@options[:file_path], '.*')
        ext = File.extname(@options[:file_path])
        dir = File.dirname(@options[:file_path])
        archive_path = File.join(dir, "#{base}_#{timestamp}#{ext}")
        
        FileUtils.mv(current_file_path, archive_path)
        
        # Maintain rotation count
        if @options[:rotate_count]
          files = Dir.glob(File.join(dir, "#{base}_*#{ext}")).sort
          while files.size > @options[:rotate_count]
            File.delete(files.shift)
          end
        end
      end

      def timestamped_file_path
        base = File.basename(@options[:file_path], '.*')
        ext = File.extname(@options[:file_path])
        dir = File.dirname(@options[:file_path])
        timestamp = Time.now.strftime(@options[:timestamp_format] || '%Y%m%d_%H%M%S')
        
        File.join(dir, "#{base}_#{timestamp}#{ext}")
      end
    end
  end
end