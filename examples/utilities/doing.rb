# ~/lib/ruby/doing.rb
# puts feedback stdout content around an action.

def doing(action_text = nil, ok: 'done', fail: 'failed')
  action_text ||= 'Working'
  print("#{action_text} ... ")
  STDOUT.flush
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    result  = yield if block_given?
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    elapsed_str = elapsed < 0.01 ? "<0.01s" : "#{elapsed.round(2)}s"
    puts "#{ok} #{elapsed_str}"
    result
  rescue => e
    puts "#{fail} #{e.message}"
    raise
  end
end
