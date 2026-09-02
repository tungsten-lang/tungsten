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

# Independent oracle for the etree-postorder relabel identity used by subtree
# ordering. `old_order[position]` names the original vertex, while
# `counts_under` takes the inverse map (original vertex -> position). After an
# etree postorder, both the column counts and parent labels must be obtainable
# by permutation alone; a fresh symbolic analysis of the postordered vertices
# is the authority checked here.
-> etree_postorder_relabel_matches(analysis, old_order)
  n = old_order.size
  none = 4294967295
  perm = u32[n]
  i = 0
  while i < n
    perm[old_order[i]] = i
    i += 1
  data1 = analysis.counts_under(perm)
  parent1 = data1[0]
  counts1 = data1[1]

  # Forest postorder, with deterministic child/root traversal. The identity
  # does not depend on sibling or component order, only child-before-parent.
  kid_head = u32[n]
  kid_next = u32[n]
  i = 0
  while i < n
    kid_head[i] = none
    i += 1
  i = n
  while i > 0
    i -= 1
    p = parent1[i]
    if p != none
      kid_next[i] = kid_head[p]
      kid_head[p] = i
  post = u32[n]
  stack = u32[n]
  state = u32[n]
  sp = 0
  r = n
  while r > 0
    r -= 1
    if parent1[r] == none
      stack[sp] = r
      sp += 1
  pc = 0
  while sp > 0
    v = stack[sp - 1]
    if state[v] == 0
      state[v] = 1
      child = kid_head[v]
      while child != none
        stack[sp] = child
        sp += 1
        child = kid_next[child]
    else
      sp -= 1
      post[pc] = v
      pc += 1
  return false if pc != n

  postpos = u32[n]
  k = 0
  while k < n
    postpos[post[k]] = k
    k += 1
  transformed_parent = u32[n]
  transformed_counts = u32[n]
  order2 = []
  k = 0
  while k < n
    old_label = post[k]
    p = parent1[old_label]
    transformed_parent[k] = p == none ? none : postpos[p]
    transformed_counts[k] = counts1[old_label]
    order2.push(old_order[old_label])
    k += 1
  perm2 = u32[n]
  k = 0
  while k < n
    perm2[order2[k]] = k
    k += 1
  fresh = analysis.counts_under(perm2)
  transformed_parent == fresh[0] && transformed_counts == fresh[1]

# The fused u32 score reducer must retain arbitrary-precision Integer
# semantics even when the sum of squares exceeds 64 bits.
score_counts = u32[2]
score_counts[0] = 4294967295
score_counts[1] = 4294967295
wide_score = ccall("__w_u32_fill_flops", score_counts)
check_named("score_reduce.u128_exact",
            wide_score[0] == 8589934590 &&
            wide_score[1] == 36893488130239234050)

# Raw-return bitset helpers keep the same array/value semantics as their boxed
# companions while avoiding an Int box/unbox at typed hot-loop call sites.
bit_src = u32[4]
bit_src[0] = 0xf0f0f0f0
bit_src[1] = 0xaaaaaaaa
bit_src[2] = 0x0000ffff
bit_src[3] = 0x80000001
bit_dst_boxed = u32[4]
bit_dst_raw = u32[4]
bit_dst_boxed[0] = 0x0f0f0f0f
bit_dst_boxed[1] = 0x55555555
bit_dst_boxed[2] = 0xffff0000
bit_dst_boxed[3] = 0x00000001
i = 0
while i < 4
  bit_dst_raw[i] = bit_dst_boxed[i]
  i += 1
boxed_merge = ccall("__w_u32_merge_count", bit_dst_boxed, 0, bit_src, 0, 4)
raw_merge = ccall_nobox(
  "__w_u32_merge_count_raw", bit_dst_raw, 0, bit_src, 0, 4)
check_named("bitset_raw.merge_matches_boxed",
            raw_merge == boxed_merge && bit_dst_raw == bit_dst_boxed)
boxed_andnot = ccall(
  "__w_u32_andnot_count", bit_src, 0, bit_dst_boxed, 0, 4)
raw_andnot = ccall_nobox(
  "__w_u32_andnot_count_raw", bit_src, 0, bit_dst_raw, 0, 4)
check_named("bitset_raw.andnot_matches_boxed", raw_andnot == boxed_andnot)

