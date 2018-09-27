# lib/smart_message.rb
# frozen_string_literal: true

require 'awesome_print'
require 'debug_me'
include DebugMe

require 'hashie'

require_relative './smart_message/version'

require_relative './smart_message/base'
require_relative './smart_message/plugin'

# SmartMessage abstracts messages from the backend broker process
module SmartMessage
end # module SmartMessage
