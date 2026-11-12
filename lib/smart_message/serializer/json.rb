# lib/smart_message/serializer/json.rb
# encoding: utf-8
# frozen_string_literal: true

require 'json' # STDLIB
require 'time'
require 'date'

module SmartMessage
  module Serializer
    # JSON serializer.
    #
    # JSON has fewer types than Ruby, so a round trip changes some values:
    #
    #   Time, DateTime  => ISO 8601 String (microseconds kept)
    #   Date            => ISO 8601 String
    #   Symbol          => String
    #   BigDecimal      => String in plain notation ('1.0')
      #   anything else   => its #to_h when it has one, else #to_s
    #   Hash keys       => Symbols, at every level
    #
    # Declare a coercion on the message class to get a type back:
    #
    #   coerce_key :placed_at, ->(v) { v.is_a?(String) ? Time.parse(v) : v }
    #
    # The header's published_at is restored to a Time automatically.
    class Json < Base
      # Convert a value into something JSON represents the same way in
      # every process, whatever JSON extensions happen to be loaded.
      def self.jsonify(value)
        case value
        when Hash                         then value.to_h { |key, item| [key.to_s, jsonify(item)] }
        when Array                        then value.map { |item| jsonify(item) }
        when String, Integer, Float, true, false, nil then value
        when Symbol                       then value.to_s
        when Time, DateTime               then value.iso8601(6)
        when Date                         then value.iso8601
        else
          if defined?(BigDecimal) && value.is_a?(BigDecimal)
            value.to_s('F') # plain decimal notation, whatever has patched #to_s
          elsif value.respond_to?(:to_h)
            jsonify(value.to_h)
          else
            value.to_s
          end
        end
      end

      private

      def do_encode(message_hash)
        ::JSON.generate(self.class.jsonify(message_hash))
      end

      def do_decode(payload)
        ::JSON.parse(payload, symbolize_names: true)
      end
    end
  end
end
