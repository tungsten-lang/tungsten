t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

n = 2_000_000

sum = (0...n)
  .map { |x| x * 3 + 1 }
  .select { |x| x % 2 == 0 }
  .map { |x| x / 2 }
  .reduce(0, :+)

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts sum
puts "elapsed: #{'%.3f' % (t1 - t0)}s"
