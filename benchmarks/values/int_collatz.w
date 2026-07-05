t0 = clock

sum = 0

1..1000000 ->
  x = i
  steps = 0
  while x != 1
    if x % 2 == 0
      x = x / 2
    else
      x = 3 * x + 1
    steps = steps + 1
  sum = sum + steps

t1 = clock
<< sum
<< "elapsed: [t1 - t0]s"
