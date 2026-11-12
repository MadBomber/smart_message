# examples/city_scenario/common/logger.rb
# frozen_string_literal: true

require_relative 'city'

module Common
  # Gives a program a logger that writes to $CITY_LOG_DIR/<name>.log.
  # SmartMessage's own log lines go to the same file.
  module Logger
    # @param name [String, nil] log file name; defaults to the program's file name
    # @return [SmartMessage::Logger::Base]
    def setup_logger(name: nil)
      @logger = Common::City.setup!(name || File.basename($PROGRAM_NAME, '.rb'))
    end

    def logger
      @logger ||= setup_logger
    end
  end
end
