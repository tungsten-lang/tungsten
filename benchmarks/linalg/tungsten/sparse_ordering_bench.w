# Exact minimum-degree ordering crossover benchmark.
#
# Build once, then alternate modes in fresh processes:
#   tungsten-compiler compile --release --out /tmp/sparse_ordering_bench \
#     benchmarks/linalg/tungsten/sparse_ordering_bench.w
#   /tmp/sparse_ordering_bench scan 30 20
#   /tmp/sparse_ordering_bench heap 30 20

use core/sparse

mode = ARGV[0] == nil ? "heap" : ARGV[0]
g = ARGV[1] == nil ? 30 : ARGV[1].to_i
reps = ARGV[2] == nil ? 20 : ARGV[2].to_i
n = g * g

ri = []
ci = []
i = 0
while i < n
  ri.push(i)
  ci.push(i)
  row = i / g
  col = i % g
  if col + 1 < g
    ri.push(i)
    ci.push(i + 1)
  if row + 1 < g
    ri.push(i)
    ci.push(i + g)
  i += 1

analysis = SparseAnalysis.new(SparsePattern.new(n, n, ri, ci))
scan_ref = analysis.min_degree_ordering_scan
heap_ref = analysis.min_degree_ordering_heap
raise "scan/heap ordering mismatch" if scan_ref != heap_ref

result = nil
t0 = clock()
k = 0
while k < reps
  if mode == "scan"
    result = analysis.min_degree_ordering_scan
  elsif mode == "heap"
    result = analysis.min_degree_ordering_heap
  else
    raise "mode must be scan or heap"
  k += 1
t1 = clock()

checksum = 0
i = 0
while i < result.size
  checksum = (checksum + (i + 1) * (result[i] + 1)) % 1_000_000_007
  i += 1
ns = (t1 - t0) * ~1000000000.0 / reps
<< "BENCH sparse_ordering mode=" + mode + " g=" + g.to_s + " n=" + n.to_s + " reps=" + reps.to_s + " ns_per_order=" + ns.round(1).to_s + " checksum=" + checksum.to_s
