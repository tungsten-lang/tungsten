t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

a = 0
b = 1
i = 0
while i < 100000
  a, b = b, a + b
  i += 1
end

digits = b.to_s.length

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts digits
puts "elapsed: #{'%.3f' % (t1 - t0)}s"
