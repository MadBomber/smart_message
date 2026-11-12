# Configuration

## Precedence

A setting is looked up in this order, and the first place that has a value wins:

1. **the message instance**: `message.transport(t)`
2. **the message class**: `OrderMessage.transport(t)`
3. **a parent class**, nearest first (class settings are inherited)
4. **the global configuration**: `SmartMessage.configure { |config| config.transport = t }`

There is no step 5. In particular:

- **There is no default transport.** A class with no transport anywhere has none, and publishing or subscribing raises `SmartMessage::Errors::TransportNotConfigured`.
- **Logging is off unless configured.** With no logger anywhere, nothing is logged and no file or directory is created.

What can be set where:

| Setting | Instance | Class (inherited) | Global |
|---------|----------|-------------------|--------|
| transport(s) | `message.transport(t)` | `MessageClass.transport(t)` | `config.transport` |
| logger | | `MessageClass.logger(l)` | `config.logger` |
| `from`, `to`, `reply_to` | `message.from(id)`, or `new(from: id)` | `MessageClass.from(id)` | |
| version | | `MessageClass.version(n)` | |
| deduplication | | `ddq_size`, `ddq_storage`, `enable_deduplication!` | |
| validators, property descriptions | | `property ...` | |
| description | | `MessageClass.description(text)`, not inherited | |

### Inheritance

A class reads its own value, else its nearest ancestor's. Writing a setting on a class never changes its parent or a sibling.

```ruby
SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport.create(:memory)   # global
end

class AppMessage < SmartMessage::Base
  from 'my-app'
end

class AuditMessage < AppMessage
  transport SmartMessage::Transport.create(:file, file_path: 'log/audit.jsonl')
end

class LoginAudit < AuditMessage
end

AppMessage.transport.class    # => SmartMessage::Transport::MemoryTransport   (global)
LoginAudit.transport.class    # => SmartMessage::Transport::FileTransport     (from AuditMessage)
LoginAudit.from               # => "my-app"                                    (from AppMessage)

LoginAudit.reset_transport    # forget a class's own value; the inherited one shows through
```

Transports are resolved when they are used, so changing the class or global transport later affects messages that already exist, unless the instance has its own.

### Instance overrides

```ruby
message = OrderMessage.new(order_id: 'ORD-1')
message.transport(SmartMessage::Transport.create(:stdout))   # this message only
message.publish
message.reset_transport                                      # back to the class's transports
```

### Several transports

A class or an instance can have more than one transport. Pass an Array:

```ruby
class OrderMessage < SmartMessage::Base
  transport [
    SmartMessage::Transport.create(:redis, namespace: 'production'),
    SmartMessage::Transport.create(:file, file_path: 'log/orders.jsonl')
  ]
end

OrderMessage.transports            # => both
OrderMessage.transport             # => the first
OrderMessage.multiple_transports?  # => true
```

`publish` sends to each and reports each outcome; `subscribe` subscribes on each. See [Publishing](../reference/publishing.md).

## Global configuration

```ruby
SmartMessage.configure do |config|
  # Transport: none by default
  config.transport = SmartMessage::Transport.create(:redis, namespace: 'production')

  # Logging: off by default.  See the Logging page for the accepted values.
  config.logger    = 'log/smart_message.log'
  config.log_level = :info

  # Dead letter queue file
  config.dlq_path = '/var/lib/my_app/dead_letters.jsonl'

  # Dispatcher
  config.dispatcher_max_threads = 10
  config.dispatcher_max_queue   = 1_000
  config.shutdown_timeout       = 5
end
```

| Setting | Default | Meaning |
|---------|---------|---------|
| `transport` | `nil` | A transport instance, or an Array of them, for classes that do not set their own |
| `logger` | `nil` | See [Logging](../reference/logging.md) |
| `log_level`, `log_format`, `log_include_source`, `log_structured_data`, `log_colorize`, `log_options` | unset | Shape the built-in Lumberjack logger; see [Logging](../reference/logging.md) |
| `dlq_path` | `$SMART_MESSAGE_DLQ_PATH`, else `$XDG_STATE_HOME/smart_message/dead_letters.jsonl`, else `~/.local/state/smart_message/dead_letters.jsonl` | File of the default [dead letter queue](../reference/dead-letter-queue.md); stored as an absolute path |
| `dispatcher_max_threads` | `[CPU count * 2, 4].max` | Handler threads per [dispatcher](dispatcher.md) |
| `dispatcher_max_queue` | `1000` | Handler calls that may wait for a thread |
| `shutdown_timeout` | `5` | Seconds `SmartMessage.shutdown` waits when called without `timeout:` |

The dispatcher settings are read when a dispatcher is created (that is, when a transport is created), so configure them first.

Other entry points:

```ruby
SmartMessage.configuration                 # the current configuration object
SmartMessage.configuration = saved         # replace it (useful around a test)
SmartMessage.reset_configuration!          # back to defaults; also forgets the default dead letter queue
SmartMessage.configuration.transport_configured?
SmartMessage.configuration.logger_configured?
```

## Per-class logger

```ruby
class PaymentMessage < SmartMessage::Base
  logger Logger.new('log/payments.log')
end
```

A class logger receives the messages logged on behalf of that class (creation, publishing, subscription). Transports, the dispatcher and the dead letter queue always use the global logger.

## The `config` block

`config` on a message class evaluates its block in the class, which lets you group settings:

```ruby
OrderMessage.config do
  transport SmartMessage::Transport.create(:memory)
  from 'order-service'
end
```

## In tests

Give each test its own state rather than sharing a server-wide default:

```ruby
def setup
  @saved = SmartMessage.configuration
  SmartMessage.configuration = SmartMessage::Configuration.new
  SmartMessage.configure do |config|
    config.transport = SmartMessage::Transport.create(:memory)
    config.dlq_path  = File.join(Dir.mktmpdir, 'dead_letters.jsonl')
  end
end

def teardown
  SmartMessage.configuration = @saved
  SmartMessage::DeadLetterQueue.reset_default!
end
```

For tests against Redis, use a unique `namespace:` per test run. The `db` number does not isolate pub/sub channels.
