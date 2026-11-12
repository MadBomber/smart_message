# frozen_string_literal: true

# The smallest useful message: two properties.
class GreetingMessage < SmartMessage::Base
  description 'A greeting for one person'
  from 'stdout-demo'

  property :first_name, required: true
  property :last_name,  required: true
end
