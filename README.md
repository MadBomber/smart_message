# SmartMessage

`SmartMessage` is to messages like `ActiveRecord` is to databases. SmartMessage resides between the business logic and message encoding (aka serializer) and delivery means (aka broker).

Related gems:

* [smart_message-broker-kafka](https://github.com/MadBomber/smart_message-broker-kafka)

* [smart_message-broker-rabbitmq](https://github.com/MadBomber/smart_message-broker-rabbitmq)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'smart_message'
```

And then execute:

    $ bundle

By the way - did you know that your application does not have to be a Rails application in order to take advantage of the bundler?  Well, now you do.

Or install it yourself as:

    $ gem install smart_message

## Discussion

SmartMessage is to messages like ActiveRecord is to databases. SmartMessage resides between business logic and message encoding (aka serializer) and delivery means.

### Terminolog

### Plugins

SmartMessage supports plugins at both the instance-level and class-level of message definitions.  This approach also supports gateway architectures in which messages originating on one broker are transfered to a different broker for ultimate delivery.

#### Serializer

A `SmartMessage::Serializer` is a capability to take the content of a SmartMessage and encode it in a way that it can be transmitted by a `SmartMessage::Broker`

An example of a serializer is `SmartMessage::Serializer::JSON` which encodes the `SmartMessage` content into a JSON text sctring.

Serializers must support two instance methods: encode and decode.  The `encode` method has one required parameter - a SmartMessage instance.  The `decode` methods has two required parameters.  The first is a message header hash that contains the `message_class` used for dispatching the received message to its business logic.  The second parameter is an encoded string buffer.

#### Broker

A SmartMessage::Broker is a process that moves messages wihtin a large distributed system.  A broker provides the means for publishing and subscribing to messages.  Examples of potential borkers are RabbitMQ, Kafka, zeroMQ, et.al.

#### Logger

A SmartMessage::Logger is a process for keeping a log of activities.  The standard Ruby Logger class can be used for this process.

## Usage

TODO: Write usage instructions here

### Defining a SmartMessage

```ruby
class MyMessage < SmartMessage::Base
  # property names should not start with '_sm_'
  property :foo   # hashie options ...
  property :bar   # hashie options ...
  property :baz   # hashie options ...
  # ... as many properties (aka attributes, fields) as needed

  # Business logic in the `process` method.  This is the
  # method that will be called when a message of this class
  # is received.
  def process
  end
end # class MyMessage < SmartMessage::Base
```

### Configuring the Class

Here is an example of where there are two different back end message delivery systems with different serializers and different loggers.  The same message has been defined on both back end systems.

```ruby
class BackEndOne < SmartMessage::Base; end
class BackEndTwo < SmartMessage::Base; end

BackEndOne.config do
  broker      SmartMessage::Broker::BrokerOne.new
  serializer  SmartMessage::Serializer::SerializerOne.new
  logger      SmartMessage::Logger::LoggerOne.new
end

BackEndTwo.config do
  broker      SmartMessage::Broker::BrokerTwo.new
  serializer  SmartMessage::Serializer::SerializerTwo.new
  logger      SmartMessage::Logger::LoggerTwo.new
end

class MyMessageOne < BackEndOne
  property :foo
  def process
    MyMessageTwo.new(self.to_h).publish
  end
end

class MyMessageTwo < BackEndOne
  property :foo
end
```

This kind of configuration is a gateway.  It takes messages from one system and republished them on another system.  Using a gateway architecture it is possible for example to subscribe to messages from RabbitMQ and republish those messages on Kafka.

One-way gateways are safest.  If a two-way gateway is needed extra business in the `process` methods is required to prevent the same message content from ping-ponging back-n-forth between the two seperate back end systems forever.

### Configuring an Instance

SmartMessage supports two-levels of configuration.  All instances of a message class can have a different configuration from its class; however, all sub-classes of a message class will have the same configuration as the top-level class.

```ruby
my_message.config do
  broker      SmartMessage::Broker::YourBroker.new
  serializer  SmartMessage::Serializer::YourSerializer.new
  logger      SmartMessage::Logger::YourLogger.new
end
```


### Publishing the Instance

```ruby
my_message = MyMessage.new(foo: 'one', baz: 'three', xyzzy: 'ignored')

# since 'xyzzy' is not defined as a valid property of this message
# this entry in the constructor will be ignored.  No exceptions; no
# warnings are generated.

my_message.bar = 'two'
# or my_message[:bar]  = 'two'
# or my_message['bar'] = 'two'

my_message.publish
```

### Subscribe a Class

When a SmartMessage::Broker receives a message, it will inspect the message to determine which message class the raw serialized message belongs to.  It then creates an instance of that message class and involkes the `process` method on the instance.

```ruby
MyMessage.subscribe
```

### Unsubscribe a Class

```ruby
MyMessage.unsubscribe

```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/smart_message.
