# examples/city_scenario/smart_message_ai_agent.rb
# frozen_string_literal: true
#
# A base class for an agent that reports a scenario by choosing one of the
# available SmartMessage classes, filling in its properties, and
# publishing it.
#
# With the ruby_llm gem installed and a provider API key in the
# environment, a language model chooses the message class and writes the
# property values from the class and property descriptions.  Without
# them the agent uses its fallback rules, so the program always runs.
# (ruby_llm is not a dependency of smart_message: install it yourself and
# run without `bundle exec`, or add it to your own Gemfile.)
#
# Subclasses override the hooks marked "Override".  See visitor.rb.

require 'json'

begin
  require 'ruby_llm'
rescue LoadError
  # optional: the agent falls back to rules
end

require_relative 'common/service'

class SmartMessageAIAgent
  include Common::Service

  MAX_ATTEMPTS = 3

  attr_reader :ai_available

  def initialize(service_name)
    setup_service(service_name)
    setup_ai
    logger.info("#{self.class} initialized as '#{service_name}' (AI #{ai_available ? 'available' : 'not available'})")
  end

  #########################################################
  ## Hooks

  # Override: the module that holds the message classes.
  def message_module
    Messages
  end

  # Override: return false to hide a message class from the agent.
  def include_message_class?(_message_class)
    true
  end

  # Override: the +to+ address for a message class (nil broadcasts).
  def recipient_for(_message_class)
    nil
  end

  # Override: what the model is told when it chooses a message class.
  def build_selection_context(scenario)
    "An AI agent needs to send a message for this scenario: #{scenario[:description]}"
  end

  # Override: what the model is told when it fills in the properties.
  def build_property_context(scenario, message_class)
    "Generate realistic values for a #{message_class} message based on: #{scenario[:description]}"
  end

  # Override: the message class to use when no model is available.
  # @param available [Hash] class name => message class
  def fallback_message_class(available, scenario)
    keyword = scenario[:type].to_s.downcase
    name, klass = available.find { |class_name, _klass| class_name.downcase.include?(keyword) }
    name ? klass : available.values.first
  end

  # Override: property values to use when no model is available.
  # @return [Hash] property name => value
  def generate_fallback_values(_message_class, _scenario)
    {}
  end

  # Override: configure RubyLLM providers.
  def configure_rubyllm
    RubyLLM.configure do |config|
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
      config.openai_api_key    = ENV.fetch('OPENAI_API_KEY', nil)
      config.gemini_api_key    = ENV.fetch('GEMINI_API_KEY', nil)
      config.ollama_api_base   = ENV.fetch('OLLAMA_API_BASE', nil)
      config.log_file          = Common::City.log_file("#{service_name}_llm")
      config.log_level         = :info
    end
  end

  #########################################################
  ## Reporting a scenario

  # Choose a message class for the scenario, fill it in, and publish it.
  #
  # @param scenario [Hash] :type, :description, and anything the hooks use
  # @return [SmartMessage::Base] the published message
  # @raise [SmartMessage::Errors::ValidationError] when no valid message
  #   could be built in MAX_ATTEMPTS attempts
  def send_message_for_scenario(scenario)
    message_class = select_message_class(discover_message_classes, scenario)
    logger.info("Scenario '#{scenario[:type]}' will be reported with #{message_class}")
    publish_with_retry(message_class, scenario)
  end

  # @return [Hash] class name (without the module) => message class
  def discover_message_classes
    @message_classes ||= message_module.constants.sort.filter_map do |name|
      constant = message_module.const_get(name)
      [name.to_s, constant] if message_class?(constant) && include_message_class?(constant)
    end.to_h
  end

  def message_class?(constant)
    constant.is_a?(Class) && constant < SmartMessage::Base
  end

  def select_message_class(available, scenario)
    raise ArgumentError, "#{message_module} has no message classes for #{service_name}" if available.empty?

    (ai_available && ai_select_message_class(available, scenario)) || fallback_message_class(available, scenario)
  end

  # Build a message.  Nothing is validated or published here.
  #
  # @param problems [Array<String>] validation failures of the previous attempt
  # @return [SmartMessage::Base]
  def build_message(message_class, scenario, problems = [])
    values   = ai_available && ai_property_values(message_class, scenario, problems)
    values ||= generate_fallback_values(message_class, scenario)
    values   = values.transform_keys(&:to_sym).except(:from, :to, :_sm_header)

    message_class.new(**values, from: service_name, to: recipient_for(message_class))
  end

  # Publish, giving the validation failures back to the model for another
  # try when the message is invalid.
  def publish_with_retry(message_class, scenario)
    problems = []

    MAX_ATTEMPTS.times do |attempt|
      message = build_message(message_class, scenario, problems)
      message.publish
      logger.info("Published #{message_class} (attempt #{attempt + 1})")
      return message
    rescue SmartMessage::Errors::ValidationError => e
      problems = validation_problems(e)
      logger.warn("Attempt #{attempt + 1} was invalid: #{problems.join('; ')}")
      raise if attempt == MAX_ATTEMPTS - 1 || !ai_available
    end
  end

  # @return [Array<String>] one line per failed property
  def validation_problems(error)
    error.errors.map { |failure| "Property '#{failure[:property]}' (#{failure[:value].inspect}): #{failure[:message]}" }
  end

  # @return [Hash] property name => description, with the validation rule appended
  def property_guide(message_class)
    message_class.property_descriptions.to_h do |property, description|
      rule = message_class.property_validators.dig(property, :message)
      [property, [description, rule].compact.join(' - ')]
    end
  end

  def service_emoji = '🤖'

  private

  def setup_ai
    raise LoadError, 'the ruby_llm gem is not installed' unless defined?(RubyLLM)

    configure_rubyllm
    @llm          = RubyLLM.chat
    @ai_available = true
  rescue StandardError, LoadError => e
    @ai_available = false
    logger.warn("AI not available: #{e.message}. Using fallback rules.")
  end

  # @return [Class, nil] the model's choice, or nil when it gave no usable answer
  def ai_select_message_class(available, scenario)
    descriptions = available.map { |name, klass| "#{name}: #{klass.description}" }.join("\n\n")
    answer = @llm.ask(<<~PROMPT).content.strip
      #{build_selection_context(scenario)}

      Available message types:
      #{descriptions}

      Which message type is most appropriate? Respond with ONLY the class name.
    PROMPT

    available[answer]
  rescue StandardError => e
    logger.error("AI selection failed: #{e.message}")
    nil
  end

  # @return [Hash, nil] the model's property values, or nil when it gave no usable answer
  def ai_property_values(message_class, scenario, problems)
    properties = property_guide(message_class).map { |property, guide| "#{property}: #{guide}" }.join("\n")
    retry_note = problems.empty? ? '' : "The previous attempt was invalid. Fix these:\n#{problems.join("\n")}"

    values = JSON.parse(@llm.ask(<<~PROMPT).content)
      #{build_property_context(scenario, message_class)}

      Properties to fill:
      #{properties}

      #{retry_note}
      Respond with ONLY a JSON object of property values.
    PROMPT
    values if values.is_a?(Hash)
  rescue StandardError => e
    logger.error("AI property generation failed: #{e.message}")
    nil
  end
end
