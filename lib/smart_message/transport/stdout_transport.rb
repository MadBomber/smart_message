# lib/smart_message/transport/stdout_transport.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'file_transport'

module SmartMessage
    module Transport
      class StdoutTransport < FileTransport
        def initialize(options = {})
          defaults = { file_path: $stdout, file_mode: 'w', file_type: :regular }
          super(defaults.merge(options))
        end
      end
    end
  end
