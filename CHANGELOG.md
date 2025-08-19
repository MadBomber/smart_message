# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.6] 2025-08-19

### Added
- **Entity-Aware Message Filtering**: Advanced subscription filtering system enabling precise message routing
  - New subscription filter parameters: `broadcast:`, `to:`, `from:` for `subscribe` method
  - Filter by broadcast messages only: `MyMessage.subscribe(broadcast: true)`
  - Filter by destination entity: `MyMessage.subscribe(to: 'service-name')`
  - Filter by sender entity: `MyMessage.subscribe(from: 'sender-service')`
  - Support for array-based filters: `subscribe(from: ['admin', 'system'])`
  - Combined filters with OR logic: `subscribe(broadcast: true, to: 'my-service')`
  - String-to-array automatic conversion for convenience: `subscribe(to: 'service')` becomes `['service']`
  - Full backward compatibility - existing subscriptions work unchanged
- **Real-Time Header Synchronization**: Message headers now update automatically when addressing fields change
  - Instance-level `from()`, `to()`, `reply_to()` methods now update both instance variables and message headers
  - Enables filtering to work correctly when addressing is changed after message creation
  - Reset methods (`reset_from`, `reset_to`, `reset_reply_to`) also update headers
  - Critical for entity-aware filtering functionality
- **Enhanced Example Programs**
  - New comprehensive filtering example: `examples/08_entity_addressing_with_filtering.rb`
  - Demonstrates all filtering capabilities with real-world microservice scenarios
  - Improved timing with sleep statements for better output visualization
  - Updated basic addressing example: `examples/08_entity_addressing_basic.rb`
  - Both examples now show clear interleaved publish/receive output flow

### Changed
- **Message Subscription Architecture**: Subscription storage updated to support filtering
  - Dispatcher now stores subscription objects with filter criteria instead of simple method strings
  - Subscription objects contain `{process_method: string, filters: hash}` structure
  - All transport implementations updated to pass filter options through subscription chain
  - RedisTransport updated to accept new filter_options parameter
- **Header Addressing Behavior**: Message headers now reflect real-time addressing changes
  - **BREAKING**: Headers are no longer immutable after creation - they update when addressing methods are called
  - This change enables entity-aware filtering to work correctly with dynamic addressing
  - Previous behavior kept original addressing in headers while instance methods showed new values

### Fixed
- **Message Filtering Logic**: Resolved critical filtering implementation issues
  - Fixed message_matches_filters? method to properly evaluate filter criteria
  - Corrected AND/OR logic for combined broadcast and entity-specific filters
  - Ensured filtering works with both class-level and instance-level addressing
- **Test Suite Compatibility**: Updated all tests to work with new subscription structure
  - Fixed ProcHandlerTest to expect subscription objects instead of string arrays
  - Updated TransportTest to handle new subscription object format
  - Fixed AddressingTest to reflect new real-time header update behavior
  - All existing functionality preserved with full backward compatibility

### Enhanced
- **Message Processing Performance**: Filtering happens at subscription level, reducing processing overhead
  - Messages not matching filter criteria are ignored by handlers, improving efficiency
  - Enables microservices to process only relevant messages
  - Reduces unnecessary handler invocations and processing cycles
- **Developer Experience**: Clear examples demonstrate filtering benefits and usage patterns
  - Examples show both what DOES and DOESN'T get processed
  - Demonstrates gateway patterns, admin message handling, and microservice communication
  - Educational value enhanced with comprehensive console output and timing

### Documentation
- **Entity-Aware Filtering Guide**: Comprehensive examples showing all filtering capabilities
  - Broadcast vs directed message handling patterns
  - Admin/monitoring system integration examples
  - Request-reply routing with filters
  - Gateway pattern implementations with dynamic routing
  - Best practices for microservice message filtering
- **Breaking Change Documentation**: Clear explanation of header behavior changes
  - Migration guide for applications depending on immutable headers
  - Benefits of real-time header updates for filtering functionality

