# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.15] 2025-09-10

### Added
- **Multi-Transport Publishing**: Messages can now be configured to publish to multiple transports simultaneously
  - **Core Feature**: Configure messages with an array of transports using `transport [transport1, transport2, transport3]` syntax
  - **Resilient Publishing**: Publishing succeeds if ANY configured transport works; only fails if ALL transports fail
  - **Error Handling**: Individual transport failures are logged but don't prevent publishing to remaining transports
  - **Backward Compatibility**: Single transport configuration continues to work unchanged (`transport single_transport`)
  - **Utility Methods**: Added `transports()`, `single_transport?()`, and `multiple_transports?()` for transport introspection
  - **Use Cases**: Supports redundancy, integration, migration, and fan-out messaging patterns

### Enhanced
- **Transport Configuration API**: Extended transport configuration methods to handle both single transports and transport arrays
  - **Plugins Module**: Updated `transport()` method in `lib/smart_message/plugins.rb` to accept arrays while maintaining backward compatibility
  - **Internal Storage**: Transport arrays stored internally but `transport()` getter returns first transport for existing code compatibility
  - **Instance Overrides**: Instance-level transport configuration can override class-level multi-transport settings
- **Publishing Pipeline**: Enhanced message publishing in `lib/smart_message/messaging.rb` for multi-transport support
  - **Parallel Publishing**: Iterates through all configured transports and publishes to each
  - **Comprehensive Logging**: Logs successful and failed transports with detailed error information
  - **Error Aggregation**: Collects all transport errors and raises `PublishError` only when all transports fail
  - **Success Tracking**: Continues processing even when individual transports fail

### Added - Error Handling
- **PublishError**: New error class `SmartMessage::Errors::PublishError` for multi-transport failure scenarios
  - **Condition**: Only raised when ALL configured transports fail to publish
  - **Error Detail**: Aggregates error messages from all failed transports for comprehensive debugging
  - **Added to**: `lib/smart_message/errors.rb`

### Added - Documentation
- **Comprehensive Guide**: Created `docs/transports/multi-transport.md` with complete multi-transport documentation
  - **Real-World Examples**: High-availability, development/production dual publishing, monitoring integration, A/B testing
  - **Best Practices**: Performance considerations, environment-specific configuration, health monitoring
  - **Troubleshooting**: Common issues, debugging techniques, and solutions
- **Integration Updates**: Updated main transport documentation and index to reference multi-transport capability
  - **Transport Layer**: Added multi-transport section to `docs/reference/transports.md`
  - **Table of Contents**: Added multi-transport link to main documentation index

### Added - Testing
- **Comprehensive Test Suite**: Created `test/multi_transport_test.rb` with 12 test cases covering all functionality
  - **Backward Compatibility**: Verified single transport behavior remains unchanged
  - **Multi-Transport Scenarios**: Tests for successful publishing, partial failures, complete failures
  - **Configuration Testing**: Class vs instance configuration, transport introspection, method chaining
  - **Mock Transports**: Added `FailingTransport` and `CountingTransport` for controlled testing
  - **Integration Tests**: Real transport combinations (Memory + STDOUT)

### Added - Examples
- **README Integration**: Added multi-transport example to main README.md with practical use case
  - **Features Section**: Added multi-transport publishing bullet point to feature list
  - **Transport Implementations**: Complete section with `CriticalOrderMessage` example showing 3 transports
  - **Key Benefits**: Highlighted redundancy, integration, migration, and resilience benefits
- **Example File**: Created `examples/multi_transport_example.rb` demonstrating all multi-transport functionality
  - **Usage Patterns**: Single transport (backward compatibility), multiple transports, instance overrides
  - **Error Scenarios**: Partial transport failure resilience and complete failure handling
  - **Utility Demonstrations**: Transport counting, type checking, and configuration inspection

## [0.0.14] 2025-09-10