subset = u32[2]
superset = u32[2]
subset[0] = 0x00000121
subset[1] = 0x80000000
superset[0] = 0x00000021
superset[1] = 0x80000000
check_named("bitset_raw.subset_ignores_requested_bit",
            ccall_nobox("__w_u32_subset_except_raw",
                        subset, 0, superset, 0, 2, 8) == 1)
check_named("bitset_raw.subset_rejects_other_missing_bit",
            ccall_nobox("__w_u32_subset_except_raw",
                        subset, 0, superset, 0, 2, 5) == 0)
checked_subset_true = ccall_nobox(
  "__w_u32_subset_except_raw", subset, 0, superset, 0, 2, 8)
trusted_subset_true = ccall_nobox(
  "__w_u32_subset_except_trusted_raw", subset, 0, superset, 0, 2, 8)
checked_subset_false = ccall_nobox(
  "__w_u32_subset_except_raw", subset, 0, superset, 0, 2, 5)
trusted_subset_false = ccall_nobox(
  "__w_u32_subset_except_trusted_raw", subset, 0, superset, 0, 2, 5)
check_named("bitset_raw.subset_trusted_matches_checked",
            trusted_subset_true == checked_subset_true &&
            trusted_subset_false == checked_subset_false)

subset_bad_a_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", nil, 0, superset, 0, 2, 8)
rescue error
  subset_bad_a_raised = true
end
subset_bad_b_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, 0, nil, 0, 2, 8)
rescue error
  subset_bad_b_raised = true
end
subset_bad_a_ebits_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", u64[2], 0, superset, 0, 2, 8)
rescue error
  subset_bad_a_ebits_raised = true
end
subset_bad_b_ebits_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, 0, u64[2], 0, 2, 8)
rescue error
  subset_bad_b_ebits_raised = true
end
check_named("bitset_raw.subset_checks_arrays",
            subset_bad_a_raised && subset_bad_b_raised &&
            subset_bad_a_ebits_raised && subset_bad_b_ebits_raised)

subset_neg_aoff_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, -1, superset, 0, 2, 8)
rescue error
  subset_neg_aoff_raised = true
end
subset_a_range_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, 1, superset, 0, 2, 8)
rescue error
  subset_a_range_raised = true
end
subset_neg_boff_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, 0, superset, -1, 2, 8)
rescue error
  subset_neg_boff_raised = true
end
subset_b_range_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, 0, superset, 1, 2, 8)
rescue error
  subset_b_range_raised = true
end
subset_neg_words_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, 0, superset, 0, -1, 0)
rescue error
  subset_neg_words_raised = true
end
subset_zero_words_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, 0, superset, 0, 0, 0)
rescue error
  subset_zero_words_raised = true
end
subset_neg_except_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, 0, superset, 0, 2, -1)
rescue error
  subset_neg_except_raised = true
end
subset_high_except_raised = false
begin
  ccall_nobox("__w_u32_subset_except_raw", subset, 0, superset, 0, 2, 64)
rescue error
  subset_high_except_raised = true
end
check_named("bitset_raw.subset_checks_ranges_and_except",
            subset_neg_aoff_raised && subset_a_range_raised &&
            subset_neg_boff_raised && subset_b_range_raised &&
            subset_neg_words_raised && subset_zero_words_raised &&
            subset_neg_except_raised && subset_high_except_raised)

# Whole-state checkpoint copies use one checked native bulk operation. Cover
# offsets and overlap so eval/native agree on the helper's memmove semantics.
bit_copy_src = u32[6]
i = 0
while i < bit_copy_src.size()
  bit_copy_src[i] = i * 17 + 3
  i += 1
bit_copy_dst = u32[6]
copied = ccall_nobox(
  "__w_u32_copy_raw", bit_copy_dst, 1, bit_copy_src, 2, 3)
check_named("bitset_raw.copy_offsets",
            copied == 3 && bit_copy_dst[0] == 0 &&
            bit_copy_dst[1] == 37 && bit_copy_dst[2] == 54 &&
            bit_copy_dst[3] == 71 && bit_copy_dst[4] == 0)
copied = ccall_nobox(
  "__w_u32_copy_raw", bit_copy_src, 1, bit_copy_src, 0, 5)
check_named("bitset_raw.copy_overlap",
            copied == 5 && bit_copy_src[0] == 3 &&
            bit_copy_src[1] == 3 && bit_copy_src[2] == 20 &&
            bit_copy_src[3] == 37 && bit_copy_src[4] == 54 &&
            bit_copy_src[5] == 71)
