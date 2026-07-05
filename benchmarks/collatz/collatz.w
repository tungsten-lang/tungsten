## u64: n, steps
fn collatz_steps(n)
  steps = 0

  while n != 1
    if n % 2 == 0
      n = n / 2
    else
      n = 3 * n + 1

    steps += 1
  return steps

fn main
  total = 0 ## u64

  1..5000000 ->
    total += collatz_steps(i)

  total

<< main
