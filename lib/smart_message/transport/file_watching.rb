# lib/smart_message/transport/file_watching.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # Module for file watching and subscription support (reading/tailing).
    module FileWatching
      
      private
      
      def logger
        # Ensure we have a proper logger, not just an IO object
        if @logger && @logger.respond_to?(:error) && @logger.respond_to?(:info) && @logger.respond_to?(:warn)
          return @logger
        end
        @logger = SmartMessage::Logger.default
      end
      
      public
      def start_file_polling(message_class, process_method, filter_options)
        poll_interval = filter_options[:poll_interval] || @options[:poll_interval] || 1.0
        file_path = subscription_file_path(message_class, filter_options)
        
        @polling_thread = Thread.new do
          Thread.current.name = "FileTransport-Poller"
          last_position = @options[:read_from_end] ? (File.exist?(file_path) ? File.size(file_path) : 0) : 0
          
          loop do
            sleep poll_interval
            next unless File.exist?(file_path)
            
            current_size = File.size(file_path)
            if current_size > last_position
              process_new_file_content(file_path, last_position, current_size, message_class)
              last_position = current_size
            end
          end
        rescue => e
          logger.error { "[FileTransport] Polling thread error: #{e.message}" }
        end
      end

      def process_new_file_content(file_path, start_pos, end_pos, message_class)
        File.open(file_path, 'r', encoding: @options[:encoding]) do |file|
          file.seek(start_pos)
          content = file.read(end_pos - start_pos)
          
          content.each_line do |line|
            next if line.strip.empty?
            
            begin
              receive(message_class, line.strip)
            rescue => e
              begin
                logger.error { "[FileTransport] Error processing message: #{e.message}" }
              rescue
                # Fallback if logger is not available
              end
            end
          end
        end
      end

      def subscription_file_path(message_class, filter_options)
        filter_options[:file_path] || 
          @options[:subscription_file_path] ||
          File.join(File.dirname(@options[:file_path]), "#{message_class.to_s.downcase}.jsonl")
      end
    end
  end
end