copy_range_raised = false
begin
  ccall_nobox("__w_u32_copy_raw", bit_copy_dst, 4, bit_copy_src, 0, 3)
rescue error
  copy_range_raised = error.to_s.include?("range")
end
check_named("bitset_raw.copy_checks_range", copy_range_raised)
copy_type_raised = false
begin
  ccall_nobox("__w_u32_copy_raw", u64[6], 0, bit_copy_src, 0, 3)
rescue error
  copy_type_raised = true
end
check_named("bitset_raw.copy_checks_type", copy_type_raised)

# Slice views are writable fixed-range aliases (only growth is forbidden), so
# the bulk helper follows ordinary element-write semantics and updates the
# parent storage.
copy_view_parent = u32[5]
copy_view = copy_view_parent.slice_view(1, 3)
copy_view_src = u32[3]
copy_view_src[0] = 101
copy_view_src[1] = 202
copy_view_src[2] = 303
ccall_nobox("__w_u32_copy_raw", copy_view, 0, copy_view_src, 0, 3)
check_named("bitset_raw.copy_writes_mutable_view",
            copy_view_parent[0] == 0 && copy_view_parent[1] == 101 &&
            copy_view_parent[2] == 202 && copy_view_parent[3] == 303 &&
            copy_view_parent[4] == 0)

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

# Exact-score workspaces are intentionally reused, but one analysis can still
# be shared safely by callers. Exercise owned counts plus all scalar/public
# score views concurrently against two distinct permutations.
identity_order = u32[n]
reverse_order = u32[n]
identity_perm = u32[n]
reverse_perm = u32[n]
i = 0
while i < n
  identity_order[i] = i
  reverse_order[i] = n - 1 - i
  identity_perm[i] = i
  reverse_perm[n - 1 - i] = i
  i += 1
identity_score = analysis.predictions_for_order(identity_order)
reverse_score = analysis.predictions_for_order(reverse_order)
identity_counts = analysis.counts_under(identity_perm)
reverse_counts = analysis.counts_under(reverse_perm)
score_thread_ok = u32[8]
score_threads = []
i = 0
while i < 8
  slot = i
  score_thread = Thread.new ->
    ok = 0 == 0
    iteration = 0
    while iteration < 40
      order = identity_order
      perm = identity_perm
      expected_score = identity_score
      expected_counts = identity_counts
      if ((iteration + slot) & 1) != 0
        order = reverse_order
        perm = reverse_perm
        expected_score = reverse_score
        expected_counts = reverse_counts
      score = analysis.predictions_for_order(order)
      counts = analysis.counts_under(perm)
      ok = 0 == 1 if score != expected_score || counts != expected_counts
      ok = 0 == 1 if analysis.flops_for_order(order) != expected_score[1]
      ok = 0 == 1 if analysis.prefix_flops_for_order(order, n) != expected_score[1]
      iteration += 1
    score_thread_ok[slot] = 1 if ok
  score_threads.push(score_thread)
  i += 1
i = 0
while i < score_threads.size
  score_threads[i].join
  i += 1
score_threads_ok = true
i = 0
while i < score_thread_ok.size
  score_threads_ok = false if score_thread_ok[i] != 1
  i += 1
check_named("analysis.shared_score_workspace.thread_safe", score_threads_ok)


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
check_named("score_reduce.flops_only_matches_pair",
            grid_analysis.flops_for_order(md_order) == md_pred[1])

# Exact scoring reuses private parent/count buffers, but the public count API
# must continue to return owned results that neither alias those buffers nor a
# later public result.
owned_counts = grid_analysis.counts_under(nil)
owned_parent0 = owned_counts[0][0]
owned_count0 = owned_counts[1][0]
owned_counts[0][0] = owned_parent0 == 0 ? 1 : 0
owned_counts[1][0] = owned_count0 + 1
fresh_counts = grid_analysis.counts_under(nil)
check_named("counts_under.results_are_owned",
            fresh_counts[0][0] == owned_parent0 &&
            fresh_counts[1][0] == owned_count0)
grid_analysis.predictions_for_order(md_order)
check_named("counts_under.result_survives_scoring",
            fresh_counts[0][0] == owned_parent0 &&
            fresh_counts[1][0] == owned_count0)