### Fixed
- **Configuration Architecture**: Fixed `SmartMessage::Serializer.default` method to properly reflect transport-owned serialization architecture
  - **Issue**: `SmartMessage::Serializer.default` was trying to access a non-existent `default_serializer` method on global configuration
  - **Root Cause**: Serialization belongs to transports, not global configuration, but the method was attempting to check global config first
  - **Solution**: Updated method to return framework default (`SmartMessage::Serializer::Json`) directly without depending on global configuration
  - **Architecture Clarification**: Each transport owns and configures its own serializer (line 19 in transport/base.rb: `@serializer = options[:serializer] || default_serializer`)
  - **Demo Fix**: Updated `examples/memory/14_global_configuration_demo.rb` to remove incorrect `config.serializer =` attempts and added architecture comments
- **Test Method Signatures**: Completed wrapper-to-message architecture transition by fixing remaining method signature issues
  - **dispatcher_test.rb**: Changed `processer_one` and `processer_two` from instance methods to class methods (`def self.`)
  - **Message Format**: Updated methods to use flat message structure (`message._sm_header.message_class` and `message.to_json`) instead of old two-tier format (`message_header, encoded_message = message`)
  - **subscribe_test.rb**: Fixed `business_logic` method to be a class method (`def self.business_logic`) to match subscription call pattern
  - **Result**: All tests now pass (`176 runs, 578 assertions, 0 failures, 0 errors, 1 skips`) completing the architectural transition

## [0.0.13] 2025-09-10

### Changed
- **BREAKING: Transport-Level Serialization Architecture**: Major architectural rework moving serializer responsibility from message classes to transport layer
  - **Core Change**: Serializers now associated with transports instead of message classes, enabling different transports to use different serialization formats
  - **Message Structure**: Eliminated wrapper objects in favor of flat message structure with `_sm_header` routing metadata
  - **Serialization Format**: Messages now serialized as single JSON objects containing both header and payload data (e.g., `{"_sm_header": {...}, "content": "value", "property": "data"}`)
  - **Transport Flexibility**: Each transport can now use its own serializer (JSON, MessagePack, etc.) independently
  - **Backward Compatibility**: Added `_sm_payload` and `split` methods to maintain compatibility with existing proc handlers
  - **Performance**: Simplified message processing pipeline with direct message instance passing instead of complex wrapper handling

### Fixed
- **Message Reconstruction**: Fixed critical bug in `SmartMessage::Base#initialize` where payload properties were not properly extracted from flat serialized structure
  - **Root Cause**: Initialization logic looked for `props[:_sm_payload]` but flat structure stores properties directly in `props`
  - **Solution**: Changed to `payload_props = props.except(:_sm_header)` to extract all non-header properties
  - **Impact**: Proc handlers now receive correct message content, resolving nil property values in `_sm_payload`
- **Circuit Breaker Test Compatibility**: Updated circuit breaker tests to use new transport method signatures
  - **Issue**: Tests were calling `transport.publish(header, payload)` with two arguments
  - **Fix**: Updated to `transport.publish(message_instance)` with single message parameter
  - **Result**: All circuit breaker tests now pass with new architecture
- **Deduplication Test Format**: Updated deduplication tests from old wrapper format to new flat structure
  - **Changed**: `_sm_payload: { content: "value" }` → `content: "value"`
  - **Maintained**: Full deduplication functionality with handler-scoped DDQ system

### Enhanced
- **Transport Serialization Control**: Each transport implementation can now specify its preferred serializer
  - **Memory Transport**: Returns message objects directly without serialization for performance
  - **STDOUT Transport**: Uses JSON serializer with pretty printing for human readability
  - **Redis Transport**: Uses MessagePack with JSON fallback for efficient network transmission
- **Message Processing Pipeline**: Streamlined architecture with direct message instance routing
  - **Eliminated**: Complex wrapper object creation and management overhead
  - **Simplified**: Transport `receive` method now directly reconstructs message instances from flat data
  - **Improved**: Cleaner separation between transport concerns and message processing logic

