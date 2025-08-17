# lib/smart_message/wrapper.rb
# encoding: utf-8
# frozen_string_literal: true

# TODO: consider having a serializer plugin for the wrapper that is
#       different than that used for the payload.

require_relative './header.rb'

module SmartMessage
  module Wrapper
    # Every smart message has a common wrapper format that contains
    # information used to support the dispatching of subscribed
    # messages upon receipt from a transport as well as the serialized
    # payload.
    class Base < Hashie::Dash
      include Hashie::Extensions::IndifferentAccess
      include Hashie::Extensions::MergeInitializer
      include Hashie::Extensions::MethodAccess

      # Common attributes of the smart message standard header
      # Using '_sm_' as a prefix to avoid potential collision with
      # a user's message definition.
      property :_sm_header
      property :_sm_payload

      def initialize(props = {}, &block)
        attributes = {
          _sm_header: SmartMessage::Header.new(
            uuid:           SecureRandom.uuid,
            message_class:  self.class.to_s,
            published_at:   2,
            publisher_pid:  3
          )
        }.merge(props)

        super(attributes, &block)
      end


    end
  end
end