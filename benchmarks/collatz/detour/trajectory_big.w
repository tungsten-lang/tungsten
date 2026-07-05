# Compiled bignum Collatz trajectory of the maximal run-up family 2^k - 1.
#
# This runs the FULL standard-Collatz trajectory of 2^k - 1 to 1, in COMPILED Tungsten,
# on arbitrary-precision integers (the peak is ~2*3^k, a 0.48*k-digit number). The proper
# idiom for a bignum accumulator is `## big` -- it types the variable as a BigInt from the
# start, so every op (3*v, v/2, v%2, v != 1) takes the BigInt-correct path. (`Math.promote`
# is for OVERFLOW DETECTION in mostly-i64 code; it deliberately leaves `## i64`-typed values
# on the wrapping path, so it is NOT the tool for a born-big trajectory.)
#
# Validated exactly against the interpreted/Python counts and the runup.w family:
#     k=1000   -> 12157 steps          k=100000 -> 1,344,926 steps (~22 s)
# (peak = exactly 2*3^k - 2; see runup.w / Part D for why 2^k-1 = -1 mod 2^k climbs hardest.)
#
# Build + run (k defaults to 1000; pass another on the command line):
#     bin/tungsten -o /tmp/tb benchmarks/collatz/detour/trajectory_big.w && /tmp/tb 100000
#
# NOTE: compiled, not interpreted -- the whole point is that compiled bignum works here.

av = argv()
k = 1000
if av.size() > 0
  k = av[0].to_i()

v = 1 ## big          # BigInt accumulator: arithmetic + comparisons stay arbitrary-precision
i = 0
while i < k
  v = v * 2
  i = i + 1
v = v - 1             # v = 2^k - 1 (all k bits set)

steps = 0
while v != 1
  if (v % 2) == 0
    v = v / 2
  else
    v = 3 * v + 1
  steps = steps + 1

<< "2^" + k.to_s() + " - 1 reached 1 in steps: " + steps.to_s()