# Etree postordering is a pure relabeling of the same chordal completion.
# Exercise the exact parent/count transform on a forest (including an isolated
# vertex), duplicate structural entries, and both one-triangle conventions.
post_disc_ri = [0, 0, 1, 3, 4, 5, 3, 7, 8]
post_disc_ci = [1, 2, 2, 4, 5, 6, 6, 8, 9]
post_disc_order = [6, 0, 9, 3, 10, 2, 8, 4, 1, 7, 5]
post_disc_analysis = SparseAnalysis.new(
  SparsePattern.new(11, 11, post_disc_ri, post_disc_ci))
check_named("etree_postorder.disconnected_forest_relabel",
            etree_postorder_relabel_matches(
              post_disc_analysis, post_disc_order))

post_dup_ri = [0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 3, 4, 5]
post_dup_ci = [1, 1, 2, 2, 2, 3, 4, 4, 4, 5, 5, 6, 6]
post_dup_order = [4, 0, 6, 2, 5, 1, 3]
post_dup_analysis = SparseAnalysis.new(
  SparsePattern.new(7, 7, post_dup_ri, post_dup_ci))
check_named("etree_postorder.duplicate_edges_relabel",
            etree_postorder_relabel_matches(
              post_dup_analysis, post_dup_order))

post_conn_ri = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 6, 7, 2]
post_conn_ci = [1, 3, 2, 4, 4, 5, 4, 6, 5, 7, 8, 7, 8, 7]
post_conn_order = [7, 2, 5, 0, 8, 3, 1, 6, 4]
post_upper_analysis = SparseAnalysis.new(
  SparsePattern.new(9, 9, post_conn_ri, post_conn_ci))
post_lower_analysis = SparseAnalysis.new(
  SparsePattern.new(9, 9, post_conn_ci, post_conn_ri))
check_named("etree_postorder.connected_upper_only_relabel",
            etree_postorder_relabel_matches(
              post_upper_analysis, post_conn_order))
check_named("etree_postorder.connected_lower_only_relabel",
            etree_postorder_relabel_matches(
              post_lower_analysis, post_conn_order))

# The degree-3 core-lift bitmap is capped before allocation.  23,168 is the
# largest dimension whose n*ceil(n/32) u32 matrix fits within 64 MiB.
check_named("core_lift.memory_cap_boundary",
            SparseAnalysis.core_lift_fits?(23168) &&
            !SparseAnalysis.core_lift_fits?(23169))

# The sparse core lift performs the same exact elimination without an n-by-n
# bitmap.  Vertex 0 has the three missing K6 triangle vertices as neighbors;
# eliminating it closes that triangle and leaves an exact K6 residual.
scl_ri = []
scl_ci = []
a = 0
while a < 7
  b = a + 1
  while b < 7
    keep = !(a == 0 && b >= 4)
    keep = false if (
      (a == 1 && b == 2) || (a == 1 && b == 3) ||
      (a == 2 && b == 3))
    if keep
      scl_ri.push(a)
      scl_ci.push(b)
    b += 1
  a += 1
scl_analysis = SparseAnalysis.new(
  SparsePattern.new(7, 7, scl_ri, scl_ci))
scl = SparseAnalysis.sparse_core_lift_reduce(
  7, scl_analysis.typed_ri, scl_analysis.typed_ci, scl_ri.size,
  3, 7, scl_ri.size)
check_named("sparse_core_lift.degree3_prefix",
            scl != nil && scl[1] == 1 && scl[0][0] == 0 &&
            scl[3] == 6 && scl[6] == 15 && scl[7] == 16)
core_ri = []
core_ci = []
i = 0
while i < scl[6]
  core_ri.push(scl[4][i])
  core_ci.push(scl[5][i])
  i += 1
core_analysis = SparseAnalysis.new(
  SparsePattern.new(scl[3], scl[3], core_ri, core_ci))
core_order = [5, 4, 3, 2, 1, 0]
whole_order = [scl[0][0]]
i = 0
while i < core_order.size
  whole_order.push(scl[2][core_order[i]])
  i += 1
check_named("sparse_core_lift.exact_score_split",
            scl_analysis.flops_for_order(whole_order) ==
            scl[7] + core_analysis.flops_for_order(core_order))
scl2 = SparseAnalysis.sparse_core_lift_reduce(
  7, scl_analysis.typed_ri, scl_analysis.typed_ci, scl_ri.size,
  3, 7, scl_ri.size)
