# frozen_string_literal: true

# A registration with required properties and validators.
class UserRegistrationMessage < SmartMessage::Base
  description 'A new user registration (schema version 1)'
  from 'registration-service'

  property :user_id,  required: true, message: 'user_id identifies the new user'
  property :email,    required: true, validate: /\A[^@\s]+@[^@\s]+\.[a-z]{2,}\z/i,
                      validation_message: 'email must look like name@example.com'
  property :age,      required: true, validate: 13..120,
                      validation_message: 'age must be between 13 and 120'
  property :username, required: true, validate: ->(value) { value.match?(/\A\w{3,20}\z/) },
                      validation_message: 'username must be 3-20 word characters'
  property :plan,     default: 'free', validate: %w[free premium enterprise],
                      validation_message: 'plan must be free, premium or enterprise'
end
