# lib/smart_message/property_descriptions.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module PropertyDescriptions
    def self.included(base)
      base.extend(ClassMethods)
      base.class_eval do
        @property_descriptions = {}
      end
    end

    module ClassMethods
      def property(property_name, options = {})
        description = options.delete(:description)
        
        # Store description if provided
        if description
          @property_descriptions ||= {}
          @property_descriptions[property_name.to_sym] = description
        end
        
        # Call original property method
        super(property_name, options)
      end

      def property_description(property_name)
        @property_descriptions&.[](property_name.to_sym)
      end

      def property_descriptions
        @property_descriptions&.dup || {}
      end

      def described_properties
        @property_descriptions&.keys || []
      end
    end
  end
end