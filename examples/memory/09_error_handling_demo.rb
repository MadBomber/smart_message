#!/usr/bin/env ruby
# examples/07_error_handling_scenarios.rb
#
# Error Handling Example: SmartMessage Validation and Version Control
#
# This example demonstrates how SmartMessage handles various error conditions:
# 1. Missing required properties
# 2. Property validation failures  
# 3. Version mismatches between publishers and subscribers
#
# These scenarios help developers understand SmartMessage's robust error handling
# and how to build resilient message-based systems.

require_relative '../../lib/smart_message'

puts "=== SmartMessage Example: Error Handling Scenarios ==="
puts

# Message for testing required property validation
class UserRegistrationMessage < SmartMessage::Base
  version 1
  description "User registration data with strict validation requirements"
  
  property :user_id, 
    required: true,
    description: "Unique identifier for the new user account"
  property :email, 
    required: true,
    validate: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i,
    validation_message: "Must be a valid email address",
    description: "User's email address (must be valid format)"
  property :age, 
    required: true,
    validate: ->(v) { v.is_a?(Integer) && v.between?(13, 120) },
    validation_message: "Age must be an integer between 13 and 120",
    description: "User's age in years (13-120)"
  property :username, 
    required: true,
    validate: ->(v) { v.is_a?(String) && v.match?(/\A[a-zA-Z0-9_]{3,20}\z/) },
    validation_message: "Username must be 3-20 characters, letters/numbers/underscores only",
    description: "Unique username (3-20 chars, alphanumeric + underscore)"
  property :subscription_type, 
    required: false,
    validate: ['free', 'premium', 'enterprise'],
    validation_message: "Subscription type must be 'free', 'premium', or 'enterprise'",
    description: "User's subscription tier"
  property :created_at, 
    default: -> { Time.now.iso8601 },
    description: "Timestamp when user account was created"

  config do
    transport SmartMessage::Transport::MemoryTransport.new
  end

  def process(message)
    message_header, message_payload = message
    user_data = JSON.parse(message_payload)
    puts "✅ User registration processed: #{user_data['username']} (#{user_data['email']})"
  end
end

# Version 2 of the same message (for version mismatch testing)
class UserRegistrationMessageV2 < SmartMessage::Base
  version 2
  description "Version 2 of user registration with additional required fields"
  
  property :user_id, 
    required: true,
    description: "Unique identifier for the new user account"
  property :email, 
    required: true,
    validate: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i,
    validation_message: "Must be a valid email address",
    description: "User's email address (must be valid format)"
  property :age, 
    required: true,
    validate: ->(v) { v.is_a?(Integer) && v.between?(13, 120) },
    validation_message: "Age must be an integer between 13 and 120",
    description: "User's age in years (13-120)"
  property :username, 
    required: true,
    validate: ->(v) { v.is_a?(String) && v.match?(/\A[a-zA-Z0-9_]{3,20}\z/) },
    validation_message: "Username must be 3-20 characters, letters/numbers/underscores only",
    description: "Unique username (3-20 chars, alphanumeric + underscore)"
  property :phone_number, 
    required: true,  # New required field in version 2
    validate: ->(v) { v.is_a?(String) && v.match?(/\A\+?[1-9]\d{1,14}\z/) },
    validation_message: "Phone number must be in international format",
    description: "User's phone number in international format (new in v2)"
  property :subscription_type, 
    required: false,
    validate: ['free', 'premium', 'enterprise'],
    validation_message: "Subscription type must be 'free', 'premium', or 'enterprise'",
    description: "User's subscription tier"
  property :created_at, 
    default: -> { Time.now.iso8601 },
    description: "Timestamp when user account was created"

  config do
    transport SmartMessage::Transport::MemoryTransport.new
  end

  def process(message)
    message_header, message_payload = message
    user_data = JSON.parse(message_payload)
    puts "✅ User registration V2 processed: #{user_data['username']} (#{user_data['email']}, #{user_data['phone_number']})"
  end
end

# Message for testing Hashie::Dash limitation with multiple required fields
class MultiRequiredMessage < SmartMessage::Base
  description "Test message demonstrating Hashie::Dash required property limitation"
  
  property :field_a, required: true, description: "First required field"
  property :field_b, required: true, description: "Second required field"
  property :field_c, required: true, description: "Third required field"
  property :field_d, required: true, description: "Fourth required field"
  property :optional_field, description: "Optional field for comparison"

  config do
    transport SmartMessage::Transport::MemoryTransport.new
  end
