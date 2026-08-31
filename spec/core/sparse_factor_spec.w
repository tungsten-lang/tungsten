# SparsePattern / SparseAnalysis / SparseFactor — factor reuse, numeric
# refactorization, typed solve lane, analysis predictions, budget gate,
# and LinAlg.slogdet.

use core/sparse

failures = 0
-> check_named(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    failures += 1

# 5-point Laplacian on a g x g grid (SPD, no exact cancellation).
g = 6
n = g * g
upper_ri = []
upper_ci = []
upper_vv = []
full_ri = []
full_ci = []
i = 0
while i < n
  upper_ri.push(i)
  upper_ci.push(i)
  upper_vv.push(~4.0)
  full_ri.push(i)
  full_ci.push(i)
  r = i / g
  c = i % g
  if c + 1 < g
    upper_ri.push(i)
    upper_ci.push(i + 1)
    upper_vv.push(~0.0 - ~1.0)
    full_ri.push(i)
    full_ci.push(i + 1)
    full_ri.push(i + 1)
    full_ci.push(i)
  if r + 1 < g
    upper_ri.push(i)
    upper_ci.push(i + g)
    upper_vv.push(~0.0 - ~1.0)
    full_ri.push(i)
    full_ci.push(i + g)
    full_ri.push(i + g)
    full_ci.push(i)
  i += 1

pattern = SparsePattern.new(n, n, upper_ri, upper_ci)
check_named("pattern.nnz", pattern.nnz == upper_ri.size)

# Dense twin for ground truth.
dense = []
i = 0
while i < n
  row = []
  j = 0
  while j < n
    row.push(~0.0)
    j += 1
  dense.push(row)
  i += 1
k = 0
while k < upper_ri.size
  r = upper_ri[k]
  c = upper_ci[k]
  dense[r][c] = upper_vv[k]
  dense[c][r] = upper_vv[k]
  k += 1

b = []
i = 0
while i < n
  b.push(~1.0 + (i % 5) * ~0.25)
  i += 1
x_ref = LinAlg.solve(dense, b)

factor = SparseFactor.cholesky(pattern, upper_vv)
x = factor.solve(b)
err = ~0.0
i = 0
while i < n
  d = x[i] - x_ref[i]
  d = ~0.0 - d if d < ~0.0
  err = d if d > err
  i += 1
check_named("cholesky.solve.matches_dense", err < ~0.0000001)

# Repeated solves on one factor.
x2 = factor.solve(b)
same = true
i = 0
while i < n
  same = false if x2[i] != x[i]
  i += 1
check_named("cholesky.solve.repeatable", same)

# Numeric refactor: A -> 2A means x -> x/2, same pattern and handle.
scaled = []
upper_vv.each -> (v)
  scaled.push(v * ~2.0)
factor.refactor(scaled)
x_half = factor.solve(b)
err = ~0.0
i = 0
while i < n
  d = x_half[i] * ~2.0 - x[i]
  d = ~0.0 - d if d < ~0.0
  err = d if d > err
  i += 1
check_named("cholesky.refactor.scales", err < ~0.0000001)
factor.release

# QR on the same square system agrees with the dense solve.
full_vals = []
k = 0
while k < full_ri.size
  full_vals.push(dense[full_ri[k]][full_ci[k]])
  k += 1
qr = SparseFactor.qr(SparsePattern.new(n, n, full_ri, full_ci), full_vals)
xq = qr.solve(b)
err = ~0.0
i = 0
while i < n
  d = xq[i] - x_ref[i]
  d = ~0.0 - d if d < ~0.0
  err = d if d > err
  i += 1
check_named("qr.solve.matches_dense", err < ~0.0000001)
qr.release

# Analysis: predicted fill equals the dense factor's structural nonzeros
# (a grid Laplacian produces no exact numeric cancellation).
analysis = SparseAnalysis.new(pattern)
l = LinAlg.cholesky(dense)
dense_fill = 0
i = 0
while i < n
  j = 0
  while j <= i
    dense_fill += 1 if l[i][j] != ~0.0
    j += 1
  i += 1
check_named("analysis.predicted_fill", analysis.predicted_fill == dense_fill)
check_named("analysis.flops_at_least_fill", analysis.predicted_flops >= analysis.predicted_fill)
check_named("analysis.budget_pass", analysis.check_budget(analysis.predicted_fill) == analysis.predicted_fill)
budget_raised = false
begin
  analysis.check_budget(1)
rescue error
  budget_raised = error.to_s.include?("exceeds budget")
check_named("analysis.budget_raises", budget_raised)

# slogdet agrees with det on a well-scaled matrix.
sd = LinAlg.slogdet(dense)
d = LinAlg.det(dense)
recon = sd[0] * Math.exp(sd[1])
rel = (recon - d) / d
rel = ~0.0 - rel if rel < ~0.0
check_named("slogdet.matches_det", rel < ~0.0000001)

if failures == 0
  << "sparse_factor_spec: all checks passed"
else
  << "sparse_factor_spec: " + failures.to_s + " FAILURES"
