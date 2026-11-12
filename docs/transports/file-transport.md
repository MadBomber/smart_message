# File Transport

`SmartMessage::Transport::FileTransport` appends each published message to a file, one serialized message per line. With the default serializer the file is JSON Lines.

## Delivery semantics

- **Append-only.** Publishing appends one line and flushes it. The transport never rewrites, trims or rotates the file.
- **Readers tail.** Subscribing starts one background poller that reads new complete lines every `poll_interval` seconds and delivers each to the handlers of the message class named in that line's header.
- **Several processes can share one file.** Writers append, readers tail. Every reader sees every line; there is no competition between readers and no acknowledgement.
- **New subscribers start at the end.** By default a subscription sees only lines written after it started. With `read_from_end: false` it reads the whole file first.
- **The read position is in memory.** A reader that restarts begins again at the end of the file (or at the beginning with `read_from_end: false`); it does not resume where it stopped.
- **Truncation is detected.** When the file becomes shorter than what a reader has consumed (it was truncated or replaced), the reader starts again from the beginning.
- A line being written when the poller looks (no newline yet) is left for the next poll.

One file can carry several message classes. A line whose class is loaded in the reading process but has no subscribers there is skipped. So is a line that names a message class the reading process has not loaded: it belongs to another reader. A line that cannot be decoded at all is logged and stored in the reading process's [dead letter queue](../reference/dead-letter-queue.md).

## Options

```ruby
SmartMessage::Transport::FileTransport.new(
  file_path:          'log/messages.jsonl',   # required
  create_directories: true,
  encoding:           nil,
  poll_interval:      0.5,
  read_from_end:      true
)

SmartMessage::Transport.create(:file, file_path: 'log/messages.jsonl')
```

| Option | Default | Meaning |
|--------|---------|---------|
| `file_path` | none, **required** | The file, as a String or Pathname; or an IO to write to. Omitting it raises `ArgumentError`. |
| `create_directories` | `true` | Create the file's directory when the file is first written |
| `encoding` | `nil` | File encoding; `nil` means Ruby's default |
| `poll_interval` | `0.5` | Seconds between checks for new lines |
| `read_from_end` | `true` | A new subscription sees only lines written after it started; `false` reads the whole file first |

When `file_path` is an IO, the transport can publish to it but not subscribe from it (`subscribe` raises `SmartMessage::Errors::TransportError`), and it never closes it.

`transport.path` returns the absolute path, or `nil` for an IO.

## Connection state

```ruby
transport.connected?   # => true until disconnect
transport.disconnect   # stops the poller and closes the file the transport opened
transport.connect      # reopens; restarts the poller if there are subscriptions
```

Publishing after `disconnect` raises `SmartMessage::Errors::TransportError`. `disconnect` is safe to call more than once.

Unsubscribing the last handler stops the poller.

## A complete program

One transport writes; a second transport, as another process would, tails the same file.

```ruby
require 'smart_message'
require 'tmpdir'

path = File.join(Dir.mktmpdir, 'events.jsonl')

# messages/event_message.rb
class EventMessage < SmartMessage::Base
  from 'event-source'
  property :name, required: true

  def self.process(message)
    puts "read from file: #{message.name}"
  end
end

writer = SmartMessage::Transport::FileTransport.new(file_path: path)
reader = SmartMessage::Transport::FileTransport.new(file_path: path, poll_interval: 0.1)

# Subscribe on the reader only
EventMessage.transport(reader)
EventMessage.subscribe

# Publish on the writer only
EventMessage.transport(writer)
EventMessage.new(name: 'started').publish
EventMessage.new(name: 'finished').publish

sleep 0.5                 # give the poller time to see the new lines
reader.disconnect
writer.disconnect
SmartMessage.shutdown

puts "lines in file: #{File.readlines(path).size}"
```

## As an audit trail

Because the file is plain JSON Lines, it is easy to inspect:

```bash
tail -f log/messages.jsonl | jq '._sm_header.message_class'
```

To record everything published on another transport, give the message class both:

```ruby
class OrderMessage < SmartMessage::Base
  transport [
    SmartMessage::Transport.create(:redis, namespace: 'production'),
    SmartMessage::Transport.create(:file, file_path: 'log/orders.jsonl')
  ]
end
```

Note that `OrderMessage.subscribe` then subscribes on both transports, so a process that both publishes and subscribes would handle each message twice, once from Redis and once from the file. Enable [deduplication](../reference/message-deduplication.md) with a shared dispatcher, or subscribe on one transport only, as the program above does.

## Replaying a file

Set `read_from_end: false` to process an existing file from the beginning:

```ruby
replay = SmartMessage::Transport::FileTransport.new(file_path: 'log/orders.jsonl', read_from_end: false)
OrderMessage.transport(replay)
OrderMessage.subscribe
```

## What it does not do

There is no file rotation, no partitioning by message class, no asynchronous write queue and no named-pipe mode. Rotate the file with an external tool if it must not grow without bound; readers start over from the beginning of the new file when it is shorter than what they had read.
