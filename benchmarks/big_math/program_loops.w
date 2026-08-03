# Program-level bignum loops — the Tungsten half of the E3 benchmark.
#
# The 21-op matrix times one operation against one mpz_* call, but idiomatic
# GMP reuses its destination across a loop while immutable Tungsten values
# allocate every pass: `big += small` is O(n) here and amortized O(1) there.
# You can win every matrix cell and still lose the real loop — these are the
# real loops. The C twin (program_loops_gmp.c) computes identical values
# with mpz destination reuse; the runner cross-checks the checksums.
#
# Output: <workload>\t<n>\t<ns_per_iter>\t<checksum>

-> bench_accumulate(n)
  r = 1 << 4096
  i = 0 ## i64
  t0 = clock()
  while i < n
    r = r + i
    i = i + 1
  t1 = clock()
  c = r % 1000000007
  << "accumulate\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_mulchain(n)
  # `## big`: an untyped accumulator would be raw-slot promoted and wrap at
  # i64 (factorial saturates 2-adically to 0 in 64 bits) — the documented
  # compiled tradeoff. The hint keeps the chain boxed and promoting.
  r = 1 ## big
  i = 2 ## i64
  t0 = clock()
  while i <= n
    r = r * i
    i = i + 1
  t1 = clock()
  c = r % 1000000007
  << "mulchain\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_addchain(n)
  # Same ## big rationale as mulchain: fib exceeds i64 by n=93.
  a = 0 ## big
  b = 1 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    t = a + b
    a = b
    b = t
    i = i + 1
  t1 = clock()
  c = b % 1000000007
  << "addchain\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_divchain(n)
  # The start width keeps the positive accumulator boxed across the timed
  # interval while `/ 3` steadily exercises division by an inline word.
  r = 1 << 65536 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    r = r / 3
    i = i + 1
  t1 = clock()
  c = r % 1000000007
  << "divchain\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

args = argv()
workload = args.size() > 0 ? args[0] : "all"
n = args.size() > 1 ? args[1].to_i() : 0

if workload == "accumulate" || workload == "all"
  bench_accumulate(n > 0 ? n : 2000000)
if workload == "mulchain" || workload == "all"
  bench_mulchain(n > 0 ? n : 50000)
if workload == "addchain" || workload == "all"
  bench_addchain(n > 0 ? n : 300000)
if workload == "divchain" || workload == "all"
  bench_divchain(n > 0 ? n : 30000)
