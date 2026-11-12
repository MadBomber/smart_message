# test/file_transport_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'helpers/transport_contract'

# The append-only file transport (review findings T1, T3, T4).
class FileTransportTest < Minitest::Test
  include TransportContract

  FT = SmartMessage::Transport::FileTransport

  def path
    @path ||= temp_path('messages.jsonl')
  end

  def new_transport(**options)
    FT.new(file_path: path, poll_interval: 0.01, **options)
  end

  def lines(file = path)
    File.readlines(file, chomp: true)
  end

  # ---- options -------------------------------------------------------------

  def test_file_path_is_required
    error = assert_raises(ArgumentError) { FT.new }

    assert_match(/file_path/, error.message)
  end

  def test_removed_options_have_no_effect_on_the_defaults
    assert_equal %i[file_path create_directories encoding poll_interval read_from_end], FT.new(file_path: path).default_options.keys
  end

  def test_path_is_absolute
    assert_equal File.expand_path('relative/messages.jsonl'), track(FT.new(file_path: 'relative/messages.jsonl')).path
    refute File.exist?('relative'), 'nothing is created until something is published'
  end

  # ---- publishing ----------------------------------------------------------

  def test_appends_one_line_per_message
    transport.publish(ContractMessage.new(value: 1))
    transport.publish(ContractMessage.new(value: 2))

    assert_equal [1, 2], lines.map { |line| JSON.parse(line)['value'] }
  end

  def test_appends_to_an_existing_file
    File.write(path, "existing line\n")

    transport.publish(ContractMessage.new(value: 1))

    assert_equal 2, lines.size
    assert_equal 'existing line', lines.first
  end

  def test_creates_missing_directories
    nested = File.join(temp_path('dir'), 'a', 'b', 'messages.jsonl')

    track(FT.new(file_path: nested)).publish(ContractMessage.new(value: 1))

    assert_equal 1, lines(nested).size
  end

  def test_without_create_directories_a_missing_directory_is_an_error
    nested  = File.join(temp_path('dir'), 'missing', 'messages.jsonl')
    careful = use(track(FT.new(file_path: nested, create_directories: false)))

    error = assert_raises(SmartMessage::Errors::PublishError) { ContractMessage.new(value: 1).publish }

    assert_instance_of Errno::ENOENT, error.result.errors.first
    assert_equal 1, dlq.size
    refute File.exist?(nested)
    assert careful.connected?
  end

  def test_concurrent_publishers_write_whole_lines
    Array.new(8) { |t| Thread.new { 25.times { |i| transport.publish(ContractMessage.new(value: "#{t}-#{i}", detail: 'x' * 300)) } } }.each(&:join)

    assert_equal 200, lines.size
    assert_equal 200, lines.map { |line| JSON.parse(line)['value'] }.uniq.size
  end

  def test_publishing_to_an_io
    io        = StringIO.new
    to_io     = track(FT.new(file_path: io))

    to_io.publish(ContractMessage.new(value: 1))
    to_io.disconnect

    assert_equal 1, io.string.lines.size
    refute io.closed?, 'an IO the transport was handed is never closed'
    assert_nil to_io.path
  end

  def test_an_io_target_cannot_be_subscribed
    use(track(FT.new(file_path: StringIO.new)))

    error = assert_raises(SmartMessage::Errors::TransportError) { collect }

    assert_match(/cannot subscribe/, error.message)
  end

  # ---- lifecycle -----------------------------------------------------------

  def test_publish_after_disconnect_raises_and_connect_reopens
    transport.publish(ContractMessage.new(value: 1))
    transport.disconnect

    refute transport.connected?
    assert_raises(SmartMessage::Errors::TransportError) { transport.publish(ContractMessage.new(value: 2)) }

    transport.connect

    assert transport.connected?
    transport.publish(ContractMessage.new(value: 3))
    assert_equal [1, 3], lines.map { |line| JSON.parse(line)['value'] }
  end

  def test_the_poller_runs_only_while_there_are_subscribers
    use
    poller = -> { Thread.list.count { |thread| thread.name == 'SmartMessage-FilePoller' && thread.alive? } }
    before = poller.call

    collect
    collect(OtherMessage)
    assert_equal before + 1, poller.call, 'one poller for every subscription'

    ContractMessage.unsubscribe!
    assert_equal before + 1, poller.call
    OtherMessage.unsubscribe!
    assert_equal before, poller.call
  end

  def test_connect_restarts_the_poller_for_existing_subscriptions
    use
    received = collect
    transport.disconnect

    transport.connect
    ContractMessage.new(value: 'after reconnect').publish

    wait_until { !received.empty? }
    assert_equal 'after reconnect', received.pop.value
  end

  # ---- reading -------------------------------------------------------------

  def test_a_new_subscription_sees_only_new_lines_by_default
    transport.publish(ContractMessage.new(value: 'old'))
    use
    received = collect

    ContractMessage.new(value: 'new').publish

    wait_until { !received.empty? }
    sleep 0.05
    assert_equal ['new'], Array.new(received.size) { received.pop.value }
  end

  def test_read_from_end_false_replays_the_file
    transport.publish(ContractMessage.new(value: 'old'))
    replaying = use(track(new_transport(read_from_end: false)))
    received  = collect

    wait_until { !received.empty? }

    assert_equal 'old', received.pop.value
    assert_same replaying, ContractMessage.transport
  end

  def test_two_transports_share_one_file
    reader = track(new_transport)
    writer = track(new_transport)
    ContractMessage.transport(reader)
    received = collect

    writer.publish(ContractMessage.new(value: 'from the writer'))

    wait_until { !received.empty? }
    assert_equal 'from the writer', received.pop.value
  end

  def test_a_corrupt_line_is_dead_lettered_and_reading_continues
    use
    received = collect

    File.open(path, 'a') { |file| file.puts('this is not a message') }
    ContractMessage.new(value: 'after the bad line').publish

    wait_until { !received.empty? }
    assert_equal 'after the bad line', received.pop.value
    wait_until { dlq.size == 1 }
    assert_equal 'this is not a message', dlq.peek[:payload]
  end

  def test_a_line_for_a_class_this_process_has_not_loaded_is_skipped
    use
    received = collect
    foreign  = transport.encode_message(ContractMessage.new(value: 1)).sub('TransportContract::ContractMessage', 'Another::Programs::Message')

    File.open(path, 'a') { |file| file.puts(foreign) }
    ContractMessage.new(value: 'ours').publish

    wait_until { !received.empty? }
    assert_equal 'ours', received.pop.value
    assert dlq.empty?, 'the other program will handle its own message'
  end

  def test_a_truncated_file_is_read_from_the_start
    use
    received = collect
    ContractMessage.new(value: 'before', detail: 'x' * 200).publish
    wait_until { received.size == 1 }

    line = transport.encode_message(ContractMessage.new(value: 'after truncation'))
    File.write(path, "#{line}\n") # shorter than what was already read

    wait_until { received.size == 2 }
    assert_equal ['before', 'after truncation'], [received.pop.value, received.pop.value]
  end

  def test_read_complete_lines_holds_back_a_partial_line
    File.write(path, "one\ntwo\npart")

    found, position = FT.read_complete_lines(path, 0)
    assert_equal %w[one two], found
    assert_equal 8, position

    assert_equal [[], 8], FT.read_complete_lines(path, position), 'the partial line is not delivered'

    File.open(path, 'a') { |file| file.write("ial\n\n  \nthree\n") }
    found, position = FT.read_complete_lines(path, position)
    assert_equal %w[partial three], found, 'blank lines are skipped'
    assert_equal File.size(path), position
  end

  def test_read_complete_lines_edge_cases
    assert_equal [[], 0], FT.read_complete_lines(temp_path('missing'), 10)

    File.write(path, "short\n")
    assert_equal [['short'], 6], FT.read_complete_lines(path, 500), 'a position past the end means the file was replaced'

    File.write(path, "café\n")
    found, = FT.read_complete_lines(path, 0, encoding: 'UTF-8')
    assert_equal ["café"], found
    assert_equal Encoding::UTF_8, found.first.encoding
  end
end
