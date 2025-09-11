# lib/smart_message/transport/partitioned_files.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # Module for fan-out/partitioned file support.
    module PartitionedFiles
      def determine_file_path(payload, header)
        if @options[:filename_selector]&.respond_to?(:call)
          @options[:filename_selector].call(payload, header)
        elsif @options[:directory]
          File.join(@options[:directory], "#{header[:message_class_name].to_s.downcase}.log")
        else
          @options[:file_path]
        end
      end

      def get_or_open_partition_handle(full_path)
        @partition_handles ||= {}
        @partition_mutexes ||= {}
        
        unless @partition_handles[full_path]
          ensure_directory_exists_for(full_path)
          @partition_handles[full_path] = File.open(full_path, file_mode, encoding: @options[:encoding])
          @partition_mutexes[full_path] = Mutex.new
        end
        
        @partition_handles[full_path]
      end

      def ensure_directory_exists_for(path)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) if @options[:create_directories] && !Dir.exist?(dir)
      end

      def close_partition_handles
        @partition_handles&.each do |_, handle|
          handle.close
        end
        @partition_handles = {}
        @partition_mutexes = {}
      end
    end
  end
end