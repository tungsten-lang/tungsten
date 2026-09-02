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

# Heap's permutation enumeration: exact small-n oracle for the symbolic
# ordering objective.  This is deliberately test-only and allocation-heavy.
-> exhaustive_min_flops(analysis, n)
  order = []
  i = 0
  while i < n
    order.push(i)
    i += 1
  counters = u32[n]
  best = analysis.predictions_for_order(order)[1]
  i = 0
  while i < n
    if counters[i] < i
      j = 0
      j = counters[i] if (i & 1) != 0
      t = order[j]
      order[j] = order[i]
      order[i] = t
      score = analysis.predictions_for_order(order)[1]
      best = score if score < best
      counters[i] = counters[i] + 1
      i = 0
    else
      counters[i] = 0
      i += 1
  best

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
row_snapshot = pattern.row_indices
col_snapshot = pattern.col_indices
row_snapshot[0] = n - 1
col_snapshot[0] = n - 1
check_named("pattern.index inspection is owned",
            pattern.row_indices[0] == upper_ri[0] &&
            pattern.col_indices[0] == upper_ci[0])
check_named("pattern has no mutable raw index surface",
            !pattern.respond_to?("row_indices_raw") &&
            !pattern.respond_to?("col_indices_raw"))

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


# ── S3/S4: components, peeling, ordering, blocked factor ─────────────────

# Two disconnected copies of the grid: components found, blocked solve
# matches the whole-matrix solve exactly in structure.
two_ri = []
two_ci = []
two_vv = []
k = 0
while k < upper_ri.size
  two_ri.push(upper_ri[k])
  two_ci.push(upper_ci[k])
  two_vv.push(upper_vv[k])
  k += 1
k = 0
while k < upper_ri.size
  two_ri.push(upper_ri[k] + n)
  two_ci.push(upper_ci[k] + n)
  two_vv.push(upper_vv[k] * ~2.0)
  k += 1
two_pattern = SparsePattern.new(n * 2, n * 2, two_ri, two_ci)
two_analysis = SparseAnalysis.new(two_pattern)
check_named("components.count", two_analysis.component_count == 2)
ids = two_analysis.components
comp_ok = true
i = 0
while i < n
  comp_ok = false if ids[i] != 0 || ids[i + n] != 1
  i += 1
check_named("components.ids", comp_ok)
ids[0] = 99
check_named("components inspection is owned",
            two_analysis.components[0] == 0 &&
            two_analysis.component_count == 2)

two_b = []
i = 0
while i < n * 2
  two_b.push(~1.0 + (i % 4) * ~0.5)
  i += 1
whole = SparseFactor.cholesky(two_pattern, two_vv)
x_whole = whole.solve(two_b)
whole.release
blocked = SparseBlockFactor.new(two_pattern, two_vv)
check_named("blocked.ncomp", blocked.ncomp == 2)
check_named("blocked.small_stays_sequential", !blocked.parallel)
x_blocked = blocked.solve(two_b)
blocked.release
err = ~0.0
i = 0
while i < n * 2
  d = x_blocked[i] - x_whole[i]
  d = ~0.0 - d if d < ~0.0
  err = d if d > err
  i += 1
check_named("blocked.solve.matches_whole", err < ~0.0000001)

# Forced worker lane plus caller-owned output exercises the parallel
# scatter/solve/gather path without making the focused spec enormous.
blocked_parallel = SparseBlockFactor.new(two_pattern, two_vv, true)
parallel_out = ccall("w_array_new_aligned", -64, n * 2)
blocked_parallel.solve_into(two_b, parallel_out)
check_named("blocked.force_parallel", blocked_parallel.parallel)
err = ~0.0
i = 0
while i < n * 2
  d = parallel_out[i] - x_whole[i]
  d = ~0.0 - d if d < ~0.0
  err = d if d > err
  i += 1
check_named("blocked.solve_into.parallel_matches_whole", err < ~0.0000001)
blocked_parallel.release

# Peeling: a path graph peels completely.
path_ri = []
path_ci = []
i = 0
while i < 9
  path_ri.push(i)
  path_ci.push(i + 1)
  i += 1
path_pattern = SparsePattern.new(10, 10, path_ri, path_ci)
path_analysis = SparseAnalysis.new(path_pattern)
peel = path_analysis.peel_order
check_named("peel.path_fully_peels", peel[0].size == 10 && peel[1].size == 0)

# Inspection must not expose the shared immutable analysis cache. Mutating a
# returned row previously changed later minimum-degree results.
path_order = path_analysis.min_degree_ordering_scan
adjacency_copy = path_analysis.symmetric_adjacency
adjacency_copy[0].push(9)
check_named("analysis.adjacency inspection is owned",
            path_analysis.min_degree_ordering_scan == path_order &&
            !path_analysis.symmetric_adjacency[0].include?(9))

