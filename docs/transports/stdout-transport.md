# Stdout Transport

`SmartMessage::Transport::StdoutTransport` writes each published message to an IO, one serialized message per line. It is useful while developing, for debugging, and for piping messages to another program.

## Delivery semantics

- **Write-only by default.** `publish` prints the message. You can call `subscribe`, but no handler is ever called, because nothing is read back.
- With `loopback: true`, each published message is also delivered to the subscribers of that same transport instance, in the same process.
- Nothing is stored, and nothing is received from other processes.

## Options

```ruby
SmartMessage::Transport::StdoutTransport.new                     # writes to $stdout
SmartMessage::Transport::StdoutTransport.new(output: $stderr)
SmartMessage::Transport::StdoutTransport.new(loopback: true)

SmartMessage::Transport.create(:stdout, loopback: true)
```

| Option | Default | Meaning |
|--------|---------|---------|
| `output` | `nil` | The IO to write to. `nil` means whatever `$stdout` is when the message is published, so output redirected later is respected. Any object with `puts` works (a `StringIO`, an open `File`). |
| `loopback` | `false` | Also deliver published messages to this transport's own subscribers |

The transport never closes the IO, because it did not open it. `disconnect` does nothing.

To write messages to a file by path, use the [File Transport](file-transport.md).

## Output format

One line per message: the JSON object the serializer produced, with the message's properties and its header under `_sm_header`.

```
{"_sm_header":{"uuid":"0b0e6f0c-...","message_class":"LogMessage","published_at":"2026-11-11T10:15:30.123456-06:00","publisher_pid":4242,"version":1,"from":"my-service","serializer":"SmartMessage::Serializer::Json"},"level":"info","text":"started"}
```

Because each line is a JSON document, the output works with line-oriented tools such as `jq`:

```bash
ruby my_program.rb | jq 'select(.level == "error") | .text'
```

## A complete program

```ruby
require 'smart_message'

# messages/log_message.rb
class LogMessage < SmartMessage::Base
  from 'my-service'
  transport SmartMessage::Transport::StdoutTransport.new(loopback: true)

  property :level, default: 'info'
  property :text,  required: true

  def self.process(message)
    $stderr.puts "handled: [#{message.level}] #{message.text}"   # stderr keeps stdout pure JSON
  end
end

LogMessage.subscribe
LogMessage.new(text: 'started').publish
LogMessage.new(level: 'error', text: 'disk is full').publish

SmartMessage.shutdown
```

Standard output gets two JSON lines. Because of `loopback: true`, the handler also runs for each message and writes to standard error; without it, only the JSON lines would appear.

## With another transport

Printing every message while also sending it somewhere real is a common use:

```ruby
class OrderMessage < SmartMessage::Base
  transport [
    SmartMessage::Transport.create(:redis, namespace: 'development'),
    SmartMessage::Transport.create(:stdout)
  ]
end
```

`OrderMessage.subscribe` subscribes on both transports, but only the Redis one delivers. See [Publishing](../reference/publishing.md).
