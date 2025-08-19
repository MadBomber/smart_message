# lib/smart_message/versioning.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Versioning module for SmartMessage::Base
  # Handles schema versioning and version validation
  module Versioning
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Validate that the header version matches the expected version for this class
    def validate_header_version!
      expected = self.class.expected_header_version
      actual = _sm_header.version
      unless actual == expected
        raise SmartMessage::Errors::ValidationError,
          "#{self.class.name} expects version #{expected}, but header has version #{actual}"
      end
    end

    # Override PropertyValidations validate! to include header and version validation
    def validate!
      # Validate message properties using PropertyValidations
      super
      
      # Validate header properties
      _sm_header.validate!
      
      # Validate header version matches expected class version  
      validate_header_version!
    end

    # Override PropertyValidations validation_errors to include header errors
    def validation_errors
      errors = []
      
      # Get message property validation errors using PropertyValidations
      errors.concat(super.map { |err| 
        err.merge(source: 'message') 
      })
      
      # Get header validation errors
      errors.concat(_sm_header.validation_errors.map { |err| 
        err.merge(source: 'header') 
      })
      
      # Check version mismatch
      expected = self.class.expected_header_version
      actual = _sm_header.version
      unless actual == expected
        errors << {
          property: :version,
          value: actual,
          message: "Expected version #{expected}, got: #{actual}",
          source: 'version_mismatch'
        }
      end
      
      errors
    end

    module ClassMethods
      # Class-level version setting
      attr_accessor :_version
      
      def version(v = nil)
        if v.nil?
          @_version || 1  # Default to version 1 if not set
        else
          @_version = v
          
          # Set up version validation for the header
          # This ensures that the header version matches the expected class version
          @expected_header_version = v
        end
      end
      
      def expected_header_version
        @expected_header_version || 1
      end
    end
  end
end