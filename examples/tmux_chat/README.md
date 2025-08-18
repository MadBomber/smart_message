# SmartMessage Tmux Chat Visualization

This is an enhanced version of the many-to-many chat example that uses tmux to provide a clear, visual representation of the messaging interactions between different agents across multiple chat rooms.

## Overview

Instead of having all output mixed together in a single terminal, this tmux version separates:

- **Room Monitors**: Visual displays showing activity in each chat room
- **Human Agents**: Interactive chat clients for simulated users
- **Bot Agents**: Automated responders with various capabilities

## Layout

The tmux session creates three windows:

### Window 0: Chat Control Center (2x2 grid)
```
┌─────────────────┬─────────────────┐
│   General Room  │    Tech Room    │
│     Monitor     │     Monitor     │
├─────────────────┼─────────────────┤
│   Random Room   │  System Info &  │
│     Monitor     │   Instructions  │
└─────────────────┴─────────────────┘
```

### Window 1: Human Agents (3 panes)
```
┌─────────────────┬─────────────────┐
│                 │      Bob        │
│     Alice       ├─────────────────┤
│                 │     Carol       │
└─────────────────┴─────────────────┘
```

### Window 2: Bot Agents (2 panes)
```
┌─────────────────┬─────────────────┐
│    HelpBot      │    FunBot       │
│                 │                 │
└─────────────────┴─────────────────┘
```

## Features

### Room Monitors
Each room monitor shows:
- Real-time message activity for that specific room
- User join/leave notifications
- Command detections
- Activity status (active/quiet/inactive)
- Message count and participant statistics

### Human Agents
Interactive chat clients with:
- Command support (`/join`, `/leave`, `/list`, `/help`, `/quit`)
- Multi-room messaging
- Auto-response to mentions
- Real-time message display

### Bot Agents
Automated agents with capabilities like:
- **HelpBot**: `/help`, `/stats`, `/time`
- **FunBot**: `/joke`, `/weather`, `/echo`
- Keyword responses (hello, help, thank you)
- Command processing with visual feedback

## Quick Start

### Prerequisites
- tmux installed (`brew install tmux` on macOS)
- Ruby with SmartMessage gem
- Terminal with decent size (recommended: 120x40 or larger)

### Running the Demo

```bash
# Start the entire chat system
cd examples/tmux_chat
./start_chat_demo.sh
```

### Navigation

Once in tmux:

**Switch Between Windows:**
- **Ctrl+b then 0**: Switch to Control Center (room monitors)
- **Ctrl+b then 1**: Switch to Human Agents (Alice, Bob, Carol)
- **Ctrl+b then 2**: Switch to Bot Agents (HelpBot, FunBot)

**Move Between Panes (within a window):**
- **Ctrl+b then o**: Cycle through all panes in current window
- **Ctrl+b then arrow keys**: Move directly to pane in that direction (↑↓←→)
- **Ctrl+b then ;**: Toggle between current and last pane

**Other Useful Commands:**
- **Ctrl+b then z**: Zoom current pane (toggle fullscreen)
- **Ctrl+b then d**: Detach from session (keeps it running)
- **Ctrl+b then ?**: Show all tmux commands

### Getting Started Workflow

1. **After starting the demo**, you'll be in the Human Agents window (window 1)
2. **Look for the active pane** (has colored border) - usually Alice's pane
3. **Start typing immediately** - you're in the chat interface, not bash
4. **Try these first commands:**
   ```
   /join general
   Hello everyone!
   /help
   ```
5. **Switch to other agents** using `Ctrl+b then o` to see different perspectives
6. **Watch room activity** by switching to Control Center: `Ctrl+b then 0`

### Interacting with Agents

In any human agent pane (Alice, Bob, Carol):
```bash
# Join rooms
/join general
/join tech
/join random

# Send messages (goes to all your active rooms)
Hello everyone!

# Use bot commands
/help
/joke
/weather Tokyo
/stats

# Mention other users
@alice how are you?

# Leave rooms
/leave tech

# Exit
/quit
```

