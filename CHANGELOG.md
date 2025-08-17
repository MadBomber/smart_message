# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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