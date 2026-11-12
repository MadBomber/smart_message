#!/usr/bin/env ruby
# examples/file/03_file_watching_demo.rb
# frozen_string_literal: true
#
# Watching a file: the tailing poller
#
# Subscribing on a FileTransport starts one background thread that tails
# the file and delivers every new line to the handlers of the message class
# named in that line.  Writers append, readers tail, so several transports
# (or several processes) can share one file.
#
#   poll_interval:  seconds between checks for new lines (default 0.5)
#   read_from_end:  true  - only lines written after subscribing (default)
#                   false - read the whole file first, then tail

require_relative '../support/example_helper'
require_relative 'messages/log_entry'

LOG_PATH = Example.tmp_path('shared.jsonl')

def file_transport(**options)
  SmartMessage::Transport::FileTransport.new(file_path: LOG_PATH, poll_interval: 0.05, **options)
end

# Append entries numbered +range+ through the writer's transport.
def write_entries(writer, range)
  range.each do |sequence|
    entry = LogEntry.new(sequence: sequence, text: "entry #{sequence}")
    entry.transport(writer)
    entry.publish
  end
end

# Two readers, standing in for two other processes.  In a real reader
# process this is simply: LogEntry.transport(file_transport); LogEntry.subscribe
module LiveReader
  def self.receive(entry) = Example.inbox.add(:live, entry.sequence)
end

module ReplayReader
  def self.receive(entry) = Example.inbox.add(:replay, entry.sequence)
end

def received?(name, sequences) = Example.wait_until { Example.inbox[name].sort == sequences }

Example.title 'File watching (tailing poller)'
writer = file_transport
write_entries(writer, 1..3) # history, written before anyone listens

Example.section 'read_from_end: true (default) sees only new lines'
live = file_transport
live.subscribe('LogEntry', 'LiveReader.receive')

Example.section 'read_from_end: false replays the file, then tails it'
replay = file_transport(read_from_end: false)
replay.subscribe('LogEntry', 'ReplayReader.receive')

write_entries(writer, 4..6)
Example.check('the replaying reader received the history and the new lines') { received?(:replay, [1, 2, 3, 4, 5, 6]) }
Example.check('the live reader received the new lines only') { received?(:live, [4, 5, 6]) }
puts <<~SEEN
  live:   #{Example.inbox[:live].sort}
  replay: #{Example.inbox[:replay].sort}
SEEN

Example.section 'A transport can read its own writes'
LogEntry.transport(writer)
LogEntry.subscribe { |entry| Example.inbox.add(:self, entry.sequence) }
LogEntry.new(sequence: 7, text: 'entry 7').publish
Example.check('the writer received its own entry through the file') { received?(:self, [7]) }
Example.check('so did both readers') { received?(:live, [4, 5, 6, 7]) && received?(:replay, (1..7).to_a) }

Example.section 'A truncated file is read again from the start'
File.truncate(LOG_PATH, 0)
write_entries(writer, 8..8)
Example.check('all three readers received the entry written after truncation') do
  received?(:self, [7, 8]) && received?(:live, [4, 5, 6, 7, 8]) && received?(:replay, (1..8).to_a)
end

Example.section 'Unsubscribing the last handler stops the poller'
live.unsubscribe!('LogEntry')
replay.disconnect
write_entries(writer, 9..9)
Example.check('the writer still receives') { received?(:self, [7, 8, 9]) }
Example.check('the stopped readers received nothing more') do
  Example.inbox.count(:live) == 5 && Example.inbox.count(:replay) == 8
end

Example.section 'A line that is not a message goes to the dead letter queue'
File.write(LOG_PATH, "this is not JSON\n", mode: 'a')
dlq = SmartMessage::DeadLetterQueue.default
Example.check('the unreadable line was stored with its error') do
  Example.wait_until { dlq.size == 1 } && dlq.peek[:payload] == 'this is not JSON' && dlq.peek[:error].include?('DecodeError')
end
write_entries(writer, 10..10)
Example.check('the poller carries on with the next line') { received?(:self, [7, 8, 9, 10]) }

Example.finish
