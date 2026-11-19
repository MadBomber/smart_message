# Memory Transport Examples

Examples that run in one process on `SmartMessage::Transport::MemoryTransport`. They need no external service, which makes them the place to learn the message API. Most of what they show (handlers, addressing, filters, validation, deduplication, dead letters, logging) works the same on every transport.

```bash
bundle exec ruby -Ilib examples/memory/03_point_to_point_orders.rb
bundle exec ruby examples/run_all.rb memory     # all of them
```

Each script checks its own result and exits non-zero when it is wrong. See [`../README.md`](../README.md) for the runner and the shared helper.

## Examples

| Script | Shows |
|--------|-------|
| [`01_message_deduplication_demo.rb`](01_message_deduplication_demo.rb) | `enable_deduplication!`, `ddq_size`, `ddq_storage`; one queue per handler; `ddq_stats`, `clear_ddq!` |
| [`02_dead_letter_queue_demo.rb`](02_dead_letter_queue_demo.rb) | Failed handlers and failed publishes land in the dead letter queue; inspecting, filtering and replaying it |
| [`03_point_to_point_orders.rb`](03_point_to_point_orders.rb) | 1-to-1: an order service and a payment service exchanging request and response |
| [`04_publish_subscribe_events.rb`](04_publish_subscribe_events.rb) | 1-to-many: one event, three independent subscribers |
| [`05_many_to_many_chat.rb`](05_many_to_many_chat.rb) | Many-to-many: chat agents and a bot; subscribing and unsubscribing at run time |
| [`06_stdout_publish_only.rb`](06_stdout_publish_only.rb) | `StdoutTransport`: one JSON line per message, the `output:` option |
| [`07_proc_handlers_demo.rb`](07_proc_handlers_demo.rb) | Handler forms: default `process`, block, proc, lambda, `'Class.method'`; handler ids; `unsubscribe` |
| [`08_custom_logger_demo.rb`](08_custom_logger_demo.rb) | A custom `SmartMessage::Logger::Base` subclass, a standard library `Logger`, global and per-class loggers |
| [`09_error_handling_demo.rb`](09_error_handling_demo.rb) | `valid?`, `validation_errors`, `validate!`, validators, schema versions, `TransportNotConfigured`, reserved property names |
| [`10_entity_addressing_basic.rb`](10_entity_addressing_basic.rb) | `from`, `to`, `reply_to`: point-to-point, broadcast, request-reply, instance overrides |
| [`11_entity_addressing_with_filtering.rb`](11_entity_addressing_with_filtering.rb) | Subscription filters `to:`, `from:`, `broadcast:` and their combinations |
| [`12_regex_filtering_microservices.rb`](12_regex_filtering_microservices.rb) | Regexps and mixed arrays in filters |
| [`13_header_block_configuration.rb`](13_header_block_configuration.rb) | Class methods, the `header do ... end` block, and instance-level addressing |
| [`14_global_configuration_demo.rb`](14_global_configuration_demo.rb) | `SmartMessage.configure`: transport, logger, `dlq_path`; class and instance precedence; resetting |
| [`15_logger_demo.rb`](15_logger_demo.rb) | The built-in loggers: text and JSON files, levels, keyword data, console colour, `Logger::Default` |
| [`16_pretty_print_demo.rb`](16_pretty_print_demo.rb) | `pretty_print`, `payload_hash`, `to_h` |

`00_run_all_demos.rb` runs `../run_all.rb memory`.

The message classes are in [`messages/`](messages/), one class per file.

## MemoryTransport options

```ruby
SmartMessage::Transport::MemoryTransport.new(
  auto_process:   true,   # deliver to subscribers on publish
  store_messages: nil,    # keep published messages; default: only when auto_process is false
  max_messages:   1000,   # how many stored messages to keep
  serialize:      true    # encode on publish and decode on delivery, as a real transport does
)
```

With `auto_process: false` the transport only stores. `all_messages` returns the stored entries (`{ message_class:, payload:, published_at: }`), `message_count` counts them, and `process_all` delivers them to subscribers and removes them.

Handlers run on the dispatcher's thread pool, so `publish` returns before they finish. To wait for them:

```ruby
dispatcher = transport.dispatcher
sleep 0.01 until dispatcher.status[:in_flight].zero? && dispatcher.queue_length.zero?
```

The examples do this with a deadline through `Example.wait_for_idle(transport)`.

## Diagrams

- [Memory transport architecture](memory_transport_architecture.svg)
- [Point-to-point pattern](point_to_point_pattern.svg) (example 03)
- [Publish-subscribe pattern](publish_subscribe_pattern.svg) (example 04)
