# lib/smart_message/property_validations.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module PropertyValidations
    def self.included(base)
      base.extend(ClassMethods)
      base.class_eval do
        @property_validators = {}
      end
    end

    module ClassMethods
      def property(property_name, options = {})
        # Extract our custom options before passing to Hashie::Dash
        # Note: Hashie's 'message' option only works with 'required', so we use 'validation_message'
        validator = options.delete(:validate)
        validation_message = options.delete(:validation_message)

        # Call original property method first
        super(property_name, options)

        # Then store validator if provided
        if validator
          @property_validators ||= {}
          @property_validators[property_name.to_sym] = {
            validator: validator,
            message: validation_message || "Validation failed for property '#{property_name}'"
          }

          # Note: We don't override setter methods since they may conflict with Hashie::Dash
          # Instead, validation happens during validate! calls
        end
      end

      def property_validator(property_name)
        @property_validators&.[](property_name.to_sym)
      end

      def property_validators
        @property_validators&.dup || {}
      end

      def validated_properties
        @property_validators&.keys || []
      end

      # Validate all properties with validators
      def validate_all(instance)
        validated_properties.each do |property_name|
          validator_info = property_validator(property_name)
          next unless validator_info

          value = instance.send(property_name)
          validator = validator_info[:validator]
          error_message = validator_info[:message]

          # Skip validation if value is nil and property is not required
          next if value.nil? && !instance.class.required_properties.include?(property_name)

          # Perform validation
          is_valid = case validator
                     when Proc
                       instance.instance_exec(value, &validator)
                     when Symbol
                       instance.send(validator, value)
                     when Regexp
                       !!(value.to_s =~ validator)
                     when Class
                       value.is_a?(validator)
                     when Array
                       validator.include?(value)
                     when Range
                       validator.include?(value)
                     else
                       value == validator
                     end

          unless is_valid
            raise SmartMessage::Errors::ValidationError, "#{instance.class.name}##{property_name}: #{error_message}"
          end
        end
        true
      end
    end

    # Instance methods
    def validate!
      self.class.validate_all(self)
    end

    def valid?
      validate!
      true
    rescue SmartMessage::Errors::ValidationError
      false
    end

    def validation_errors
      errors = []
      self.class.validated_properties.each do |property_name|
        validator_info = self.class.property_validator(property_name)
        next unless validator_info

        value = send(property_name)
        validator = validator_info[:validator]

        # Skip validation if value is nil and property is not required
        next if value.nil? && !self.class.required_properties.include?(property_name)

        # Perform validation
        is_valid = case validator
                   when Proc
                     instance_exec(value, &validator)
                   when Symbol
                     send(validator, value)
                   when Regexp
                     !!(value.to_s =~ validator)
                   when Class
                     value.is_a?(validator)
                   when Array
                     validator.include?(value)
                   when Range
                     validator.include?(value)
                   else
                     value == validator
                   end

        unless is_valid
          errors << {
            property: property_name,
            value: value,
            message: validator_info[:message]
          }
        end
      end
      errors
    end
  end
end
