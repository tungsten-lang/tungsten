# Sparse factor-reuse benchmark: one-shot factor+solve per call versus the
# retained SparseFactor (factor once / solve many / numeric refactor).
# 30x30 grid Laplacian (n = 900, SPD), deterministic RHS set.
#
#   bin/tungsten --release -o /tmp/sparse_bench benchmarks/linalg/tungsten/sparse_bench.w

use core/sparse

-> now_ms
  ccall("__w_clock_ms")

g = 30
n = g * g
upper_ri = []
upper_ci = []
upper_vv = []
i = 0
while i < n
  upper_ri.push(i)
  upper_ci.push(i)
  upper_vv.push(~4.0)
  r = i / g
  c = i % g
  if c + 1 < g
    upper_ri.push(i)
    upper_ci.push(i + 1)
    upper_vv.push(~0.0 - ~1.0)
  if r + 1 < g
    upper_ri.push(i)
    upper_ci.push(i + g)
    upper_vv.push(~0.0 - ~1.0)
  i += 1

sm = SparseMatrix.coo(n, n, upper_ri, upper_ci, upper_vv)
b = []
i = 0
while i < n
  b.push(~1.0 + (i % 7) * ~0.125)
  i += 1

reps = 50

# One-shot lane: convert + order + symbolic + numeric + solve, every call.
t0 = now_ms
x = nil
k = 0
while k < reps
  x = sm.solve_chol(b)
  k += 1
t1 = now_ms
<< "BENCH sparse_oneshot_chol_900_x" + reps.to_s + " ms=" + (t1 - t0).to_s + " x0=" + x[0].round(4).to_s

# Retained lane: factor once, solve many.
pattern = SparsePattern.new(n, n, upper_ri, upper_ci)
t0 = now_ms
factor = SparseFactor.cholesky(pattern, upper_vv)
t1 = now_ms
factor_ms = t1 - t0
t0 = now_ms
k = 0
while k < reps
  x = factor.solve(b)
  k += 1
t1 = now_ms
<< "BENCH sparse_factor_once ms=" + factor_ms.to_s
<< "BENCH sparse_reuse_solve_900_x" + reps.to_s + " ms=" + (t1 - t0).to_s + " x0=" + x[0].round(4).to_s

# Typed solve lane: no list conversion per call.
bb = ccall("w_array_new_aligned", -64, n)
xx = ccall("w_array_new_aligned", -64, n)
i = 0
while i < n
  bb[i] = b[i] + ~0.0
  i += 1
t0 = now_ms
k = 0
while k < reps
  factor.solve_into(bb, xx)
  k += 1
t1 = now_ms
<< "BENCH sparse_solve_into_900_x" + reps.to_s + " ms=" + (t1 - t0).to_s + " x0=" + xx[0].round(4).to_s

# Numeric refactor lane: same pattern, new values each round (symbolic
# analysis reused), one solve per refactor.
t0 = now_ms
k = 0
while k < reps
  scaled = []
  j = 0
  while j < upper_vv.size
    scaled.push(upper_vv[j] * (~1.0 + (k % 3) * ~0.5))
    j += 1
  factor.refactor(scaled)
  factor.solve_into(bb, xx)
  k += 1
t1 = now_ms
<< "BENCH sparse_refactor_solve_900_x" + reps.to_s + " ms=" + (t1 - t0).to_s
factor.release

# Analysis-only predictions (result-only kernels).
t0 = now_ms
analysis = SparseAnalysis.new(pattern)
fill = analysis.predicted_fill
flops = analysis.predicted_flops
t1 = now_ms
<< "BENCH sparse_analysis_900 ms=" + (t1 - t0).to_s + " fill=" + fill.to_s + " flops=" + flops.to_s

<< "sparse_bench done"
