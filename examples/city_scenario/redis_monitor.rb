#!/usr/bin/env ruby
# examples/city_scenario/redis_monitor.rb
# frozen_string_literal: true
#
# Shows every message the city publishes, as it happens.
#
# It listens with its own Redis connection and a pattern subscription on
# the city's namespace, so it sees the raw JSON each SmartMessage travels
# as: the message's properties plus its header under "_sm_header".

require 'json'
require 'redis'

require_relative 'common/city'

class RedisMonitor
  RESET  = "\e[0m"
  COLORS = {
    /Health/    => "\e[32m", # green
    /Fire/      => "\e[31m", # red
    /Police/    => "\e[34m", # blue
    /Alarm/     => "\e[33m", # yellow
    /Emergency/ => "\e[35m"  # magenta
  }.freeze
  STATUS_COLORS = { 'healthy' => "\e[32m", 'warning' => "\e[33m", 'critical' => "\e[93m", 'failed' => "\e[31m" }.freeze

  # The lines shown under each kind of message.
  DETAILS = {
    /HealthCheck/       => ->(data) { ["🏥 Check ID: #{data['check_id']}"] },
    /HealthStatus/      => lambda { |data|
      ["#{STATUS_COLORS.fetch(data['status'], RESET)}📊 #{data['service_name']}: #{data['status'].to_s.upcase}#{RESET}",
       "📝 #{data['details']}"]
    },
    /FireEmergency/     => lambda { |data|
      ["🔥 #{data['house_address']} - #{data['fire_type']} (#{data['severity']})", "👥 Occupants: #{data['occupants_status']}"]
    },
    /FireDispatch/      => lambda { |data|
      ["🚒 Engines: #{Array(data['engines_assigned']).join(', ')}", "📍 Location: #{data['location']}",
       "⏱️  ETA: #{data['estimated_arrival']}"]
    },
    /SilentAlarm/       => lambda { |data|
      ["🚨 #{data['bank_name']} - #{data['alarm_type']} (#{data['severity']})", "📍 #{data['location']}"]
    },
    /PoliceDispatch/    => lambda { |data|
      ["🚔 Units: #{Array(data['units_assigned']).join(', ')}", "📍 Location: #{data['location']}",
       "⏱️  ETA: #{data['estimated_arrival']}"]
    },
    /EmergencyResolved/ => lambda { |data|
      ["✅ #{data['incident_type']} resolved: #{data['outcome']}", "📍 #{data['location']}",
       "⏱️  Duration: #{data['duration_minutes']} minutes"]
    },
    /Emergency911/      => lambda { |data|
      ["📞 #{data['emergency_type']} (#{data['severity']}) at #{data['caller_location']}", "📝 #{data['description']}"]
    }
  }.freeze

  def initialize(redis: Redis.new(url: Common::City.redis_url), pattern: "#{Common::City.namespace}:*", out: $stdout)
    @redis   = redis
    @pattern = pattern
    @out     = out
  end

  def start_monitoring
    @out.puts <<~BANNER
      🔍 SmartMessage Redis Monitor
         Watching channels matching #{@pattern}
         Press Ctrl+C to stop

    BANNER

    %w[INT TERM].each { |signal| Signal.trap(signal) { exit(0) } }
    @redis.psubscribe(@pattern) do |on|
      on.pmessage { |_pattern, channel, payload| @out.puts format_message(channel, payload) }
    end
  end

  # @return [String] the lines to show for one published payload
  def format_message(channel, payload, now: Time.now)
    data   = JSON.parse(payload)
    header = data.fetch('_sm_header', {})
    name   = header['message_class'] || channel

    [
      "#{color_for(name)}[#{now.strftime('%H:%M:%S')}] #{name}#{RESET}",
      "   📤 From: #{header['from'] || 'unknown'}",
      "   📥 To: #{header['to'] || 'broadcast'}",
      *details_for(name, data).map { |line| "   #{line}" },
      ''
    ].join("\n")
  rescue JSON::ParserError, TypeError
    "📋 [#{now.strftime('%H:%M:%S')}] #{channel}: #{payload.to_s[0, 100]}\n"
  end

  # @return [Array<String>]
  def details_for(message_class, data)
    _pattern, formatter = DETAILS.find { |pattern, _formatter| pattern.match?(message_class) }
    formatter ? formatter.call(data) : []
  end

  # @return [String] an ANSI colour escape
  def color_for(message_class)
    _pattern, color = COLORS.find { |pattern, _color| pattern.match?(message_class) }
    color || "\e[37m"
  end
end

RedisMonitor.new.start_monitoring if __FILE__ == $PROGRAM_NAME