check_named("sparse_core_lift.deterministic",
            scl2 != nil && scl2[0] == scl[0] && scl2[1] == scl[1] &&
            scl2[2] == scl[2] && scl2[3] == scl[3] &&
            scl2[4] == scl[4] && scl2[5] == scl[5] &&
            scl2[6] == scl[6] && scl2[7] == scl[7])
check_named("sparse_core_lift.caps_fail_closed",
            SparseAnalysis.sparse_core_lift_reduce(
              7, scl_analysis.typed_ri, scl_analysis.typed_ci,
              scl_ri.size, 3, 5, scl_ri.size) == nil &&
            SparseAnalysis.sparse_core_lift_reduce(
              7, scl_analysis.typed_ri, scl_analysis.typed_ci,
              scl_ri.size, 4, 7, scl_ri.size) == nil)
check_named("sparse_core_lift.input_lengths_fail_closed",
            SparseAnalysis.sparse_core_lift_reduce(
              7, u32[0], scl_analysis.typed_ci, 1,
              3, 7, 1) == nil &&
            SparseAnalysis.sparse_core_lift_reduce(
              7, scl_analysis.typed_ri, u32[0], 1,
              3, 7, 1) == nil)
policy_n = 32768
policy_m = 196608
policy_core_n = 16384
policy_core_edges = 65536
check_named("sparse_core_lift.workspace_model_exact",
            SparseAnalysis.sparse_core_lift_workspace_bytes(
              policy_n, policy_m) == 17469696)
check_named("sparse_core_lift.synthetic_resource_admitted",
            SparseAnalysis.sparse_core_lift_workspace_fits?(
              policy_n, policy_m) &&
            SparseAnalysis.sparse_core_lift_workspace_fits?(400001, 1) &&
            SparseAnalysis.sparse_core_lift_candidate_fits?(
              policy_n, policy_m, policy_core_n, policy_core_edges))
check_named("sparse_core_lift.policy_caps_fail_closed",
            !SparseAnalysis.sparse_core_lift_workspace_fits?(1000000, 1) &&
            !SparseAnalysis.sparse_core_lift_candidate_fits?(
              policy_n, policy_m, policy_n, policy_core_edges) &&
            !SparseAnalysis.sparse_core_lift_candidate_fits?(
              policy_n, policy_m, policy_core_n, policy_m + 1))
check_named("sparse_core_lift.amd_pool_is_bounded",
            SparseAnalysis.sparse_core_lift_amd_iw_words(
              policy_n, policy_m, policy_core_n,
              policy_core_edges) > 4 * policy_core_edges + policy_core_n &&
            SparseAnalysis.sparse_core_lift_candidate_fits?(
              policy_n, policy_m, policy_core_n,
              8 * policy_core_n + 1) &&
            SparseAnalysis.sparse_core_lift_amd_iw_words(
              1000000, 1, 500000, 1) < 0)

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
check_named("amd.bounded_pool_fails_closed",
            grid_analysis.amd_core(
              n, gri, gci, gm, 10, 1, 0, 1).size == 0)

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

# Biconnected one-dissection candidate.  A graph with a single block is the
# exact AMD anchor; articulation-heavy graphs defer every child-side cut
# vertex to its parent block and always return a deterministic bijection.
cycle_ri = []
cycle_ci = []
i = 0
while i < 8
  cycle_ri.push(i)
  cycle_ci.push((i + 1) % 8)
  i += 1
cycle_analysis = SparseAnalysis.new(
  SparsePattern.new(8, 8, cycle_ri, cycle_ci))
cycle_biconn = cycle_analysis.biconn_ordering
check_named("biconn.cycle_anchor",
            cycle_biconn == cycle_analysis.min_degree_ordering)
check_named("biconn.cycle_deterministic",
            cycle_analysis.biconn_ordering == cycle_biconn)

path_biconn = path_analysis.biconn_ordering
check_named("biconn.chain_bijection",
            path_biconn.size == 10 && path_biconn.sort.uniq.size == 10)
check_named("biconn.chain_deterministic",
            path_analysis.biconn_ordering == path_biconn)
check_named("biconn.chain_no_extra_fill",
            path_analysis.predictions_for_order(path_biconn)[1] ==
            path_analysis.predictions_for_order(path_order)[1])

