$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require 'smart_message'

require 'minitest/autorun'

class MyMessage < SmartMessage::Base
  property :foo
  property :bar
  property :baz
end # class MyMessage < SmartMessage::Base
