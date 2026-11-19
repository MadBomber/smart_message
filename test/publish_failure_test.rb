# test/publish_failure_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

# A failed publish is never reported as a success (review findings R1, R7).
class PublishFailureTest < Minitest::Test
  class Notice < SmartMessage::Base
    from 'notice-service'
    property :text
  end

  # A transport that cannot deliver anything
  class BrokenTransport < SmartMessage::Transport::Base
    def do_publish(_message_class, _serialized_message)
      raise IOError, 'wire is cut'
    end
  end

  # A serializer that cannot encode anything
  class BrokenSerializer < SmartMessage::Serializer::Base
    private

    def do_encode(_hash) = raise(TypeError, 'cannot encode')
    def do_decode(_payload) = {}
  end

  def teardown
    Notice.reset_transport
  end

  def test_single_failing_transport_raises_and_dead_letters
    Notice.transport(BrokenTransport.new)
    message = Notice.new(text: 'hello')

    error = assert_raises(SmartMessage::Errors::PublishError) { message.publish }

    assert_match(/BrokenTransport: wire is cut/, error.message)
    assert error.result.failure?
    assert_instance_of IOError, error.result.errors.first

    assert_equal 1, dlq.size, 'the unpublished message is in the dead letter queue'
    entry = dlq.peek
    assert_equal message.uuid, entry[:header][:uuid]
    assert_match(/IOError: wire is cut/, entry[:error])
    assert_equal 'PublishFailureTest::BrokenTransport', entry[:transport]
  end

  def test_failed_publish_is_not_counted_as_published
    Notice.transport(BrokenTransport.new)
    SS.reset('PublishFailureTest::Notice', 'publish')

    assert_raises(SmartMessage::Errors::PublishError) { Notice.new(text: 'hello').publish }

    assert_equal 0, SS.get('PublishFailureTest::Notice', 'publish')
  end

  def test_one_failing_transport_among_several_is_reported_in_the_result
    good = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
    bad  = BrokenTransport.new
    Notice.transport([good, bad])

    result = Notice.new(text: 'hello').publish

    refute result.success?, 'not every transport accepted the message'
    assert result.partial?
    assert_equal [good], result.successful.map(&:transport)
    assert_equal [bad],  result.failed.map(&:transport)
    assert_equal 'wire is cut', result.failed.first.error.message
    assert_equal 1, good.message_count
    assert_equal 1, dlq.size
    assert_equal 'PublishFailureTest::BrokenTransport', dlq.peek[:transport]
  end

  def test_successful_publish_returns_a_result_and_leaves_the_dlq_empty
    transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
    Notice.transport(transport)
    message = Notice.new(text: 'hello')

    result = message.publish

    assert_instance_of SmartMessage::PublishResult, result
    assert result.success?
    refute result.partial?
    assert_equal message.uuid, result.uuid
    assert_equal 'PublishFailureTest::Notice', result.message_class
    assert_equal [{ transport: 'MemoryTransport', success: true, error: nil }], result.to_h[:outcomes]
    assert dlq.empty?
  end

  def test_transport_publish_raises_directly
    transport = BrokenTransport.new

    assert_raises(IOError) { transport.publish(Notice.new(text: 'hello')) }
  end

  def test_repeated_failures_open_the_transport_circuit
    transport = BrokenTransport.new(circuit_breaker: { transport_publish: { threshold: { failures: 2, within: 60 } } })
    message   = Notice.new(text: 'hello')

    2.times { assert_raises(IOError) { transport.publish(message) } }

    assert_raises(BreakerMachines::CircuitOpenError) { transport.publish(message) }
    assert transport.transport_circuit_stats[:transport_publish][:open]

    transport.reset_transport_circuits!
    assert transport.transport_circuit_stats[:transport_publish][:closed]
  end

  def test_one_transports_failures_do_not_open_another_transports_circuit
    failing = BrokenTransport.new(circuit_breaker: { transport_publish: { threshold: { failures: 1, within: 60 } } })
    healthy = SmartMessage::Transport::MemoryTransport.new(auto_process: false)

    assert_raises(IOError) { failing.publish(Notice.new(text: 'x')) }

    assert failing.transport_circuit_stats[:transport_publish][:open]
    assert healthy.transport_circuit_stats[:transport_publish][:closed]
    assert healthy.publish(Notice.new(text: 'x'))
  end

  def test_failing_serializer_raises_and_never_returns_a_payload
    serializer = BrokenSerializer.new

    error = assert_raises(SmartMessage::Errors::SerializationError) { serializer.encode({ a: 1 }) }
    assert_match(/TypeError - cannot encode/, error.message)

    transport = SmartMessage::Transport::MemoryTransport.new(serializer: serializer, auto_process: false)
    Notice.transport(transport)

    assert_raises(SmartMessage::Errors::PublishError) { Notice.new(text: 'hello').publish }
    assert_equal 0, transport.message_count, 'nothing was handed to the transport'
    assert_equal 1, dlq.size
  end

  def test_a_dlq_that_cannot_be_written_is_logged_and_the_publish_error_still_raises
    log = StringIO.new
    SmartMessage.configure do |config|
      config.logger   = SmartMessage::Logger::Default.new(log_file: log, level: :error)
      config.dlq_path = File.join(temp_path('missing_dir'), 'dlq.jsonl')
    end
    FileUtils.rm_rf(File.dirname(SmartMessage.configuration.dlq_path))
    SmartMessage::DeadLetterQueue.default # creates the directory...
    FileUtils.rm_rf(File.dirname(SmartMessage.configuration.dlq_path)) # ...which then disappears
    Notice.transport(BrokenTransport.new)

    assert_raises(SmartMessage::Errors::PublishError) { Notice.new(text: 'hello').publish }

    assert_match(/Failed to store unpublished message in DLQ/, log.string)
  end
end
