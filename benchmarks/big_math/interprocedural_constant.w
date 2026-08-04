# GEMMA-20: repeated constant-argument BigInt call experiment.
#
# The ordinary method recomputes its constant expression. `fn` is Tungsten's
# existing pure/memoized spelling. The hoisted lane is an upper-bound proxy for
# whole-program constant specialization: the same value is built once before
# timing, with only its observable low bits consumed in the loop.

-> ordinary_bignum_op(x)
  x + (1 << 4096) + (1 << 2048) + 987654321

fn memoized_bignum_op(x)
  x + (1 << 4096) + (1 << 2048) + 987654321

-> print_result(lane, n, started_at, finished_at, sink)
  << lane + "\t" + n.to_s() + "\t" + ((finished_at - started_at) * ~1000000000.0 / n.to_f()).to_s() + "\t" + sink.to_s()

-> run_ordinary(n)
  arg = 12345
  ordinary_bignum_op(arg)
  sink = 0 ## i64
  i = 0 ## i64
  t0 = clock()
  while i < n
    value = ordinary_bignum_op(arg)
    sink = sink ^ (value & 65535)
    i += 1
  t1 = clock()
  print_result("ordinary", n, t0, t1, sink)

-> run_memoized(n)
  arg = 12345
  # Seed before timing, matching the steady-state repeated-call claim.
  memoized_bignum_op(arg)
  sink = 0 ## i64
  i = 0 ## i64
  t0 = clock()
  while i < n
    value = memoized_bignum_op(arg)
    sink = sink ^ (value & 65535)
    i += 1
  t1 = clock()
  print_result("memoized", n, t0, t1, sink)

-> run_hoisted(n)
  arg = 12345
  value = arg + (1 << 4096) + (1 << 2048) + 987654321
  sink = 0 ## i64
  i = 0 ## i64
  t0 = clock()
  while i < n
    sink = sink ^ (value & 65535)
    i += 1
  t1 = clock()
  print_result("hoisted", n, t0, t1, sink)

args = argv()
lane = args.size() > 0 ? args[0] : "ordinary"
n = args.size() > 1 ? args[1].to_i() : 2000001
if lane == "ordinary"
  run_ordinary(n)
elsif lane == "memoized"
  run_memoized(n)
else
  run_hoisted(n)
