# examples/support/failing_transport.rb
# frozen_string_literal: true

# A transport whose backend is always down.  A transport reports a failed
# delivery by raising from #do_publish.
class FailingTransport < SmartMessage::Transport::Base
  def do_publish(_message_class, _serialized_message)
    raise SmartMessage::Errors::TransportError, 'simulated outage'
  end
end
