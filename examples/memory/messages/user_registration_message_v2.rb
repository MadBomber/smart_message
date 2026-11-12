# frozen_string_literal: true

require_relative 'user_registration_message'

# Version 2 of the registration schema adds a phone number.  A subclass
# inherits the parent's properties, validators and addressing.
class UserRegistrationMessageV2 < UserRegistrationMessage
  description 'A new user registration (schema version 2)'
  version 2

  property :phone_number, required: true, validate: /\A\+?\d{10,15}\z/,
                          validation_message: 'phone_number must be 10-15 digits'
end
