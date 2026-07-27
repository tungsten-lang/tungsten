# The multiplier operand is masked to 15 bits so the product stays inside
# the 47-bit inline-int payload: (2^15)(2654435761) < 2^47. The original
# unmasked form overflowed i48 from v ~ 106k on, so 98%+ of iterations
# allocated BigInts through w_mul's promotion path — the "method dispatch"
# primitive was really measuring bignum malloc churn (53% allocation in the
# branch profile).
+ Mixer
  -> new(@k)
    self
  -> mix(v)
    ((v & 32767) * 2654435761) ^ @k

# primitive: method_call — 8000000 ops
chk = 0 ## i64
o = Mixer.new(7)
n = 8000000 ## i64
__ev = env("BENCH_ITERS")
if __ev != nil && __ev != ""
  n = __ev.to_i() ## i64
t0 = clock
i = 0 ## i64
while i < n
  chk = chk ^ o.mix(i)
  i = i + 1
t1 = clock
<< "ops: [n]"
<< chk
<< "elapsed: [t1 - t0]s"
