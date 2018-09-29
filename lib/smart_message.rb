# lib/smart_message.rb
# frozen_string_literal: true

require 'date'
require 'json'

require 'awesome_print'
require 'debug_me'
include DebugMe

require 'hashie'

require_relative './smart_message/version'
require_relative './smart_message/errors'

require_relative './smart_message/base'
require_relative './smart_message/broker'

# SmartMessage abstracts messages from the backend broker process
module SmartMessage
end # module SmartMessage
