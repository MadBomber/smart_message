$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

class Object
  def debug_me_context
    my_hash = Hash.new
    self.instance_variables.each do |attribute|
      my_hash.merge!({ attribute => self.instance_variable_get(attribute) })
    end
    return my_hash
  end
end

require 'smart_message'

require 'minitest/autorun'
require 'minitest/power_assert'
require 'shoulda'

require 'ap'
require 'debug_me'
include DebugMe

unless defined?(DebugMeDefaultOptions)
  DebugMeDefaultOptions = {
  tag: 'DEBUG:',   # A tag to prepend to each output line
  time: true,      # Include a time-stamp in front of the tag
  header: true,    # Print a header string before printing the variables
  lvar: true,      # Include local variables
  ivar: true,      # Include instance variables in the output
  cvar: true,      # Include class variables in the output
  cconst: true,    # Include class constants
  file: File.open('test.log', 'a')    # The output file
  }
end
