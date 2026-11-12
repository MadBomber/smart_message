# lib/smart_message/versioning.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Versioning module for SmartMessage::Base
  # Handles schema versioning and version validation
  module Versioning
    DEFAULT_VERSION = 1

    def self.included(base)
      base.extend(ClassMethods)
    end

    # @return [Boolean] true for an Integer greater than zero
    def self.valid_version?(value)
      value.is_a?(Integer) && value.positive?
    end

    # Validate that the header version matches the expected version for this class
    def validate_header_version!
      expected = self.class.version
      actual   = _sm_header.version
      return true if actual == expected

      raise SmartMessage::Errors::ValidationError,
            "#{self.class.name} expects version #{expected}, but header has version #{actual}"
    end

    # Every validation failure for this message: its own properties, its
    # header, and the header version against the class version.
    #
    # @return [Array<Hash>] { property:, value:, message:, source: } where
    #   source is 'message', 'header', or 'version_mismatch'
    def validation_errors
      errors = super.map { |error| error.merge(source: 'message') }
      errors.concat(_sm_header.validation_errors.map { |error| error.merge(source: 'header') })

      expected = self.class.version
      actual   = _sm_header.version
      unless actual == expected
        errors << {
          property: :version,
          value:    actual,
          message:  "Expected version #{expected}, got: #{actual}",
          source:   'version_mismatch'
        }
      end

      errors
    end

    private

    def format_validation_error(error)
      case error[:source]
      when 'header'
        "#{SmartMessage::Header.name}##{error[:property]}: #{error[:message]}"
      when 'version_mismatch'
        "#{self.class.name} expects version #{self.class.version}, but header has version #{error[:value]}"
      else
        super
      end
    end

    module ClassMethods
      # Get the schema version, or set it for this class and its subclasses.
      #
      # @param new_version [Integer, nil] a positive Integer
      # @raise [ArgumentError] when the version is not a positive Integer
      def version(new_version = nil)
        return setting(:version, DEFAULT_VERSION) if new_version.nil?

        unless Versioning.valid_version?(new_version)
          raise ArgumentError, "version must be a positive Integer, got: #{new_version.inspect}"
        end

        set_setting(:version, new_version)
      end

      # The version a message of this class must carry in its header
      def expected_header_version
        version
      end
    end
  end
end
