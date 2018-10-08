# lib/smart_message/header.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom'   # STDLIB

module SmartMessage
  class Header < Hashie::Dash
    include Hashie::Extensions::IndifferentAccess
    include Hashie::Extensions::MergeInitializer
    include Hashie::Extensions::MethodAccess

    property :uuid
    property :message_class
    property :published_at
    property :published_pid

  end
end