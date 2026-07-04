# Collatz conjecture / Hailstone sequence

-> collatz(n)
  seq = [n]
  while n != 1
    if n % 2 == 0
      n = n / 2
    else
      n = 3 * n + 1
    seq.push(n)
  seq

seq = collatz(27)
puts "Collatz(27): [seq.length] steps"
puts "First 10: [seq.first(10)]"
puts "Last 10:  [seq.last(10)]"

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten collatz.w`
## expect stdout
## Collatz(27): 112 steps
## First 10: 27
## Last 10:  1
