# lib/smart_message/header.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Every smart message has a common header format that contains
  # information used to support the dispatching of subscribed
  # messages upon receipt from a broker.
  class Header < Hashie::Dash
    include Hashie::Extensions::IndifferentAccess
    include Hashie::Extensions::MergeInitializer
    include Hashie::Extensions::MethodAccess

    # Common attributes of the smart message standard header
    property :uuid
    property :message_class
    property :published_at
    property :publisher_pid
  end
end