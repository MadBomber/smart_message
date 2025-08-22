#!/bin/bash

# SmartMessage City Demo Launcher for iTerm2
# Creates a new iTerm2 window with separate tabs for each city service

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if iTerm2 is available
if ! ls /Applications/iTerm.app &>/dev/null; then
    echo "Error: iTerm2 is not installed."
    echo "Please install iTerm2 from https://iterm2.com/"
    exit 1
fi

echo "Starting SmartMessage City Demo in iTerm2..."

# Create the iTerm2 window and tabs using AppleScript
osascript <<EOF
tell application "iTerm2"
    activate
    
    -- Create new window
    set newWindow to (create window with default profile)
    
    -- Tab 1: Health Department (already created)
    tell current session of current tab of newWindow
        set name to "Health Department"
        write text "cd '$DEMO_DIR'"
        write text "clear"
        write text "echo 'Starting Health Department...'"
        write text "ruby health_department.rb"
    end tell
    
    -- Tab 2: Police Department
    tell newWindow
        set newTab to (create tab with default profile)
        tell current session of newTab
            set name to "Police Department"
            write text "cd '$DEMO_DIR'"
            write text "clear"
            write text "echo 'Starting Police Department...'"
            write text "ruby police_department.rb"
        end tell
    end tell
    
    -- Tab 3: Fire Department
    tell newWindow
        set newTab to (create tab with default profile)
        tell current session of newTab
            set name to "Fire Department"
            write text "cd '$DEMO_DIR'"
            write text "clear"
            write text "echo 'Starting Fire Department...'"
            write text "ruby fire_department.rb"
        end tell
    end tell
    
    -- Tab 4: Local Bank
    tell newWindow
        set newTab to (create tab with default profile)
        tell current session of newTab
            set name to "Local Bank"
            write text "cd '$DEMO_DIR'"
            write text "clear"
            write text "echo 'Starting Local Bank...'"
            write text "ruby local_bank.rb"
        end tell
    end tell
    
    -- Tab 5: House #1
    tell newWindow
        set newTab to (create tab with default profile)
        tell current session of newTab
            set name to "House #1"
            write text "cd '$DEMO_DIR'"
            write text "clear"
            write text "echo 'Starting House #1...'"
            write text "ruby house.rb '456 Oak Street'"
        end tell
    end tell
    
    -- Tab 6: House #2
    tell newWindow
        set newTab to (create tab with default profile)
        tell current session of newTab
            set name to "House #2"
            write text "cd '$DEMO_DIR'"
            write text "clear"
            write text "echo 'Starting House #2...'"
            write text "ruby house.rb '789 Pine Lane'"
        end tell
    end tell
    
    -- Tab 7: Redis Monitor
    tell newWindow
        set newTab to (create tab with default profile)
        tell current session of newTab
            set name to "Redis Monitor"
            write text "cd '$DEMO_DIR'"
            write text "clear"
            write text "echo 'Starting Redis Message Monitor...'"
            write text "ruby redis_monitor.rb"
        end tell
    end tell
    
    -- Tab 8: Redis Statistics
    tell newWindow
        set newTab to (create tab with default profile)
        tell current session of newTab
            set name to "Redis Statistics"
            write text "cd '$DEMO_DIR'"
            write text "clear"
            write text "echo 'Starting Redis Statistics Dashboard...'"
            write text "ruby redis_stats.rb"
        end tell
    end tell
    
    -- Tab 9: Control Panel
    tell newWindow
        set newTab to (create tab with default profile)
        tell current session of newTab
            set name to "Control Panel"
            write text "cd '$DEMO_DIR'"
            write text "clear"
            write text "cat << 'CONTROL_PANEL_EOF'
===== SmartMessage City Demo Control Panel =====

CITY SERVICES:
  Tab 1: Health Department (broadcasts health checks every 5s)
  Tab 2: Police Department (responds to bank alarms)
  Tab 3: Fire Department (responds to house fires)
  Tab 4: Local Bank (occasional silent alarms)
  Tab 5: House #1 (456 Oak Street)
  Tab 6: House #2 (789 Pine Lane)
  Tab 7: Redis Monitor (real-time message traffic)
  Tab 8: Redis Statistics (performance dashboard)
  Tab 9: Control Panel (this tab)

CONTROLS:
  ./stop_demo.sh     - Stop all city services
  Cmd+W             - Close current tab
  Cmd+1,2,3,4,5,6,7,8,9 - Switch to tab
  Ctrl+C            - Stop service in current tab

MESSAGE FLOWS:
  Health Checks: Health Dept -> All Services
  Health Status: All Services -> Health Dept (colored output)
  Bank Alarms:   Bank -> Police (silent alarm system)
  House Fires:   Houses -> Fire Dept (emergency response)
  Emergencies:   All -> Health Dept (incident resolution)

WHAT TO WATCH:
  Tab 1: Health status with GREEN/YELLOW/ORANGE/RED colors
  Tab 2: Police dispatching units to bank robberies
  Tab 3: Fire trucks responding to house fires
  Tab 4: Bank triggering occasional silent alarms
  Tab 5/6: Houses occasionally catching fire
  Tab 7: Real-time Redis message traffic (color-coded)
  Tab 8: Redis performance metrics & pub/sub statistics

STATUS COLORS:
  🟢 Green: healthy    🟡 Yellow: warning
  🟠 Orange: critical  🔴 Red: failed

Ready! Watch the city come alive with emergency services!
========================================================
CONTROL_PANEL_EOF"
        end tell
    end tell
    
    -- Switch back to first tab
    tell newWindow
        select (first tab)
    end tell
    
end tell
EOF


if [ $? -eq 0 ]; then
    echo ""
    echo "✅ City Demo started successfully in iTerm2!"
    echo ""
    echo "🏥 Tab 1: Health Department - monitors all city services"
    echo "🚔 Tab 2: Police Department - responds to bank alarms"
    echo "🚒 Tab 3: Fire Department - responds to house fires"
    echo "🏦 Tab 4: Local Bank - triggers occasional alarms"
    echo "🏠 Tab 5/6: Houses - occasionally catch fire"
    echo "🔍 Tab 7: Redis Monitor - real-time message traffic"
    echo "📊 Tab 8: Redis Statistics - performance dashboard"
    echo ""
    echo "📱 Use Cmd+1,2,3,4,5,6,7,8,9 to switch between tabs"
    echo "🛑 Run ./stop_demo.sh to stop all services"
    echo ""
    echo "🌟 Watch Tab 1 for colored health status updates!"
    echo "🔍 Check Tab 7 for real-time message traffic & Tab 8 for Redis stats!"
else
    echo "❌ Failed to start demo. Please check that iTerm2 is installed and running."
    exit 1
fi