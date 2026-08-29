# Matched microbenchmark for fused elementwise runtime overheads.
#
# Usage:
#   runtime_overheads N ITERS fresh
#   runtime_overheads N ITERS reuse
#
# `fresh` is the ordinary reassignment spelling that automatic destination
# reuse may optimize when the old result is proven dead and unaliased.
# `reuse` is the existing explicit contract and isolates the parallel arg
# block plus scheduler from output allocation. Run each mode in a separate
# process so their allocation history and persistent-site state cannot mix.

-> run_fresh(n, iters) (i64 i64) i64
  x = i64[n]
  i = 0 ## i64
  while i < n
    x[i] = i
    i += 1

  y = (x .* 3) .+ 7
  k = 0 ## i64
  t0 = clock()
  while k < iters
    y = (x .* 3) .+ (k & 15)
    k += 1
  elapsed = clock() - t0
  checksum = y[0] + y[n - 1]
  << "fresh\tn=" + n.to_s() + "\titers=" + iters.to_s() + "\tns_per_iter=" + (elapsed * ~1000000000.0 / iters.to_f()).to_s() + "\tchecksum=" + checksum.to_s()
  checksum

-> run_reuse(n, iters) (i64 i64) i64
  x = i64[n]
  i = 0 ## i64
  while i < n
    x[i] = i
    i += 1

  y = (x .* 3) .+ 7 ## reuse
  k = 0 ## i64
  t0 = clock()
  while k < iters
    y = (x .* 3) .+ (k & 15) ## reuse
    k += 1
  elapsed = clock() - t0
  checksum = y[0] + y[n - 1]
  << "reuse\tn=" + n.to_s() + "\titers=" + iters.to_s() + "\tns_per_iter=" + (elapsed * ~1000000000.0 / iters.to_f()).to_s() + "\tchecksum=" + checksum.to_s()
  checksum

args = argv()
n = args.size() > 0 ? args[0].to_i() : 32768
iters = args.size() > 1 ? args[1].to_i() : 500
mode = args.size() > 2 ? args[2] : "reuse"

if mode == "fresh"
  run_fresh(n, iters)
else
  run_reuse(n, iters)
