# frozen_string_literal: true

# NOT a usable message class: loading this file raises
# SmartMessage::Errors::ReservedPropertyName, because 'to' is addressing
# (it lives in the header) and cannot be declared as a property.
# 09_error_handling_demo.rb loads it to show the error.
class ReservedPropertyMessage < SmartMessage::Base
  property :subject
  property :to
end
