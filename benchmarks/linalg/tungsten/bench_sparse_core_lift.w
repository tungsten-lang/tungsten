# Isolate the sparse degree-3 core-lift lane on one flat COO pattern.
#
#   bench_sparse_core_lift PATTERN
#
# PATTERN is `n m r0 c0 ...`, the same compact format used by the SSI corpus
# adapter.  Prints the production structural-admission decision and the exact
# whole-pattern flop score of residual AMD plus reduction dimensions and time.

use core/sparse_factor

path = ARGV[0]
toks = File.read(path).split(" ")
n = toks[0].to_i
m = toks[1].to_i
ri = []
ci = []
k = 0
while k < m
  ri.push(toks[2 + 2 * k].to_i)
  ci.push(toks[3 + 2 * k].to_i)
  k += 1

analysis = SparseAnalysis.new(SparsePattern.new(n, n, ri, ci))
t0 = clock_ms
reduced = SparseAnalysis.sparse_core_lift_reduce(
  n, analysis.typed_ri, analysis.typed_ci, m, 3)
t1 = clock_ms
if reduced == nil
  << "reduce\tnil\tms\t" + (t1 - t0).to_s
  exit(0)

prefix = reduced[0]
prefix_n = reduced[1]
core_vertices = reduced[2]
core_n = reduced[3]
core_ri = reduced[4]
core_ci = reduced[5]
core_m = reduced[6]
prefix_flops = reduced[7]
summary = "reduce\tn\t" + n.to_s + "\tm\t" + m.to_s
summary += "\tprefix\t" + prefix_n.to_s + "\tcore_n\t" + core_n.to_s
summary += "\tcore_m\t" + core_m.to_s + "\tprefix_flops\t" + prefix_flops.to_s
summary += "\tms\t" + (t1 - t0).to_s
<< summary

admitted = SparseAnalysis.sparse_core_lift_candidate_fits?(
  n, m, core_n, core_m)
<< "admitted\t" + admitted.to_s
if admitted
  v0 = clock_ms
  core_order = analysis.amd_core(core_n, core_ri, core_ci, core_m)
  candidate = []
  i = 0
  while i < prefix_n
    candidate.push(prefix[i])
    i += 1
  i = 0
  while i < core_n
    candidate.push(core_vertices[core_order[i]])
    i += 1
  pred = analysis.predictions_for_order(candidate)
  v1 = clock_ms
  result = "amd\tfill\t" + pred[0].to_s
  result += "\tflops\t" + pred[1].to_s + "\tms\t" + (v1 - v0).to_s
  << result

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
