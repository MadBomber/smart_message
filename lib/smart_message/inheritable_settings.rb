# lib/smart_message/inheritable_settings.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # One mechanism for every class-level setting.
  #
  # A class that extends this module stores only the values it sets itself.
  # Reading a setting returns the class's own value, else the nearest
  # ancestor's value, else the default.  Writing never touches an ancestor
  # or a sibling.
  #
  #   class Parent < SmartMessage::Base; end
  #   class Child  < Parent; end
  #
  #   Parent.set_setting(:version, 2)
  #   Child.setting(:version)          # => 2  (inherited)
  #   Child.set_setting(:version, 3)
  #   Parent.setting(:version)         # => 2  (unchanged)
  module InheritableSettings
    # @return [Boolean] true when this class (not an ancestor) set +name+
    def own_setting?(name)
      !@sm_settings.nil? && @sm_settings.key?(name)
    end

    # @return [Object, nil] the value this class set itself
    def own_setting(name)
      @sm_settings&.[](name)
    end

    # Read a setting through the inheritance chain.
    def setting(name, default = nil)
      owner = setting_owner(name)
      owner ? owner.own_setting(name) : default
    end

    # @return [Class, nil] the nearest class in the chain that set +name+
    def setting_owner(name)
      klass = self
      while klass.respond_to?(:own_setting?)
        return klass if klass.own_setting?(name)

        klass = klass.superclass
      end
      nil
    end

    # @return [Boolean] true when this class or an ancestor set +name+
    def setting?(name)
      !setting_owner(name).nil?
    end

    # Set this class's own value.
    def set_setting(name, value)
      (@sm_settings ||= {})[name] = value
    end

    # Forget this class's own value so the inherited one shows through.
    def clear_setting(name)
      @sm_settings&.delete(name)
    end

    # Hash-valued settings (validators, descriptions) merge down the chain:
    # ancestors first, so a subclass entry overrides its parent's.
    def merged_setting(name)
      chain = []
      klass = self
      while klass.respond_to?(:own_setting?)
        chain.unshift(klass.own_setting(name)) if klass.own_setting?(name)
        klass = klass.superclass
      end
      chain.reduce({}) { |merged, own| merged.merge(own) }
    end

    # Add one entry to this class's own copy of a hash-valued setting.
    def add_to_setting(name, key, value)
      set_setting(name, (own_setting(name) || {}).merge(key => value))
    end
  end
end
