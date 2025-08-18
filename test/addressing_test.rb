# test/addressing_test.rb

require_relative "test_helper"

module AddressingTest
  
  # Test message classes for addressing functionality
  class BasicAddressingMessage < SmartMessage::Base
    from 'basic-service'
    
    property :content
  end

  class PointToPointMessage < SmartMessage::Base
    from 'sender-service'
    to 'receiver-service'
    reply_to 'callback-service'
    
    property :data
  end

  class BroadcastMessage < SmartMessage::Base
    from 'broadcast-service'
    # No 'to' field = broadcast
    
    property :announcement
  end

  class RequestMessage < SmartMessage::Base
    from 'client-service'
    to 'api-service'
    reply_to 'client-service'
    
    property :request_id
    property :payload
  end

  class ResponseMessage < SmartMessage::Base
    from 'api-service'
    # 'to' will be set dynamically
    
    property :request_id
    property :response_data
    property :success, default: true
  end

  class Test < Minitest::Test
    
    def setup
      # Reset any class-level addressing that might interfere
    end

    # =======================================================================
    # DSL Method Tests
    # =======================================================================

    def test_class_level_from_dsl_method
      assert_equal 'basic-service', BasicAddressingMessage.from
      assert_equal 'sender-service', PointToPointMessage.from
      assert_equal 'broadcast-service', BroadcastMessage.from
    end

    def test_class_level_to_dsl_method
      assert_nil BasicAddressingMessage.to
      assert_equal 'receiver-service', PointToPointMessage.to
      assert_nil BroadcastMessage.to
    end

    def test_class_level_reply_to_dsl_method
      assert_nil BasicAddressingMessage.reply_to
      assert_equal 'callback-service', PointToPointMessage.reply_to
      assert_nil BroadcastMessage.reply_to
    end

    def test_class_level_addressing_helper_methods
      # Test from helper methods
      assert PointToPointMessage.from_configured?
      refute PointToPointMessage.from_missing?

      # Test to helper methods  
      assert PointToPointMessage.to_configured?
      refute PointToPointMessage.to_missing?
      refute BroadcastMessage.to_configured?
      assert BroadcastMessage.to_missing?

      # Test reply_to helper methods
      assert PointToPointMessage.reply_to_configured?
      refute PointToPointMessage.reply_to_missing?
      refute BroadcastMessage.reply_to_configured?
      assert BroadcastMessage.reply_to_missing?
    end

    def test_class_level_addressing_reset_methods
      # Create test class to avoid affecting other tests
      test_class = Class.new(SmartMessage::Base) do
        from 'test-service'
        to 'target-service'
        reply_to 'reply-service'
      end

      # Verify initial values
      assert_equal 'test-service', test_class.from
      assert_equal 'target-service', test_class.to
      assert_equal 'reply-service', test_class.reply_to

      # Test reset methods
      test_class.reset_from
      assert_nil test_class.from

      test_class.reset_to
      assert_nil test_class.to

      test_class.reset_reply_to
      assert_nil test_class.reply_to
    end

    # =======================================================================
    # Header Field Tests
    # =======================================================================

    def test_header_contains_addressing_fields
      message = PointToPointMessage.new(data: "test")
      header = message._sm_header

      assert_equal 'sender-service', header.from
      assert_equal 'receiver-service', header.to
      assert_equal 'callback-service', header.reply_to
    end

    def test_header_addressing_with_broadcast_message
      message = BroadcastMessage.new(announcement: "System maintenance")
      header = message._sm_header

      assert_equal 'broadcast-service', header.from
      assert_nil header.to
      assert_nil header.reply_to
    end

    def test_header_addressing_field_types
      message = PointToPointMessage.new(data: "test")
      header = message._sm_header

      assert_instance_of String, header.from
      assert_instance_of String, header.to
      assert_instance_of String, header.reply_to
    end

    # =======================================================================
    # Instance-Level Addressing Tests
    # =======================================================================

    def test_instance_level_from_override
      message = PointToPointMessage.new(data: "test")
      
      # Initial value should be class default
      assert_equal 'sender-service', message.from
      
      # Override at instance level
      message.from('override-sender')
      assert_equal 'override-sender', message.from
      
      # Class value should remain unchanged
      assert_equal 'sender-service', PointToPointMessage.from
    end

    def test_instance_level_to_override
      message = PointToPointMessage.new(data: "test")
      
      # Initial value should be class default
      assert_equal 'receiver-service', message.to
      
      # Override at instance level
      message.to('override-receiver')
      assert_equal 'override-receiver', message.to
      
      # Class value should remain unchanged
      assert_equal 'receiver-service', PointToPointMessage.to
    end

    def test_instance_level_reply_to_override
      message = PointToPointMessage.new(data: "test")
      
      # Initial value should be class default
      assert_equal 'callback-service', message.reply_to
      
      # Override at instance level
      message.reply_to('override-callback')
      assert_equal 'override-callback', message.reply_to
      
      # Class value should remain unchanged
      assert_equal 'callback-service', PointToPointMessage.reply_to
    end

    def test_instance_addressing_helper_methods
      message = PointToPointMessage.new(data: "test")
      
      # Test configured? methods
      assert message.from_configured?
      assert message.to_configured?
      assert message.reply_to_configured?
      
      # Test missing? methods
      refute message.from_missing?
      refute message.to_missing?
      refute message.reply_to_missing?
    end

    def test_instance_addressing_reset_methods
      message = PointToPointMessage.new(data: "test")
      
      # Override some values
      message.from('new-sender')
      message.to('new-receiver')
      message.reply_to('new-callback')
      
      # Reset to class defaults
      message.reset_from
      assert_equal 'sender-service', message.from
      
      message.reset_to
      assert_equal 'receiver-service', message.to
      
      message.reset_reply_to
      assert_equal 'callback-service', message.reply_to
    end

    # =======================================================================
    # Address Validation Tests
    # =======================================================================

    def test_from_field_is_required
      # Attempt to create message without 'from' should fail
      assert_raises ArgumentError do
        Class.new(SmartMessage::Base) do
          # No 'from' specified
          property :data
        end.new(data: "test")
      end
    end

    def test_from_field_validation_error_message
      error = assert_raises ArgumentError do
        Class.new(SmartMessage::Base) do
          property :data
        end.new(data: "test")
      end
      
      assert_includes error.message, "From entity ID is required"
    end

    def test_to_and_reply_to_fields_are_optional
      # Should work fine without 'to' and 'reply_to'
      message_class = Class.new(SmartMessage::Base) do
        from 'test-service'
        property :data
      end
      
      message = message_class.new(data: "test")
      header = message._sm_header
      
      assert_equal 'test-service', header.from
      assert_nil header.to
      assert_nil header.reply_to
    end

    def test_message_validation_includes_addressing
      message = PointToPointMessage.new(data: "test")
      
      # Should validate successfully
      assert message.valid?
      assert_empty message.validation_errors
      
      # Validate! should not raise
      begin
        message.validate!
        assert true, "validate! should not raise for valid message"
      rescue => e
        flunk "validate! raised #{e.class}: #{e.message}"
      end
    end

    # =======================================================================
    # Messaging Pattern Tests
    # =======================================================================

    def test_point_to_point_messaging_pattern
      message = PointToPointMessage.new(data: "point-to-point test")
      header = message._sm_header
      
      # Point-to-point should have from, to, and reply_to
      assert_equal 'sender-service', header.from
      assert_equal 'receiver-service', header.to
      assert_equal 'callback-service', header.reply_to
      
      # Verify this is not a broadcast message
      refute_nil header.to
    end

    def test_broadcast_messaging_pattern
      message = BroadcastMessage.new(announcement: "broadcast test")
      header = message._sm_header
      
      # Broadcast should have from but no to
      assert_equal 'broadcast-service', header.from
      assert_nil header.to
      assert_nil header.reply_to
    end

    def test_request_reply_messaging_pattern
      # Request message
      request = RequestMessage.new(
        request_id: "REQ-123",
        payload: { action: "get_user", user_id: 456 }
      )
      request_header = request._sm_header
      
      assert_equal 'client-service', request_header.from
      assert_equal 'api-service', request_header.to
      assert_equal 'client-service', request_header.reply_to
      
      # Response message (destination set dynamically)
      response = ResponseMessage.new(
        request_id: "REQ-123",
        response_data: { user: { id: 456, name: "Alice" } },
        success: true
      )
      
      # Override instance addressing (since header is set at creation time)
      response.to(request_header.reply_to)
      
      # Verify instance addressing is set correctly
      assert_equal 'api-service', response.from
      assert_equal 'client-service', response.to  # Set via instance override
      assert_nil response.reply_to  # No default for response class
    end

    def test_gateway_pattern_addressing_override
      # Start with a message configured for internal routing
      internal_message = PointToPointMessage.new(data: "internal data")
      
      # Override for external gateway routing
      internal_message.from('gateway-service')
      internal_message.to('external-partner-api')
      internal_message.reply_to('gateway-callback')
      
      # Test instance addressing changes (not header, since header is set at creation)
      assert_equal 'gateway-service', internal_message.from
      assert_equal 'external-partner-api', internal_message.to
      assert_equal 'gateway-callback', internal_message.reply_to
      
      # Verify class defaults remain unchanged
      assert_equal 'sender-service', PointToPointMessage.from
      assert_equal 'receiver-service', PointToPointMessage.to
      assert_equal 'callback-service', PointToPointMessage.reply_to
    end

    # =======================================================================
    # Class Isolation Tests
    # =======================================================================

    def test_addressing_configuration_isolated_between_classes
      # Verify each class has independent addressing
      assert_equal 'basic-service', BasicAddressingMessage.from
      assert_equal 'sender-service', PointToPointMessage.from
      assert_equal 'broadcast-service', BroadcastMessage.from
      
      # Verify changing one doesn't affect others
      temp_class = Class.new(SmartMessage::Base) do
        from 'temp-service'
        to 'temp-target'
      end
      
      assert_equal 'temp-service', temp_class.from
      assert_equal 'temp-target', temp_class.to
      
      # Other classes should be unaffected
      assert_equal 'basic-service', BasicAddressingMessage.from
      assert_nil BasicAddressingMessage.to
    end

    def test_instance_addressing_isolated_between_instances
      message1 = PointToPointMessage.new(data: "message 1")
      message2 = PointToPointMessage.new(data: "message 2")
      
      # Override addressing on first message
      message1.from('custom-sender-1')
      message1.to('custom-receiver-1')
      
      # Second message should retain class defaults
      assert_equal 'sender-service', message2.from
      assert_equal 'receiver-service', message2.to
      
      # First message should have overrides
      assert_equal 'custom-sender-1', message1.from
      assert_equal 'custom-receiver-1', message1.to
    end

    # =======================================================================
    # Header Integration Tests
    # =======================================================================

    def test_header_inherits_from_message_addressing
      message = PointToPointMessage.new(data: "test")
      header = message._sm_header
      
      # Header should reflect current message addressing
      assert_equal message.from, header.from
      assert_equal message.to, header.to
      assert_equal message.reply_to, header.reply_to
    end

    def test_header_reflects_addressing_at_creation_time
      message = PointToPointMessage.new(data: "test")
      
      # Header should reflect addressing at creation time
      header = message._sm_header
      assert_equal 'sender-service', header.from
      assert_equal 'receiver-service', header.to
      assert_equal 'callback-service', header.reply_to
      
      # Change instance addressing after creation
      message.from('updated-sender')
      message.to('updated-receiver')
      message.reply_to('updated-callback')
      
      # Header values remain from creation time (this is the current behavior)
      assert_equal 'sender-service', header.from
      assert_equal 'receiver-service', header.to
      assert_equal 'callback-service', header.reply_to
      
      # But instance addressing has changed
      assert_equal 'updated-sender', message.from
      assert_equal 'updated-receiver', message.to
      assert_equal 'updated-callback', message.reply_to
    end

    def test_header_addressing_properties_exist
      message = BasicAddressingMessage.new(content: "test")
      header = message._sm_header
      
      # Verify addressing properties exist on header
      assert_respond_to header, :from
      assert_respond_to header, :to
      assert_respond_to header, :reply_to
      
      # Verify they return expected types
      assert_kind_of String, header.from
      assert header.to.nil? || header.to.is_a?(String)
      assert header.reply_to.nil? || header.reply_to.is_a?(String)
    end

    def test_header_addressing_properties_are_validated
      message = BasicAddressingMessage.new(content: "test")
      header = message._sm_header
      
      # Validate header includes addressing validation
      begin
        header.validate!
        assert true, "header.validate! should not raise for valid header"
      rescue => e
        flunk "header.validate! raised #{e.class}: #{e.message}"
      end
      
      # Should be valid with proper from field
      assert header.valid?
      assert_empty header.validation_errors
    end

  end # class Test < Minitest::Test
end # module AddressingTest