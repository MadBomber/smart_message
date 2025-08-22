#!/usr/bin/env ruby

require 'smart_message'
# require 'smart_message/transport/redis_transport'
# require 'smart_message/serializer/json'
require 'ruby_llm'
require 'logger'
require 'json'
require 'securerandom'

# Dynamically require all message files in the messages directory
Dir[File.join(__dir__, 'messages', '*.rb')].each { |file| require file }

class Visitor
  def initialize
    @service_name = 'visitor'
    setup_logging
    setup_ai
    @logger.info("Visitor initialized - AI-powered message generation system ready")
  end

  def setup_logging
    log_file = File.join(__dir__, 'visitor.log')
    @logger = Logger.new(log_file)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
    @logger.info("Visitor logging started")
  end

  def setup_ai
    # Initialize the AI model for intelligent message selection
    begin
      configure_rubyllm
      # RubyLLM.chat returns a Chat instance, we can use it directly
      @llm = RubyLLM.chat
      @ai_available = true
      @logger.info("AI model initialized for message analysis")
    rescue => e
      @ai_available = false
      @logger.warn("AI model not available: #{e.message}. Using fallback logic.")
    end
  end


  def configure_rubyllm
    # TODO: Add some of these configuration items to AIA.config
    RubyLLM.configure do |config|
      config.anthropic_api_key  = ENV.fetch('ANTHROPIC_API_KEY', nil)
      config.deepseek_api_key   = ENV.fetch('DEEPSEEK_API_KEY', nil)
      config.gemini_api_key     = ENV.fetch('GEMINI_API_KEY', nil)
      config.gpustack_api_key   = ENV.fetch('GPUSTACK_API_KEY', nil)
      config.mistral_api_key    = ENV.fetch('MISTRAL_API_KEY', nil)
      config.openrouter_api_key = ENV.fetch('OPENROUTER_API_KEY', nil)
      config.perplexity_api_key = ENV.fetch('PERPLEXITY_API_KEY', nil)

      # These providers require a little something extra
      config.openai_api_key         = ENV.fetch('OPENAI_API_KEY', nil)
      config.openai_organization_id = ENV.fetch('OPENAI_ORGANIZATION_ID', nil)
      config.openai_project_id      = ENV.fetch('OPENAI_PROJECT_ID', nil)

      config.bedrock_api_key       = ENV.fetch('BEDROCK_ACCESS_KEY_ID', nil)
      config.bedrock_secret_key    = ENV.fetch('BEDROCK_SECRET_ACCESS_KEY', nil)
      config.bedrock_region        = ENV.fetch('BEDROCK_REGION', nil)
      config.bedrock_session_token = ENV.fetch('BEDROCK_SESSION_TOKEN', nil)

      # Ollama is based upon the OpenAI API so it needs to over-ride a few things
      config.ollama_api_base = ENV.fetch('OLLAMA_API_BASE', nil)

      # --- Custom OpenAI Endpoint ---
      # Use this for Azure OpenAI, proxies, or self-hosted models via OpenAI-compatible APIs.
      config.openai_api_base = ENV.fetch('OPENAI_API_BASE', nil) # e.g., "https://your-azure.openai.azure.com"

      # --- Default Models ---
      # Used by RubyLLM.chat, RubyLLM.embed, RubyLLM.paint if no model is specified.
      # config.default_model            = 'gpt-4.1-nano'            # Default: 'gpt-4.1-nano'
      # config.default_embedding_model  = 'text-embedding-3-small'  # Default: 'text-embedding-3-small'
      # config.default_image_model      = 'dall-e-3'                # Default: 'dall-e-3'

      # --- Connection Settings ---
      # config.request_timeout            = 120 # Request timeout in seconds (default: 120)
      # config.max_retries                = 3   # Max retries on transient network errors (default: 3)
      # config.retry_interval             = 0.1 # Initial delay in seconds (default: 0.1)
      # config.retry_backoff_factor       = 2   # Multiplier for subsequent retries (default: 2)
      # config.retry_interval_randomness  = 0.5 # Jitter factor (default: 0.5)

      # --- Logging Settings ---
      # config.log_file   = '/logs/ruby_llm.log'
      config.log_level = :fatal # debug level can also be set to debug by setting RUBYLLM_DEBUG envar to true
    end
  end


  def report_robbery
    @logger.info("Starting robbery reporting process")

    # Step 1: Collect all message descriptions
    message_descriptions = collect_message_descriptions
    @logger.info("Collected descriptions for #{message_descriptions.size} message types")

    # Step 2: Ask AI to select appropriate message for robbery
    selected_message_class = ask_ai_for_message_selection(message_descriptions)
    @logger.info("AI selected message type: #{selected_message_class}")

    # Step 3: Collect property descriptions for selected message
    property_descriptions = collect_property_descriptions(selected_message_class)
    @logger.info("Collected #{property_descriptions.size} properties for #{selected_message_class}")

    # Step 4: Generate message instance using AI
    message_instance = generate_message_instance(selected_message_class, property_descriptions)
    @logger.info("Generated message instance with AI-provided values")

    # Step 5: Publish the message
    publish_message(message_instance)
    @logger.info("Successfully published robbery report message")

    message_instance
  end

  private

  def collect_message_descriptions
    @logger.info("Scanning Messages module for available message classes")

    message_descriptions = {}

    # Get all message classes from the Messages module
    Messages.constants.each do |const_name|
      const = Messages.const_get(const_name)

      # Check if it's a SmartMessage class
      if const.is_a?(Class) && const < SmartMessage::Base
        description = const.respond_to?(:description) ? const.description : "No description available"
        message_descriptions[const_name.to_s] = {
          class: const,
          description: description
        }
        @logger.info("Found message class: #{const_name} - #{description[0..100]}...")
      end
    end

    message_descriptions
  end

  def ask_ai_for_message_selection(message_descriptions)
    @logger.info("Asking AI to select appropriate message type for robbery reporting")

    if @ai_available
      # Build prompt for AI
      descriptions_text = message_descriptions.map do |class_name, info|
        "#{class_name}: #{info[:description]}"
      end.join("\n\n")

      prompt = <<~PROMPT
        You are helping a visitor to a city report a robbery they witnessed.

        Below are the available message types in the city's emergency communication system:

        #{descriptions_text}

        Based on these options, which message type would be most appropriate for reporting a robbery?

        Please respond with ONLY the exact class name (e.g., "SilentAlarmMessage") - no additional text or explanation.
      PROMPT

      @logger.info("Sending prompt to AI for message type selection")
      @logger.info("=== AI PROMPT ===\n#{prompt}\n=== END PROMPT ===")
      begin
        response = @llm.ask(prompt)
        @logger.info("=== AI RESPONSE ===\n#{response}\n=== END RESPONSE ===")
        selected_class_name = response.content.strip

        @logger.info("AI response processed: #{selected_class_name}")

        # Validate the AI's selection
        if message_descriptions[selected_class_name]
          selected_class = message_descriptions[selected_class_name][:class]
          @logger.info("AI selection validated: #{selected_class}")
          return selected_class
        end
      rescue => e
        @logger.error("AI request failed: #{e.message}")
      end
    end

    # Fallback logic when AI is not available or fails
    @logger.info("Using fallback message selection logic")

    # Look for SilentAlarmMessage first (most appropriate for robbery)
    # SMELL: This of course is a cheat because its a known scenario
    if message_descriptions['SilentAlarmMessage']
      @logger.info("Selected SilentAlarmMessage for robbery reporting")
      return message_descriptions['SilentAlarmMessage'][:class]
    end

    # If no SilentAlarmMessage, find any message with "alarm" in the name
    alarm_message = message_descriptions.find { |name, _| name.downcase.include?('alarm') }
    if alarm_message
      @logger.info("Selected #{alarm_message[0]} as fallback alarm message")
      return alarm_message[1][:class]
    end

    # Last resort: use first available message
    first_message = message_descriptions.first
    if first_message
      @logger.info("Using first available message type: #{first_message[0]}")
      return first_message[1][:class]
    end

    raise "No valid message type found for robbery reporting"
  end

  def collect_property_descriptions(message_class)
    @logger.info("Collecting property descriptions for #{message_class}")

    # Get property descriptions using SmartMessage's built-in method
    if message_class.respond_to?(:property_descriptions)
      property_descriptions = message_class.property_descriptions
      @logger.info("Retrieved #{property_descriptions.size} property descriptions from class method")

      property_descriptions.each do |prop, desc|
        @logger.info("Property: #{prop} - #{desc}")
      end

      return property_descriptions
    else
      @logger.warn("Property descriptions method not available on #{message_class}")
      return {}
    end
  end

  def generate_message_instance(message_class, property_descriptions)
    @logger.info("Asking AI to generate property values for #{message_class}")

    property_values = nil

    if @ai_available
      # Build prompt for AI to generate property values
      properties_text = property_descriptions.map do |prop, desc|
        "#{prop}: #{desc}"
      end.join("\n")

      prompt = <<~PROMPT
        You are helping generate a robbery report message. The visitor witnessed a robbery at a local business.

        Please provide values for the following properties of a #{message_class} message:

        #{properties_text}

        Context: A visitor witnessed a robbery at a local store and wants to report it to the police.
        The visitor is reporting this incident, so the 'from' field should be set to 'visitor'.

        Please respond with a JSON object containing the property values. Use realistic values that make sense for a robbery report.
        For timestamps, use the current date/time format.

        Example format:
        {
          "property1": "value1",
          "property2": "value2"
        }
      PROMPT

      @logger.info("Sending property generation prompt to AI")
      @logger.info("=== AI PROPERTY PROMPT ===\n#{prompt}\n=== END PROMPT ===")
      begin
        response = @llm.ask(prompt)
        @logger.info("=== AI PROPERTY RESPONSE ===\n#{response}\n=== END RESPONSE ===")

        # Parse AI response as JSON
        property_values = JSON.parse(response.content)
        @logger.info("Successfully parsed AI response as JSON")
      rescue JSON::ParserError => e
        @logger.error("Failed to parse AI response as JSON: #{e.message}")
        property_values = nil
      rescue => e
        @logger.error("AI request failed: #{e.message}")
        property_values = nil
      end
    end

    # Fallback to hardcoded values if AI failed
    if property_values.nil?
      @logger.info("Using fallback property values")
      property_values = generate_fallback_values(message_class)
    end

    # Ensure 'from' is set to 'visitor'
    property_values['from'] = 'visitor'

    # Create message instance using keyword arguments
    begin
      # Convert hash to keyword arguments
      kwargs = property_values.transform_keys(&:to_sym)
      message_instance = message_class.new(**kwargs)
      @logger.info("Successfully created message instance")
      return message_instance
    rescue => e
      @logger.error("Failed to create message instance: #{e.message}")
      # Try with fallback values
      fallback_values = generate_fallback_values(message_class)
      fallback_values['from'] = 'visitor'
      fallback_kwargs = fallback_values.transform_keys(&:to_sym)
      message_instance = message_class.new(**fallback_kwargs)
      @logger.info("Created message instance with fallback values")
      return message_instance
    end
  end

  def generate_fallback_values(message_class)
    @logger.info("Generating fallback values for #{message_class}")

    # Basic fallback values for common message types
    case message_class.to_s
    when /SilentAlarmMessage/
      {
        'bank_name' => 'First National Bank',
        'location' => '123 Main Street',
        'alarm_type' => 'robbery',
        'timestamp' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        'severity' => 'high',
        'details' => 'Visitor reported armed robbery in progress',
        'from' => 'visitor'
      }
    when /PoliceDispatchMessage/
      {
        'dispatch_id' => SecureRandom.hex(4),
        'units_assigned' => ['Unit-101', 'Unit-102'],
        'location' => '123 Main Street',
        'incident_type' => 'robbery',
        'priority' => 'emergency',
        'estimated_arrival' => '3 minutes',
        'timestamp' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        'from' => 'visitor'
      }
    else
      {
        'timestamp' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        'details' => 'Visitor reported robbery incident',
        'from' => 'visitor'
      }
    end
  end

  def publish_message(message_instance)
    @logger.info("Publishing message: #{message_instance.class}")

    begin
      message_instance.publish
      @logger.info("Message published successfully to Redis transport")

      # Log the message content for debugging
      @logger.info("Published message content: #{message_instance.to_h}")
    rescue => e
      @logger.error("Failed to publish message: #{e.message}")
      raise
    end
  end
end

# Main execution
if __FILE__ == $0
  begin
    visitor = Visitor.new
    puts "🎯 Smart Visitor - AI-Powered Robbery Reporting System"
    puts "   Analyzing available message types..."
    puts "   Asking AI to select appropriate message format..."
    puts "   Generating intelligent robbery report..."
    puts "   Publishing to city emergency services..."

    message = visitor.report_robbery

    puts "\n✅ Robbery report successfully generated and published!"
    puts "   Message Type: #{message.class}"
    puts "   Content: #{message.to_h}"
    puts "   Check visitor.log for detailed execution log"
  rescue => e
    puts "\n❌ Error in visitor program: #{e.message}"
    puts "   Check visitor.log for details"
    exit(1)
  end
end
