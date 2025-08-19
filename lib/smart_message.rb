# lib/smart_message.rb
# encoding: utf-8
# frozen_string_literal: true

# FIXME: handle this better
class MilClass  # IMO nil is the same as an empty String
  def to_s
    ''
  end
end


require 'active_support/core_ext/string/inflections'
require 'date'  # STDLIB

# Production logging should use the logger framework, not debug_me

require 'hashie'         # Your friendly neighborhood hash library.

require_relative './simple_stats'

require_relative './smart_message/version'
require_relative './smart_message/errors'
require_relative './smart_message/circuit_breaker'
require_relative './smart_message/dead_letter_queue'

require_relative './smart_message/dispatcher.rb'
require_relative './smart_message/transport.rb'
require_relative './smart_message/base.rb'

# SmartMessage abstracts messages from the backend transport process
module SmartMessage
  # The super class of all smart messages
  # class Base < Dash from the Hashie gem plus mixins
  # end

  # encapsulates the message transport plugin
  # module Transport is defined in transport.rb

  # encapsulates the message code/decode serializer
  module Serializer
    # the super class of the message serializer
    class Base
    end
  end

  # encapsulates the message logging capability
  module Logger
    # the super class of the message logger
    class Base
    end
  end
end # module SmartMessage

require_relative './smart_message/serializer'
require_relative './smart_message/logger'
