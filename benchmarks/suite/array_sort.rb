t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

n = 2_000_000
arr = Array.new(n)
seed = 42
n.times do |i|
  seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
  arr[i] = seed
end

arr.sort!

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts "first=#{arr[0]} last=#{arr[n - 1]}"
puts "elapsed: #{'%.3f' % (t1 - t0)}s"
