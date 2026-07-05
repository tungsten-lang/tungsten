t0 = Time.monotonic

n = 2_000_000
arr = Array(Int32).new(n, 0)
seed = 42_u32
n.times do |i|
  seed = (seed &* 1103515245_u32 &+ 12345_u32) & 0x7FFFFFFF_u32
  arr[i] = seed.to_i32
end

arr.sort!

t1 = Time.monotonic
elapsed = (t1 - t0).total_seconds
puts "first=#{arr[0]} last=#{arr[n - 1]}"
puts "elapsed: #{"%.3f" % elapsed}s"
