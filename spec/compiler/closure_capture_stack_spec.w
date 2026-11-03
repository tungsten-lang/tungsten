# spec: compiled -- native closure scratch must fit a bounded thread stack
# A dynamic receiver keeps each block as a closure. Its capture scratch used
# to accumulate on the thread stack until SIGBUS/SIGSEGV, even though each
# invocation completed before the next iteration.

box = {"values": [1, 2, 3]}
result = i64[1]
thread = Thread.new ->
  iterations = 0
  while iterations < 1000000
    sum = 0
    box["values"].each -> (value)
      sum += value
    result[0] += sum
    iterations += 1
thread.join
raise "closure sum mismatch" if result[0] != 6000000
<< "PASS bounded closure capture stack"
