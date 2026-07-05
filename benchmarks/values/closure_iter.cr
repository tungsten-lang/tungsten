t0 = Time.monotonic

n = 2_000_000

sum = (0...n)
  .map { |x| x.to_i64 * 3 + 1 }
  .select { |x| x % 2 == 0 }
  .map { |x| x // 2 }
  .reduce(0_i64) { |acc, x| acc + x }

t1 = Time.monotonic
elapsed = (t1 - t0).total_seconds
puts sum
puts "elapsed: #{"%.3f" % elapsed}s"
