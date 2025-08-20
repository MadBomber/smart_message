# smart_message/.irbrc

require_relative './lib/smart_message'

SmartMessage.configure do |config|
  config.logger = STDOUT
  config.log_level = :info
  config.log_format = :text
  config.log_colorize = true
end

LOG = SmartMessage.configuration.default_logger

class TheMessage < SmartMessage::Base
  version 3
  description "my simple message"

  header do
    from 'dewayne'
    to 'madbomber'
  end

  property :data, required: true
end
