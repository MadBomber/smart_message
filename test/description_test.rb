# test/description_test.rb

require_relative "test_helper"

module DescriptionTest
  class BasicMessage < SmartMessage::Base
    from 'test-service'
    
    description "A basic test message for unit testing"
    
    property :field1
    property :field2
  end

  class MessageWithoutDescription < SmartMessage::Base
    from 'test-service'
    
    property :data
  end

  class MessageWithLateDescription < SmartMessage::Base
    from 'test-service'
    
    property :value
  end

  class Test < Minitest::Test
    context "Class-level description" do
      should "set and retrieve message class description" do
        assert_equal "A basic test message for unit testing", BasicMessage.description
      end

      should "return default description when no description is set" do
        assert_equal "DescriptionTest::MessageWithoutDescription is a SmartMessage", MessageWithoutDescription.description
      end

      should "allow setting description after class definition" do
        MessageWithLateDescription.description "Added after class definition"
        assert_equal "Added after class definition", MessageWithLateDescription.description
      end

      should "convert description to string" do
        class SymbolDescription < SmartMessage::Base
    from 'test-service'
    
          description :symbolic_description
        end
        
        assert_equal "symbolic_description", SymbolDescription.description
      end

      should "not inherit description from parent class" do
        class ParentMessage < SmartMessage::Base
    from 'test-service'
    
          description "Parent description"
        end
        
        class ChildMessage < ParentMessage
        end
        
        assert_equal "Parent description", ParentMessage.description
        assert_equal "DescriptionTest::Test::ChildMessage is a SmartMessage", ChildMessage.description
        
        # Child can have its own description
        ChildMessage.description "Child description"
        assert_equal "Child description", ChildMessage.description
        assert_equal "Parent description", ParentMessage.description
      end

      should "work alongside property descriptions" do
        class FullyDocumented < SmartMessage::Base
    from 'test-service'
    
          description "A fully documented message class"
          
          property :id, description: "Unique identifier"
          property :name, description: "Display name"
        end
        
        assert_equal "A fully documented message class", FullyDocumented.description
        assert_equal "Unique identifier", FullyDocumented.property_description(:id)
        assert_equal "Display name", FullyDocumented.property_description(:name)
      end

      should "be settable within config block" do
        class ConfiguredMessage < SmartMessage::Base
    from 'test-service'
    
          config do
            description "Set within config block"
          end
        end
        
        assert_equal "Set within config block", ConfiguredMessage.description
      end

      should "handle empty string description" do
        class EmptyDescription < SmartMessage::Base
    from 'test-service'
    
          description ""
        end
        
        assert_equal "", EmptyDescription.description
      end

      should "handle multiline description" do
        class MultilineDescription < SmartMessage::Base
    from 'test-service'
    
          description <<~DESC
            This is a multiline description
            that spans several lines
            for detailed documentation
          DESC
        end
        
        expected = <<~DESC
          This is a multiline description
          that spans several lines
          for detailed documentation
        DESC
        
        assert_equal expected.strip, MultilineDescription.description.strip
      end
    end
  end
end