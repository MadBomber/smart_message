# test/logger_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

# The three loggers share one interface (review findings L1 to L4).
module LoggerContract
  LEVELS = SmartMessage::Logger::LEVELS

  # The including class defines #new_logger(level:) and #output (what the
  # logger has written so far, as a String).

  def test_contract_every_level_takes_a_string_a_block_and_keyword_data
    logger = new_logger(level: :debug)

    LEVELS.each do |level|
      assert_nil logger.public_send(level, "#{level} as a string").then { nil }
      logger.public_send(level) { "#{level} as a block" }
      logger.public_send(level, "#{level} with data", order_id: 42, tags: %w[a b])
    end
  end

  def test_contract_level_accepts_symbols_strings_and_integers
    logger = new_logger(level: :debug)

    { warn: 2, 'error' => 3, 'INFO' => 1, 0 => 0, fatal: 4 }.each do |given, expected|
      logger.level = given
      assert_equal expected, SmartMessage::Logger.severity(given)
    end
  end

  def test_contract_unknown_levels_are_rejected
    logger = new_logger(level: :info)

    [:loud, 'verbose', 9, -1, nil].each do |bad|
      assert_raises(ArgumentError, "level #{bad.inspect}") { logger.level = bad }
      assert_raises(ArgumentError, "add #{bad.inspect}") { logger.add(bad, 'text') }
    end
  end

  def test_contract_predicates_exist_for_every_level
    logger = new_logger(level: :warn)

    LEVELS.each { |level| assert_includes [true, false], logger.public_send(:"#{level}?") }
  end

  def test_contract_add_logs_at_the_given_level
    logger = new_logger(level: :debug)

    logger.add(:warn, 'added by symbol')
    logger.add(3, 'added by number', key: 'value')
    logger.add('info') { 'added by block' }
  end

  def test_contract_close_can_be_called
    new_logger(level: :info).close
  end

  def test_contract_works_as_the_framework_logger
    logger = new_logger(level: :debug)
    SmartMessage.configure { |config| config.logger = logger }

    assert_same logger, SmartMessage::Logger.default

    transport = SmartMessage::Transport::MemoryTransport.new
    klass     = Class.new(SmartMessage::Base) { property :value }
    klass.transport(transport)
    assert klass.new(value: 1, from: 'logger-test').publish.success?
  ensure
    transport&.dispatcher&.shutdown(timeout: 1)
  end
end

