require "big"

t0 = Time.monotonic

a = BigInt.new(0)
b = BigInt.new(1)
i = 0
while i < 100000
  a, b = b, a + b
  i += 1
end

digits = b.to_s.size

t1 = Time.monotonic
elapsed = (t1 - t0).total_seconds
puts digits
puts "elapsed: #{"%.3f" % elapsed}s"
