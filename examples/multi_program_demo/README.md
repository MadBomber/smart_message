# SmartMessage Multi-Program Demo

This demo showcases SmartMessage's capability to enable communication between multiple independent Ruby programs using a publish/subscribe pattern with message filtering and acknowledgments.

## Overview

The demo consists of three programs that communicate asynchronously:

1. **Health Publisher** - Continuously publishes health check messages for simulated services
2. **Acknowledging Subscriber** - Processes incoming messages and sends back acknowledgments
3. **Logging Subscriber** - Logs all broadcast messages with detailed formatting

## Message Types

The demo uses four message types to demonstrate different communication patterns:

- **HealthCheckMessage** - Service health status with metrics (cpu, memory, response times)
- **AcknowledgmentMessage** - Confirms successful or failed message processing
- **WorkRequestMessage** - Job requests with priority levels and payloads
- **SystemEventMessage** - System events with severity levels (info, warning, error, critical)

## Prerequisites

- Ruby (2.5 or higher)
- Redis server (running locally on default port 6379)
- iTerm2 (for the macOS terminal interface)
- The SmartMessage gem and its dependencies

### Installing Redis

```bash
# macOS
brew install redis
brew services start redis

# Ubuntu/Debian
sudo apt-get install redis-server
sudo systemctl start redis

# RHEL/CentOS/Fedora
sudo yum install redis
sudo systemctl start redis
```

### Installing iTerm2

```bash
# macOS with Homebrew
brew install --cask iterm2

# Or download directly from https://iterm2.com/
```

## Running the Demo

### Quick Start

1. Make the scripts executable:
```bash
chmod +x start_demo.sh stop_demo.sh
```

2. Start all programs in iTerm2:
```bash
./start_demo.sh
```

This will:
- Create a new iTerm2 window with separate tabs
- Launch each program in its own tab
- Create a control panel tab with helpful commands
- Switch to the Health Publisher tab to start

3. To stop the demo:
```bash
./stop_demo.sh
```

### Manual Start (without iTerm2)

You can also run each program individually in separate terminal windows:

```bash
# Terminal 1
ruby health_publisher.rb

# Terminal 2
ruby acknowledging_subscriber.rb

# Terminal 3
ruby logging_subscriber.rb
```

## What to Observe

### Health Publisher (Tab 1)
- Publishes health checks every 5 seconds
- Monitors 5 simulated services (api-gateway, user-service, order-service, payment-service, notification-service)
- Simulates service degradation over time
- payment-service will become unhealthy after 60 seconds
- notification-service will occasionally report as degraded after 30 seconds

### Acknowledging Subscriber (Tab 2)
- Listens for messages directed to it or broadcast
- Processes each message type differently
- Sends acknowledgment messages back to the sender
- Tracks processing statistics (processed count, failed count)
- Simulates different processing times based on message priority

### Logging Subscriber (Tab 3)
- Subscribes to ALL broadcast messages
- Displays detailed message information including:
  - Message headers (ID, from, to, version)
  - All message properties
  - Formatted output with separators
- Shows running statistics every 10 messages

### Control Panel (Tab 4)
- Displays helpful commands and shortcuts
- Shows message flow explanation
- Provides quick reference for iTerm2 shortcuts

## Message Flow

1. **Health Checks**: 
   - Publisher → Broadcast → Both subscribers receive
   - Publisher → Acknowledging Subscriber (targeted) → Acknowledgment sent back

2. **Acknowledgments**:
   - Acknowledging Subscriber → Original sender (targeted response)
   - Also broadcast so Logging Subscriber can track all activity

3. **Filtering Examples**:
   - Broadcast messages: `to: nil` - received by all broadcast subscribers
   - Targeted messages: `to: 'service-name'` - received only by that service
   - Pattern matching: `to: /^ack-.*/` - matches services starting with "ack-"

## iTerm2 Controls

While in the demo window:

- `Cmd+1,2,3,4` - Switch to tabs 1,2,3,4 (Health Publisher, Acknowledging Subscriber, Logging Subscriber, Control Panel)
- `Cmd+[` / `Cmd+]` - Previous/Next tab
- `Cmd+Option+E` - Expose all tabs (overview mode)
- `Cmd+W` - Close current tab
- `Cmd+Shift+W` - Close current window
- `Cmd+T` - Create new tab
- `Ctrl+C` - Stop the program running in current tab

The demo window stays open until you explicitly close it or run `./stop_demo.sh`

## Architecture Highlights

This demo showcases several SmartMessage features:

- **Redis Transport**: All messages are routed through Redis for reliable pub/sub messaging

- **Decoupled Communication**: Programs don't need direct references to each other
- **Message Filtering**: Subscribers can filter by sender, recipient, or broadcast
- **Message Validation**: All messages are validated before publishing
- **Async Processing**: Messages are processed in separate threads via Dispatcher
- **Graceful Shutdown**: All programs handle SIGINT/SIGTERM for clean shutdown
- **Error Handling**: Failed message processing generates error acknowledgments

## Customization

### Change Publishing Interval

Pass an interval in seconds to the health publisher:
```bash
ruby health_publisher.rb 10  # Publish every 10 seconds instead of 5
```

### Add More Message Types

1. Create a new message class in `messages/` directory
2. Define properties with validation
3. Add subscriptions in the subscriber programs
4. Create a publisher to send the messages

### Modify Service Simulation

Edit `health_publisher.rb` to:
- Add more monitored services
- Change degradation timing
- Modify metrics generation
- Adjust status determination logic

## Troubleshooting

### Demo Window Already Open
If a demo window is already open:
- Switch to the existing window using `Cmd+`` (backtick) to cycle through windows
- Or run `./stop_demo.sh` to close it and start fresh

### Programs Not Stopping
If programs don't stop cleanly:
```bash
# Run the stop script which handles cleanup
./stop_demo.sh

# Or manually kill Ruby processes
pkill -f "health_publisher.rb"
pkill -f "acknowledging_subscriber.rb"
pkill -f "logging_subscriber.rb"
```

### iTerm2 Not Found
If you get an error about iTerm2 not being found:
```bash
# Install iTerm2 via Homebrew
brew install --cask iterm2

# Or download from https://iterm2.com/
```

### Permission Denied
If scripts won't execute:
```bash
chmod +x start_demo.sh stop_demo.sh
```

## Next Steps

This demo provides a foundation for understanding SmartMessage. You can extend it by:

1. Adding a WorkRequest publisher that sends job requests
2. Creating a SystemEvent publisher for application events
3. Implementing persistent message storage
4. Adding message retry logic for failed processing
5. Creating a web dashboard to visualize message flow
6. Implementing different transport backends (RabbitMQ, Kafka, etc.)