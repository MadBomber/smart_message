# frozen_string_literal: true

# A message in a fleet whose entity ids follow naming conventions such as
# "payment-gateway", "prod-orders" or "system-monitor".
class MicroserviceMessage < SmartMessage::Base
  description 'A message between microservices with pattern-friendly ids'

  property :action, required: true
  property :detail
end