### Stopping the Demo

```bash
# From outside tmux
./stop_chat_demo.sh

# Or from inside tmux
Ctrl+b then d  # Detach
./stop_chat_demo.sh
```

## Architecture

### File-Based Transport

This example uses a custom `FileTransport` that:
- Writes messages to room-specific queue files in `/tmp/smart_message_chat/`
- Polls files for new messages
- Enables inter-process communication between tmux panes
- Cleans up automatically on shutdown

### Message Types

Three types of messages flow through the system:

1. **ChatMessage**: Regular chat messages
2. **BotCommandMessage**: Commands directed to bots
3. **SystemNotificationMessage**: Join/leave/system events

### Agent Types

- **BaseAgent**: Common functionality for all agents
- **HumanChatAgent**: Interactive user simulation
- **BotChatAgent**: Automated response agents
- **RoomMonitor**: Display-only room activity monitors

## Advantages Over Single-Terminal Version

### Visual Clarity
- **Room Separation**: See each room's activity independently
- **Agent Separation**: Each agent has its own display space
- **Real-time Updates**: Monitors show live activity as it happens

### Better Understanding
- **Message Flow**: Clearly see how messages route between rooms
- **Agent Behavior**: Watch how different agents respond to events
- **System Dynamics**: Observe the many-to-many messaging patterns

### Interactive Experience
- **Multiple Perspectives**: Switch between different agent viewpoints
- **Live Interaction**: Type and send messages in real-time
- **System Monitoring**: Watch room activity while participating

## Example Workflow

1. **Start the demo**: `./start_chat_demo.sh`
2. **Watch the Control Center**: See rooms come online and initial messages
3. **Switch to Human Agents**: Navigate to Alice, Bob, or Carol
4. **Join rooms**: Use `/join general` to participate
5. **Send messages**: Type anything to chat in your active rooms
6. **Try bot commands**: Use `/joke`, `/weather`, `/help`
7. **Watch interactions**: Switch back to Control Center to see message flow
8. **Monitor bots**: Check Bot Agents window to see bot responses

## Customization

### Adding New Rooms
Edit `start_chat_demo.sh` to add more room monitors:
```bash
tmux new-window -t $SESSION_NAME -n "New-Room"
tmux send-keys "ruby room_monitor.rb newroom" C-m
```

### Adding New Agents
Create additional panes:
```bash
tmux split-window -t $SESSION_NAME:1 -v
tmux send-keys "ruby human_agent.rb david David" C-m
```

### Custom Bot Capabilities
Modify `bot_agent.rb` or create new bots:
```bash
ruby bot_agent.rb mybot MyBot "custom,commands,here"
```

## Troubleshooting

### Common Issues

**Tmux not found**:
```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt-get install tmux
```

**Messages not appearing**:
- Check that `/tmp/smart_message_chat/` directory exists
- Verify agents have joined the same rooms
- Try stopping and restarting the demo

**Pane too small**:
- Resize terminal window to at least 120x40
- Use `Ctrl+b then z` to zoom a pane temporarily

**Agents not responding**:
- Check that agents are in the same rooms (`/list` command)
- Verify bot capabilities match the commands being used

**Agents crash with console errors**:
- Fixed in latest version - agents now handle missing IO.console gracefully
- If issues persist, check Ruby version and terminal compatibility

### Manual Cleanup

If the automatic cleanup doesn't work:
```bash
# Kill tmux session
tmux kill-session -t smart_message_chat

# Remove message queues
rm -rf /tmp/smart_message_chat
```

## Educational Value

This visualization helps understand:

- **Many-to-many messaging patterns**
- **Room-based routing and filtering** 
- **Agent coordination and communication**
- **Event-driven architecture**
- **Real-time system monitoring**
- **Service discovery and capabilities**

Perfect for demonstrating SmartMessage's power in complex, distributed scenarios!