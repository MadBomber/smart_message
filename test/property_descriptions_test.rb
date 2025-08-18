# test/property_descriptions_test.rb

require_relative "test_helper"

module PropertyDescriptionsTest
  class MessageWithDescriptions < SmartMessage::Base
    from 'test-service'
    
    property :order_id, description: "Unique identifier for the order"
    property :amount, description: "Order total in cents"
    property :currency, default: 'USD', description: "ISO currency code"
    property :items, description: "Array of order line items"
    property :status # No description
    property :created_at, default: -> { Time.now }
  end

  class Test < Minitest::Test
    context "PropertyDescriptions module" do
      setup do
        @message_class = PropertyDescriptionsTest::MessageWithDescriptions
      end

      should "store property descriptions when defined" do
        assert_equal "Unique identifier for the order", @message_class.property_description(:order_id)
        assert_equal "Order total in cents", @message_class.property_description(:amount)
        assert_equal "ISO currency code", @message_class.property_description(:currency)
        assert_equal "Array of order line items", @message_class.property_description(:items)
      end

      should "return nil for properties without descriptions" do
        assert_nil @message_class.property_description(:status)
        assert_nil @message_class.property_description(:created_at)
      end

      should "return nil for non-existent properties" do
        assert_nil @message_class.property_description(:nonexistent)
      end

      should "return all property descriptions as a hash" do
        descriptions = @message_class.property_descriptions
        
        assert_kind_of Hash, descriptions
        assert_equal 4, descriptions.size
        assert_equal "Unique identifier for the order", descriptions[:order_id]
        assert_equal "Order total in cents", descriptions[:amount]
        assert_equal "ISO currency code", descriptions[:currency]
        assert_equal "Array of order line items", descriptions[:items]
        refute descriptions.key?(:status)
        refute descriptions.key?(:created_at)
      end

      should "return list of properties that have descriptions" do
        described_props = @message_class.described_properties
        
        assert_kind_of Array, described_props
        assert_equal 4, described_props.size
        assert_includes described_props, :order_id
        assert_includes described_props, :amount
        assert_includes described_props, :currency
        assert_includes described_props, :items
        refute_includes described_props, :status
        refute_includes described_props, :created_at
      end

      should "not affect normal property functionality" do
        message = @message_class.new(
          order_id: "ORD-123",
          amount: 2500,
          items: ["Widget A", "Widget B"],
          status: "pending"
        )

        assert_equal "ORD-123", message.order_id
        assert_equal 2500, message.amount
        assert_equal "USD", message.currency # Should use default
        assert_equal ["Widget A", "Widget B"], message.items
        assert_equal "pending", message.status
        assert_kind_of Time, message.created_at
      end

      should "maintain property descriptions across subclasses" do
        # Note: Hashie::Dash doesn't inherit property metadata, so subclasses
        # need to redefine properties to get descriptions
        class SubMessage < SmartMessage::Base
    from 'test-service'
    
          property :order_id, description: "Unique identifier for the order"
          property :extra_field, description: "An additional field"
        end

        # Subclass has its own property descriptions
        assert_equal "Unique identifier for the order", SubMessage.property_description(:order_id)
        
        # New property description should work
        assert_equal "An additional field", SubMessage.property_description(:extra_field)
        
        # Parent class should not have child's property description
        assert_nil @message_class.property_description(:extra_field)
      end

      should "work with properties that have other options like default and transform" do
        class ComplexMessage < SmartMessage::Base
    from 'test-service'
    
          property :with_default, default: "default_value", description: "Has a default value"
          property :transformed_field, transform_with: ->(v) { v.to_s.upcase }, description: "Gets uppercased"
        end

        assert_equal "Has a default value", ComplexMessage.property_description(:with_default)
        assert_equal "Gets uppercased", ComplexMessage.property_description(:transformed_field)
        
        # Test that other options still work with valid data
        message = ComplexMessage.new(
          transformed_field: "hello"
        )
        assert_equal "default_value", message.with_default
        assert_equal "HELLO", message.transformed_field
      end


      should "return empty hash when no descriptions are defined" do
        class NoDescriptionMessage < SmartMessage::Base
    from 'test-service'
    
          property :field1
          property :field2
        end

        assert_equal({}, NoDescriptionMessage.property_descriptions)
        assert_equal([], NoDescriptionMessage.described_properties)
      end
    end
  end
end