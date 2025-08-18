#!/bin/bash
# examples/tmux_chat/start_chat_demo.sh
#
# Tmux session manager for the many-to-many chat visualization

set -e

SESSION_NAME="smart_message_chat"
CHAT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting SmartMessage Tmux Chat Demo${NC}"
echo -e "${BLUE}======================================${NC}"

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo -e "${RED}❌ tmux is not installed. Please install tmux first.${NC}"
    echo "On macOS: brew install tmux"
    echo "On Ubuntu: sudo apt-get install tmux"
    exit 1
fi

# Check if Ruby is available
if ! command -v ruby &> /dev/null; then
    echo -e "${RED}❌ Ruby is not installed.${NC}"
    exit 1
fi

# Clean up any existing session
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
    echo -e "${YELLOW}🧹 Cleaning up existing session...${NC}"
    tmux kill-session -t $SESSION_NAME
fi

# Clean up shared message queues
echo -e "${YELLOW}🧹 Cleaning up message queues...${NC}"
rm -rf /tmp/smart_message_chat

echo -e "${GREEN}📺 Creating tmux session layout...${NC}"

# Create new session with first window
tmux new-session -d -s $SESSION_NAME -x 120 -y 40

# Rename first window and set up control center
tmux rename-window -t $SESSION_NAME:0 "Chat-Control"

# Window 0: Control Center (2x2 layout)
echo -e "${GREEN}🏢 Setting up Control Center...${NC}"

# Top left: General room monitor
tmux send-keys -t $SESSION_NAME:0 "cd '$CHAT_DIR'" C-m
tmux send-keys -t $SESSION_NAME:0 "ruby room_monitor.rb general" C-m

# Split horizontally for top right: Tech room monitor  
tmux split-window -t $SESSION_NAME:0 -h
tmux send-keys -t $SESSION_NAME:0.1 "cd '$CHAT_DIR'" C-m
tmux send-keys -t $SESSION_NAME:0.1 "ruby room_monitor.rb tech" C-m

# Split vertically (bottom left): Random room monitor
tmux split-window -t $SESSION_NAME:0.0 -v
tmux send-keys -t $SESSION_NAME:0.2 "cd '$CHAT_DIR'" C-m
tmux send-keys -t $SESSION_NAME:0.2 "ruby room_monitor.rb random" C-m

# Split vertically (bottom right): System overview
tmux split-window -t $SESSION_NAME:0.1 -v
tmux send-keys -t $SESSION_NAME:0.3 "cd '$CHAT_DIR'" C-m
tmux send-keys -t $SESSION_NAME:0.3 "echo 'SmartMessage Chat System'; echo '========================'; echo 'Rooms: general, tech, random'; echo 'Agents starting up...'; echo ''; echo 'Instructions:'; echo '1. Switch to other windows to see agents'; echo '2. In agent windows, type messages or commands'; echo '3. Use /join <room> to join rooms'; echo '4. Use /help for more commands'; tail -f /dev/null" C-m

# Wait a moment for room monitors to start
sleep 2

# Window 1: Human Agents (3 panes)
echo -e "${GREEN}👥 Setting up Human Agents...${NC}"
tmux new-window -t $SESSION_NAME -n "Human-Agents"

# Alice (left pane)
tmux send-keys -t $SESSION_NAME:1 "cd '$CHAT_DIR'" C-m
tmux send-keys -t $SESSION_NAME:1 "ruby human_agent.rb alice Alice" C-m

# Split for Bob (top right)
tmux split-window -t $SESSION_NAME:1 -h
tmux send-keys -t $SESSION_NAME:1.1 "cd '$CHAT_DIR'" C-m 
tmux send-keys -t $SESSION_NAME:1.1 "ruby human_agent.rb bob Bob" C-m

# Split for Carol (bottom right)
tmux split-window -t $SESSION_NAME:1.1 -v
tmux send-keys -t $SESSION_NAME:1.2 "cd '$CHAT_DIR'" C-m
tmux send-keys -t $SESSION_NAME:1.2 "ruby human_agent.rb carol Carol" C-m

# Wait for agents to start
sleep 2

