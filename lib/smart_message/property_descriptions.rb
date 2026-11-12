# lib/smart_message/property_descriptions.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Adds a +description:+ option to the property DSL.  Descriptions are
  # inherited by subclasses.
  module PropertyDescriptions
    def self.included(base)
      base.extend(InheritableSettings)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def property(property_name, options = {})
        options     = options.dup
        description = options.delete(:description)

        super(property_name, options)

        add_to_setting(:property_descriptions, property_name.to_sym, description) if description
      end

      def property_description(property_name)
        property_descriptions[property_name.to_sym]
      end

      def property_descriptions
        merged_setting(:property_descriptions)
      end

      def described_properties
        property_descriptions.keys
      end
    end
  end
end
