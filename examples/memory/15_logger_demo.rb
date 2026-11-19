#!/usr/bin/env ruby
# examples/memory/15_logger_demo.rb
# frozen_string_literal: true
#
# The built-in loggers
#
# config.logger selects the logger; the log_* settings shape the
# Lumberjack logger that a path, STDOUT/STDERR or :default produce:
#
#   config.logger              = 'log/app.log'   # or STDOUT, :default, a logger object
#   config.log_level           = :debug
#   config.log_format          = :json            # default :text
#   config.log_colorize        = true             # console output only
#   config.log_include_source  = true             # file:line of the caller
#   config.log_options         = { roll_by_size: true, max_file_size: 10 * 1024 * 1024, keep_files: 5 }
#
# Applications may use the same logger: SmartMessage::Logger.default.

require 'json'
require 'stringio'
require_relative '../support/example_helper'
require_relative 'messages/logged_message'

TRANSPORT = SmartMessage::Transport::MemoryTransport.new
LoggedMessage.transport(TRANSPORT)
LoggedMessage.subscribe

# Reconfigure the global logger; settings not named go back to defaults.
def configure_logger(target, level: :info, format: :text, colorize: false)
  SmartMessage.configure do |config|
    config.logger       = target
    config.log_level    = level
    config.log_format   = format
    config.log_colorize = colorize
  end
  SmartMessage::Logger.default
end

def publish_logged(title)
  LoggedMessage.new(title: title).publish
  Example.wait_for_idle(TRANSPORT)
end

# Close the current logger so its file is complete, then read the file.
# Ruby's log device starts a new file with a "# Logfile created on ..."
# comment line; that line is skipped.
def log_lines(path)
  SmartMessage::Logger.default.close
  File.readlines(path, chomp: true).reject { it.start_with?('#') }
end

Example.title 'Built-in loggers'

Example.section 'Text format to a file, level :info'
text_path = Example.tmp_path('log', 'text.log')
logger    = configure_logger(text_path)
publish_logged('text format')
logger.info('Application message', user_id: 42)
logger.debug('not written at :info')
lines = log_lines(text_path)
lines.each { puts "  #{it}" }
Example.check('the framework logged the publish') { lines.any?(/INFO .*Published: LoggedMessage/) }
Example.check('the application line carries its keyword data and source location') do
  lines.any?(/15_logger_demo\.rb:\d+ : Application message .*user_id.*42/)
end
Example.check('debug lines are filtered at :info') { lines.none?(/not written/) }

Example.section 'JSON format, level :debug'
json_path = Example.tmp_path('log', 'json.log')
logger    = configure_logger(json_path, level: :debug, format: :json)
publish_logged('json format')
logger.warn('Queue is filling up', queue: 'orders', depth: 870)
entries = log_lines(json_path).map { JSON.parse(it) }
puts "  #{entries.last}"
Example.check('every line is a JSON object with timestamp, level and message') do
  entries.all? { (%w[timestamp level message] - it.keys).empty? }
end
Example.check('keyword data is nested under "data"') do
  entries.last['data'] == { 'queue' => 'orders', 'depth' => 870 }
end
Example.check('debug entries are present at :debug') { entries.any? { it['level'] == 'DEBUG' } }

Example.section 'Colourised console output'
configure_logger(STDOUT, colorize: true)
publish_logged('console')
SmartMessage::Logger.default.error('Something to notice')
Example.check('a console logger is never closed with the logger') do
  SmartMessage::Logger.default.close
  !STDOUT.closed?
end

Example.section 'SmartMessage::Logger::Default (standard library Logger) on any IO'
buffer = StringIO.new
configure_logger(SmartMessage::Logger::Default.new(log_file: buffer, level: :warn))
publish_logged('default logger')
SmartMessage::Logger.default.warn('Disk almost full', free_mb: 12)
puts "  #{buffer.string}"
Example.check('only warn and above were written') do
  buffer.string.include?('Disk almost full') && !buffer.string.include?('Published')
end

Example.section 'Logging off again'
configure_logger(nil)
Example.check('nil selects the Null logger') { SmartMessage::Logger.default.is_a?(SmartMessage::Logger::Null) }
Example.check('all four messages were delivered meanwhile') { Example.inbox.count(:logged) == 4 }

Example.finish