# Two triangles share only vertex 2.  Tarjan pops the right triangle first,
# making it the root under the fixed lowest-block-id tie; the left triangle's
# interiors must therefore precede the shared articulation.
cut_ri = [0, 1, 0, 2, 3, 2]
cut_ci = [1, 2, 2, 3, 4, 4]
cut_analysis = SparseAnalysis.new(SparsePattern.new(5, 5, cut_ri, cut_ci))
cut_order = cut_analysis.biconn_ordering
cut_pos0 = cut_order.index(0)
cut_pos1 = cut_order.index(1)
cut_pos2 = cut_order.index(2)
check_named("biconn.two_cliques_bijection",
            cut_order.size == 5 && cut_order.sort.uniq.size == 5)
check_named("biconn.two_cliques_defers_articulation",
            cut_pos0 < cut_pos2 && cut_pos1 < cut_pos2)
check_named("biconn.two_cliques_deterministic",
            cut_analysis.biconn_ordering == cut_order)

# Flat-CSR biconn construction canonicalizes duplicate entries, opposite
# triangle copies, and structural self entries before Tarjan. It must preserve
# the exact block-cut order of the corresponding simple graph.
dup_cut_ri = cut_ri + cut_ci + [0, 2, 4]
dup_cut_ci = cut_ci + cut_ri + [1, 2, 4]
dup_cut_analysis = SparseAnalysis.new(
  SparsePattern.new(5, 5, dup_cut_ri, dup_cut_ci))
check_named("biconn.duplicate_opposite_self_canonical",
            dup_cut_analysis.biconn_ordering == cut_order)

# A disconnected block forest includes every component and leaves isolates as
# a deterministic zero-fill prefix.
forest_ri = [0, 1, 3, 4, 3]
forest_ci = [1, 2, 4, 5, 5]
forest_analysis = SparseAnalysis.new(
  SparsePattern.new(7, 7, forest_ri, forest_ci))
forest_order = forest_analysis.biconn_ordering
check_named("biconn.disconnected_isolate_bijection",
            forest_order.size == 7 && forest_order.sort.uniq.size == 7)
check_named("biconn.disconnected_isolate_first", forest_order[0] == 6)
check_named("biconn.disconnected_deterministic",
            forest_analysis.biconn_ordering == forest_order)

# The production route is bounded by an explicit raw-workspace estimate.
# Raw m is deliberately representation-sensitive because the canonical CSR
# allocates its key array before duplicate/opposite entries are collapsed.
biconn_n = 262144
check_named("biconn.policy_admits_synthetic_sparse_boundary",
            SparseAnalysis.biconn_candidate_fits?(
              biconn_n, 6 * biconn_n))
max_biconn_isolates = (134217728 - 1048832) / 196
check_named("biconn.policy_caps_isolate_heavy_n",
            SparseAnalysis.biconn_candidate_fits?(max_biconn_isolates, 0) &&
            !SparseAnalysis.biconn_candidate_fits?(
              max_biconn_isolates + 1, 0))
check_named("biconn.policy_caps_raw_m",
            SparseAnalysis.biconn_candidate_fits?(biconn_n, 6 * biconn_n) &&
            !SparseAnalysis.biconn_candidate_fits?(
              biconn_n, 7 * biconn_n))

# Portfolio gates are resource/structure predicates, not matrix identities.
# Exercise both sides with generated dimensions that do not correspond to
# challenge rows.
policy_budget = 150000000
check_named("portfolio_policy.rgsub_workspace_models",
            SparseAnalysis.rgsub_coordinator_workspace_bytes(
              12000, 72000) == 5848576 &&
            SparseAnalysis.rgsub_worker_workspace_bytes(
              6000, 10000) <= 134217728 &&
            SparseAnalysis.rgsub_worker_workspace_bytes(
              6000, 5000000) > 134217728 &&
            SparseAnalysis.rgsub_queued_job_workspace_bytes(
              6000, 5000000) == 40124096)
check_named("portfolio_policy.rgsub_resource_and_budget",
            SparseAnalysis.terminal_rgsub_portfolio_fits?(
              12000, 72000, policy_budget) &&
            !SparseAnalysis.terminal_rgsub_portfolio_fits?(
              600000, 600000, policy_budget) &&
            SparseAnalysis.terminal_rgsub_portfolio_fits?(
              150001, 72000, policy_budget))
