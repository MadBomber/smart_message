# Smart Home IoT Data Flow - Redis Pub/Sub Transport

This document describes the data flow architecture for the Smart Home IoT example using SmartMessage's Redis transport. The system demonstrates how multiple IoT devices communicate through Redis pub/sub channels with targeted message routing.

## System Architecture Overview

The smart home system consists of three types of IoT devices and a central dashboard, all communicating through Redis pub/sub channels. Each message type uses its own Redis channel for efficient routing and scaling.

![Smart Home System Architecture](smart_home_system_architecture.svg)

## Message Flow Details

### 1. Sensor Data Flow
All IoT devices continuously publish sensor readings to the `SensorDataMessage` Redis channel:

- **🌡️ Thermostat**: Temperature readings, battery level
- **📹 Camera**: Motion detection status, battery level  
- **🚪 Door Lock**: Lock/unlock status, battery level

**Example SensorDataMessage:**
```json
{
  "device_id": "THERM-001",
  "device_type": "thermostat", 
  "location": "living_room",
  "sensor_type": "temperature",
  "value": 22.5,
  "unit": "celsius",
  "timestamp": "2025-08-18T10:30:00Z",
  "battery_level": 85.2
}
```

### 2. Device Command Flow
The dashboard and external systems send commands to specific devices via the `DeviceCommandMessage` channel:

![Device Command Flow](device_command_flow.svg)

**Device Command Filtering Rules:**
- **THERM-*** devices: Accept `set_temperature`, `get_status`
- **CAM-*** devices: Accept `start_recording`, `stop_recording`, `get_status`
- **LOCK-*** devices: Accept `lock`, `unlock`, `get_status`

### 3. Alert System Flow
Devices publish critical notifications to the `AlertMessage` channel when conditions are detected:

![Alert System Flow](alert_system_flow.svg)

### 4. Dashboard Status Flow
The dashboard aggregates all system data and publishes periodic status updates:

![Dashboard Status Flow](dashboard_status_flow.svg)

## Channel-Based Architecture Benefits

### 1. **Efficient Message Routing**
Each message type uses its own Redis channel, preventing unnecessary message processing:

| Channel | Publishers | Subscribers | Purpose |
|---------|------------|-------------|---------|
| `SensorDataMessage` | All Devices | Dashboard | Real-time sensor readings |
| `DeviceCommandMessage` | Dashboard, Apps | All Devices | Device control commands |
| `AlertMessage` | All Devices | Dashboard | Critical notifications |
| `DashboardStatusMessage` | Dashboard | Dashboard, Apps | System status updates |

### 2. **Device-Specific Command Filtering**
Devices use prefix-based filtering to process only relevant commands:

```ruby
# Example: Thermostat command filtering
def self.handle_command(message_header, message_payload)
  command_data = JSON.parse(message_payload)
  
  # Only process commands for thermostats
  return unless command_data['device_id']&.start_with?('THERM-')
  return unless ['set_temperature', 'get_status'].include?(command_data['command'])
  
  # Process the command...
end
```

### 3. **Scalable Pub/Sub Pattern**
The architecture supports easy scaling:

- ✅ **Add new device types**: Just define new device ID prefixes
- ✅ **Add new message types**: Create new Redis channels as needed  
- ✅ **Multiple instances**: Each device can have multiple instances
- ✅ **Load balancing**: Redis handles distribution automatically

## Running the Example

To see this data flow in action:

```bash
# Ensure Redis is running
redis-server

# Run the IoT example
cd examples
ruby 04_redis_smart_home_iot.rb
```

**What you'll observe:**
1. **Device initialization** and Redis connection setup
2. **Sensor data publishing** every 3-5 seconds per device
3. **Command routing** with device-specific responses
4. **Alert generation** when motion is detected or conditions change
5. **Dashboard status updates** every 10 seconds showing active device counts

## Redis Channel Monitoring

You can monitor the Redis channels directly:

```bash
# View active channels
redis-cli PUBSUB CHANNELS

# Monitor all channel activity
redis-cli MONITOR

# Subscribe to specific channels
redis-cli SUBSCRIBE SensorDataMessage
redis-cli SUBSCRIBE DeviceCommandMessage
redis-cli SUBSCRIBE AlertMessage
redis-cli SUBSCRIBE DashboardStatusMessage
```

## Key Design Patterns Demonstrated

### 1. **Message Class as Channel Name**
SmartMessage automatically uses the message class name as the Redis channel name, providing clean separation.

### 2. **Device ID-Based Routing**
Commands are filtered by device ID prefixes, ensuring only intended devices process commands.

### 3. **Centralized Monitoring**
The dashboard subscribes to all channels, providing comprehensive system visibility.

### 4. **Event-Driven Alerts**
Devices autonomously generate alerts based on sensor readings and conditions.

### 5. **Graceful Degradation**
System falls back to memory transport if Redis is unavailable, ensuring development continues.

This architecture demonstrates production-ready IoT messaging patterns using Redis pub/sub for efficient, scalable device communication.