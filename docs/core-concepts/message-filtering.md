# Message Filtering

A subscription can carry filters on the header's addressing fields. The dispatcher checks them for each incoming message and calls the handler only when they match.

Filters are applied in the subscriber's process, after the transport has delivered the message. They reduce what a handler sees, not what travels over the transport.

```ruby
MessageClass.subscribe(handler = nil, from: nil, to: nil, broadcast: nil, &block)
```

| Filter | Accepts | Matches when |
|--------|---------|--------------|
| `from:` | String, Regexp, or an Array of them | the header's `from` equals a String or matches a Regexp |
| `to:` | String, Regexp, or an Array of them | the header's `to` equals a String or matches a Regexp |
| `broadcast:` | `true` | the header's `to` is `nil` |

Any other filter value raises `ArgumentError` at subscribe time.

## How filters combine

- No filters: the handler gets every message of the class.
- `from:` must match when it is given.
- `to:` and `broadcast:` are alternatives: when either is given, at least one of them must match.

So `subscribe(from: 'billing', to: 'me', broadcast: true)` means: from billing, and either addressed to me or addressed to nobody.

A message with `to: nil` never matches a `to:` filter, and a message with `from: nil` never matches a `from:` filter.

## Examples

```ruby
# messages/alert_message.rb
class AlertMessage < SmartMessage::Base
  property :text, required: true

  def self.process(message)
    puts "#{message.from} -> #{message.to || 'all'}: #{message.text}"
  end
end

# Exact sender
AlertMessage.subscribe(from: 'payment-service')

# Any of several senders
AlertMessage.subscribe(from: %w[admin monitoring])

# Pattern
AlertMessage.subscribe(from: /\Apayment-/)

# Strings and patterns together
AlertMessage.subscribe(from: ['admin', /\Asystem-/])

# Addressed to this service
AlertMessage.subscribe(to: 'order-service')

# Addressed to this service, or broadcast
AlertMessage.subscribe(to: 'order-service', broadcast: true)

# Broadcasts only
AlertMessage.subscribe(broadcast: true)

# From admins, to any production service
AlertMessage.subscribe(from: /\Aadmin-/, to: /-prod\z/)
```

## Several subscriptions on one class

Each `subscribe` call with a block, proc or lambda adds a separate handler with its own filters:

```ruby
AlertMessage.subscribe(broadcast: true)      { |message| Dashboard.show(message.text) }
AlertMessage.subscribe(to: 'on-call')        { |message| Pager.page(message.text) }
AlertMessage.subscribe(from: /\Asecurity-/)  { |message| SecurityLog.append(message.to_h) }
```

A message that matches several subscriptions is delivered to each of them.

A handler named by a String (`"Class.method"`, including the default `"AlertMessage.process"`) is identified by that String. Subscribing the same named handler twice with different filters creates two subscriptions that call the same method, and a message matching both calls it twice; `unsubscribe` with that name removes both. When you want different filters for different work, use different handlers.

## A complete program

```ruby
require 'smart_message'

SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::MemoryTransport.new
end

# messages/notice_message.rb
class NoticeMessage < SmartMessage::Base
  property :text, required: true
end

NoticeMessage.subscribe(broadcast: true)                 { |m| puts "broadcast   : #{m.text}" }
NoticeMessage.subscribe(to: 'billing')                   { |m| puts "to billing  : #{m.text}" }
NoticeMessage.subscribe(from: /\Aadmin-/)                { |m| puts "from admin  : #{m.text}" }
NoticeMessage.subscribe(to: 'billing', broadcast: true)  { |m| puts "billing+all : #{m.text}" }

NoticeMessage.new(text: 'one',   from: 'ops').publish                       # broadcast, billing+all
NoticeMessage.new(text: 'two',   from: 'ops', to: 'billing').publish        # to billing, billing+all
NoticeMessage.new(text: 'three', from: 'admin-1', to: 'shipping').publish   # from admin

SmartMessage.shutdown
```

## Inspecting subscriptions

```ruby
transport = NoticeMessage.transport
transport.subscribers['NoticeMessage']
# => [{ subscriber_id: "NoticeMessage.proc_...", process_method: "...", filters: { broadcast: true, to: nil, from: nil } }, ...]
```