check_named("portfolio_policy.biconn_workspace_and_budget",
            SparseAnalysis.biconn_portfolio_fits?(
              biconn_n, 6 * biconn_n, 200000000) &&
            !SparseAnalysis.biconn_portfolio_fits?(
              biconn_n, 6 * biconn_n, 100000000))

# Passive boundary terminals change the correct local objective.  On this
# five-vertex counterexample the S-only graph prefers identity (cost 9), while
# keeping B={3,4} live makes [2,0,1] strictly better: prefix 41 -> 34 and full
# global 46 -> 39. The prefix worker must return only the three movable IDs.
boundary_ri = [0, 1, 0, 0, 1, 1]
boundary_ci = [2, 2, 3, 4, 3, 4]
boundary_analysis = SparseAnalysis.new(
  SparsePattern.new(5, 5, boundary_ri, boundary_ci))
boundary_analysis_rev = SparseAnalysis.new(
  SparsePattern.new(5, 5, boundary_ci, boundary_ri))
boundary_seed = [0, 1, 2, 3, 4]
boundary_better = [2, 0, 1, 3, 4]
check_named("rgreedy_boundary.exact_prefix_cost",
            boundary_analysis.prefix_flops_for_order(boundary_seed, 3) == 41 &&
            boundary_analysis.prefix_flops_for_order(boundary_better, 3) == 34 &&
            boundary_analysis_rev.prefix_flops_for_order(boundary_seed, 3) == 41 &&
            boundary_analysis_rev.prefix_flops_for_order(boundary_better, 3) == 34)
check_named("rgreedy_boundary.exact_global_delta",
            boundary_analysis.flops_for_order(boundary_seed) == 46 &&
            boundary_analysis.flops_for_order(boundary_better) == 39)
boundary_ref = boundary_analysis.rgreedy_prefix_refine(
  5, boundary_analysis.typed_ri, boundary_analysis.typed_ci,
  boundary_analysis.pattern.nnz, boundary_seed, 41, 1000000, [0, 3])
check_named("rgreedy_boundary.frozen_terminals",
            boundary_ref[0].size == 3 &&
            boundary_ref[0].sort == [0, 1, 2] &&
            boundary_ref[1] ==
              boundary_analysis.prefix_flops_for_order(
                boundary_ref[0] + [3, 4], 3))
check_named("rgreedy_boundary.not_worse", boundary_ref[1] <= 41)
check_named("rgreedy_boundary.finds_strict_win",
            boundary_ref[1] == 34 && boundary_ref[0][0] == 2)

# Watcher MINL records the exact fill supports of a blocking four-cycle.
# Here fill edge 1-4 is initially blocked by common nonneighbors 2 and 3;
# deleting its fill support 2-4 must wake and retest 1-4. Both are removed
# in three tests, whereas a one-pass scan would leave 1-4 behind.
watch_ri = [0, 1, 1, 3]
watch_ci = [2, 2, 3, 4]
watch_analysis = SparseAnalysis.new(
  SparsePattern.new(5, 5, watch_ri, watch_ci))
watch_seed = [0, 3, 1, 4, 2]
watch_seed_flops = watch_analysis.flops_for_order(watch_seed)
watch_stats = []
watch_ref = watch_analysis.minl_descent(
  watch_seed, watch_seed_flops, 1000000, 0, 1, watch_stats)
check_named("minl_watch.wake_chain_stats", watch_stats == [2, 3, 1, 0])
check_named("minl_watch.wake_chain_bijection",
            watch_ref[0].size == 5 && watch_ref[0].sort.uniq.size == 5)
check_named("minl_watch.wake_chain_exact",
            watch_ref[1] == 17 &&
            watch_ref[1] == watch_analysis.flops_for_order(watch_ref[0]) &&
            watch_ref[1] < watch_seed_flops)
watch_stats2 = []
watch_ref2 = watch_analysis.minl_descent(
  watch_seed, watch_seed_flops, 1000000, 0, 1, watch_stats2)
check_named("minl_watch.wake_chain_deterministic",
            watch_stats2 == watch_stats && watch_ref2 == watch_ref)
# Sequential portfolio passes share one dense workspace split into mutable G+
# and immutable reset halves. The ready pass must reproduce a fresh call
# exactly, including watcher statistics.
watch_words = 5 * ((5 + 31) >> 5)
watch_workspace = u32[watch_words * 2]
watch_ws_stats1 = []
watch_ws_ref1 = watch_analysis.minl_descent_workspace(
  watch_seed, watch_seed_flops, 1000000, 0, 1, watch_ws_stats1,
  watch_workspace, 0)
