# smart_message/.irbrc

require_relative './lib/smart_message'

class TheMessage < SmartMessage::Base
  version 3
  description "my simple message"

  header do
    from 'dewayne'
    to 'madbomber'
  end

  property :data, required: true
end
