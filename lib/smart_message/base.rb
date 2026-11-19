# lib/smart_message/base.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom' # STDLIB

module SmartMessage
  # The foundation class for the smart message
  class Base < Hashie::Dash
    # property options from:, with:, and transform_with:
    include Hashie::Extensions::Dash::PropertyTranslation

    include Hashie::Extensions::Coercion
    include Hashie::Extensions::DeepMerge
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::MethodAccess

    include SmartMessage::PropertyDescriptions
    include SmartMessage::PropertyValidations
    include SmartMessage::Plugins
    include SmartMessage::Addressing
    include SmartMessage::Subscription
    include SmartMessage::Versioning
    include SmartMessage::Messaging
    include SmartMessage::Utilities
    include SmartMessage::Deduplication

    # Names a message class may not use for a property, because the
    # framework reads or defines them on every message.
    RESERVED_PROPERTY_NAMES = %i[
      from to reply_to uuid
      publish transport transports config logger
      validate! valid? validation_errors
      to_h to_hash message_header
    ].freeze

    class << self
      # Declare a message property.
      #
      # @raise [SmartMessage::Errors::ReservedPropertyName] when the name
      #   collides with the framework (see RESERVED_PROPERTY_NAMES; names
      #   starting with '_sm_' are reserved too)
      def property(property_name, options = {})
        assert_property_name_allowed!(property_name)
        super
      end

      # @return [Boolean] true when +property_name+ cannot be declared
      def reserved_property_name?(property_name)
        name = property_name.to_sym
        RESERVED_PROPERTY_NAMES.include?(name) || name.start_with?('_sm_')
      end

      # @return [Array<Class>] every loaded SmartMessage::Base subclass
      def descendants
        subclasses.flat_map { |klass| [klass, *klass.descendants] }
      end

      private

      def assert_property_name_allowed!(property_name)
        return if equal?(SmartMessage::Base) # the framework's own properties
        return unless reserved_property_name?(property_name)

        raise SmartMessage::Errors::ReservedPropertyName,
              "#{name || 'message class'}: property name '#{property_name}' is reserved by SmartMessage"
      end
    end

    # The header travels with the message at the same level as its
    # properties (a flat structure).
    property :_sm_header

    # Build a message.
    #
    #   OrderMessage.new(order_id: 1, from: 'order-service')
    #   OrderMessage.new({ order_id: 1 })
    #
    # +from+, +to+ and +reply_to+ are addressing, not properties; they go
    # into the header.  Passing +_sm_header+ (a Hash or a Header) rebuilds a
    # message that was received from a transport.
    #
    # Values are deep-copied, so the message never shares nested Hashes or
    # Arrays with the caller.  Nothing is validated here; see #validate!.
    def initialize(attributes = nil, **props, &block)
      props = (attributes || {}).to_h.transform_keys(&:to_sym).merge(props)
      props = Utilities.deep_copy(props)

      header = build_header(props.delete(:_sm_header), props)

      super({ _sm_header: header }.merge(props), &block)

      self.class.logger.debug { "[SmartMessage] Created: #{self.class.name}" }
    end

    def [](property)
      super(property.to_sym)
    end

    # Coercion wraps []= when it is included, so an override has to call
    # the coercing writer itself or coerce_key would be skipped.
    def []=(property, value)
      set_value_with_coercion(property.to_sym, value)
    end

    # Convert the message to a Hash with one Symbol key per declared
    # property.  The header is included as a plain Hash under :_sm_header.
    def to_h
      self.class.properties.to_h do |name|
        [name, name == :_sm_header ? _sm_header.to_h : self[name]]
      end
    end
    alias to_hash to_h

    private

    # @param existing [Hash, SmartMessage::Header, nil] a received header
    # @param props [Hash] constructor properties; addressing keys are removed
    # @return [SmartMessage::Header]
    def build_header(existing, props)
      return existing.dup if existing.is_a?(SmartMessage::Header)
      return SmartMessage::Header.new(existing) if existing.is_a?(Hash)

      SmartMessage::Header.new(
        uuid:          SecureRandom.uuid,
        message_class: self.class.to_s,
        published_at:  Time.now,
        publisher_pid: Process.pid,
        version:       self.class.version,
        from:          props.delete(:from)     || self.class.from,
        to:            props.delete(:to)       || self.class.to,
        reply_to:      props.delete(:reply_to) || self.class.reply_to
      )
    end

    # A copy shares no mutable state with the original: it has its own
    # header and its own nested values.
    def initialize_copy(other)
      super
      other.each_pair do |name, value|
        _regular_writer(name, name == :_sm_header ? value.dup : Utilities.deep_copy(value))
      end
    end
  end
end
