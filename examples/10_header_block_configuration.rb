#!/usr/bin/env ruby
# examples/10_header_block_configuration.rb
#
# Demonstrates the different ways to configure message addressing:
# - Method 1: Direct class methods (from, to, reply_to)
# - Method 2: Header block DSL
# - Method 3: Instance-level overrides
# - Shortcut accessor methods for addressing

require_relative '../lib/smart_message'

puts "🎯 SmartMessage Header Block Configuration Demo"
puts "=" * 50

# =============================================================================
# Method 1: Direct Class Methods
# =============================================================================

puts "\n📡 Method 1: Direct Class Methods"
puts "-" * 40

class DirectMethodMessage < SmartMessage::Base
  version 1
  description "Configured using direct class methods"
  
  # Configure addressing using individual methods
  from 'service-a'
  to 'service-b'
  reply_to 'service-a-callback'
  
  property :data, required: true
  
  config do
    transport SmartMessage::Transport.create(:stdout)
    serializer SmartMessage::Serializer::JSON.new
  end
end

msg1 = DirectMethodMessage.new(data: "Method 1 test")
puts "From: #{msg1.from}"
puts "To: #{msg1.to}"
puts "Reply-to: #{msg1.reply_to}"

# =============================================================================
# Method 2: Header Block DSL
# =============================================================================

puts "\n📡 Method 2: Header Block DSL"
puts "-" * 40

class HeaderBlockMessage < SmartMessage::Base
  version 1
  description "Configured using header block DSL"
  
  # Configure all addressing in a single block
  header do
    from 'service-x'
    to 'service-y'
    reply_to 'service-x-callback'
  end
  
  property :data, required: true
  
  config do
    transport SmartMessage::Transport.create(:stdout)
    serializer SmartMessage::Serializer::JSON.new
  end
end

msg2 = HeaderBlockMessage.new(data: "Method 2 test")
puts "From: #{msg2.from}"
puts "To: #{msg2.to}"
puts "Reply-to: #{msg2.reply_to}"

# =============================================================================
# Method 3: Mixed Approach
# =============================================================================

puts "\n📡 Method 3: Mixed Approach"
puts "-" * 40

class MixedConfigMessage < SmartMessage::Base
  version 1
  description "Configured using mixed approaches"
  
  # Some configuration in header block
  header do
    from 'mixed-service'
    to 'target-service'
  end
  
  # Additional configuration outside block
  reply_to 'mixed-callback'
  
  property :data, required: true
  
  config do
    transport SmartMessage::Transport.create(:stdout)
    serializer SmartMessage::Serializer::JSON.new
  end
end

msg3 = MixedConfigMessage.new(data: "Method 3 test")
puts "From: #{msg3.from}"
puts "To: #{msg3.to}"
puts "Reply-to: #{msg3.reply_to}"

# =============================================================================
# Instance-Level Overrides
# =============================================================================

puts "\n📡 Instance-Level Overrides"
puts "-" * 40

class FlexibleMessage < SmartMessage::Base
  version 1
  description "Demonstrates instance-level addressing overrides"
  
  # Default configuration using header block
  header do
    from 'default-sender'
    to 'default-recipient'
    reply_to 'default-callback'
  end
  
  property :data, required: true
  
  config do
    transport SmartMessage::Transport.create(:stdout)
    serializer SmartMessage::Serializer::JSON.new
  end
end

# Create with defaults
msg4 = FlexibleMessage.new(data: "Default config")
puts "\nDefault configuration:"
puts "From: #{msg4.from}"
puts "To: #{msg4.to}"
puts "Reply-to: #{msg4.reply_to}"

# Override using method chaining
msg5 = FlexibleMessage.new(data: "Chained overrides")
msg5.from('override-sender')
    .to('override-recipient')
    .reply_to('override-callback')

puts "\nMethod chaining overrides:"
puts "From: #{msg5.from}"
puts "To: #{msg5.to}"
puts "Reply-to: #{msg5.reply_to}"

# Override using setter syntax
msg6 = FlexibleMessage.new(data: "Setter overrides")
msg6.from = 'setter-sender'
msg6.to = 'setter-recipient'
msg6.reply_to = 'setter-callback'

puts "\nSetter syntax overrides:"
puts "From: #{msg6.from}"
puts "To: #{msg6.to}"
puts "Reply-to: #{msg6.reply_to}"

# =============================================================================
# Accessing Addressing Values
# =============================================================================

puts "\n📡 Accessing Addressing Values"
puts "-" * 40

msg7 = FlexibleMessage.new(data: "Access demo")
msg7.from = 'demo-service'
msg7.to = 'demo-target'

puts "\nThree ways to access addressing:"

# Method 1: Shortcut methods (recommended)
puts "\n1. Shortcut methods:"
puts "   msg.from     => #{msg7.from}"
puts "   msg.to       => #{msg7.to}"
puts "   msg.reply_to => #{msg7.reply_to}"

# Method 2: Via header object
puts "\n2. Via header object:"
puts "   msg._sm_header.from     => #{msg7._sm_header.from}"
puts "   msg._sm_header.to       => #{msg7._sm_header.to}"
puts "   msg._sm_header.reply_to => #{msg7._sm_header.reply_to}"

# Method 3: Class defaults
puts "\n3. Class defaults (unchanged by instances):"
puts "   FlexibleMessage.from     => #{FlexibleMessage.from}"
puts "   FlexibleMessage.to       => #{FlexibleMessage.to}"
puts "   FlexibleMessage.reply_to => #{FlexibleMessage.reply_to}"

# =============================================================================
# Header Synchronization
# =============================================================================

puts "\n📡 Header Synchronization"
puts "-" * 40

msg8 = FlexibleMessage.new(data: "Sync demo")
puts "\nInitial values:"
puts "Instance from: #{msg8.from}"
puts "Header from: #{msg8._sm_header.from}"

# Change instance value
msg8.from = 'new-sender'
puts "\nAfter changing instance value:"
puts "Instance from: #{msg8.from}"
puts "Header from: #{msg8._sm_header.from} (automatically synced)"

# Headers stay in sync
msg8.to = 'new-target'
puts "\nHeaders stay synchronized:"
puts "Instance to: #{msg8.to}"
puts "Header to: #{msg8._sm_header.to}"

# =============================================================================
# Configuration Checks
# =============================================================================

puts "\n📡 Configuration Checks"
puts "-" * 40

class CheckableMessage < SmartMessage::Base
  version 1
  
  header do
    from 'check-service'
    # Note: to is not set
  end
  
  property :data
  
  config do
    transport SmartMessage::Transport.create(:stdout)
    serializer SmartMessage::Serializer::JSON.new
  end
end

# Class-level checks
puts "\nClass-level configuration checks:"
puts "from_configured?     => #{CheckableMessage.from_configured?}"
puts "to_configured?       => #{CheckableMessage.to_configured?}"
puts "reply_to_configured? => #{CheckableMessage.reply_to_configured?}"
puts "to_missing?          => #{CheckableMessage.to_missing?}"

# Instance-level checks
msg9 = CheckableMessage.new(data: "Check test")
msg9.to = 'instance-target'

puts "\nInstance-level configuration checks:"
puts "from_configured?     => #{msg9.from_configured?}"
puts "to_configured?       => #{msg9.to_configured?}"
puts "reply_to_configured? => #{msg9.reply_to_configured?}"

# Reset functionality
msg9.reset_to
puts "\nAfter reset_to:"
puts "to_configured? => #{msg9.to_configured?}"
puts "to value:      => #{msg9.to.inspect}"

puts "\n✅ Header Block Configuration Demo Complete!"