## [0.0.5] 2025-08-18

### Added
- **Enhanced Description DSL**: Extended class-level `description` method with automatic defaults
  - Classes without explicit descriptions now automatically get `"ClassName is a SmartMessage"` default
  - Instance method `message.description` provides access to class description
  - Backward compatible with existing description implementations
  - Improves developer experience by eliminating nil description values
- **Comprehensive Error Handling Example** (`examples/07_error_handling_scenarios.rb`)
  - Demonstrates missing required property validation with detailed error messages
  - Shows custom property validation failures with multiple validation types (regex, range, enum, proc)
  - Illustrates version mismatch detection between message classes and headers
  - **NEW**: Documents Hashie::Dash limitation where only first missing required property is reported
  - Provides educational content about SmartMessage's robust validation framework
  - Includes suggestions for potential improvements to multi-property validation
- **Complete Property Documentation**: All examples now include comprehensive descriptions
  - Message class descriptions added to all example programs (01-06 + tmux_chat)
  - Individual property descriptions added with detailed explanations of purpose and format
  - Enhanced readability and educational value of all demonstration code
  - Consistent documentation patterns across all messaging scenarios

### Fixed
- **Critical: Infinite Loop Bug in Chat Examples**
  - Fixed infinite message loops in `examples/03_many_to_many_chat.rb` and `examples/tmux_chat/bot_agent.rb`
  - **Root Cause**: Bots responding to other bots' messages containing trigger keywords ("hello", "hi")
  - **Solution**: Added `return if chat_data['message_type'] == 'bot'` to prevent bot-to-bot responses
  - Examples now terminate properly without requiring manual intervention
  - Maintains proper bot functionality for human interactions and explicit commands
- **Example Termination**: Chat examples now shutdown cleanly without hanging indefinitely

### Changed
- **Enhanced Documentation Coverage**
  - Updated README.md with comprehensive description DSL documentation
  - Enhanced `docs/properties.md` with updated class description behavior and default handling
  - Updated `docs/getting-started.md`, `docs/architecture.md`, and `docs/examples.md` with description examples
  - All documentation now demonstrates proper message and property description usage
- **Improved Example Educational Value**
  - All example programs enhanced with descriptive class and property documentation
  - Better demonstration of SmartMessage's self-documenting capabilities
  - Examples serve as both functional demonstrations and documentation references

### Documentation
- **Hashie::Dash Limitation Discovery**: Documented important framework limitation in error handling example
  - Only first missing required property reported during validation failures
  - Provides clear explanation of incremental error discovery behavior
  - Suggests potential solutions for improved multi-property validation
- **Comprehensive Description System**: Complete documentation of message documentation capabilities
  - Class-level description DSL with automatic defaults
  - Property-level descriptions with usage patterns
  - Integration with existing SmartMessage validation and introspection systems

## [0.0.2] - 2025-08-17

### Added
- **Property Descriptions**: New property-level description system for message documentation
  - Add descriptions to individual properties using `property :name, description: "text"`
  - Access descriptions programmatically via `property_description(:name)` method
  - Get all property descriptions with `property_descriptions` method
  - List properties with descriptions using `described_properties` method
  - Implemented via new `SmartMessage::PropertyDescriptions` module
- **Class-Level Descriptions**: New message class documentation system
  - Set class descriptions using `description "text"` class method
  - Retrieve descriptions with `MyMessage.description`
  - Can be set within config blocks or after class definition
  - Useful for API documentation and code generation tools
- **Enhanced Documentation**
  - Added comprehensive property system documentation (`docs/properties.md`)
  - Documents all Hashie::Dash options and SmartMessage enhancements
  - Includes examples of property transformations, coercions, and translations
  - Added to documentation table of contents

### Changed
- Updated README.md with property and class description examples
- Enhanced SmartMessage::Base with property introspection capabilities