# Min-degree ordering improves predicted fill on the grid vs natural order.
grid_analysis = SparseAnalysis.new(pattern)
natural = []
i = 0
while i < n
  natural.push(i)
  i += 1
nat_pred = grid_analysis.predictions_for_order(natural)
md_order = grid_analysis.min_degree_ordering
md_pred = grid_analysis.predictions_for_order(md_order)
check_named("mindeg.is_permutation", md_order.sort.uniq.size == n)
check_named("mindeg.heap_matches_scan", grid_analysis.min_degree_ordering_heap == grid_analysis.min_degree_ordering_scan)
check_named("mindeg.fill_not_worse", md_pred[0] <= nat_pred[0])
check_named("mindeg.natural_matches_analysis", nat_pred[0] == grid_analysis.predicted_fill)

# AMD policy variants remain deterministic bijections.  The default call is
# pinned to the historical alpha-10/aggressive/LIFO policy.
gri = grid_analysis.typed_ri
gci = grid_analysis.typed_ci
gm = pattern.nnz
check_named("amd.default_policy_stable",
            grid_analysis.amd_core(n, gri, gci, gm) == md_order)
amd_fifo = grid_analysis.amd_core(n, gri, gci, gm, 10, 1, 1)
amd_nonagg = grid_analysis.amd_core(n, gri, gci, gm, 10, 0)
amd_nodense = grid_analysis.amd_core(n, gri, gci, gm, 0 - 1)
check_named("amd.fifo_bijection",
            amd_fifo.size == n && amd_fifo.sort.uniq.size == n)
check_named("amd.nonagg_bijection",
            amd_nonagg.size == n && amd_nonagg.sort.uniq.size == n)
check_named("amd.nodense_bijection",
            amd_nodense.size == n && amd_nodense.sort.uniq.size == n)
check_named("amd.fifo_deterministic",
            grid_analysis.amd_core(n, gri, gci, gm, 10, 1, 1) == amd_fifo)
check_named("amd.nonagg_deterministic",
            grid_analysis.amd_core(n, gri, gci, gm, 10, 0) == amd_nonagg)

# Profile/bandwidth candidates: deterministic bijections on connected and
# disconnected graphs.  A naturally labelled path has the canonical RCM
# order 0..n-1 (CM starts at the opposite pseudo-peripheral endpoint, then the
# final reversal restores natural order).
path_rcm = path_analysis.rcm_ordering
path_natural = []
i = 0
while i < 10
  path_natural.push(i)
  i += 1
check_named("rcm.path_canonical", path_rcm == path_natural)
check_named("rcm.deterministic", path_analysis.rcm_ordering == path_rcm)

two_rcm = two_analysis.rcm_ordering
check_named("rcm.disconnected_bijection",
            two_rcm.size == n * 2 && two_rcm.sort.uniq.size == n * 2)

sloan21 = two_analysis.sloan_ordering(2, 1)
sloan12 = two_analysis.sloan_ordering(1, 2)
check_named("sloan21.disconnected_bijection",
            sloan21.size == n * 2 && sloan21.sort.uniq.size == n * 2)
check_named("sloan12.disconnected_bijection",
            sloan12.size == n * 2 && sloan12.sort.uniq.size == n * 2)
check_named("sloan21.deterministic",
            two_analysis.sloan_ordering(2, 1) == sloan21)
check_named("sloan12.deterministic",
            two_analysis.sloan_ordering(1, 2) == sloan12)

# The K=8 window lane is an exact subset DP, not merely an exact final
# acceptance gate: on a whole eight-vertex graph it must equal exhaustive
# enumeration of all 8! orders.
oracle_ri = [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 0, 4]
oracle_ci = [1, 2, 3, 4, 5, 6, 7, 0, 3, 5, 6, 7, 5, 7]
oracle_analysis = SparseAnalysis.new(SparsePattern.new(8, 8, oracle_ri, oracle_ci))
oracle_seed = [0, 1, 2, 3, 4, 5, 6, 7]
oracle_seed_flops = oracle_analysis.predictions_for_order(oracle_seed)[1]
oracle_exact = exhaustive_min_flops(oracle_analysis, 8)
oracle_dp = oracle_analysis.window_dp(oracle_seed, oracle_seed_flops, 8, 10000000)
oracle_dp2 = oracle_analysis.window_dp(oracle_seed, oracle_seed_flops, 8, 10000000)
check_named("window_dp.exhaustive_exact", oracle_dp[1] == oracle_exact)
check_named("window_dp.is_permutation", oracle_dp[0].sort.uniq.size == 8)
check_named("window_dp.deterministic", oracle_dp == oracle_dp2)

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
