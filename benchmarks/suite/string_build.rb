t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
n = 400000
s = String.new
n.times { s << "abcdefghijklmnopqrstuvwxyz" }
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts s.length
puts format("elapsed: %.6fs", t1 - t0)
