# test/configuration_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

# Global configuration (review findings K3, K4, L1, L2, R15).
class ConfigurationTest < Minitest::Test
  def config = SmartMessage.configuration

  # ---- logging -------------------------------------------------------------

  def test_no_configuration_means_no_logging_and_no_files
    Dir.mktmpdir('sm_unconfigured') do |directory|
      Dir.chdir(directory) do
        fresh = SmartMessage::Configuration.new
        fresh.dlq_path = File.join(directory, 'elsewhere', 'dlq.jsonl')
        SmartMessage.configuration = fresh

        logger = SmartMessage::Logger.default
        logger.error('goes nowhere')
        klass     = Class.new(SmartMessage::Base) { property :value }
        transport = SmartMessage::Transport::MemoryTransport.new
        klass.transport(transport)
        klass.new(value: 1, from: 'config-test').publish
        transport.dispatcher.shutdown(timeout: 1)

        assert_instance_of SmartMessage::Logger::Null, logger
        refute fresh.logger_configured?
        assert_empty Dir.children(directory), 'nothing was created in the working directory'
      end
    end
  end

  def test_the_logger_is_built_once
    config.logger = temp_path('memo.log')

    first = SmartMessage::Logger.default

    assert_instance_of SmartMessage::Logger::Lumberjack, first
    assert_same first, SmartMessage::Logger.default
    assert_same first, config.default_logger
    assert_same first, Class.new(SmartMessage::Base).logger
  end

  def test_the_logger_is_rebuilt_when_a_log_setting_changes
    config.logger = temp_path('rebuild.log')
    first = SmartMessage::Logger.default

    config.log_level = :debug
    second = SmartMessage::Logger.default

    refute_same first, second
    assert_equal 0, second.level

    config.logger = nil
    assert_instance_of SmartMessage::Logger::Null, SmartMessage::Logger.default
  end

  def test_log_settings_shape_the_lumberjack_logger
    file = temp_path('settings.log')
    SmartMessage.configure do |c|
      c.logger              = file
      c.log_level           = :warn
      c.log_format          = :json
      c.log_include_source  = false
      c.log_structured_data = false
      c.log_options         = { roll_by_size: true, keep_files: 2 }
    end

    logger = SmartMessage::Logger.default

    assert_equal file, logger.log_file
    assert_equal 2, logger.level
    assert_equal :json, logger.format
    refute logger.include_source
    refute logger.structured_data
    assert_equal [2, 10 * 1024 * 1024], logger.send(:rotation_args)
  end

  def test_any_logger_object_is_used_as_it_is
    io     = StringIO.new
    custom = ::Logger.new(io)
    config.logger = custom

    assert_same custom, SmartMessage::Logger.default

    transport = SmartMessage::Transport::MemoryTransport.new # logs through the standard Logger interface
    transport.dispatcher.shutdown(timeout: 1)
    assert_match(/MemoryTransport.*Initialized/, io.string)
  end

  def test_a_pathname_logger_is_a_log_file
    file = Pathname(temp_path('pathname.log'))
    config.logger = file

    logger = SmartMessage::Logger.default
    assert_instance_of SmartMessage::Logger::Lumberjack, logger
    assert_equal file.to_s, logger.log_file
  end

  def test_a_value_that_is_not_a_logger_is_rejected_when_set
    [:stdout, 42, Object.new].each do |bad|
      error = assert_raises(ArgumentError, "logger = #{bad.inspect}") { config.logger = bad }
      assert_match(/config\.logger must be/, error.message)
    end
    assert_nil config.logger
  end

  def test_a_class_level_logger_overrides_the_global_one
    global = SmartMessage::Logger::Null.new
    own    = SmartMessage::Logger::Null.new
    config.logger = global
    klass  = Class.new(SmartMessage::Base)

    assert_same global, klass.logger
    klass.logger(own)
    assert_same own, klass.logger
    assert_same own, klass.new(from: 'x').logger
    assert_same global, SmartMessage::Logger.default
  end

  # ---- dead letter queue path ----------------------------------------------

  def test_default_dlq_path_is_absolute_and_outside_the_working_directory
    default = SmartMessage::Configuration.default_dlq_path({})

    assert_equal File.join(Dir.home, '.local', 'state', 'smart_message', 'dead_letters.jsonl'), default
    refute default.start_with?(Dir.pwd + File::SEPARATOR) && Dir.pwd != Dir.home
  end

  def test_default_dlq_path_follows_the_environment
    path = SmartMessage::Configuration.method(:default_dlq_path)

    assert_equal '/var/state/smart_message/dead_letters.jsonl', path.call('XDG_STATE_HOME' => '/var/state')
    assert_equal '/data/app.jsonl', path.call('SMART_MESSAGE_DLQ_PATH' => '/data/app.jsonl', 'XDG_STATE_HOME' => '/var/state')
    assert_equal File.expand_path('relative.jsonl'), path.call('SMART_MESSAGE_DLQ_PATH' => 'relative.jsonl')
    assert_equal path.call({}), path.call('SMART_MESSAGE_DLQ_PATH' => '', 'XDG_STATE_HOME' => '')
  end

  def test_dlq_path_is_stored_absolute_and_used_by_the_default_queue
    target = temp_path('configured_dlq.jsonl')
    config.dlq_path = target
    SmartMessage::DeadLetterQueue.reset_default!

    assert_equal target, SmartMessage::DeadLetterQueue.default.file_path

    config.dlq_path = 'relative/dlq.jsonl'
    assert_equal File.expand_path('relative/dlq.jsonl'), config.dlq_path
  end

  # ---- transport and dispatcher --------------------------------------------

  def test_transport_setting
    refute config.transport_configured?
    assert_nil config.default_transport

    transport = SmartMessage::Transport::MemoryTransport.new
    config.transport = transport

    assert config.transport_configured?
    assert_same transport, config.default_transport
  end

  def test_dispatcher_defaults
    fresh = SmartMessage::Configuration.new

    assert_operator fresh.dispatcher_max_threads, :>=, 4
    assert_equal 1_000, fresh.dispatcher_max_queue
    assert_equal SmartMessage::DEFAULT_SHUTDOWN_TIMEOUT, fresh.shutdown_timeout
  end

  # ---- configure / reset ---------------------------------------------------

  def test_configure_yields_the_configuration_and_returns_it
    yielded = nil

    returned = SmartMessage.configure { |c| yielded = c }

    assert_same config, yielded
    assert_same config, returned
  end

  def test_reset_configuration_returns_to_the_defaults
    SmartMessage.configure do |c|
      c.logger                 = temp_path('reset.log')
      c.transport              = SmartMessage::Transport::MemoryTransport.new
      c.dispatcher_max_threads = 1
    end

    SmartMessage.reset_configuration!

    refute config.logger_configured?
    refute config.transport_configured?
    assert_equal SmartMessage::Configuration::DEFAULT_DISPATCHER_MAX_THREADS, config.dispatcher_max_threads
    assert_equal SmartMessage::Configuration.default_dlq_path, config.dlq_path
    assert_instance_of SmartMessage::Logger::Null, SmartMessage::Logger.default
  end
end
