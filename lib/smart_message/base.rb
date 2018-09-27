# lib/smart_message/base.rb
# frozen_string_literal: true

module SmartMessage
  # A message can't be very smart if it does not know how to
  # send and receive itself.
  class NoPluginConfigured < RuntimeError; end

  # The foundation class for the smart message
  class Base < Hashie::Dash
    @@plugin = nil

    include Hashie::Extensions::Coercion
    include Hashie::Extensions::MergeInitializer
    include Hashie::Extensions::MethodAccess
    include Hashie::Extensions::IndifferentAccess
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::DeepMerge
    include Hashie::Extensions::Dash::PropertyTranslation

    def initialize(*args)
      super
    end

    ###################################################
    ## Class methods

    def self.plugin
      @@plugin
    end

    def self.config(plugin=SmartMessage::StdoutPlugin)
      @@plugin = plugin
      debug_me{[ '@@plugin' ]}
    end

    def self.publish
      debug_me
      check_plugin
      @@plugin.send(self)
    end

    def self.subscribe
      debug_me
      check_plugin
      @@plugin.subscribe(self)
    end

    def self.process
      debug_me
      check_plugin
    end

    private

    def self.check_plugin
      raise SmartMessage::NoPluginConfigured if @@plugin.nil?
    end
  end # class base
end # module SmartMessage