end

# Error demonstration class
class ErrorDemonstrator
  def initialize
    puts "🚀 Starting Error Handling Demonstrations\n"
  end

  def run_all_scenarios
    scenario_1_missing_required_properties
    puts "\n" + "="*60 + "\n"
    
    scenario_2_validation_failures
    puts "\n" + "="*60 + "\n"
    
    scenario_3_version_mismatches
    puts "\n" + "="*60 + "\n"
    
    scenario_4_hashie_limitation
    puts "\n" + "="*60 + "\n"
    
    puts "✨ All error scenarios demonstrated!"
    puts "\nKey Takeaways:"
    puts "• SmartMessage validates required properties at creation time"
    puts "• Custom validation rules provide detailed error messages"
    puts "• Version mismatches are detected during message processing"
    puts "• Hashie::Dash limitation: only reports first missing required property"
    puts "• Proper error handling ensures system resilience"
  end

  private

  def scenario_1_missing_required_properties
    puts "📋 SCENARIO 1: Missing Required Properties"
    puts "="*50
    puts
    
    puts "Attempting to create UserRegistrationMessage with missing required fields..."
    puts
    
    # Test Case 1: Missing user_id
    puts "🔴 Test Case 1A: Missing user_id (required field)"
    begin
      missing_user_id = UserRegistrationMessage.new(
        email: "john@example.com",
        age: 25,
        username: "johndoe",
        from: 'ErrorDemonstrator'
      )
      puts "❌ ERROR: Should have failed but didn't!"
    rescue => e
      puts "✅ Expected error caught: #{e.class.name}"
      puts "   Message: #{e.message}"
    end
    puts

    # Test Case 2: Missing multiple required fields
    puts "🔴 Test Case 1B: Missing multiple required fields (email, age)"
    begin
      missing_multiple = UserRegistrationMessage.new(
        user_id: "USER-123",
        username: "johndoe",
        from: 'ErrorDemonstrator'
      )
      puts "❌ ERROR: Should have failed but didn't!"
    rescue => e
      puts "✅ Expected error caught: #{e.class.name}"
      puts "   Message: #{e.message}"
    end
    puts

    # Test Case 3: Valid message (should work)
    puts "🟢 Test Case 1C: All required fields provided (should succeed)"
    begin
      valid_user = UserRegistrationMessage.new(
        user_id: "USER-123",
        email: "john@example.com", 
        age: 25,
        username: "johndoe",
        from: 'ErrorDemonstrator'
      )
      puts "✅ Message created successfully"
      puts "   User: #{valid_user.username} (#{valid_user.email})"
      
      # Subscribe and publish to test processing
      UserRegistrationMessage.subscribe
      valid_user.publish
    rescue => e
      puts "❌ Unexpected error: #{e.class.name}: #{e.message}"
    end
  end

  def scenario_2_validation_failures  
    puts "📋 SCENARIO 2: Property Validation Failures"
    puts "="*50
    puts
    
    puts "Testing custom validation rules..."
    puts "Note: SmartMessage validates properties when validate! is called explicitly"
    puts "      or automatically during publish operations."
    puts

    # Test Case 1: Invalid email format
    puts "🔴 Test Case 2A: Invalid email format"
    begin
      invalid_email = UserRegistrationMessage.new(
        user_id: "USER-124",
        email: "not-an-email",  # Invalid format
        age: 25,
        username: "janedoe",
        from: 'ErrorDemonstrator'
      )
      puts "   Message created, now validating..."
      invalid_email.validate!  # Explicitly trigger validation
      puts "❌ ERROR: Should have failed validation but didn't!"
    rescue => e
      puts "✅ Expected validation error caught: #{e.class.name}"
      puts "   Message: #{e.message}"
    end
    puts

    # Test Case 2: Invalid age (too young)
    puts "🔴 Test Case 2B: Invalid age (too young)"
    begin
      invalid_age = UserRegistrationMessage.new(
        user_id: "USER-125",
        email: "kid@example.com",
        age: 10,  # Too young (< 13)
        username: "kiduser",
        from: 'ErrorDemonstrator'
      )
      puts "   Message created, now validating..."
      invalid_age.validate!  # Explicitly trigger validation
      puts "❌ ERROR: Should have failed validation but didn't!"
    rescue => e
      puts "✅ Expected validation error caught: #{e.class.name}"
      puts "   Message: #{e.message}"
    end
    puts

    # Test Case 3: Invalid username format
    puts "🔴 Test Case 2C: Invalid username (special characters)"
    begin
      invalid_username = UserRegistrationMessage.new(
        user_id: "USER-126",
        email: "user@example.com",
        age: 30,
        username: "user@123!",  # Contains invalid characters
        from: 'ErrorDemonstrator'
      )
      puts "   Message created, now validating..."
      invalid_username.validate!  # Explicitly trigger validation
      puts "❌ ERROR: Should have failed validation but didn't!"
    rescue => e
      puts "✅ Expected validation error caught: #{e.class.name}"
      puts "   Message: #{e.message}"
    end
    puts

    # Test Case 4: Invalid subscription type
    puts "🔴 Test Case 2D: Invalid subscription type"
    begin
      invalid_subscription = UserRegistrationMessage.new(
        user_id: "USER-127",
        email: "user@example.com",
        age: 30,
        username: "validuser",
        subscription_type: "platinum",  # Not in allowed list
        from: 'ErrorDemonstrator'
      )
      puts "   Message created, now validating..."
      invalid_subscription.validate!  # Explicitly trigger validation
      puts "❌ ERROR: Should have failed validation but didn't!"
    rescue => e
      puts "✅ Expected validation error caught: #{e.class.name}"
      puts "   Message: #{e.message}"
    end
    puts

    # Test Case 5: All validations pass
    puts "🟢 Test Case 2E: All validations pass (should succeed)"
    begin
      valid_user = UserRegistrationMessage.new(
        user_id: "USER-128",
        email: "valid@example.com",
        age: 25,
        username: "validuser123",
        subscription_type: "premium",
        from: 'ErrorDemonstrator'
      )
      puts "   Message created, now validating..."
      valid_user.validate!  # Explicitly trigger validation
      puts "✅ All validations passed successfully"
      puts "   User: #{valid_user.username} (#{valid_user.subscription_type} plan)"
      
      valid_user.publish
    rescue => e
      puts "❌ Unexpected error: #{e.class.name}: #{e.message}"
    end
  end

  def scenario_3_version_mismatches
    puts "📋 SCENARIO 3: Version Mismatches"
    puts "="*50
    puts
    
    puts "Testing version compatibility between publishers and subscribers..."
    puts

    # Subscribe to V1 messages
    puts "🔧 Setting up V1 subscriber..."
    UserRegistrationMessage.subscribe
    puts

    # Subscribe to V2 messages  
    puts "🔧 Setting up V2 subscriber..."
    UserRegistrationMessageV2.subscribe
    puts

    # Test Case 1: V1 message to V1 subscriber (should work)
    puts "🟢 Test Case 3A: V1 message → V1 subscriber (compatible)"
    begin
      v1_message = UserRegistrationMessage.new(
        user_id: "USER-V1-001",
        email: "v1user@example.com",
        age: 28,
        username: "v1user",
        from: 'ErrorDemonstrator'
      )
      puts "✅ V1 Message created (version #{v1_message._sm_header.version})"
      v1_message.publish
    rescue => e
      puts "❌ Unexpected error: #{e.class.name}: #{e.message}"
    end
    puts

    # Test Case 2: V2 message to V2 subscriber (should work)
    puts "🟢 Test Case 3B: V2 message → V2 subscriber (compatible)"
    begin
      v2_message = UserRegistrationMessageV2.new(
        user_id: "USER-V2-001",
        email: "v2user@example.com",
        age: 32,
        username: "v2user",
        phone_number: "+1234567890",
        from: 'ErrorDemonstrator'
      )
      puts "✅ V2 Message created (version #{v2_message._sm_header.version})"
      v2_message.publish
    rescue => e
      puts "❌ Unexpected error: #{e.class.name}: #{e.message}"
    end
    puts

    # Test Case 3: Demonstrate version mismatch handling
    puts "🔴 Test Case 3C: Version mismatch demonstration"
    puts "   Creating a message with manually modified version header..."
    begin
      # Create a V1 message but manually change its version
      version_mismatch_message = UserRegistrationMessage.new(
        user_id: "USER-MISMATCH-001",
        email: "mismatch@example.com",
        age: 35,
        username: "mismatchuser",
        from: 'ErrorDemonstrator'
      )
      
      puts "✅ Original message created with version #{version_mismatch_message._sm_header.version}"
      
      # Manually modify the header version to simulate a mismatch
      version_mismatch_message._sm_header.version = 99
      puts "🔧 Manually changed header version to #{version_mismatch_message._sm_header.version}"
      
      # Try to validate - this should catch the version mismatch
      puts "🔍 Attempting to validate message with mismatched version..."
      version_mismatch_message.validate!
      
      puts "❌ ERROR: Version mismatch should have been detected!"
    rescue => e
      puts "✅ Expected version mismatch error caught: #{e.class.name}"
      puts "   Message: #{e.message}"
    end
    puts

    # Test Case 4: Show version information
    puts "📊 Test Case 3D: Version information display"
    v1_msg = UserRegistrationMessage.new(user_id: "INFO-V1", email: "info@example.com", age: 25, username: "infouser", from: 'ErrorDemonstrator')
    v2_msg = UserRegistrationMessageV2.new(user_id: "INFO-V2", email: "info@example.com", age: 25, username: "infouser", phone_number: "+1234567890", from: 'ErrorDemonstrator')
    
    puts "📋 Version Information:"
    puts "   UserRegistrationMessage (V1):"
    puts "     Class version: #{UserRegistrationMessage.version}"
    puts "     Expected header version: #{UserRegistrationMessage.expected_header_version}"
    puts "     Instance header version: #{v1_msg._sm_header.version}"
    puts
    puts "   UserRegistrationMessageV2 (V2):"
    puts "     Class version: #{UserRegistrationMessageV2.version}"  
    puts "     Expected header version: #{UserRegistrationMessageV2.expected_header_version}"
    puts "     Instance header version: #{v2_msg._sm_header.version}"
  end

  def scenario_4_hashie_limitation
    puts "📋 SCENARIO 4: Hashie::Dash Limitation with Multiple Missing Required Properties"
    puts "="*80
    puts
    
    puts "Demonstrating a limitation in Hashie::Dash (SmartMessage's base class)..."
    puts "When multiple required properties are missing, only the FIRST one is reported."
    puts
    
    puts "🔴 Test Case 4A: All 4 required fields missing (field_a, field_b, field_c, field_d)"
    puts "Expected: Ideally should report all missing fields"
    puts "Actual Hashie::Dash behavior:"
    begin
      message = MultiRequiredMessage.new(optional_field: "present", from: 'ErrorDemonstrator')
      puts "❌ ERROR: Should have failed but didn't!"
    rescue => e
      puts "✅ Error caught: #{e.class.name}"
      puts "   Message: #{e.message}"
      puts "   📊 Analysis: Only 'field_a' is reported, despite 3 other missing required fields"
    end
    puts
    
    puts "🔴 Test Case 4B: Incremental discovery (fixing one field at a time)"
    test_data = [
      { name: "Provide field_a only", data: { field_a: "value_a", optional_field: "test" } },
      { name: "Provide field_a + field_b", data: { field_a: "value_a", field_b: "value_b", optional_field: "test" } },
      { name: "Provide field_a + field_b + field_c", data: { field_a: "value_a", field_b: "value_b", field_c: "value_c", optional_field: "test" } }
    ]
    
    test_data.each_with_index do |test_case, index|
      puts "   #{index + 1}. #{test_case[:name]}:"
      begin
        message = MultiRequiredMessage.new(test_case[:data].merge(from: 'ErrorDemonstrator'))
        puts "      ✅ Success: Message created"
      rescue => e
        field_name = e.message.match(/property '([^']+)'/)[1] rescue 'unknown'
        puts "      ❌ Still missing: #{field_name}"
      end
    end
    
    puts
    puts "📊 LIMITATION SUMMARY:"
    puts "="*50
    puts "🔍 Issue: Hashie::Dash stops validation at the first missing required property"
    puts "📋 Impact: Poor developer experience - must fix errors one at a time"
    puts "⚡ UX Problem: In forms with many required fields, users see only one error at a time"
    puts
    puts "💡 Potential Solutions:"
    puts "• Override Hashie::Dash initialization to collect ALL missing required fields"
    puts "• Add SmartMessage enhancement: validate_all_required! method"
    puts "• Provide aggregate error messages listing all missing properties"
    puts "• Use custom validation that reports multiple missing fields simultaneously"
    puts
    puts "🚀 Example of better error message:"
    puts '   "Missing required properties: field_a, field_b, field_c, field_d"'
    puts "   vs current: \"The property 'field_a' is required\""
  end
end

# Run the demo if this file is executed directly
if __FILE__ == $0
  demo = ErrorDemonstrator.new
  demo.run_all_scenarios
end