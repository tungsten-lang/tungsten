t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

sum = 0
n = 1
while n <= 1_000_000
  x = n
  steps = 0
  while x != 1
    if x % 2 == 0
      x = x / 2
    else
      x = 3 * x + 1
    end
    steps += 1
  end
  sum += steps
  n += 1
end

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts sum
puts "elapsed: #{'%.3f' % (t1 - t0)}s"
