# lib/smart_message/base.rb
# frozen_string_literal: true

module SmartMessage
  # The foundation class for the smart message
  class Base < Hashie::Dash
    @@plugin = nil

    include Hashie::Extensions::Dash::PropertyTranslation

    include Hashie::Extensions::Coercion
    include Hashie::Extensions::DeepMerge
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::IndifferentAccess
    include Hashie::Extensions::MergeInitializer
    include Hashie::Extensions::MethodAccess

    def initialize(*args)
      super
    end

    ###################################################
    ## Common methods

    def publish
      debug_me
      check_plugin
      @@plugin.send(self)
    end

    def subscribe
      debug_me
      check_plugin
      @@plugin.subscribe(self)
    end

    def process
      debug_me
      check_plugin
    end

    def plugin
      @@plugin
    end

    private

    def check_plugin
      raise Errors::NoPluginConfigured unless configured?
    end

    ###################################################
    ## Class methods

    public

    class << self
      def plugin
        @@plugin
      end

      def config(broker=SmartMessage::StdoutPlugin)
        @@plugin = broker
        debug_me{[ '@@plugin' ]}
      end

      def configured?
        !@@plugin.nil?
      end

    end # class << self
  end # class Base
end # module SmartMessage
