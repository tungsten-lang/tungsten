# Complete parent-vs-baseline and bounded diverse-parent nullspace campaign for
# the <2,2,6> rank-20 target.
#
# Usage:
#   flipfleet_226_block_nullspace_scan COUNT ARCHIVE_LIMIT [RANK20_OUTPUT]
#
# All 2^nullity-1 relations are enumerated when nullity <= 20.  This tool
# treats any larger parent-vs-baseline hull as an error, so a successful run
# really is exhaustive for the requested deterministic parent bank.  Every
# proper projection through rank 21 is materialized and independently exact-
# checked.  A certificate is written only when rank <= 20 is reached.

use flipfleet_226_block_gl_parent_lib
use flipfleet_rect_archive_nullspace

-> ff226ns_fail(message)
  << "FF226_NULLSPACE_ERROR " + message
  exit(1)
  0

-> ff226ns_materialize(left, du, dv, dw, count, relation, projected)
  out_u = i64[42]
  out_v = i64[42]
  out_w = i64[42]
  rank = ffnd_materialize(left.us(), left.vs(), left.ws(), left.rank(), du, dv, dw, count, relation, out_u, out_v, out_w) ## i64
  if rank != projected || rank < 1 || rank > 42
    return nil
  child = FFBCScheme.new(2, 2, 6, rank)
  i = 0 ## i64
  while i < rank
    child.us()[i] = out_u[i]
    child.vs()[i] = out_v[i]
    child.ws()[i] = out_w[i]
    i += 1
  child.set_rank(rank)
  child

# stats:
# 0 pairs, 1 zero differences, 2 difference sum, 3 difference min,
# 4 difference max, 5 nullity sum, 6 nullity min, 7 nullity max,
# 8 relations, 9 proper relations, 10 rank<=20 projections,
# 11 exact rank<=20, 12 rank21 projections, 13 exact gates,
# 14 exact-gate failures, 15 nullity-over-20, 16 minimum proper rank,
# 17 elimination reductions, 18 maximum relations in one pair.
-> ff226ns_audit_pair(left, right, stats, nullity_hist, minrank_hist) (FFBCScheme FFBCScheme i64[] i64[] i64[])
  stats[0] += 1
  capacity = left.rank() + right.rank() ## i64
  du = i64[capacity]
  dv = i64[capacity]
  dw = i64[capacity]
  owners = i64[capacity]
  difference = ffnd_build_difference(left.us(), left.vs(), left.ws(), left.rank(), right.us(), right.vs(), right.ws(), right.rank(), du, dv, dw, owners) ## i64
  if difference == 0
    stats[1] += 1
    return nil

  stats[2] += difference
  if difference < stats[3]
    stats[3] = difference
  if difference > stats[4]
    stats[4] = difference
  combo_words = ffnd_combo_words(difference) ## i64
  basis = i64[difference * combo_words]
  elimination = i64[5]
  nullity = ffran_build_nullspace(du, dv, dw, difference, 2, 2, 6, basis, elimination) ## i64
  if nullity < 1 || elimination[2] + nullity != difference
    ff226ns_fail("elimination")
  stats[5] += nullity
  stats[17] += elimination[4]
  if nullity < stats[6]
    stats[6] = nullity
  if nullity > stats[7]
    stats[7] = nullity
  if nullity < nullity_hist.size()
    nullity_hist[nullity] += 1
  if nullity > 20
    stats[15] += 1
    return nil

  relation_limit = 1 << nullity ## i64
  if relation_limit - 1 > stats[18]
    stats[18] = relation_limit - 1
  relation = i64[combo_words]
  best = nil
  pair_min_rank = 0x7fffffff ## i64
  code = 1 ## i64
  while code < relation_limit
    z = ffnd_clear(relation, 0, combo_words) ## i64
    bit = 0 ## i64
    while bit < nullity
      if ((code >> bit) & 1) != 0
        z = ffnd_xor(basis, bit * combo_words, relation, 0, combo_words)
      bit += 1
    stats[8] += 1
    if ffran_relation_exact(du, dv, dw, difference, 2, 2, 6, relation, 0) != 1
      ff226ns_fail("basis relation code=" + code.to_s())
    score = i64[3]
    projected = ffnd_score_mask(relation, 0, owners, difference, left.rank(), score) ## i64
    if projected > 0
      stats[9] += 1
      if projected < pair_min_rank
        pair_min_rank = projected
      if projected < stats[16]
        stats[16] = projected
      if projected <= 21
        child = ff226ns_materialize(left, du, dv, dw, difference, relation, projected)
        if child == nil
          ff226ns_fail("materialize code=" + code.to_s())
        stats[13] += 1
        if ffbc_verify_exact(child) != 1
          stats[14] += 1
          ff226ns_fail("exact gate rank=" + projected.to_s())
        if projected <= 20
          stats[10] += 1
          stats[11] += 1
          if best == nil || child.rank() < best.rank()
            best = fflc_clone(child)
        if projected == 21
          stats[12] += 1
    code += 1
  if pair_min_rank < minrank_hist.size()
    minrank_hist[pair_min_rank] += 1
  best

-> ff226ns_write_rank20(path, child) (String FFBCScheme) i64
  if child == nil || child.rank() > 20 || ffbc_verify_exact(child) != 1
    return 0
  if ffbc_write(path, child) != child.rank()
    return 0
  replay = ffbc_load_exact(path, 2, 2, 6, 32)
  if replay == nil || replay.rank() != child.rank() || ffbc_verify_exact(replay) != 1
    return 0
  if fflc_term_set_distance(replay, child) != 0
    return 0
  1

