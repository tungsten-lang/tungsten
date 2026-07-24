# Collatz: sum of stopping-time steps for 1..1,000,000.
# Hot loop typed `## i64` — fixed-width integers, the apples-to-apples
# comparison to C's int64_t (not Tungsten's default arbitrary-precision Int).
t0 = clock
sum = 0 ## i64
i0 = 1 ## i64
while i0 <= 1000000
  x = i0 ## i64
  steps = 0 ## i64
  while x != 1
    if x % 2 == 0
      x = x / 2
    else
      x = 3 * x + 1
    steps = steps + 1
  sum = sum + steps
  i0 = i0 + 1
t1 = clock
<< sum
<< "elapsed: [t1 - t0]s"
