# Fused map-filter-reduce pipeline benchmark.
#
# Each rep r computes Σ x² for even x in (1+r .. N+r) and accumulates
# into a u64 total. Tungsten fuses the whole `/select(:even?)/sq:sum`
# chain into ONE counted loop with no intermediate arrays — the filter
# is a conditional `continue`, the map is inline `x*x`, the reduce is an
# inline accumulator fold.
#
# The per-rep range is SHIFTED by r so every pass produces a distinct
# sum — this stops an optimizing compiler from hoisting the otherwise
# loop-invariant REPS loop and running it once. The accumulated total is
# deterministic, fits u64, and is identical across every language.
#
# N/REPS come from argv (defaults 1_000_000 / 100).

a = argv()
n = 1000000
reps = 100

if a.size >= 1
  n = a[0].to_i
if a.size >= 2
  reps = a[1].to_i

total = 0 ## u64
r = 0

while r < reps
  lo = 1 + r
  hi = n + r
  total += (lo..hi)/select(:even?)/sq:sum
  r += 1

<< total
