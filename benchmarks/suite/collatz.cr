t0 = Time.instant

sum = 0_i64
n = 1_i64
while n <= 1_000_000
  x = n
  steps = 0_i64
  while x != 1
    if x % 2 == 0
      x = x // 2
    else
      x = 3_i64 &* x &+ 1_i64
    end
    steps += 1
  end
  sum += steps
  n += 1
end

t1 = Time.instant
elapsed = (t1 - t0).total_seconds
puts sum
puts "elapsed: #{"%.3f" % elapsed}s"
