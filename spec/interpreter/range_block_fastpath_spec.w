-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + ": got " + got.to_s() + ", expected " + want.to_s()
    exit 1

captured = 0
0..4 -> captured++
check("captured increment", captured, 5)

# This is the interactive workload that motivated the exact linear fold. It
# must finish without walking a billion block invocations and still preserve
# the inclusive endpoint.
billion = 0
0..1_000_000_000 -> billion++
check("billion captured increments", billion, 1_000_000_001)

linear = 10
2...7 -> linear += 3
check("captured constant delta", linear, 25)

explicit = []
0...4 -> (x)
  explicit.push(x)
check("explicit parameter", explicit, [0, 1, 2, 3])

broken = []
0..9 -> (x)
  if x == 3
    break
  broken.push(x)
check("break propagation", broken, [0, 1, 2])

nexted = []
0...6 -> (x)
  if x % 2 == 0
    next
  nexted.push(x)
check("next propagation", nexted, [1, 3, 5])

stepped = []
(0..8).step(2) -> (x)
  stepped.push(x)
check("step parameter", stepped, [0, 2, 4, 6, 8])

# A nested closure retains its own invocation environment. This body must not
# take the reusable-environment path, or every closure would observe the final
# iteration's x.
closures = []
0...3 -> (x)
  closures.push(-> () x)
check("closure capture first", closures[0].call(), 0)
check("closure capture middle", closures[1].call(), 1)
check("closure capture last", closures[2].call(), 2)
