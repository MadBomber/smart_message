# Quick Start

## Install

SmartMessage requires Ruby 4.0 or newer.

```ruby
# Gemfile
gem 'smart_message'
```

```bash
bundle install
```

## A complete program

Save this as `quick_start.rb` and run `ruby quick_start.rb`. It uses the memory transport, so it needs no external service.

```ruby
require 'smart_message'

# In an application this class lives in messages/welcome_message.rb
class WelcomeMessage < SmartMessage::Base
  description 'Welcomes a new user'
  from 'signup-service'
  transport SmartMessage::Transport::MemoryTransport.new

  property :user_name, required: true
  property :email,     required: true,
                       validate: /\A[^@\s]+@[^@\s]+\z/,
                       validation_message: 'email must look like an address'
  property :plan,      default: 'free', validate: %w[free pro]

  # The default handler: a class method named process
  def self.process(message)
    puts "Welcome #{message.user_name} <#{message.email}> on the #{message.plan} plan"
  end
end

# Subscribe the default handler (WelcomeMessage.process)
WelcomeMessage.subscribe

# Publish a message.  publish validates first and returns a PublishResult.
result = WelcomeMessage.new(user_name: 'Alice', email: 'alice@example.com').publish
puts "Published #{result.uuid}: success=#{result.success?}"

# An invalid message is not sent.
begin
  WelcomeMessage.new(user_name: 'Bob', email: 'not-an-address').publish
rescue SmartMessage::Errors::ValidationError => e
  puts "Not published: #{e.message}"
end

# Handlers run on a thread pool.  Wait for them before the program ends.
SmartMessage.shutdown
```

Output (the `Welcome` line comes from another thread, so its position can vary):

```
Published 6c5f0f0e-...: success=true
Welcome Alice <alice@example.com> on the free plan
Not published: WelcomeMessage#email: email must look like an address
```

The rest of this page explains each part.

## Message classes

A message class inherits from `SmartMessage::Base`. In an application, keep message classes in a `messages/` directory, one class per file.

```ruby
class WelcomeMessage < SmartMessage::Base
  description 'Welcomes a new user'   # optional
  version 1                           # optional, default 1

  property :user_name, required: true
  property :plan,      default: 'free'
end
```

`property` accepts `required:`, `message:`, `default:`, `validate:`, `validation_message:` and `description:`. See [Properties and Validation](../core-concepts/properties.md).

## A transport is required

There is no default transport. A message class gets one in either of two ways:

```ruby
# On the class (subclasses inherit it)
WelcomeMessage.transport SmartMessage::Transport::MemoryTransport.new

# Globally, for every class that does not set its own
SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::MemoryTransport.new
end
```

Publishing or subscribing with no transport raises `SmartMessage::Errors::TransportNotConfigured`.

Four transports ship with the gem: memory, stdout, file and Redis pub/sub. They differ in what they guarantee; read [Transports](../reference/transports.md) before choosing one for production.

## A sender is required

Every message needs a `from`. Set a default on the class, or pass it when building the message:

```ruby
class WelcomeMessage < SmartMessage::Base
  from 'signup-service'
end

WelcomeMessage.new(user_name: 'Alice', email: 'a@example.com', from: 'admin-console')
```

A message with no `from` fails validation. `to` and `reply_to` are optional; see [Addressing](../core-concepts/addressing.md).

## Building and validating

`new` never raises for a missing or invalid property. Validation happens when you ask for it, and when you publish.

```ruby
message = WelcomeMessage.new(user_name: 'Bob')   # email is missing: no error yet

message.valid?              # => false
message.validation_errors   # => [{ property: :email, value: nil, message: "...", source: "message" }]
message.validate!           # raises SmartMessage::Errors::ValidationError
```

## Publishing

```ruby
result = message.publish
```

`publish` calls `validate!`, sends the message on every configured transport, and returns a `SmartMessage::PublishResult`. It raises `SmartMessage::Errors::PublishError` when every transport fails. See [Publishing](../reference/publishing.md).

## Subscribing

You subscribe at the class level. A handler is a class method, a block, a proc or a lambda.

```ruby
# 1. The default handler: WelcomeMessage.process
WelcomeMessage.subscribe

# 2. A class method somewhere else, named as "Class.method"
WelcomeMessage.subscribe('Mailer.send_welcome')

# 3. A block
WelcomeMessage.subscribe do |message|
  Metrics.increment('signups', plan: message.plan)
end

# 4. A proc or lambda
audit = ->(message) { AuditLog.record(message.to_h) }
WelcomeMessage.subscribe(audit)
```

`subscribe` returns a handler id. Pass it to `unsubscribe` to remove that handler; `unsubscribe!` removes every handler of the class.

Handlers run on a thread pool, each with its own copy of the message. A handler that raises does not affect the others; its copy of the message goes to the [dead letter queue](../reference/dead-letter-queue.md).

## Waiting for handlers

Because handlers run on other threads, a short script can reach its last line before they finish. `SmartMessage.shutdown` waits for them:

```ruby
SmartMessage.shutdown               # waits config.shutdown_timeout seconds (default 5)
SmartMessage.shutdown(timeout: 30)  # or as long as you say
```

SmartMessage also registers `SmartMessage.shutdown` with `at_exit`, so handlers that are still running when the process ends get the configured timeout to finish. Calling it yourself makes the wait explicit and lets you check the return value (`true` when everything finished in time). Call it once, at the end: after a shutdown the thread pools are closed, and a handler for any later message runs on the thread that published or received it.

## A second program: filters and two handlers

```ruby
require 'smart_message'

SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::MemoryTransport.new
end

# messages/alert_message.rb
class AlertMessage < SmartMessage::Base
  from 'monitoring'

  property :level, required: true, validate: %w[info warning critical]
  property :text,  required: true

  def self.process(message)
    puts "[#{message.level}] #{message.text} (to: #{message.to || 'everyone'})"
  end
end

# Every alert
AlertMessage.subscribe

# Only alerts addressed to the on-call entity
AlertMessage.subscribe(to: 'on-call') do |message|
  puts "PAGE on-call: #{message.text}"
end

AlertMessage.new(level: 'info', text: 'Deploy finished').publish
AlertMessage.new(level: 'critical', text: 'Database is down', to: 'on-call').publish

SmartMessage.shutdown
```

It prints three lines: both alerts from `AlertMessage.process`, and the page for the second one.

## Next steps

- [Transports](../reference/transports.md): what each transport guarantees
- [Properties and Validation](../core-concepts/properties.md)
- [Message Filtering](../core-concepts/message-filtering.md)
- [Dead Letter Queue](../reference/dead-letter-queue.md)
- [Examples](examples.md)
