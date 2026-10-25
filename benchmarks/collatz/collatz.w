## u64: n, steps, k
fn collatz_steps(n)
  k = cttz(n)
  n = n >> k
  steps = k

  while n > 1
    n = 3 * n + 1
    k = cttz(n)
    n = n >> k
    steps += 1 + k
  return steps

fn main
  total = 0 ## u64

  1..5000000 ->
    total += collatz_steps(i)

  total

<< main
