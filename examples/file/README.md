# SmartMessage FileTransport Examples

This directory contains comprehensive examples demonstrating the capabilities of SmartMessage's FileTransport class. The FileTransport provides powerful file-based messaging with support for multiple formats, FIFO operations, file watching, and advanced routing patterns.

## Quick Start

Run all examples:
```bash
ruby 00_run_all_file_demos.rb all
```

Run interactively:
```bash
ruby 00_run_all_file_demos.rb
```

## Examples Overview

### 1. Basic File Transport Demo (`01_basic_file_transport_demo.rb`)

**What it demonstrates:**
- Core FileTransport functionality
- Multiple output formats (JSON, YAML, raw)
- Append vs overwrite modes
- Custom serialization for CSV output
- File rotation concepts

**Key concepts:**
- Message persistence to files
- Format flexibility
- Custom serializers
- Write mode configuration

**Sample output:**
```ruby
# JSON format
{"level":"INFO","message":"Application started","timestamp":"2024-01-15T10:00:00Z","component":"main"}

# Custom CSV format
timestamp,user_id,action,details
2024-01-15T10:00:00Z,12345,login,"{:ip=>\"192.168.1.1\"}"
```

### 2. FIFO Transport Demo (`02_fifo_transport_demo.rb`)

**What it demonstrates:**
- Named pipes (FIFO) for inter-process communication
- Real-time message streaming
- Multiple writer processes to single reader
- Non-blocking FIFO operations
- Message filtering with FIFOs

**Key concepts:**
- Process-to-process messaging
- Real-time communication
- Concurrent access patterns
- System-level integration

**Requirements:**
- Unix-like system with `mkfifo` support
- Will be skipped automatically on unsupported systems

**Sample usage:**
```ruby
# Create FIFO transport
fifo_transport = SmartMessage::Transport::FileTransport.new(
  file_path: '/tmp/message_pipe.fifo',
  file_type: :fifo,
  format: :json
)
```

### 3. File Watching Demo (`03_file_watching_demo.rb`)

**What it demonstrates:**
- File change monitoring
- Configuration file watching
- Log rotation handling
- Multiple file monitoring
- Pattern-based content processing

**Key concepts:**
- Reactive file processing
- Configuration change detection
- Log aggregation patterns
- Real-time file monitoring

**Sample configuration:**
```ruby
# Watch for file changes
watching_transport = SmartMessage::Transport::FileTransport.new(
  file_path: 'application.log',
  enable_subscriptions: true,
  subscription_mode: :poll_changes,
  poll_interval: 0.5,
  read_from: :end
)
```

### 4. Multi-Transport File Demo (`04_multi_transport_file_demo.rb`)

**What it demonstrates:**
- Fan-out messaging to multiple files
- Conditional routing based on message content
- Combining FileTransport with other transports
- Archive and cleanup strategies
- Performance monitoring

**Key concepts:**
- Message routing patterns
- Multi-destination publishing
- Archive management
- Performance optimization

**Advanced patterns:**
```ruby
# Fan-out to multiple destinations
AuditEvent.configure do |config|
  config.transport = [
    main_transport,      # JSON format
    audit_transport,     # YAML format  
    backup_transport     # Custom format
  ]
end
```

## Demo Runner (`00_run_all_file_demos.rb`)

The demo runner provides multiple ways to explore the examples:

### Interactive Mode
```bash
ruby 00_run_all_file_demos.rb
```
- Menu-driven interface
- Run individual demos or all demos
- System requirement checking
- Automatic FIFO support detection

### Command Line Mode
```bash
# Run all demos
ruby 00_run_all_file_demos.rb all

# List available demos
ruby 00_run_all_file_demos.rb list

# Run specific demo
ruby 00_run_all_file_demos.rb 1
```

## System Requirements

- **Ruby**: 2.7 or later
- **Platform**: Cross-platform (Windows, macOS, Linux)
- **FIFO Support**: Unix-like systems for FIFO demos
- **Dependencies**: SmartMessage gem

## Key FileTransport Features Demonstrated

### File Operations
- ✅ Writing to regular files
- ✅ Append and overwrite modes
- ✅ Multiple output formats
- ✅ Custom serialization
- ✅ File rotation handling

### FIFO Operations
- ✅ Named pipe creation and usage
- ✅ Inter-process communication
- ✅ Blocking and non-blocking modes
- ✅ Multiple writers, single reader
- ✅ Real-time message streaming

### File Watching
- ✅ Change detection and monitoring
- ✅ Configuration file watching
- ✅ Log rotation awareness
- ✅ Multiple file monitoring
- ✅ Pattern-based processing

### Advanced Features
- ✅ Multi-transport configurations
- ✅ Message routing and filtering
- ✅ Performance monitoring
- ✅ Archive strategies
- ✅ Error handling

## Best Practices Shown

1. **Message Class Organization**
   - Store message classes in `messages/` directory
   - Use clear, descriptive property definitions
   - Include validation where appropriate

2. **Transport Configuration**
   - Choose appropriate formats for use case
   - Configure proper file modes
   - Handle cleanup in ensure blocks

3. **Error Handling**
   - Graceful degradation for unsupported features
   - Proper resource cleanup
   - Informative error messages

4. **Performance Considerations**
   - Appropriate polling intervals
   - Efficient serialization
   - Resource management

## Troubleshooting

### FIFO Not Supported
If you see "FIFOs are not supported on this system":
- This is expected on Windows
- FIFO demos will be automatically skipped
- Other demos will still work normally

### Permission Errors
If you encounter permission errors:
- Ensure write access to the demo directory
- Check that temporary directories can be created
- Verify file system supports the operations

### Performance Issues
If file operations seem slow:
- Adjust polling intervals in file watching demos
- Consider using smaller message sizes
- Check available disk space

## Next Steps

After exploring these examples:

1. **Adapt for Your Use Case**
   - Modify message classes for your domain
   - Adjust file formats and paths
   - Customize routing logic

2. **Integration Patterns**
   - Combine with other SmartMessage transports
   - Add to existing logging infrastructure
   - Build monitoring dashboards

3. **Production Considerations**
   - Add proper error handling
   - Implement log rotation
   - Monitor file system usage
   - Add authentication/authorization

## Related Examples

- `../memory/` - Memory transport examples
- `../redis/` - Redis transport examples  
- `../multi_transport_example.rb` - Cross-transport patterns

For more information, see the main SmartMessage documentation.