# Loggers that write somewhere also share these.
module WritingLoggerContract
  include LoggerContract

  def test_writes_messages_at_or_above_the_level_only
    logger = new_logger(level: :warn)

    logger.debug('debug text')
    logger.info('info text')
    logger.warn('warn text')
    logger.error('error text')
    logger.fatal('fatal text')

    refute_match(/debug text|info text/, output)
    assert_match(/WARN.*warn text/, output)
    assert_match(/ERROR.*error text/, output)
    assert_match(/FATAL.*fatal text/, output)
  end

  def test_predicates_follow_the_level
    logger = new_logger(level: :warn)

    assert_equal [false, false, true, true, true], LEVELS.map { |level| logger.public_send(:"#{level}?") }
    assert_equal 2, logger.level

    logger.level = :debug
    assert logger.debug?
  end

  def test_a_block_below_the_level_is_never_evaluated
    logger = new_logger(level: :error)
    called = false

    logger.debug do
      called = true
      'expensive'
    end

    refute called
    refute_match(/expensive/, output)
  end

  def test_a_block_at_the_level_is_evaluated_and_written
    logger = new_logger(level: :info)

    logger.info { 'built lazily' }

    assert_match(/built lazily/, output)
  end

  def test_changing_the_level_takes_effect
    logger = new_logger(level: :error)
    logger.info('hidden')

    logger.level = :info
    logger.info('shown')

    refute_match(/hidden/, output)
    assert_match(/shown/, output)
  end

  def test_the_line_names_the_calling_file_and_line
    logger = new_logger(level: :info)

    logger.info('where am I'); line = __LINE__
    logger.add(:info, 'and here'); added = __LINE__

    assert_match(/logger_test\.rb:#{line}\b.*where am I/, output)
    assert_match(/logger_test\.rb:#{added}\b.*and here/, output)
  end

  def test_keyword_data_is_written
    logger = new_logger(level: :info)

    logger.info('with data', order_id: 42)

    assert_match(/with data.*order_id.*42/, output)
  end
end

class NullLoggerTest < Minitest::Test
  include LoggerContract

  def new_logger(level: nil)
    SmartMessage::Logger::Null.new
  end

  def test_nothing_is_enabled_and_blocks_are_never_evaluated
    logger = new_logger
    called = false

    SmartMessage::Logger::LEVELS.each do |level|
      refute logger.public_send(:"#{level}?")
      assert_nil logger.public_send(level) { called = true }
    end

    refute called
    logger.level = :debug
    refute logger.debug?, 'a null logger stays silent whatever level it is given'
  end
end

class DefaultLoggerTest < Minitest::Test
  include WritingLoggerContract

  def new_logger(level: nil)
    @io = StringIO.new
    SmartMessage::Logger::Default.new(log_file: @io, level: level)
  end

  def output = @io.string

  def test_defaults_to_info
    assert_equal 1, SmartMessage::Logger::Default.new(log_file: StringIO.new).level
  end

  def test_line_format
    logger = new_logger(level: :info)

    logger.info('formatted')

    assert_match(/\A\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\] INFO  -- logger_test\.rb:\d+ : formatted\n\z/, output)
  end

  def test_writes_to_a_file_and_creates_its_directory
    file   = File.join(temp_path('logs'), 'nested', 'default.log')
    logger = SmartMessage::Logger::Default.new(log_file: file)

    logger.info('to a file')
    logger.close

    assert_match(/to a file/, File.read(file))
    assert_equal file, logger.log_file
  end

  def test_close_leaves_an_io_it_was_handed_open
    logger = new_logger

    logger.close

    refute @io.closed?
  end
end

class LumberjackLoggerTest < Minitest::Test
  include WritingLoggerContract

  LJ = SmartMessage::Logger::Lumberjack

  def new_logger(level: nil, **options)
    @file = temp_path('lumberjack.log')
    @last = LJ.new(log_file: @file, level: level, **options)
  end

  def output
    @last.logger.flush
    File.read(@file)
  end

  # Parsed JSON lines, without the "# Logfile created" header
  def json_lines
    output.lines.reject { |line| line.start_with?('#') }.map { |line| JSON.parse(line) }
  end

  def test_defaults
    logger = new_logger

    assert_equal 1, logger.level
    assert_equal :text, logger.format
    assert logger.include_source
    assert logger.structured_data
    refute logger.colorize
    refute logger.console_output?
  end

  def test_text_format
    logger = new_logger(level: :info)

    logger.warn('text line', order_id: 42)

    assert_match(/^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\] WARN  -- logger_test\.rb:\d+ : text line \{order_id: 42\}$/, output)
  end

  def test_json_format_nests_keyword_data_under_data
    logger = new_logger(level: :debug, format: :json)

    logger.info('json line', order_id: 42, message: 'not the log message', 'dotted.key' => { nested: [1, :two] })
    logger.debug { 'no data' }

    first, second = json_lines
    assert_equal %w[timestamp level message source data], first.keys
    assert_equal 'INFO', first['level']
    assert_equal 'json line', first['message'], 'keyword data cannot overwrite the reserved fields'
    assert_match(/\Alogger_test\.rb:\d+\z/, first['source'])
    assert_equal({ 'order_id' => 42, 'message' => 'not the log message', 'dotted.key' => { 'nested' => [1, 'two'] } }, first['data'])
    assert_equal %w[timestamp level message source], second.keys
    assert_equal 'DEBUG', second['level']
  end

  def test_source_and_data_can_be_turned_off
    logger = new_logger(level: :info, format: :json, include_source: false, structured_data: false)

    logger.info('bare', order_id: 42)

    assert_equal %w[timestamp level message], json_lines.first.keys
  end

  def test_colour_is_for_the_console_only
    refute new_logger(colorize: true).colorize, 'a file is never coloured'

    assert_equal "\e[1;37;41mline\e[0m", LJ.colorize_line('line', 'ERROR')
    assert_equal "\e[97mline\e[0m", LJ.colorize_line('line', :info)
    assert_equal 'line', LJ.colorize_line('line', 'UNKNOWN')
  end

  def test_console_output_is_coloured_when_asked
    out, _err = capture_subprocess_io do
      logger = LJ.new(log_file: STDOUT, level: :info, colorize: true)
      assert logger.console_output?
      assert logger.colorize
      logger.error('on the console')
      logger.logger.flush
      logger.close
    end

    assert_match(/\e\[1;37;41m.*ERROR.*on the console.*\e\[0m/, out)
    refute STDOUT.closed?
  end

  def test_rotates_by_size_inside_its_own_directory
    directory = temp_path('rotation')
    file      = File.join(directory, 'rotating.log')
    logger    = LJ.new(log_file: file, roll_by_size: true, max_file_size: 500, keep_files: 3)

    60.times { |i| logger.info("line #{i} #{'x' * 60}") }
    logger.logger.flush
    logger.close

    files = Dir.children(directory).sort
    assert_includes files, 'rotating.log'
    assert_operator files.size, :>, 1, 'the log was rotated'
    assert_operator files.size, :<=, 3, 'old files beyond keep_files are removed'
    assert(files.all? { |name| name.start_with?('rotating.log') })
  end

  def test_rotation_arguments
    args = ->(**options) { LJ.new(log_file: temp_path('args.log'), **options).send(:rotation_args) }

    assert_equal [], args.call
    assert_equal [5, 10 * 1024 * 1024], args.call(roll_by_size: true)
    assert_equal [2, 99], args.call(roll_by_size: true, keep_files: 2, max_file_size: 99)
    assert_equal ['daily'], args.call(roll_by_date: true)
    assert_equal ['weekly'], args.call(roll_by_date: true, roll_period: 'weekly')
  end
end

class LoggerModuleTest < Minitest::Test
  def test_severity
    assert_equal [0, 1, 2, 3, 4], SmartMessage::Logger::LEVELS.map { |level| SmartMessage::Logger.severity(level) }
    assert_equal 2, SmartMessage::Logger.severity('WARN')
    assert_equal ::Logger::ERROR, SmartMessage::Logger.severity(:error)
    assert_raises(ArgumentError) { SmartMessage::Logger.severity(:unknown) }
    assert_raises(ArgumentError) { SmartMessage::Logger.severity(5) }
  end

  def test_an_override_wins_until_it_is_reset
    override = SmartMessage::Logger::Null.new

    SmartMessage::Logger.default = override
    assert_same override, SmartMessage::Logger.default

    SmartMessage::Logger.reset!
    refute_same override, SmartMessage::Logger.default
  end

  def test_base_requires_an_implementation
    bare = SmartMessage::Logger::Base.new

    assert_raises(NotImplementedError) { bare.level }
    assert_raises(NotImplementedError) { bare.level = :info }
    assert_raises(NotImplementedError) { bare.add(:info, 'text') }
    assert_nil bare.close
  end
end
