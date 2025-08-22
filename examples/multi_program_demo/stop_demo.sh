#!/bin/bash

# SmartMessage City Demo Shutdown Script for iTerm2
# Stops all city services and closes the iTerm2 demo window

echo "Stopping SmartMessage City Demo..."

# Check if iTerm2 is running  
if ! pgrep -f "iTerm2" > /dev/null; then
    echo "iTerm2 is not running."
    exit 0
fi

# Function to find and close demo window
echo "Looking for SmartMessage city demo window in iTerm2..."

WINDOW_CLOSED=$(osascript <<'EOF'
tell application "iTerm2"
    set windowFound to false
    
    repeat with theWindow in windows
        tell theWindow
            set tabNames to {}
            repeat with theTab in tabs
                set end of tabNames to (name of current session of theTab)
            end repeat
            
            -- Check if this window has our city demo tabs
            if "Health Department" is in tabNames or "Police Department" is in tabNames or "Fire Department" is in tabNames or "Local Bank" is in tabNames then
                set windowFound to true
                
                -- Send Ctrl+C to stop programs
                repeat with theTab in tabs
                    tell current session of theTab
                        write text (character id 3) -- Ctrl+C
                    end tell
                end repeat
                
                delay 2
                close theWindow
                exit repeat
            end if
        end tell
    end repeat
    
    return windowFound
end tell
EOF
)

if [ "$WINDOW_CLOSED" = "true" ]; then
    echo "✅ City demo window found and closed successfully."
else
    echo "⚠️  No city demo window found. Checking for orphaned processes..."
fi

# Clean up any remaining city service processes
echo "Checking for remaining city service processes..."

ORPHANS=$(pgrep -f "(health_department|police_department|fire_department|local_bank|house)\.rb")

if [ -n "$ORPHANS" ]; then
    echo "Found orphaned city service processes. Cleaning up..."
    echo "$ORPHANS" | while read pid; do
        echo "  Stopping process $pid..."
        kill -TERM "$pid" 2>/dev/null || true
    done
    
    # Wait a moment for graceful termination
    sleep 1
    
    # Force kill any remaining processes
    REMAINING=$(pgrep -f "(health_department|police_department|fire_department|local_bank|house)\.rb")
    if [ -n "$REMAINING" ]; then
        echo "Force killing remaining processes..."
        echo "$REMAINING" | while read pid; do
            echo "  Force killing process $pid..."
            kill -KILL "$pid" 2>/dev/null || true
        done
    fi
    
    echo "✅ Orphaned processes cleaned up."
else
    echo "✅ No orphaned processes found."
fi

echo ""
echo "🛑 SmartMessage city demo has been stopped."
echo "   All emergency services are offline."
echo ""
echo "💡 To start the city demo again, run: ./start_demo.sh"