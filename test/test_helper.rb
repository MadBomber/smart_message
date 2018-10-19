$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require 'smart_message'

require 'minitest/autorun'
require 'minitest/power_assert'
require 'shoulda'

require 'ap'
require 'debug_me'
include DebugMe