### Added
- **Emergency Services Multi-Program Demo**: Complete emergency dispatch simulation system
  - Added comprehensive emergency services message definitions with validation
  - Emergency Dispatch Center (911) routing calls to appropriate departments
  - Fire Department, Police Department, and Health Department service implementations
  - AI-powered visitor generating realistic emergency scenarios with retry logic
  - Health monitoring system across all city services with status reporting
  - Continuous observation generation with diverse emergency scenarios every 15 seconds

### Enhanced
- **Message Definition Property System**: Improved DRY principles and AI integration
  - Extracted inline array validations into VALID_* constants (VALID_SEVERITY, VALID_EMERGENCY_TYPES, etc.)
  - Updated property descriptions to use constants dynamically (#{VALID_SEVERITY.join(', ')})
  - Enhanced property descriptions to include valid values for better AI prompting
  - Standardized validation message format using constant interpolation across all message types
- **SmartMessage Class-Level Addressing**: Added setter method support for flexible syntax
  - Added from=, to=, reply_to= setter methods to complement existing getter methods
  - Enables both ClassName.from(value) and ClassName.from = value syntax patterns
  - Maintains backward compatibility while improving developer experience

### Added
- **Documentation Website**: MkDocs-based documentation site with GitHub Pages deployment
  - Added `mkdocs.yml` configuration with Material theme and SmartMessage branding
  - Created GitHub Actions workflow (`.github/workflows/deploy-github-pages.yml`) for automatic documentation deployment
  - Reorganized documentation structure into logical sections: Getting Started, Core Concepts, Reference, and Development
  - Added custom CSS styling for improved header visibility and readability
  - Integrated SmartMessage logo and branding throughout the documentation
  - Documentation now automatically deploys to GitHub Pages on push to master branch
  - Live documentation available at: https://madbomber.github.io/smart_message/

## [0.0.10] 2025-08-20
### Added
- **Handler-Scoped Message Deduplication**: Advanced DDQ (Deduplication Queue) system with automatic handler isolation
  - Handler-only DDQ scoping using `"MessageClass:HandlerMethod"` key format for natural isolation
  - Automatic subscriber identification eliminates need for explicit `me:` parameter in API
  - Cross-process deduplication support with independent DDQ instances per handler
  - Memory and Redis storage backends with O(1) performance using hybrid Array + Set data structure
  - Seamless integration with dispatcher - no changes required to existing subscription code
  - Per-handler statistics and monitoring capabilities with DDQ utilization tracking
  - Thread-safe circular buffer implementation with automatic eviction of oldest entries
  - Configuration DSL: `ddq_size`, `ddq_storage`, `enable_deduplication!`, `disable_deduplication!`
  - Comprehensive documentation and examples demonstrating distributed message processing scenarios

### Fixed
- **Message Filtering Logic**: Fixed critical bug in subscription filtering where nil broadcast filters caused incorrect behavior
  - **Root Cause**: `filters.key?(:broadcast)` returned true even when broadcast value was nil
  - **Solution**: Changed condition to check for non-nil values: `filters[:to] || filters[:broadcast]`
  - **Impact**: Subscription filtering now works correctly with nil filter values and maintains backward compatibility
- **Circuit Breaker Test Compatibility**: Added error handling for non-existent message classes in DDQ initialization
  - Added rescue blocks around `constantize` calls to gracefully handle fake test classes
  - DDQ initialization now skips gracefully for test classes that cannot be constantized
  - Maintains proper DDQ functionality for real message classes while supporting test scenarios

## [0.0.9] 2025-08-20
### Added
- **Advanced Logging Configuration System**: Comprehensive logger configuration with multiple output formats and options
  - New SmartMessage configuration options: `log_level`, `log_format`, `log_colorize`, `log_include_source`, `log_structured_data`, `log_options`
  - Support for symbol-based log levels: `:info`, `:debug`, `:warn`, `:error`, `:fatal`
  - Colorized console output with customizable color schemes using ANSI terminal colors
  - File-based logging without colorization for clean log files
  - JSON structured logging support with metadata inclusion
  - Log rolling capabilities: size-based and date-based rolling with configurable retention
  - Source location tracking for debugging (file, line number, method)
  - Complete Lumberjack logger integration with SmartMessage configuration system
  - New comprehensive logger demonstration: `examples/show_logger.rb`
  - Application-level logger access through `SmartMessage.configuration.default_logger`
- **Transport Layer Abstraction**: Complete refactoring from legacy Broker to modern Transport architecture
  - New `SmartMessage::Transport` module providing pluggable message delivery backends
  - Transport registry system for dynamic plugin discovery and registration
  - Base transport class with standardized interface for all implementations
  - Memory, STDOUT, and Redis transport implementations with production-ready features
  - File-based transport support for inter-process communication
- **Message Wrapper Architecture**: Unified message envelope system for cleaner dataflow
  - New `SmartMessage::Wrapper::Base` class consolidating header and payload
  - Simplified method signatures throughout message processing pipeline
  - `_sm_` prefixed properties to avoid collision with user message definitions
  - Support for different initialization patterns and automatic header generation
- **HeaderDSL for Configuration**: Simplified message class setup with declarative syntax
  - New `SmartMessage::Addressing::HeaderDSL` providing cleaner class-level configuration
  - Declarative `from`, `to`, `reply_to` methods for entity addressing
  - Automatic header field configuration without boilerplate code
- **Advanced Message Filtering**: Regular expression support for flexible subscription patterns
  - Regex pattern matching for `from:` and `to:` filters (e.g., `from: /^payment-.*/`)
  - Array filters combining exact strings and patterns: `from: ['admin', /^system-.*/]`
  - Environment-based routing patterns for dev/staging/production separation
  - Service pattern routing for microservices architecture
  - New example demonstrating regex filtering in microservices (`09_regex_filtering_microservices.rb`)
- **Performance Benchmarking Tools**: Comprehensive performance measurement infrastructure
  - New benchmark suite comparing thread pool and Ractor implementations
  - JSON-based benchmark result storage with detailed metrics
  - Benchmark comparison tool for analyzing performance across runs
  - Ractor-based message processing implementation for parallel execution
- **Improved Documentation Structure**: Complete documentation overhaul
  - New modular documentation in `docs/` directory covering all major features
  - Dedicated guides for transports, serializers, dispatcher, and filtering
  - Architecture overview with component relationships
  - Troubleshooting guide for common issues
  - Example README with comprehensive usage patterns

### Changed
- **BREAKING: Transport API Migration**: Complete replacement of Broker with Transport
  - All `broker` references must be updated to `transport`
  - `SmartMessage::Broker` removed in favor of `SmartMessage::Transport`
  - Transport implementations now in `lib/smart_message/transport/` directory
  - Updated all examples and tests to use new transport terminology
- **Simplified Module Structure**: Cleaner separation of concerns
  - Extracted addressing logic into `SmartMessage::Addressing` module
  - Separated messaging functionality into `SmartMessage::Messaging` module
  - Created dedicated `SmartMessage::Plugins` module for plugin management
  - Moved versioning logic to `SmartMessage::Versioning` module
  - Utilities consolidated in `SmartMessage::Utilities` module
- **Enhanced Error Messages**: More descriptive error handling throughout
  - Improved header validation error messages with context
  - Better transport registration error reporting
  - Clearer serialization failure messages

### Fixed
- **Message Processing Simplification**: Removed unnecessary complexity in message wrapper
  - Eliminated redundant processing steps in wrapper initialization
  - Streamlined header and payload handling
  - Fixed potential race conditions in concurrent message processing
- **Header Method Handling**: Improved reliability of header field access
  - Fixed edge cases in header method delegation
  - Ensured consistent behavior across all header field operations
  - Better error messages for invalid header operations

### Enhanced
- **Developer Experience**: Significant improvements to API usability
  - More intuitive transport registration and discovery
  - Cleaner message class definition with HeaderDSL
  - Simplified subscription syntax with powerful filtering
  - Better separation between framework internals and user code
- **Testing Infrastructure**: Expanded test coverage
  - New tests for transport layer abstraction
  - Comprehensive filtering tests including regex patterns
  - Performance benchmark test suite
  - Proc handler integration tests
- **Example Programs**: Enhanced educational value
  - Added performance benchmarking examples
  - New regex filtering demonstration for microservices
  - Dead letter queue demonstration with retry scenarios
  - Updated all examples to use modern transport architecture

### Deprecated
- **Broker System**: Legacy broker implementation marked for removal
  - `SmartMessage::Broker` and all subclasses deprecated
  - Migration path provided through transport layer
  - Broker terminology replaced with transport throughout codebase

## [0.0.8] 2025-08-19

### Added
- **File-Based Dead Letter Queue System**: Production-ready DLQ implementation with comprehensive replay capabilities
  - JSON Lines (.jsonl) format for efficient message storage and retrieval
  - FIFO queue operations: `enqueue`, `dequeue`, `peek`, `size`, `clear`
  - Configurable file paths with automatic directory creation
  - Global default instance and custom instance support for different use cases
  - Comprehensive replay functionality with transport override capabilities
  - Administrative tools: `statistics`, `filter_by_class`, `filter_by_error_pattern`, `export_range`
  - Thread-safe operations with Mutex protection for concurrent access
  - Integration with circuit breaker fallbacks for automatic failed message capture

### Fixed
- **Code Quality: Dead Letter Queue Refactoring**: Eliminated multiple code smells for improved maintainability
  - **Hardcoded Serialization Assumption**: Added `payload_format` tracking with flexible deserialization supporting multiple formats
  - **Incomplete Header Restoration**: Complete header field restoration including `message_class`, `published_at`, `publisher_pid`, and `version`
  - **Transport Override Not Applied**: Fixed replay logic to properly apply transport overrides before message publishing
  - **Repeated File Reading Patterns**: Extracted common file iteration logic into reusable `read_entries_with_filter` method
- **Test Suite: Logger State Pollution**: Fixed cross-test contamination in logger tests
  - **Root Cause**: Class-level logger state persisting between tests due to shared `@@logger` variable
  - **Solution**: Added explicit logger reset in "handle nil logger gracefully" test to ensure clean state
  - **Result**: Full test suite now passes with 0 failures, 0 errors (151 runs, 561 assertions)

### Enhanced
- **Dead Letter Queue Reliability**: Robust error handling and graceful degradation
  - Automatic fallback to JSON deserialization for unknown payload formats with warning logs
  - Graceful handling of corrupted DLQ entries without breaking queue operations
  - Enhanced error context capture including stack traces and retry counts
  - Backward compatibility maintained for existing DLQ files and message formats
- **Circuit Breaker Integration**: Enhanced fallback mechanism with DLQ integration
  - Circuit breaker fallbacks now include proper circuit name identification for debugging
  - Automatic serializer format detection and storage for accurate message replay
  - Seamless integration between transport circuit breakers and dead letter queue storage
- **Code Maintainability**: Eliminated code duplication and improved design patterns
  - DRY principle applied to file reading operations with reusable filter methods
  - Consistent error handling patterns across all DLQ operations
  - Clear separation of concerns between queue operations, replay logic, and administrative functions

### Documentation
- **Dead Letter Queue Configuration**: Multiple configuration options for different deployment scenarios
  - Global default configuration: `SmartMessage::DeadLetterQueue.configure_default(path)`
  - Instance-level configuration with custom paths for different message types
  - Environment-based configuration using ENV variables for deployment flexibility
  - Per-environment path configuration for development, staging, and production

## [0.0.7] 2025-08-19
### Added
- **Production-Grade Circuit Breaker Integration**: Comprehensive reliability patterns using BreakerMachines gem
  - Circuit breaker protection for message processing operations with configurable failure thresholds
  - Transport-level circuit breakers for publish/subscribe operations with automatic fallback
  - Integrated circuit breaker DSL throughout SmartMessage components for production reliability
  - Memory and Redis storage backends for circuit breaker state persistence
  - Built-in fallback mechanisms including dead letter queue, retry with exponential backoff, and graceful degradation
  - Circuit breaker statistics and introspection capabilities for monitoring and debugging

### Fixed
- **Critical: Redis Transport Header Preservation**: Fixed message header information loss during Redis pub/sub transport
  - **Root Cause**: Redis transport was only sending message payload through channels, reconstructing generic headers on receive
  - **Impact**: Message addressing information (`from`, `to`, `reply_to`) was lost, breaking entity-aware filtering and routing
  - **Solution**: Modified Redis transport to combine header and payload into JSON structure during publish/subscribe
  - **Result**: Full header information now preserved across Redis transport with backward compatibility fallback
  - Redis IoT example now displays all expected sensor data, alerts, and real-time device monitoring output
- **Performance: Dispatcher Shutdown Optimization**: Dramatically improved dispatcher shutdown speed
  - **Previous Issue**: Slow 1-second polling with no timeout mechanism caused delays up to several minutes
  - **Optimization**: Replaced with native `wait_for_termination(3)` using Concurrent::ThreadPool built-in timeout
  - **Performance Gain**: Shutdown now completes in milliseconds instead of seconds
  - Removed unnecessary circuit breaker wrapper - thread pool handles timeout and fallback natively
- **Code Quality: Transport Method Signature Consistency**: Ensured all transport `do_publish` methods use consistent parameters
  - Standardized `do_publish(message_header, message_payload)` signature across all transport implementations
  - Updated Redis, STDOUT, and Memory transports for consistent interface

### Changed
- **Dispatcher Architecture**: Simplified shutdown mechanism leveraging Concurrent::ThreadPool native capabilities
  - Removed custom timeout polling logic in favor of built-in `wait_for_termination` method
  - Eliminated redundant circuit breaker for shutdown operations - thread pool provides timeout and fallback
  - **BREAKING**: Removed `router_pool_shutdown` circuit breaker configuration (no longer needed)
- **Redis Transport Protocol**: Enhanced message format to preserve complete header information
  - Redis messages now contain both header and payload: `{header: {...}, payload: "..."}`
  - Automatic fallback to legacy behavior for malformed or old-format messages
  - Maintains full backward compatibility with existing Redis deployments

### Enhanced
- **Circuit Breaker Integration**: Strategic application of reliability patterns where most beneficial
  - Message processing operations protected with configurable failure thresholds and fallback behavior
  - Transport publish/subscribe operations wrapped with circuit breakers for external service protection
  - Clean separation between internal operations (thread pools) and external dependencies (Redis, etc.)
- **Redis Transport Reliability**: Production-ready Redis pub/sub with complete message fidelity
  - Full message header preservation enables proper entity-aware filtering and routing
  - IoT examples now demonstrate complete real-time messaging with sensor data, alerts, and device commands
  - Enhanced error handling with JSON parsing fallbacks for malformed messages
- **Developer Experience**: Cleaner, more maintainable codebase with proper separation of concerns
  - Circuit breakers applied strategically for external dependencies, not internal thread management
  - Simplified shutdown logic leverages proven Concurrent::ThreadPool patterns
  - Clear distinction between reliability mechanisms and business logic

### Documentation
- **Circuit Breaker Patterns**: Examples of proper BreakerMachines DSL usage throughout codebase
  - Strategic application for external service protection vs internal thread management
  - Configuration examples for different failure scenarios and recovery patterns
  - Best practices for production-grade messaging reliability

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