watch_ws_stats2 = []
watch_ws_ref2 = watch_analysis.minl_descent_workspace(
  watch_seed, watch_seed_flops, 1000000, 0, 1, watch_ws_stats2,
  watch_workspace, 1)
check_named("minl_workspace.fresh_equivalent",
            watch_ws_ref1 == watch_ref && watch_ws_stats1 == watch_stats)
check_named("minl_workspace.reset_equivalent",
            watch_ws_ref2 == watch_ref && watch_ws_stats2 == watch_stats)
minl_short_workspace_raised = false
begin
  watch_analysis.minl_descent_workspace(
    watch_seed, watch_seed_flops, 1000000, 0, 1, nil,
    u32[watch_words * 2 - 1], 0)
rescue error
  minl_short_workspace_raised = error.to_s.include?("undersized")
end
check_named("minl_workspace.rejects_undersized_buffer",
            minl_short_workspace_raised)
watch_deg_stats = []
watch_deg_ref = watch_analysis.minl_descent(
  watch_seed, watch_seed_flops, 1000000, 0, 2, watch_deg_stats)
check_named("minl_watch.degree_schedule_deterministic",
            watch_deg_stats == [2, 3, 1, 0] && watch_deg_ref == watch_ref)
# Completion replay consumes six word-ops here. A budget of seven exhausts
# during the first clique row; the incomplete predicate must not mutate G+.
watch_budget_stats = []
watch_budget_ref = watch_analysis.minl_descent(
  watch_seed, watch_seed_flops, 7, 0, 1, watch_budget_stats)
check_named("minl_watch.budget_fails_closed",
            watch_budget_stats == [0, 1, 0, 2] &&
            watch_budget_ref[0] == watch_seed &&
            watch_budget_ref[1] == watch_seed_flops)

# A chordless four-cycle plus the fill diagonal 0-2 is already a minimal
# triangulation. Its witness supports are all original edges, so it receives
# no removable watches and is tested exactly once.
permanent_ri = [0, 1, 2, 0]
permanent_ci = [1, 2, 3, 3]
permanent_analysis = SparseAnalysis.new(
  SparsePattern.new(4, 4, permanent_ri, permanent_ci))
permanent_seed = [1, 0, 2, 3]
permanent_seed_flops = permanent_analysis.flops_for_order(permanent_seed)
permanent_stats = []
permanent_ref = permanent_analysis.minl_descent(
  permanent_seed, permanent_seed_flops, 1000000, 0, 1, permanent_stats)
check_named("minl_watch.permanent_witness_stats",
            permanent_stats == [0, 1, 1, 1])
check_named("minl_watch.permanent_witness_exact",
            permanent_ref[1] == 23 &&
            permanent_ref[1] == permanent_analysis.flops_for_order(permanent_ref[0]) &&
            permanent_ref[1] == permanent_seed_flops)

# The K=8 window lane is an exact subset DP, not merely an exact final
# acceptance gate: on a whole eight-vertex graph it must equal exhaustive
# enumeration of all 8! orders.
oracle_ri = [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 0, 4]
oracle_ci = [1, 2, 3, 4, 5, 6, 7, 0, 3, 5, 6, 7, 5, 7]
oracle_analysis = SparseAnalysis.new(SparsePattern.new(8, 8, oracle_ri, oracle_ci))
oracle_seed = [0, 1, 2, 3, 4, 5, 6, 7]
oracle_seed_flops = oracle_analysis.predictions_for_order(oracle_seed)[1]
oracle_exact = exhaustive_min_flops(oracle_analysis, 8)
pair = oracle_analysis.order_descent(oracle_seed, oracle_seed_flops, 1000, 0, 0)
pair_local = true
i = 0
while i + 1 < pair[0].size
  t = pair[0][i]
  pair[0][i] = pair[0][i + 1]
  pair[0][i + 1] = t
  pair_local = false if oracle_analysis.predictions_for_order(pair[0])[1] < pair[1]
  t = pair[0][i]
  pair[0][i] = pair[0][i + 1]
  pair[0][i + 1] = t
  i += 1
check_named("pair_descent.local_optimum", pair_local)
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
