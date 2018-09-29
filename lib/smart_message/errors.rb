# smart_message/lib/smart_message/errors.rb

module SmartMessage
  module Errors
    # A message can't be very smart if it does not know how to
    # send and receive itself using a message broker
    class NoBrokerConfigured < RuntimeError; end
  end
end
