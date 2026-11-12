# examples/city_scenario/common/city.rb
# frozen_string_literal: true
#
# Process-wide setup shared by every program of the city scenario: one
# Redis transport for all message classes, a log file, and a dead letter
# queue, none of them inside the repository.
#
# Environment:
#   CITY_REDIS_URL   Redis server (default: $SMART_MESSAGE_TEST_REDIS_URL,
#                    else redis://localhost:6379)
#   CITY_NAMESPACE   Redis channel prefix (default: city_scenario).  Every
#                    program of one city must use the same namespace.
#   CITY_LOG_DIR     directory for log files and dead letters
#                    (default: <tmpdir>/smart_message_city_scenario)

require 'fileutils'
require 'tmpdir'

require_relative '../../../lib/smart_message'

module Common
  module City
    DEFAULT_REDIS_URL = 'redis://localhost:6379'
    DEFAULT_NAMESPACE = 'city_scenario'

    module_function

    # @return [String]
    def redis_url(env = ENV)
      env['CITY_REDIS_URL'] || env['SMART_MESSAGE_TEST_REDIS_URL'] || DEFAULT_REDIS_URL
    end

    # @return [String] the Redis channel prefix shared by the city's programs
    def namespace(env = ENV)
      env.fetch('CITY_NAMESPACE', DEFAULT_NAMESPACE)
    end

    # @return [String] an absolute path outside the repository
    def log_dir(env = ENV)
      File.expand_path(env.fetch('CITY_LOG_DIR') { File.join(Dir.tmpdir, 'smart_message_city_scenario') })
    end

    # @return [String] the log file for one program
    def log_file(program_name, env = ENV)
      File.join(log_dir(env), "#{program_name}.log")
    end

    # The Redis channel a message class travels on.
    # @return [String]
    def channel_for(message_class, env = ENV)
      "#{namespace(env)}:#{message_class}"
    end

    # Configure SmartMessage for this process.  Safe to call more than once.
    #
    # @param program_name [String] names the log file
    # @return [SmartMessage::Logger::Base] the logger SmartMessage and the program share
    def setup!(program_name)
      FileUtils.mkdir_p(log_dir)

      SmartMessage.configure do |config|
        config.logger    = SmartMessage::Logger::Default.new(log_file: log_file(program_name), level: :info)
        config.dlq_path  = File.join(log_dir, 'dead_letters.jsonl')
        config.transport ||= SmartMessage::Transport::RedisTransport.new(url: redis_url, namespace: namespace)
      end

      abort "No Redis server answered at #{redis_url}." unless SmartMessage.configuration.transport.connected?

      SmartMessage::Logger.default
    end

    # Disconnect the shared transport and stop the dispatchers.
    def teardown!
      SmartMessage.configuration.transport&.disconnect
      SmartMessage.shutdown
    end
  end
end
