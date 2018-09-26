# lib/smart_message/base.rb
# frozen_string_literal: true

module SmartMessage
  # The foundation class for the smart message
  class Base < Hashie::Dash
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

    def self.publish
    end

    def self.subscribe
    end

    def self.process
    end
  end # class base
end # module SmartMessage
