# SmartMessage Examples

Runnable programs for SmartMessage 0.1.0, grouped by transport. Every numbered script is self-checking: it verifies the outcome it demonstrates, prints `ok:` lines, and exits non-zero with a `FAILED:` message when the outcome is wrong.

## Running

From the repository root:

```bash
bundle install

bundle exec ruby -Ilib examples/memory/03_point_to_point_orders.rb   # one example
bundle exec ruby examples/run_all.rb                                 # all of them
bundle exec ruby examples/run_all.rb memory                          # paths containing "memory"
bundle exec rake examples                                            # same as run_all.rb
```

`run_all.rb` runs each script in its own process and prints one `PASS`, `FAIL` or `SKIP` line per script, followed by the output of any script that failed. It exits 1 when a script fails.

| Variable | Meaning | Default |
|----------|---------|---------|
| `EXAMPLE_TIMEOUT` | Seconds allowed per script | `30` |
| `SMART_MESSAGE_TEST_REDIS_URL` | Redis server for `examples/redis` | `redis://localhost:6379` |

The Redis examples are reported as `SKIP` when no server answers at that URL. `city_scenario` and `performance_metrics` are long-running, multi-process programs and are not part of `run_all.rb`.

The examples write nothing into the repository. Log files, dead letter files and transport files go to a temporary directory that is removed when the script ends.

## Layout

| Path | Contents |
|------|----------|
| [`memory/`](memory/README.md) | 16 examples on the in-memory transport: messaging patterns, handlers, addressing, filtering, validation, deduplication, dead letters, logging, configuration |
| [`file/`](file/README.md) | 3 examples on the file transport: JSON Lines output, tailing a shared file, combining a file with other transports |
| [`redis/`](redis/README.md) | Redis pub/sub examples (need a Redis server) |
| [`multi_transport_example.rb`](multi_transport_example.rb) | One message on several transports; `PublishResult`, partial failure, `PublishError` |
| [`city_scenario/`](city_scenario/README.md) | Multi-process emergency services simulation over Redis |
| `performance_metrics/` | Benchmark scripts |
| `run_all.rb` | The runner described above |
| `support/example_helper.rb` | Shared by the examples: temporary directory, `wait_until`, `wait_for_idle`, `check`, `finish` |
| `support/failing_transport.rb` | A transport that always fails, for the failure examples |
| `*/messages/` | The message classes, one per file |

Message classes live in a `messages/` directory next to the scripts that use them. That is the convention for any application built on SmartMessage: every `SmartMessage::Base` subclass goes in a directory named `messages`.

## Where to start

1. [`memory/03_point_to_point_orders.rb`](memory/03_point_to_point_orders.rb): define two messages, give them a transport, subscribe, publish.
2. [`memory/07_proc_handlers_demo.rb`](memory/07_proc_handlers_demo.rb): the handler forms.
3. [`memory/09_error_handling_demo.rb`](memory/09_error_handling_demo.rb): validation and the errors you will meet first.
4. [`memory/02_dead_letter_queue_demo.rb`](memory/02_dead_letter_queue_demo.rb): what happens to a message that fails.
5. [`multi_transport_example.rb`](multi_transport_example.rb): what `publish` returns.

## The shape of an example

```ruby
require_relative '../support/example_helper'
require_relative 'messages/order_message'

transport = SmartMessage::Transport::MemoryTransport.new
OrderMessage.transport(transport)                  # there is no default transport

OrderMessage.subscribe { |message| Example.inbox.add(:orders, message.order_id) }
OrderMessage.new(order_id: 'ORD-1', customer_id: 'CUST-7', amount: 99.99).publish

Example.wait_for_idle(transport)                   # handlers run on a thread pool
Example.check('the order was received') { Example.inbox[:orders] == ['ORD-1'] }
Example.finish
```

Things the examples rely on, all new or changed in 0.1.0 (see the `0.1.0` section of [CHANGELOG.md](../CHANGELOG.md)):

- **A transport must be configured**, on the class or with `SmartMessage.configure { |config| config.transport = ... }`.
- **`publish` returns a `SmartMessage::PublishResult`** and raises `SmartMessage::Errors::PublishError` when every transport fails.
- **Validation happens at `publish`** (or `valid?` / `validate!`), not in `new`.
- **Handlers receive one argument, the message.** `MyMessage.subscribe` with no argument calls the class method `MyMessage.process(message)`.
- **Handlers run on a thread pool.** A program that needs their results waits for them; the examples poll with a deadline (`Example.wait_until`) or wait for the dispatcher to become idle (`Example.wait_for_idle`).
- **Logging is off unless configured**, and the dead letter queue file is `SmartMessage.configuration.dlq_path`.

## Further reading

- [Documentation](../docs/index.md)
- [CHANGELOG](../CHANGELOG.md)
