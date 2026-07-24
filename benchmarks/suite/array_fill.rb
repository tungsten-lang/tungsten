t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
n = 1000000
rounds = 200
a = Array.new(n, 0)
chk = 0
rounds.times do |r|
  i = 0
  while i < n
    a[i] = i * 2654435761 + r
    i += 1
  end
  chk ^= a[(r * 7) % n]
end
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts chk
puts format("elapsed: %.6fs", t1 - t0)
