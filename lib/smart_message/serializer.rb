# lib/smart_message/serializer.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Serializers turn a message Hash into bytes and back.  A transport owns
  # one serializer and uses it for everything it sends and receives.
  module Serializer
    class << self
      # The framework's default serializer class
      def default
        SmartMessage::Serializer::Json
      end

      # Find a serializer class by short name ('json') or class name
      # ('SmartMessage::Serializer::Json').
      #
      # @param name [String, Symbol, nil]
      # @return [Class, nil] a SmartMessage::Serializer::Base subclass
      def for(name)
        wanted = name.to_s
        return nil if wanted.empty?

        available.find do |klass|
          class_name = klass.name.to_s # nil for an anonymous class
          class_name == wanted || class_name.split('::').last.to_s.casecmp?(wanted)
        end
      end

      # @return [Array<Class>] every loaded serializer class
      def available
        [SmartMessage::Serializer::Json, *SmartMessage::Serializer::Base.descendants].uniq
      end
    end
  end
end
