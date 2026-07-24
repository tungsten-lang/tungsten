require "big"

t0 = Time.monotonic

e = BigDecimal.new("0")
rep = 0
while rep < 100000
  e = BigDecimal.new("0")
  factorial = BigDecimal.new("1")
  i = 0
  while i <= 100
    e = e + BigDecimal.new("1") / factorial
    factorial = factorial * (i + 1)
    i += 1
  end
  rep += 1
end

result = (e * 1000000).to_big_i

t1 = Time.monotonic
elapsed = (t1 - t0).total_seconds
puts result
puts "elapsed: #{"%.3f" % elapsed}s"
