# Per-thread BigInt limb-arena isolation (BN_BIGINT_ARENA).
#
# Six workers run interleaved bignum product chains in parallel, each on its
# own thread-private values, and every worker self-checks its results two
# independent ways (recompute + division round-trip).  Compiled, this
# exercises the per-thread limb arena: private chunks, freelist recycling
# under churn, and pool+arena teardown when each thread exits.  Any
# cross-thread contamination of arena state shows up as a wrong product or
# a crash.
#
# Run: bin/tungsten -o /tmp/bigint-thread-iso spec/numeric/bigint_thread_isolation_spec.w && /tmp/bigint-thread-iso

count = 6 ## i64
ok = i64[count]
workers = []
i = 0 ## i64
while i < count
  slot = i ## i64
  worker = Thread.new ->
    good = 1 ## i64
    base = 12345678901234567 ## big
    a = base + slot * 1000003
    # product chain: r = a^40 built by repeated multiply (grows to ~36 limbs,
    # the arena's hazard band), with interleaved churn temporaries
    r = 1 ## big
    j = 0 ## i64
    while j < 40
      r = r * a
      t = r + a          # churn temporary: exercises alloc/release interleave
      if t < r
        good = 0
      j += 1
    # check 1: independent recompute
    s = 1 ## big
    j = 0
    while j < 40
      s = s * a
      j += 1
    if r != s
      good = 0
    # check 2: division round-trip
    q = r / a
    if q * a != r
      good = 0
    if r % a != 0
      good = 0
    ok[slot] = good
  workers.push(worker)
  i += 1

i = 0
while i < count
  workers[i].join
  i += 1

fails = 0 ## i64
i = 0
while i < count
  if ok[i] != 1
    << "FAIL: worker " + i.to_s() + " produced a wrong product"
    fails += 1
  i += 1

if fails > 0
  exit(1)
<< "PASS bigint thread isolation (6 workers, 40-deep product chains)"
