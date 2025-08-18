# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
