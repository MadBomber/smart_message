# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bundle exec rake test                 # all tests (the default task)
ruby -Ilib:test test/base_test.rb     # one test file (Minitest)
bundle exec rake examples             # run every example script; fails if one fails
bin/console                           # IRB with the gem loaded
bundle exec rake build                # build the gem into pkg/
```

Tests that need Redis use `redis://localhost:6379` (override with
`SMART_MESSAGE_TEST_REDIS_URL`). They skip only when no server answers
`PING`; with a server running nothing is skipped. Every run writes to its
own temporary directory and uses its own Redis namespace, so nothing lands
in the working directory.

## What the gem is

SmartMessage separates a message's content from how it is delivered. A
message class inherits from `SmartMessage::Base` (a `Hashie::Dash`),
declares properties, and is given one or more transports. Version 0.1.0;
Ruby 4.0 or newer.

Built in: four transports (`:memory`, `:stdout`, `:file`, `:redis` pub/sub)
and one serializer (JSON). Other transports live in separate
`smart_message-transport-*` gems.

## Layout (`lib/smart_message/`)

| File | Role |
|------|------|
| `base.rb` | `SmartMessage::Base`: construction, reserved property names, `to_h`, copying |
| `header.rb` | `_sm_header`: uuid, message_class, published_at, version, from/to/reply_to, `extensions` |
| `inheritable_settings.rb` | The one mechanism for class-level settings (own value, else the parent's) |
| `plugins.rb`, `addressing.rb`, `versioning.rb`, `deduplication.rb` | Class-level settings built on it |
| `property_validations.rb`, `property_descriptions.rb` | `required:`, `validate:`, `description:` property options |
| `messaging.rb`, `publish_result.rb` | `publish` and its per-transport result |
| `subscription.rb` | `subscribe` / `unsubscribe`, proc handler registry |
| `envelope.rb` | The codec: message to bytes and back, with class and channel checks |
| `dispatcher.rb` | Routes a received message to handlers on a bounded thread pool |
| `ddq.rb`, `ddq/` | Deduplication queues (memory, Redis) with atomic `reserve` / `release` |
| `dead_letter_queue.rb` | JSON Lines file of messages that could not be published or processed |
| `circuit_breaker.rb` | Circuit construction and helpers on the `breaker_machines` gem |
| `transport/` | `Base` (the contract), `Registry`, and the four transports |
| `serializer/` | `Base` and `Json` |
| `logger/` | `Base` (the interface), `Null`, `Default`, `Lumberjack` |
| `configuration.rb` | `SmartMessage.configure`: transport, logger, DLQ path, dispatcher limits |

Zeitwerk loads everything; `ddq` is inflected to `DDQ`. Do not add
`require_relative` inside `lib/smart_message/`.

## Rules the code follows

- **A failure is never reported as a success.** `publish` returns a
  `PublishResult` and raises `PublishError` when every transport fails.
  Anything that could not be published, decoded, or handled goes to the dead
  letter queue. Do not rescue an error and return a normal-looking value.
- **Class settings inherit, and only downward.** Use `setting` /
  `set_setting` from `InheritableSettings`; never class variables or a
  registry keyed by class name.
- **Validation happens in one place**: `validation_errors` (used by `valid?`,
  `validate!`, and `publish`). `new` does not raise for missing data.
- **Handlers are isolated.** Each handler of each message class has its own
  circuit breaker, its own deduplication queue, and its own copy of the
  message.
- **A transport only moves bytes.** It implements `do_publish` and calls
  `receive`; encoding, decoding, and routing belong to `Envelope` and the
  dispatcher. Every transport passes `test/helpers/transport_contract.rb`.
- **Nothing is logged, and no file is created, unless configured.**
- Every method should be testable in isolation; inject collaborators
  (an IO, a clock, a sleeper, an environment Hash) instead of reaching for
  globals.

## Conventions

- Application code keeps `SmartMessage::Base` subclasses in a directory
  named `messages`.
- Use `debug_me` for debugging output, never `puts`.
- Commit messages follow `COMMITS.md`.
- `CHANGELOG.md` is kept current; breaking changes are listed under
  **Breaking**.
