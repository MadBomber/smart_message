require 'redis'

redis = Redis.new

# Get commandstats info
cmdstats_info = redis.info("commandstats")
puts "CommandStats Info Keys:"
cmdstats_info.keys.select { |k| k.include?("publish") }.each do |key|
  puts "  #{key}: #{cmdstats_info[key]}"
end

# Parse the publish stats
cmdstat_data = cmdstats_info["cmdstat_publish"]
if cmdstat_data
  puts "\nRaw cmdstat_publish: #{cmdstat_data.inspect}"
  
  stats = {}
  cmdstat_data.split(',').each do |pair|
    key, value = pair.split('=')
    stats[key.to_sym] = value.to_f if key && value
  end
  
  puts "\nParsed stats:"
  puts "  calls: #{stats[:calls]}"
  puts "  usec: #{stats[:usec]}"
  puts "  usec_per_call: #{stats[:usec_per_call]}"
else
  puts "No cmdstat_publish found!"
end
