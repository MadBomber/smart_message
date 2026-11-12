# examples/performance_metrics/messages/benchmark_message.rb
# frozen_string_literal: true

require_relative '../../../lib/smart_message'

# One unit of benchmark work.  The message itself says how much CPU and
# how much (simulated) I/O its handler should spend.
class BenchmarkMessage < SmartMessage::Base
  description 'A unit of work for the performance benchmark'

  from 'benchmark-service'

  property :scenario_id,        required: true, description: 'The scenario this message belongs to'
  property :message_id,         required: true, description: 'Scenario name and sequence number'
  property :computation_cycles, default: 0, description: 'Iterations of floating point work for the handler'
  property :sleep_duration,     default: 0, description: 'Seconds the handler sleeps, standing in for I/O'
end
