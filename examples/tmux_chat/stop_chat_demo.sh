#!/bin/bash
# examples/tmux_chat/stop_chat_demo.sh
#
# Cleanup script for the tmux chat demo

SESSION_NAME="smart_message_chat"

echo "🧹 Stopping SmartMessage Tmux Chat Demo..."

# Kill the tmux session if it exists
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
    echo "🔴 Terminating tmux session..."
    tmux kill-session -t $SESSION_NAME
else
    echo "ℹ️  No active tmux session found."
fi

# Clean up shared message queues
echo "🗑️  Cleaning up message queues..."
rm -rf /tmp/smart_message_chat

echo "✅ Cleanup complete!"