### Tests
- Added comprehensive test suite for property descriptions (`test/property_descriptions_test.rb`)
- Added test suite for class-level descriptions (`test/description_test.rb`)
- Updated base_test.rb with class description test cases
- All tests passing with full backward compatibility

## [0.0.1] - 2025-08-17

### Added
- Comprehensive example applications demonstrating different messaging patterns
  - Point-to-point order processing example (`examples/01_point_to_point_orders.rb`)
  - Publish-subscribe event broadcasting example (`examples/02_publish_subscribe_events.rb`)
  - Many-to-many chat system example (`examples/03_many_to_many_chat.rb`)
- Interactive tmux-based visualization system for many-to-many messaging
  - File-based transport for inter-process communication (`examples/tmux_chat/`)
  - Human chat agents with interactive command support
  - Automated bot agents with joke, weather, stats, and help capabilities
  - Real-time room activity monitors with visual status updates
  - Complete tmux session management with automated setup and cleanup
  - Comprehensive documentation with navigation instructions
- Development documentation and project guidance
  - Added `CLAUDE.md` with development commands and architecture overview
  - Enhanced README with comprehensive usage examples and API documentation

### Changed
- **BREAKING**: Updated all public method signatures to use modern Ruby 3.4 keyword arguments
  - `initialize` methods now use `**props` instead of `props = {}`
  - Transport creation methods updated to use keyword argument expansion
  - Maintained backward compatibility where possible
- Improved gem metadata with links to changelog, bug tracker, and documentation
- Enhanced error handling and console compatibility across different Ruby environments
- Updated transport terminology throughout codebase for consistency

### Fixed
- IO.console compatibility issues in tmux chat visualization components
- Method signature consistency for keyword arguments across all transport classes
- Console detection and graceful fallbacks for terminal size detection
- Message processing error handling in dispatcher components

### Documentation
- Complete architectural overview in `CLAUDE.md`
- Step-by-step usage examples for all messaging patterns
- Tmux navigation and interaction guides
- Development workflow and testing instructions
- API documentation with method signatures and examples

### Examples
- **Point-to-Point**: Order processing with payment service integration
- **Publish-Subscribe**: User event broadcasting to multiple services (email, SMS, audit)
- **Many-to-Many**: Interactive chat system with rooms, bots, and human agents
- **Tmux Visualization**: Advanced multi-pane terminal interface for real-time message flow observation

## [0.0.1] - 2025-08-17

### Added
- Complete rewrite with transport abstraction layer
- Concurrent message processing with thread pools using `Concurrent::CachedThreadPool`
- Plugin registry system for transports and serializers
- Built-in statistics collection via SimpleStats
- Memory and STDOUT transport implementations
- Comprehensive test suite using Minitest with Shoulda
- Dual-level plugin configuration (class and instance level)
- Message header system with UUID, timestamps, and process tracking
- Gateway pattern support for cross-transport message routing
- Thread-safe message dispatcher with graceful shutdown
- Pluggable serialization system with JSON implementation
- Transport registry for dynamic plugin discovery

### Changed
- Migrated from legacy Broker concept to modern Transport abstraction
- Updated dependencies to remove version constraints
- Improved error handling and custom exception types

### Technical Details
- Built on Hashie::Dash with extensive extensions
- Uses ActiveSupport for string inflections
- Concurrent-ruby for thread pool management
- Supports Ruby >= 3.0.0

---

## Guidelines for Contributors

When updating this changelog:

1. **Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format**
2. **Use these categories in order:**
   - `Added` for new features
   - `Changed` for changes in existing functionality
   - `Deprecated` for soon-to-be removed features
   - `Removed` for now removed features
   - `Fixed` for any bug fixes
   - `Security` for vulnerability fixes
3. **Add entries to [Unreleased] section** until ready for release
4. **Use present tense** ("Add feature" not "Added feature")
5. **Include breaking changes** in `Changed` section with **BREAKING** prefix
6. **Link to issues/PRs** when relevant: `[#123](https://github.com/MadBomber/smart_message/issues/123)`
