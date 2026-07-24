require "big"

t0 = Time.monotonic

num = BigInt.new(0)
den = BigInt.new(1)
i = 1
while i <= 3000
  # num/den + 1/i = (num*i + den) / (den*i)
  num = num * i + den
  den = den * i
  # GCD reduce
  g = num.gcd(den)
  num = num // g
  den = den // g
  i += 1
end

digits = num.to_s.size

t1 = Time.monotonic
elapsed = (t1 - t0).total_seconds
puts digits
puts "elapsed: #{"%.3f" % elapsed}s"
