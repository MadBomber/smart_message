# lib/smart_message/broker.rb
# encoding: utf-8
# frozen_string_literal: true

# COMPATIBILITY LAYER: This file provides backward compatibility
# for the old broker terminology. New code should use Transport directly.

require_relative 'transport'

module SmartMessage
  # Legacy Broker module - redirects to Transport for compatibility
  module Broker
    # Legacy Base class that extends the new Transport::Base
    class Base < Transport::Base
    end
    
    # Legacy Stdout class that wraps the new StdoutTransport
    class Stdout < Transport::StdoutTransport
    end
  end
end

