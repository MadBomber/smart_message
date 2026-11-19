# frozen_string_literal: true

# One measurement from one host.
class SystemMetric < SmartMessage::Base
  description 'A system metric sample'
  from 'metrics-agent'

  property :metric_name, required: true
  property :value,       required: true
  property :unit,        required: true
  property :host,        required: true
end
