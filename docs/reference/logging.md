# Logging

**Logging is off unless you configure it.** With no logger configured, SmartMessage writes nothing and creates no file or directory.

## `config.logger`

```ruby
SmartMessage.configure do |config|
  config.logger = 'log/my_app.log'
end
```

| Value | Result |
|-------|--------|
| `nil` | No logging. This is the default. |
| `:default` | The built-in Lumberjack logger writing to `log/smart_message.log` (under `Rails.root` in a Rails application) |
| a String path | The built-in Lumberjack logger writing to that file. The directory is created. |
| `STDOUT` or `STDERR` | The built-in Lumberjack logger writing to the console |
| any other object | Used as it is: `Rails.logger`, `Logger.new(...)`, a `SmartMessage::Logger::Default`, or your own |

Any object with the standard Ruby `Logger` interface works. The framework only calls `debug`, `info`, `warn`, `error` and `fatal`, each with a block.

## The `log_*` settings

These shape the built-in Lumberjack logger, that is, when `config.logger` is `:default`, a String path, `STDOUT` or `STDERR`. They have no effect on a logger object you supply.

| Setting | Values | Default |
|---------|--------|---------|
| `config.log_level` | `:debug`, `:info`, `:warn`, `:error`, `:fatal` | `:info` |
| `config.log_format` | `:text` or `:json` | `:text` |
| `config.log_include_source` | `true` / `false`: add `file:line` of the caller | `true` |
| `config.log_structured_data` | `true` / `false`: keep keyword data given to log calls | `true` |
| `config.log_colorize` | `true` / `false`: colour lines by level; console output only | `false` |
| `config.log_options` | a Hash of rotation options (below) | `{}` |

Rotation options for `config.log_options`:

| Key | Meaning |
|-----|---------|
| `roll_by_size: true` | Rotate by size |
| `max_file_size:` | Bytes per file when rotating by size (default 10 MB) |
| `keep_files:` | Files to keep when rotating by size (default 5) |
| `roll_by_date: true` | Rotate by date |
| `roll_period:` | `'daily'` (default), `'weekly'` or `'monthly'` |
| `date_pattern:` | Suffix pattern for rotated files, such as `'%Y-%m-%d'` |

```ruby
SmartMessage.configure do |config|
  config.logger              = 'log/smart_message.log'
  config.log_level           = :debug
  config.log_format          = :json
  config.log_include_source  = true
  config.log_structured_data = true
  config.log_options         = { roll_by_size: true, max_file_size: 50 * 1024 * 1024, keep_files: 10 }
end
```

The logger is built once, when it is first needed, and rebuilt only after one of these settings changes.

## Output

Text format:

```
[2026-11-11 10:15:30.123] INFO  -- messaging.rb:77 : [SmartMessage] Published: OrderMessage via MemoryTransport
```

JSON format, one object per line. Keyword data given to a log call is nested under `data`, so it cannot collide with the fixed fields:

```json
{"timestamp":"2026-11-11 10:15:30.123","level":"INFO","message":"Order accepted","source":"orders.rb:12","data":{"order_id":42}}
```

The circuit breakers (the BreakerMachines gem) report through the same logger: a circuit opening is logged at `warn`, closing and half-opening at `info`. See [Circuit Breakers](circuit-breakers.md#circuit-events-in-the-log).

## What SmartMessage logs

| Level | Events |
|-------|--------|
| `debug` | Message created, routing decisions, subscriptions added, skipped Redis payloads |
| `info` | Published (with the transports used), subscribed, unsubscribed |
| `warn` | Partial publish failure, duplicate skipped, corrupt dead letter queue lines dropped |
| `error` | Transport publish failure, handler failure, payload that cannot be received, lost Redis subscriber connection, handler killed at shutdown, dead letter queue write failure |

## Using the logger yourself

```ruby
logger = SmartMessage::Logger.default   # the configured logger, or a Null logger

logger.info('Order accepted')
logger.info { "built only when the level allows it" }
logger.info('Order accepted', order_id: 42)   # keyword data
logger.level = :debug                          # Symbol, String or Integer
logger.debug?                                  # => true
logger.add(:warn, 'text')
```

Keyword data, `level=` with a Symbol and `add` with a Symbol belong to the interface of the loggers shipped with SmartMessage (`SmartMessage::Logger::Base`). A plain Ruby `Logger` does not accept keyword data.

## The shipped loggers

All three inherit from `SmartMessage::Logger::Base` and share one interface.

### `SmartMessage::Logger::Lumberjack`

What `config.logger = :default`, a path, `STDOUT` or `STDERR` builds. You can also build one yourself:

```ruby
SmartMessage.configure do |config|
  config.logger = SmartMessage::Logger::Lumberjack.new(
    log_file:        STDERR,   # a path, STDOUT or STDERR
    level:           :debug,
    format:          :text,    # :text or :json
    include_source:  true,
    structured_data: true,
    colorize:        true      # console only
  )
end
```

### `SmartMessage::Logger::Default`

A thin wrapper around Ruby's standard `Logger`. Each line carries the caller's file and line.

```ruby
SmartMessage.configure do |config|
  config.logger = SmartMessage::Logger::Default.new(
    log_file: 'log/smart_message.log',   # a path or an IO; this path is the default
    level:    :info                      # default :info
  )
end
```

Given a path, it keeps 10 files of 10 MB.

### `SmartMessage::Logger::Null`

Discards everything; message blocks are never evaluated. It is what SmartMessage uses when nothing is configured.

## Per-class loggers

A message class can have its own logger, inherited by its subclasses:

```ruby
require 'logger'

class PaymentMessage < SmartMessage::Base
  logger Logger.new('log/payments.log')
end

PaymentMessage.logger              # the class logger
PaymentMessage.logger_configured?  # => true (set on the class or an ancestor)
PaymentMessage.reset_logger        # back to the global logger
```

It receives the lines logged on behalf of that class's messages: creation, publishing and subscription. Transports, the dispatcher, deduplication and the dead letter queue use the global logger.

## Forcing a logger

`SmartMessage::Logger.default = logger` overrides the configuration until `SmartMessage::Logger.reset!` (or `SmartMessage::Logger.default = nil`). It is meant for tests.

## A complete program

```ruby
require 'smart_message'

SmartMessage.configure do |config|
  config.logger    = STDOUT
  config.log_level = :info
  config.transport = SmartMessage::Transport::MemoryTransport.new
end

# messages/ping_message.rb
class PingMessage < SmartMessage::Base
  from 'pinger'
  property :n

  def self.process(message)
    SmartMessage::Logger.default.info('handled a ping', n: message.n)
  end
end

PingMessage.subscribe
PingMessage.new(n: 1).publish
SmartMessage.shutdown
```

It prints the `Subscribed` and `Published` lines from the framework and the handler's own line with its keyword data.

## Rails

```ruby
# config/initializers/smart_message.rb
SmartMessage.configure do |config|
  config.logger = Rails.logger
end
```
