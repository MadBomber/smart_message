# test/ddq_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

# The deduplication queue backends (review findings R8, R9).
class DDQTest < Minitest::Test
  # Behaviour both backends share.  The including class defines #new_ddq.
  module Contract
    def test_reserve_is_true_once_and_false_after
      ddq = new_ddq

      assert ddq.reserve('uuid-1')
      refute ddq.reserve('uuid-1'), 'a second reservation is a duplicate'
      assert ddq.contains?('uuid-1')
      refute ddq.contains?('uuid-2')
    end

    def test_release_lets_the_uuid_be_reserved_again
      ddq = new_ddq
      ddq.reserve('uuid-1')

      ddq.release('uuid-1')

      refute ddq.contains?('uuid-1')
      assert ddq.reserve('uuid-1')
      assert_nil ddq.release('never-seen')
    end

    def test_add_records_without_answering
      ddq = new_ddq

      assert_nil ddq.add('uuid-1')
      assert_nil ddq.add('uuid-1')
      assert ddq.contains?('uuid-1')
    end

    def test_clear_forgets_everything
      ddq = new_ddq
      %w[a b c].each { |uuid| ddq.reserve(uuid) }

      ddq.clear

      assert_empty ddq.entries
      assert ddq.reserve('a')
    end

    def test_stats_and_entries
      ddq = new_ddq
      %w[a b].each { |uuid| ddq.reserve(uuid) }

      assert_equal %w[a b], ddq.entries.sort
      assert_equal 2, ddq.stats[:current_count]
      assert_equal ddq.storage_type, ddq.stats[:storage_type]
      assert_equal ddq.class.name, ddq.stats[:implementation]
    end

    def test_uuid_must_be_a_non_empty_string
      ddq = new_ddq

      [nil, '', 42, :sym].each do |bad|
        assert_raises(ArgumentError) { ddq.reserve(bad) }
        assert_raises(ArgumentError) { ddq.release(bad) }
        assert_raises(ArgumentError) { ddq.contains?(bad) }
      end
    end

    def test_exactly_one_of_many_concurrent_reservations_wins
      ddq   = new_ddq
      start = Queue.new
      wins  = Queue.new

      threads = Array.new(16) do
        Thread.new do
          start.pop
          wins << true if ddq.reserve('contested')
        end
      end
      16.times { start << :go }
      threads.each(&:join)

      assert_equal 1, wins.size
    end
  end

  class MemoryTest < Minitest::Test
    include Contract

    def new_ddq(size = 10)
      SmartMessage::DDQ::Memory.new(size)
    end

    def test_remembers_only_the_last_size_uuids
      ddq = new_ddq(3)
      %w[a b c d].each { |uuid| ddq.reserve(uuid) }

      refute ddq.contains?('a'), 'the oldest entry was evicted'
      assert_equal %w[b c d], ddq.entries
      assert_equal 3, ddq.stats[:current_count]
      assert_equal 100.0, ddq.stats[:utilization]
    end

    def test_a_released_slot_does_not_evict_a_live_entry_early
      ddq = new_ddq(3)
      %w[a b c].each { |uuid| ddq.reserve(uuid) }

      ddq.release('b')
      ddq.reserve('d') # takes the slot of 'a', the oldest

      assert_equal %w[c d], ddq.entries
      assert ddq.reserve('b')
    end

    def test_concurrent_writers_never_exceed_the_size
      ddq = new_ddq(50)

      Array.new(8) { |t| Thread.new { 200.times { |i| ddq.reserve("#{t}-#{i}") } } }.each(&:join)

      assert_equal 50, ddq.stats[:current_count]
      assert_equal 50, ddq.entries.size
      assert_equal 50, ddq.entries.uniq.size
    end

    def test_size_must_be_a_positive_integer
      [0, -1, '5', nil, 1.5].each do |bad|
        assert_raises(ArgumentError) { SmartMessage::DDQ::Memory.new(bad) }
      end
    end
  end

  class RedisTest < Minitest::Test
    include Contract

    def setup
      require_redis!
      @redis  = Redis.new(url: REDIS_TEST_URL)
      @prefix = "#{redis_namespace}:ddq"
      @ddqs   = []
    end

    def teardown
      @ddqs&.each(&:clear)
      @redis&.close
    end

    def new_ddq(size = 10, **options)
      ddq = SmartMessage::DDQ::Redis.new(size, { redis: @redis, key_prefix: @prefix }.merge(options))
      @ddqs << ddq
      ddq
    end

    def test_two_queues_with_one_prefix_share_reservations
      one = new_ddq
      two = SmartMessage::DDQ::Redis.new(10, redis: Redis.new(url: REDIS_TEST_URL), key_prefix: @prefix)

      assert one.reserve('shared')
      refute two.reserve('shared'), 'another process sees the reservation'
    ensure
      two&.redis&.close
    end

    def test_different_prefixes_are_independent
      one = new_ddq
      two = new_ddq(10, key_prefix: "#{@prefix}_other")

      assert one.reserve('uuid')
      assert two.reserve('uuid')

      one.clear
      assert two.contains?('uuid'), 'clear only removes keys under its own prefix'
    end

    def test_entries_expire_after_the_ttl
      ddq = new_ddq(10, ttl: 1)
      ddq.reserve('short-lived')

      assert_operator @redis.ttl("#{@prefix}:short-lived"), :<=, 1
      wait_until(timeout: 3, message: 'the key did not expire') { !ddq.contains?('short-lived') }
      assert ddq.reserve('short-lived')
    end

    def test_an_unreachable_server_is_reported_at_construction
      dead = Redis.new(url: 'redis://127.0.0.1:1', reconnect_attempts: 0, connect_timeout: 0.2)

      error = assert_raises(SmartMessage::Errors::TransportError) do
        SmartMessage::DDQ::Redis.new(10, redis: dead)
      end
      assert_match(/cannot connect to Redis/, error.message)
    end

    def test_fails_open_and_logs_when_redis_goes_away
      log = StringIO.new
      SmartMessage.configure { |config| config.logger = SmartMessage::Logger::Default.new(log_file: log, level: :error) }
      ddq  = new_ddq
      dead = Redis.new(url: 'redis://127.0.0.1:1', reconnect_attempts: 0, connect_timeout: 0.2)
      ddq.instance_variable_set(:@redis, dead)

      assert ddq.reserve('uuid'), 'the message is processed rather than dropped'
      refute ddq.contains?('uuid')
      assert_nil ddq.release('uuid')
      assert_match(/Error reserving UUID uuid/, log.string)
    ensure
      ddq&.instance_variable_set(:@redis, @redis)
    end
  end

  class FactoryTest < Minitest::Test
    def test_create_builds_the_requested_backend
      assert_instance_of SmartMessage::DDQ::Memory, SmartMessage::DDQ.create(:memory, 5)
      assert_instance_of SmartMessage::DDQ::Memory, SmartMessage::DDQ.create('memory')
      assert_equal SmartMessage::DDQ::DEFAULT_SIZE, SmartMessage::DDQ.create(:memory).size
    end

    def test_create_rejects_an_unknown_backend
      [:disk, nil, ''].each do |bad|
        assert_raises(ArgumentError) { SmartMessage::DDQ.create(bad) }
      end
    end

    def test_base_requires_an_implementation
      bare = SmartMessage::DDQ::Base.new(1)

      %i[clear storage_type].each { |name| assert_raises(NotImplementedError) { bare.public_send(name) } }
      %i[reserve release contains?].each { |name| assert_raises(NotImplementedError) { bare.public_send(name, 'u') } }
    end
  end
end