# Window 2: Bot Agents (2 panes)  
echo -e "${GREEN}🤖 Setting up Bot Agents...${NC}"
tmux new-window -t $SESSION_NAME -n "Bot-Agents"

# HelpBot (left pane)
tmux send-keys -t $SESSION_NAME:2 "cd '$CHAT_DIR'" C-m
tmux send-keys -t $SESSION_NAME:2 "ruby bot_agent.rb helpbot HelpBot help,stats,time" C-m

# Split for FunBot (right pane)
tmux split-window -t $SESSION_NAME:2 -h
tmux send-keys -t $SESSION_NAME:2.1 "cd '$CHAT_DIR'" C-m
tmux send-keys -t $SESSION_NAME:2.1 "ruby bot_agent.rb funbot FunBot joke,weather,echo" C-m

# Wait for bots to start
sleep 2

# Auto-join agents to rooms for demo
echo -e "${GREEN}🏠 Auto-joining agents to rooms...${NC}"

# Alice joins general and tech
tmux send-keys -t $SESSION_NAME:1.0 "/join general" C-m
sleep 0.5
tmux send-keys -t $SESSION_NAME:1.0 "/join tech" C-m

# Bob joins general and random  
tmux send-keys -t $SESSION_NAME:1.1 "/join general" C-m
sleep 0.5
tmux send-keys -t $SESSION_NAME:1.1 "/join random" C-m

# Carol joins tech and random
tmux send-keys -t $SESSION_NAME:1.2 "/join tech" C-m  
sleep 0.5
tmux send-keys -t $SESSION_NAME:1.2 "/join random" C-m

# Bots join rooms
tmux send-keys -t $SESSION_NAME:2.0 "/join general" C-m
sleep 0.5
tmux send-keys -t $SESSION_NAME:2.0 "/join tech" C-m

tmux send-keys -t $SESSION_NAME:2.1 "/join general" C-m
sleep 0.5  
tmux send-keys -t $SESSION_NAME:2.1 "/join random" C-m

sleep 1

# Send some initial messages to demonstrate the system
echo -e "${GREEN}💬 Sending demo messages...${NC}"

tmux send-keys -t $SESSION_NAME:1.0 "Hello everyone! I'm Alice." C-m
sleep 1
tmux send-keys -t $SESSION_NAME:1.1 "Hi Alice! Bob here." C-m
sleep 1
tmux send-keys -t $SESSION_NAME:1.2 "Carol joining the conversation!" C-m
sleep 1
tmux send-keys -t $SESSION_NAME:1.0 "/help" C-m
sleep 2
tmux send-keys -t $SESSION_NAME:1.1 "/joke" C-m
sleep 2

# Set focus to Human Agents window
tmux select-window -t $SESSION_NAME:1

echo -e "${GREEN}✅ Chat demo is ready!${NC}"
echo ""
echo -e "${BLUE}Navigation:${NC}"
echo "• Ctrl+b then 0: Control Center (room monitors)"  
echo "• Ctrl+b then 1: Human Agents (Alice, Bob, Carol)"
echo "• Ctrl+b then 2: Bot Agents (HelpBot, FunBot)"
echo "• Ctrl+b then o: Cycle through panes"
echo "• Ctrl+b then arrow keys: Navigate panes"
echo ""
echo -e "${BLUE}Commands in agent panes:${NC}"
echo "• /join <room>: Join a room"
echo "• /leave <room>: Leave a room"  
echo "• /list: List your active rooms"
echo "• /help: Show available commands"
echo "• /quit: Exit the agent"
echo ""
echo -e "${BLUE}Bot commands:${NC}"
echo "• /help: Show bot capabilities"
echo "• /joke: Get a random joke"
echo "• /weather <location>: Get weather"
echo "• /stats: Show bot statistics"
echo "• /time: Show current time"
echo "• /echo <message>: Echo your message"
echo ""
echo -e "${YELLOW}💡 Tip: Type messages directly to chat in your active rooms!${NC}"
echo ""
echo -e "${GREEN}🎭 Attaching to tmux session...${NC}"

# Attach to the session
tmux attach-session -t $SESSION_NAME