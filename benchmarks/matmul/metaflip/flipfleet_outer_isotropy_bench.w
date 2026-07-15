# Exhaustive weighted-isotropy audit of the rank-7 Strassen outer scheme.
#
# A 4+3 block composition is scored by the rectangular rank selected for each
# outer term.  Applying an exact GL(2,2)^3 matrix-multiplication isotropy to the
# outer scheme changes those supports without changing outer rank.  There are
# only 6^3 images, so this benchmark exhausts the complete basis orbit and all
# eight 4/3 block placements, then materializes and fully verifies every
# formula-minimizing tie.

use flipfleet_outer_isotropy

-> ffois_expect(label, condition)
  if condition != 0
    return 1
  << "OUTER_ISOTROPY_FAIL " + label
  exit(1)
  0

root = "benchmarks/matmul/metaflip/"
leaf_paths = ["matmul_3x3_rank23_d139_gf2.txt",
              "matmul_3x3x4_rank29_gf2.txt",
              "matmul_3x4x4_rank38_gf2.txt",
              "matmul_4x4_rank47_d450_gf2.txt"]
leaf_ns = i64[4]
leaf_ms = i64[4]
leaf_ps = i64[4]
leaf_ns[0] = 3
leaf_ms[0] = 3
leaf_ps[0] = 3
leaf_ns[1] = 3
leaf_ms[1] = 3
leaf_ps[1] = 4
leaf_ns[2] = 3
leaf_ms[2] = 4
leaf_ps[2] = 4
leaf_ns[3] = 4
leaf_ms[3] = 4
leaf_ps[3] = 4

leaves = []
i = 0 ## i64
while i < 4
  leaf = ffbc_load_exact(root + leaf_paths[i], leaf_ns[i], leaf_ms[i], leaf_ps[i], 128)
  ffois_expect("load leaf " + i.to_s(), leaf != nil)
  leaves.push(leaf)
  i += 1

outer = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
leader = ffbc_load_exact(root + "matmul_7x7_rank248_d2952_sedoglavic_gf2.txt", 7, 7, 7, 320)
ffois_expect("load outer", outer != nil)
ffois_expect("load leader", leader != nil)

# At most 216*8 ties.  Fixed arrays avoid generic boxing in the native scan.
tie_ci = i64[1728]
tie_cj = i64[1728]
tie_ck = i64[1728]
tie_mask = i64[1728]
tie_count = 0 ## i64
best_formula = 1 << 30 ## i64
images = 0 ## i64
placements = 0 ## i64

ci = 0 ## i64
while ci < 6
  cj = 0 ## i64
  while cj < 6
    ck = 0 ## i64
    while ck < 6
      image = ffois_image(outer, ci, cj, ck)
      ffois_expect("exact orbit image", image != nil && image.rank() == 7 && ffbc_verify_exact(image) == 1)
      images += 1
      mask = 0 ## i64
      while mask < 8
        an = ffois_alloc(mask, 0)
        am = ffois_alloc(mask, 1)
        ap = ffois_alloc(mask, 2)
        score = ffbc_score_allocation(image, an, am, ap, leaves) ## i64
        if score > 0
          placements += 1
          if score < best_formula
            best_formula = score
            tie_count = 0
          if score == best_formula
            tie_ci[tie_count] = ci
            tie_cj[tie_count] = cj
            tie_ck[tie_count] = ck
            tie_mask[tie_count] = mask
            tie_count += 1
        mask += 1
      ck += 1
    cj += 1
  ci += 1

ffois_expect("complete GL2 orbit", images == 216)
ffois_expect("all placements scored", placements == 1728)
ffois_expect("formula ties present", tie_count > 0)

best_exact = 1 << 30 ## i64
best_density = 1 << 30 ## i64
best_pairs = 0 - 1 ## i64
best_novelty = 0 - 1 ## i64
best_tie = 0 - 1 ## i64
best_scheme = nil
exact_ties = 0 ## i64
best_rank_ties = 0 ## i64
zero_ties = 0 ## i64
parity_ties = 0 ## i64
max_zero_terms = 0 ## i64
max_parity_reduction = 0 ## i64
t = 0 ## i64
while t < tie_count
  image = ffois_image(outer, tie_ci[t], tie_cj[t], tie_ck[t])
  an = ffois_alloc(tie_mask[t], 0)
  am = ffois_alloc(tie_mask[t], 1)
  ap = ffois_alloc(tie_mask[t], 2)
  candidate = ffbc_compose(image, an, am, ap, leaves)
  ffois_expect("materialized tie exact", candidate != nil && ffbc_verify_exact(candidate) == 1)
  ffois_expect("composition audit balances", candidate.compose_nominal() - candidate.rank() == candidate.compose_zero_terms() + candidate.compose_parity_reduction())
  exact_ties += 1
  rank = candidate.rank() ## i64
  if rank < best_exact
    best_rank_ties = 1
  elsif rank == best_exact
    best_rank_ties += 1
  if candidate.compose_zero_terms() > 0
    zero_ties += 1
  if candidate.compose_parity_reduction() > 0
    parity_ties += 1
  if candidate.compose_zero_terms() > max_zero_terms
    max_zero_terms = candidate.compose_zero_terms()
  if candidate.compose_parity_reduction() > max_parity_reduction
    max_parity_reduction = candidate.compose_parity_reduction()
  density = fflc_density(candidate) ## i64
  pairs = fflc_equal_factor_pairs(candidate) ## i64
  novelty = fflc_term_set_distance(leader, candidate) ## i64
  better = 0 ## i64
  if rank < best_exact
    better = 1
  elsif rank == best_exact && density < best_density
    better = 1
  elsif rank == best_exact && density == best_density && pairs > best_pairs
    better = 1
  elsif rank == best_exact && density == best_density && pairs == best_pairs && novelty > best_novelty
    better = 1
  if better == 1
    best_exact = rank
    best_density = density
    best_pairs = pairs
    best_novelty = novelty
    best_tie = t
    best_scheme = candidate
  t += 1

ffois_expect("best materialization exact", best_scheme != nil && ffbc_verify_exact(best_scheme) == 1)
output = "/tmp/matmul_7x7_outer_isotropy_best_gf2.txt"
ffois_expect("write best", ffbc_write(output, best_scheme) == best_exact)
reloaded = ffbc_load_exact(output, 7, 7, 7, 320)
ffois_expect("reparse best", reloaded != nil && reloaded.rank() == best_exact && ffbc_verify_exact(reloaded) == 1)

<< "OUTER_ISOTROPY_SUMMARY images=" + images.to_s() + " placements=" + placements.to_s() + " formula=" + best_formula.to_s() + " formula-ties=" + tie_count.to_s() + " exact-ties=" + exact_ties.to_s() + " exact=" + best_exact.to_s() + " best-rank-ties=" + best_rank_ties.to_s() + " zero-ties=" + zero_ties.to_s() + " parity-ties=" + parity_ties.to_s() + " max-zero=" + max_zero_terms.to_s() + " max-parity=" + max_parity_reduction.to_s() + " density=" + best_density.to_s() + " pairs=" + best_pairs.to_s() + " novelty=" + best_novelty.to_s() + " code=" + tie_ci[best_tie].to_s() + "," + tie_cj[best_tie].to_s() + "," + tie_ck[best_tie].to_s() + " alloc-mask=" + tie_mask[best_tie].to_s() + " output=" + output
