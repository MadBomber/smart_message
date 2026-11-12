# Examples

The repository has runnable example programs, grouped by the transport they use. Each directory has its own README that lists the programs and says how to run them.

| Directory | What it shows | Needs |
|-----------|---------------|-------|
| [examples/memory/](https://github.com/MadBomber/smart_message/tree/main/examples/memory) | Messaging patterns, handlers, filtering, addressing, deduplication, the dead letter queue, logging and configuration, all in one process | Nothing |
| [examples/file/](https://github.com/MadBomber/smart_message/tree/main/examples/file) | The file transport: appending messages to a file and tailing it | Nothing |
| [examples/redis/](https://github.com/MadBomber/smart_message/tree/main/examples/redis) | The Redis pub/sub transport | A Redis server |
| [examples/city_scenario/](https://github.com/MadBomber/smart_message/tree/main/examples/city_scenario) | Several programs (emergency dispatch, fire, police, health and others) exchanging messages over Redis | A Redis server |

Run an example from the repository root so that it uses the checked-out library:

```bash
bundle exec ruby -Ilib examples/memory/<program>.rb
```

The message classes of the city scenario are in its `messages/` directory, which is the layout recommended for applications: one `SmartMessage::Base` subclass per file under `messages/`.

## Small patterns

The programs below are complete. Each runs on its own with the memory transport.

### Request and reply

`reply_to` tells the receiver where to send its answer. The requester subscribes to replies addressed to it.

```ruby
require 'smart_message'

SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::MemoryTransport.new
end

# messages/price_request.rb
class PriceRequest < SmartMessage::Base
  property :sku, required: true

  def self.process(message)
    PriceReply.new(sku: message.sku, cents: 1299, from: 'pricing', to: message.reply_to).publish
  end
end

# messages/price_reply.rb
class PriceReply < SmartMessage::Base
  property :sku,   required: true
  property :cents, required: true
end

PriceRequest.subscribe
PriceReply.subscribe(to: 'storefront') do |reply|
  puts "storefront: #{reply.sku} costs #{reply.cents} cents"
end

PriceRequest.new(sku: 'WIDGET-1', from: 'storefront', to: 'pricing', reply_to: 'storefront').publish

SmartMessage.shutdown
```

### Broadcast with several subscribers

```ruby
require 'smart_message'

SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::MemoryTransport.new
end

# messages/user_signed_up.rb
class UserSignedUp < SmartMessage::Base
  from 'accounts'
  property :email, required: true
end

UserSignedUp.subscribe { |message| puts "mailer: welcome mail to #{message.email}" }
UserSignedUp.subscribe { |message| puts "metrics: signup counted" }
UserSignedUp.subscribe { |message| puts "audit: #{message.uuid} recorded" }

UserSignedUp.new(email: 'ann@example.com').publish

SmartMessage.shutdown
```

Each block is a separate handler with its own copy of the message.

### Testing a message class

With `auto_process: false` the memory transport stores what was published instead of delivering it, which is what a unit test usually wants.

```ruby
require 'smart_message'

# messages/invoice_message.rb
class InvoiceMessage < SmartMessage::Base
  from 'billing'
  property :number, required: true
  property :total,  validate: ->(value) { value >= 0 }
end

transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
InvoiceMessage.transport(transport)

InvoiceMessage.new(number: 'INV-7', total: 250).publish

entry   = transport.all_messages.first
decoded = transport.decode_message(entry[:payload])

puts <<~REPORT
  stored:  #{transport.message_count}
  class:   #{entry[:message_class]}
  number:  #{decoded.number}
  invalid: #{InvoiceMessage.new(total: -1).validation_errors.map { |error| error[:property] }.inspect}
REPORT
```
