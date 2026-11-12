# test/inheritance_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

# Every class-level setting follows the same rule (review findings K1 to
# K6, R2): a class reads its own value, else its parent's; writing a value
# changes that class only.  Each test uses a parent, a child, and a sibling.
class InheritanceTest < Minitest::Test
  def setup
    @parent  = Class.new(SmartMessage::Base) { property :name, validate: String, description: 'A name' }
    @child   = Class.new(@parent)
    @sibling = Class.new(@parent)
  end

  # Assert the rule for one setting.
  #
  # @param reader [Proc] klass => current value
  # @param writer [Proc] (klass, value) => sets it
  def assert_inheritable(reader, writer, parent_value:, child_value:)
    writer.call(@parent, parent_value)

    assert_equal parent_value, reader.call(@child),   'an unset child reads the parent value'
    assert_equal parent_value, reader.call(@sibling), 'an unset sibling reads the parent value'

    writer.call(@child, child_value)

    assert_equal child_value,  reader.call(@child),   'the child reads its own value'
    assert_equal parent_value, reader.call(@parent),  'changing the child leaves the parent alone'
    assert_equal parent_value, reader.call(@sibling), 'changing the child leaves the sibling alone'
  end

  def test_transport
    one = SmartMessage::Transport::MemoryTransport.new
    two = SmartMessage::Transport::MemoryTransport.new

    assert_inheritable(->(k) { k.transport }, ->(k, v) { k.transport(v) }, parent_value: one, child_value: two)
  end

  def test_unrelated_classes_do_not_share_a_transport
    other = Class.new(SmartMessage::Base)
    @parent.transport(SmartMessage::Transport::MemoryTransport.new)

    assert other.transport_missing?
    assert_nil other.transport
    assert SmartMessage::Base.transport_missing?
  end

  def test_logger
    one = SmartMessage::Logger::Null.new
    two = SmartMessage::Logger::Null.new

    assert_inheritable(->(k) { k.logger }, ->(k, v) { k.logger(v) }, parent_value: one, child_value: two)
  end

  def test_version
    assert_inheritable(->(k) { k.version }, ->(k, v) { k.version(v) }, parent_value: 2, child_value: 3)

    assert_equal 3, @child.new(from: 'svc')._sm_header.version
    assert @child.new(from: 'svc').valid?, 'a fresh message of a versioned subclass is valid'
    assert_equal 3, @child.expected_header_version
  end

  def test_version_must_be_a_positive_integer
    ['2', 0, -1, 1.5, nil].each do |bad|
      next if bad.nil? # nil is the getter

      assert_raises(ArgumentError, "version #{bad.inspect} should be rejected") { @parent.version(bad) }
    end
    refute_respond_to @parent, :_version=
  end

  def test_addressing
    %i[from to reply_to].each do |field|
      setup
      assert_inheritable(->(k) { k.public_send(field) }, ->(k, v) { k.public_send(field, v) },
                         parent_value: 'parent-entity', child_value: 'child-entity')
    end
  end

  def test_addressing_reset_reveals_the_parent_value
    @parent.from('parent-entity')
    @child.from('child-entity')

    @child.reset_from

    assert_equal 'parent-entity', @child.from
  end

  def test_anonymous_classes_keep_their_addressing_when_named
    klass = Class.new(SmartMessage::Base) { from 'anonymous-origin' }
    self.class.const_set(:LaterNamed, klass)

    assert_equal 'anonymous-origin', klass.from
    assert_equal 'anonymous-origin', klass.new.from
  ensure
    self.class.send(:remove_const, :LaterNamed)
  end

  def test_validators_are_inherited
    refute @parent.new(name: 5, from: 's').valid?
    refute @child.new(name: 5, from: 's').valid?, 'a subclass enforces its parent validators'
    assert @child.new(name: 'ok', from: 's').valid?
  end

  def test_child_validators_do_not_leak_upward_or_sideways
    @child.property :age, validate: Integer

    assert_equal %i[name age], @child.validated_properties
    assert_equal %i[name],     @parent.validated_properties
    assert_equal %i[name],     @sibling.validated_properties
  end

  def test_required_rules_are_inherited
    @parent.property :code, required: true

    assert @child.required_property?(:code)
    refute @child.new(from: 's').valid?
  end

  def test_property_descriptions_are_inherited
    @child.property :age, description: 'An age'

    assert_equal 'A name', @child.property_description(:name)
    assert_equal({ name: 'A name', age: 'An age' }, @child.property_descriptions)
    assert_equal({ name: 'A name' }, @sibling.property_descriptions)
  end

  def test_deduplication_settings
    assert_inheritable(->(k) { k.ddq_config[:size] }, ->(k, v) { k.ddq_size(v) }, parent_value: 50, child_value: 7)

    @parent.enable_deduplication!
    assert @child.ddq_enabled?
    @child.disable_deduplication!
    refute @child.ddq_enabled?
    assert @parent.ddq_enabled?
    assert @sibling.ddq_enabled?
  end

  def test_deduplication_has_real_defaults_with_enable_alone
    klass = Class.new(SmartMessage::Base) { enable_deduplication! }

    assert_equal({ enabled: true, size: SmartMessage::DDQ::DEFAULT_SIZE, storage: :memory, options: {} }, klass.ddq_config)
  end

  # ---- precedence: instance, class, global configuration (K3, K4, M7) ------

  def test_global_transport_is_used_when_the_class_has_none
    global = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
    SmartMessage.configure { |config| config.transport = global }

    refute @parent.transport_missing?
    assert_same global, @parent.transport
    assert @parent.new(name: 'x', from: 's').publish.success?
    assert_equal 1, global.message_count
  end

  def test_class_transport_wins_over_global_and_instance_wins_over_class
    global   = SmartMessage::Transport::MemoryTransport.new
    klass    = SmartMessage::Transport::MemoryTransport.new
    instance = SmartMessage::Transport::MemoryTransport.new
    SmartMessage.configure { |config| config.transport = global }

    @parent.transport(klass)
    message = @parent.new(name: 'x', from: 's')
    assert_same klass, message.transport

    message.transport(instance)
    assert_same instance, message.transport
    assert_same klass, @parent.transport

    message.reset_transport
    assert_same klass, message.transport
  end

  def test_no_transport_anywhere_means_none_and_no_connections
    assert @parent.transport_missing?
    assert_nil @parent.transport
    assert_empty @parent.transports
    assert_nil SmartMessage::Transport.default
    assert_raises(SmartMessage::Errors::TransportNotConfigured) { @parent.new(name: 'x', from: 's').publish }
    assert_raises(SmartMessage::Errors::TransportNotConfigured) { @parent.subscribe { |_m| nil } }
  end

  def test_instances_read_the_class_transport_when_they_publish
    message = @parent.new(name: 'x', from: 's')
    late    = SmartMessage::Transport::MemoryTransport.new(auto_process: false)

    @parent.transport(late) # configured after the instance was built

    assert message.publish.success?
    assert_equal 1, late.message_count
  end

  def test_resolve_transports_takes_the_first_non_empty_candidate
    resolve = SmartMessage::Plugins.method(:resolve_transports)

    assert_equal [],        resolve.call(nil, [], nil)
    assert_equal [:a],      resolve.call(nil, :a, :b)
    assert_equal %i[a b],   resolve.call([], %i[a b], :c)
  end
end
