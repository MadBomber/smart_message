# lib/smart_message/property_validations.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Adds +required:+, +validate:+ and +validation_message:+ to the property
  # DSL and runs every check in one place.
  #
  # Nothing is checked at construction.  #validation_errors lists every
  # problem, #valid? answers yes or no, and #validate! raises
  # Errors::ValidationError.  Publishing calls #validate!.
  #
  # Required rules and validators are inherited by subclasses.
  module PropertyValidations
    def self.included(base)
      base.extend(InheritableSettings)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # @option options [Boolean, Proc] :required  true, or a callable evaluated
      #   on the instance that returns true when the property is required
      # @option options [String] :message  error text for a missing required property
      # @option options [Proc, Symbol, Regexp, Class, Array, Range, Object] :validate
      # @option options [String] :validation_message  error text for a failed validator
      def property(property_name, options = {})
        options            = options.dup
        name               = property_name.to_sym
        required           = options.delete(:required)
        required_message   = options.delete(:message)
        validator          = options.delete(:validate)
        validation_message = options.delete(:validation_message)

        super(property_name, options)

        if required
          add_to_setting(:required_rules, name, {
            condition: required,
            message:   required_message || "The property '#{name}' is required for #{self.name}."
          })
        end

        return if validator.nil?

        add_to_setting(:property_validators, name, {
          validator: validator,
          message:   validation_message || "Validation failed for property '#{name}'"
        })
      end

      def property_validator(property_name)
        property_validators[property_name.to_sym]
      end

      def property_validators
        merged_setting(:property_validators)
      end

      def validated_properties
        property_validators.keys
      end

      # @return [Hash] property name => { condition:, message: }
      def required_rules
        merged_setting(:required_rules)
      end

      # @return [Array<Symbol>] names of properties declared with required:
      def required_property_names
        required_rules.keys
      end

      def required_property?(property_name)
        required_rules.key?(property_name.to_sym)
      end

      # Raise unless +instance+ is valid.
      def validate_all(instance)
        instance.validate!
      end
    end

    # @return [true]
    # @raise [SmartMessage::Errors::ValidationError] listing every failure
    def validate!
      errors = validation_errors
      return true if errors.empty?

      raise SmartMessage::Errors::ValidationError.new(
        errors.map { |error| format_validation_error(error) }.join('; '),
        errors: errors
      )
    end

    def valid?
      validation_errors.empty?
    end

    # @return [Array<Hash>] one { property:, value:, message: } per failure
    def validation_errors
      required_property_errors + validator_errors
    end

    private

    def required_property_errors
      self.class.required_rules.filter_map do |name, rule|
        next unless required_now?(rule[:condition])
        next unless self[name].nil?

        { property: name, value: nil, message: rule[:message] }
      end
    end

    def validator_errors
      self.class.property_validators.filter_map do |name, info|
        value = self[name]
        next if value.nil? # a missing value is the required rule's business
        next if run_validator(info[:validator], value)

        { property: name, value: value, message: info[:message] }
      end
    end

    # Is a required rule in force for this instance?
    def required_now?(condition)
      return !!instance_exec(&condition) if condition.respond_to?(:call)

      !!condition
    rescue StandardError
      true
    end

    # Apply one validator to one value.  A validator that raises is a
    # failed validation, never an escaped exception.
    #
    # @return [Boolean]
    def run_validator(validator, value)
      result = case validator
               when Proc    then instance_exec(value, &validator)
               when Symbol  then send(validator, value)
               when Regexp  then validator.match?(value.to_s)
               when Module  then value.is_a?(validator)
               when Array, Set then validator.include?(value)
               when Range   then validator.cover?(value)
               else              value == validator
               end
      !!result
    rescue StandardError
      false
    end

    def format_validation_error(error)
      "#{self.class.name}##{error[:property]}: #{error[:message]}"
    end
  end
end
