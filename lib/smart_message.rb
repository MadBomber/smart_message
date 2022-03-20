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

# FIXME: Move this debugging junk into a seperate file
require 'amazing_print'  # Pretty print Ruby objects with proper indentation and colors
require 'debug_me'       # A tool to print the labeled value of variables.
include DebugMe

DebugMeDefaultOptions = {
  tag: 'DEBUG:',    # A tag to prepend to each output line
  time:     true,   # Include a time-stamp in front of the tag
  strftime: '%Y-%m-%d %H:%M:%S.%6N', # timestamp format
  header:   true,   # Print a header string before printing the variables
  skip1:    true,   # skip 1 lines between different outputs
  skip2:    false,  # skip 2 lines between different outputs
  lvar:     false,  # Include local variables
  ivar:     false,  # Include instance variables in the output
  cvar:     false,  # Include class variables in the output
  cconst:   false,  # Include class constants
  levels:   0,      # Number of levels in the call trace
  file:     STDOUT  # The output file
}

require 'hashie'         # Your friendly neighborhood hash library.

require_relative './simple_stats'

require_relative './smart_message/version'
require_relative './smart_message/errors'

require_relative './smart_message/dispatcher.rb'
require_relative './smart_message/base.rb'

# SmartMessage abstracts messages from the backend broker process
module SmartMessage
  # The super class of all smart messages
  # class Base < Dash from the Hashie gem plus mixins
  # end

  # encapsulates the message broker plugin
  module Broker
    # The super class for the SmartMessage::Broker
    class Base
    end
  end

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

require_relative './smart_message/broker'
require_relative './smart_message/serializer'
require_relative './smart_message/logger'
