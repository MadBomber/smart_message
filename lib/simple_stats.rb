# lib/simple_stats.rb

require 'ap'

# A dirt simple way of collecting statistics for use in testing
# that has a multi-level key structure
class SimpleStats
  @@stat = Hash.new

  class << self

    # return the internal Hash
    def stat
      @@stat
    end


    # return the count for a specific multi-level key
    def get(*args)
      return 0 if args.empty?
      key = get_key(args)
      @@stat.key?(key) ? @@stat[key] : @@stat[key] = 0
    end


    # increment (add) counts to a multi-level key
    def add(*args, how_many: 1)
      return 0 if args.empty?
      key = get_key(args)
      @@stat.key?(key) ? @@stat[key] += how_many : @@stat[key] = how_many
    end


    def reset(*args)
      return 0 if args.empty?
      key = get_key(args)
      @@stat[key] = 0
    end


    # simulate a multi-level key using a level seperater
    def get_key(an_array, sep:'+')
      an_array.join(sep)
    end


    # return a pretty printed representation of the statistics
    def to_s
      ap @@stat
    end
  end
end # class SimpleStat

SS = SimpleStats
