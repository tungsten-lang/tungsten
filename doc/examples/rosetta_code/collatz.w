# Hailstone sequence / Collatz conjecture

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
<< "Collatz(27): [seq.size] elements"
<< "First 4: [seq.slice(0, 4)]"
<< "Last 4:  [seq.slice(seq.size - 4, 4)]"

## expect stdout
## Collatz(27): 112 elements
## First 4: [27, 82, 41, 124]
## Last 4:  [8, 4, 2, 1]
