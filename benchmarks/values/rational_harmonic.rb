t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

num = 0
den = 1
i = 1
while i <= 3000
  # num/den + 1/i = (num*i + den) / (den*i)
  num = num * i + den
  den = den * i
  # GCD reduce
  g = num.gcd(den)
  num = num / g
  den = den / g
  i += 1
end

digits = num.to_s.length

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts digits
puts "elapsed: #{'%.3f' % (t1 - t0)}s"