arguments = argv()
if arguments.size() < 2 || arguments.size() > 3
  << "usage: flipfleet_226_block_nullspace_scan COUNT ARCHIVE_LIMIT [RANK20_OUTPUT]"
  exit(2)
count = arguments[0].to_i() ## i64
archive_limit = arguments[1].to_i() ## i64
output = "/tmp/flipfleet_226_rank20.txt"
if arguments.size() == 3
  output = arguments[2]
if count < 1 || count > 65536 || archive_limit < 1 || archive_limit > 64
  << "FF226_NULLSPACE_ERROR arguments"
  exit(2)

root = "benchmarks/matmul/metaflip/"
leaf = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
baseline = ffbc_load_exact(root + "matmul_2x2x6_rank21_strassen_blocks_gf2.txt", 2, 2, 6, 32)
outer = ff226gl_outer()
if leaf == nil || baseline == nil || outer == nil || baseline.rank() != 21 || ffbc_verify_exact(baseline) != 1
  ff226ns_fail("seed")
alloc_n = ff226gl_alloc_n()
alloc_m = ff226gl_alloc_m()
alloc_p = ff226gl_alloc_p()

stats = i64[24]
stats[3] = 0x7fffffff
stats[6] = 0x7fffffff
stats[16] = 0x7fffffff
nullity_hist = i64[43]
minrank_hist = i64[43]
archive = []
archive_indices = i64[archive_limit]
best = nil
baseline_pairs = 0 ## i64
t0 = ccall("__w_clock_ms") ## i64

i = 0 ## i64
while i < count
  parent = ff226gl_parent(leaf, outer, alloc_n, alloc_m, alloc_p, i)
  if parent == nil || parent.rank() != 21 || ffbc_verify_exact(parent) != 1
    ff226ns_fail("parent=" + i.to_s())
  child = ff226ns_audit_pair(parent, baseline, stats, nullity_hist, minrank_hist)
  baseline_pairs += 1
  if child != nil && (best == nil || child.rank() < best.rank())
    best = fflc_clone(child)

  # A conservative diverse archive: zero-overlap with the baseline and at
  # least 30 symmetric-difference terms away from every retained parent.
  if archive.size() < archive_limit && fflc_term_set_distance(parent, baseline) == 42
    separated = 1 ## i64
    j = 0 ## i64
    while j < archive.size()
      if fflc_term_set_distance(parent, archive[j]) < 30
        separated = 0
      j += 1
    if separated == 1
      archive_indices[archive.size()] = i
      archive.push(fflc_clone(parent))
  i += 1

archive_pairs = 0 ## i64
i = 0
while i < archive.size()
  j = i + 1 ## i64
  while j < archive.size()
    child = ff226ns_audit_pair(archive[i], archive[j], stats, nullity_hist, minrank_hist)
    archive_pairs += 1
    if child != nil && (best == nil || child.rank() < best.rank())
      best = fflc_clone(child)
    j += 1
  i += 1
elapsed = ccall("__w_clock_ms") - t0 ## i64

if stats[3] == 0x7fffffff
  stats[3] = 0
if stats[6] == 0x7fffffff
  stats[6] = 0
if stats[16] == 0x7fffffff
  stats[16] = 0
histogram = ""
i = 0
while i < nullity_hist.size()
  if nullity_hist[i] > 0
    if histogram.size() > 0
      histogram = histogram + ","
    histogram = histogram + i.to_s() + ":" + nullity_hist[i].to_s()
  i += 1
min_histogram = ""
i = 0
while i < minrank_hist.size()
  if minrank_hist[i] > 0
    if min_histogram.size() > 0
      min_histogram = min_histogram + ","
    min_histogram = min_histogram + i.to_s() + ":" + minrank_hist[i].to_s()
  i += 1
archive_list = ""
i = 0
while i < archive.size()
  if archive_list.size() > 0
    archive_list = archive_list + ","
  archive_list = archive_list + archive_indices[i].to_s()
  i += 1

<< "FF226_NULLSPACE_SUMMARY parents=" + count.to_s() + " baseline_pairs=" + baseline_pairs.to_s() + " archive_size=" + archive.size().to_s() + " archive_indices=" + archive_list + " archive_pairs=" + archive_pairs.to_s() + " total_pairs=" + stats[0].to_s() + " zero_differences=" + stats[1].to_s() + " difference_min=" + stats[3].to_s() + " difference_max=" + stats[4].to_s() + " nullity_min=" + stats[6].to_s() + " nullity_max=" + stats[7].to_s() + " nullity_hist=" + histogram + " relations=" + stats[8].to_s() + " proper_relations=" + stats[9].to_s() + " minrank_hist=" + min_histogram + " minimum_proper_rank=" + stats[16].to_s() + " rank_le20_projections=" + stats[10].to_s() + " rank_le20_exact=" + stats[11].to_s() + " rank21_projections=" + stats[12].to_s() + " exact_gates=" + stats[13].to_s() + " gate_failures=" + stats[14].to_s() + " nullity_over20=" + stats[15].to_s() + " max_pair_relations=" + stats[18].to_s() + " elapsed_ms=" + elapsed.to_s()

if stats[15] != 0
  ff226ns_fail("nonexhaustive parent hulls=" + stats[15].to_s())
if best == nil
  << "FF226_NULLSPACE_BEST none"
  exit(0)
if ff226ns_write_rank20(output, best) != 1
  ff226ns_fail("certificate write")
<< "FF226_NULLSPACE_BEST rank=" + best.rank().to_s() + " density=" + fflc_density(best).to_s() + " exact=1 output=" + output
