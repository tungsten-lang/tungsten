require "bigdecimal"

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

e = BigDecimal("0")
rep = 0
while rep < 100000
  e = BigDecimal("0")
  factorial = BigDecimal("1")
  i = 0
  while i <= 100
    e = e + BigDecimal("1") / factorial
    factorial = factorial * (i + 1)
    i += 1
  end
  rep += 1
end

result = (e * 1000000).to_i

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts result
puts "elapsed: #{'%.3f' % (t1 - t0)}s"
