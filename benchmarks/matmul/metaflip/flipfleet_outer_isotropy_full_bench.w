# Exhaustive materialisation audit of every weighted Strassen-outer recipe.
#
# The formula-minimum audit deliberately materialises only nominal-rank ties.
# That is sufficient for ordinary composition scoring but not for
# support-truncating tunnelling: a more expensive nominal recipe can map more
# leaf products to zero and finish at a lower exact rank.  This harness closes
# that gap by full-gating all 6^3 GL(2,2) images and all eight 4/3 placements.

use flipfleet_outer_isotropy

-> ffoisf_expect(label, condition)
  if condition != 0
    return 1
  << "OUTER_ISOTROPY_FULL_FAIL " + label
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
  ffoisf_expect("load leaf " + i.to_s(), leaf != nil)
  leaves.push(leaf)
  i += 1

outer = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
leader = ffbc_load_exact(root + "matmul_7x7_rank248_d2952_sedoglavic_gf2.txt", 7, 7, 7, 320)
ffoisf_expect("load exact inputs", outer != nil && leader != nil)

formula_best = 1 << 30 ## i64
formula_worst = 0 ## i64
exact_best = 1 << 30 ## i64
best_rank_ties = 0 ## i64
best_density = 1 << 30 ## i64
best_pairs = 0 - 1 ## i64
best_novelty = 0 - 1 ## i64
best_ci = 0 - 1 ## i64
best_cj = 0 - 1 ## i64
best_ck = 0 - 1 ## i64
best_mask = 0 - 1 ## i64
best_scheme = nil
materialized = 0 ## i64
zero_recipes = 0 ## i64
parity_recipes = 0 ## i64
max_zero = 0 ## i64
max_parity = 0 ## i64
exact_hist = i64[32]

ci = 0 ## i64
while ci < 6
  cj = 0 ## i64
  while cj < 6
    ck = 0 ## i64
    while ck < 6
      image = ffois_image(outer, ci, cj, ck)
      ffoisf_expect("exact orbit image", image != nil && image.rank() == 7 && ffbc_verify_exact(image) == 1)
      mask = 0 ## i64
      while mask < 8
        an = ffois_alloc(mask, 0)
        am = ffois_alloc(mask, 1)
        ap = ffois_alloc(mask, 2)
        formula = ffbc_score_allocation(image, an, am, ap, leaves) ## i64
        ffoisf_expect("formula score", formula > 0)
        if formula < formula_best
          formula_best = formula
        if formula > formula_worst
          formula_worst = formula

        candidate = ffbc_compose(image, an, am, ap, leaves)
        ffoisf_expect("materialized exact", candidate != nil && ffbc_verify_exact(candidate) == 1)
        ffoisf_expect("nominal agrees", candidate.compose_nominal() == formula)
        ffoisf_expect("audit balances", formula - candidate.rank() == candidate.compose_zero_terms() + candidate.compose_parity_reduction())
        materialized += 1
        if candidate.compose_zero_terms() > 0
          zero_recipes += 1
        if candidate.compose_parity_reduction() > 0
          parity_recipes += 1
        if candidate.compose_zero_terms() > max_zero
          max_zero = candidate.compose_zero_terms()
        if candidate.compose_parity_reduction() > max_parity
          max_parity = candidate.compose_parity_reduction()

        rank = candidate.rank() ## i64
        if rank >= 240 && rank < 272
          exact_hist[rank - 240] = exact_hist[rank - 240] + 1
        rank_improved = 0 ## i64
        if rank < exact_best
          exact_best = rank
          best_rank_ties = 1
          rank_improved = 1
        elsif rank == exact_best
          best_rank_ties += 1
        density = fflc_density(candidate) ## i64
        pairs = fflc_equal_factor_pairs(candidate) ## i64
        novelty = fflc_term_set_distance(leader, candidate) ## i64
        better = 0 ## i64
        if rank_improved == 1
          better = 1
        elsif rank == exact_best && (best_scheme == nil || density < best_density)
          better = 1
        elsif rank == exact_best && density == best_density && pairs > best_pairs
          better = 1
        elsif rank == exact_best && density == best_density && pairs == best_pairs && novelty > best_novelty
          better = 1
        if better == 1
          best_scheme = candidate
          best_density = density
          best_pairs = pairs
          best_novelty = novelty
          best_ci = ci
          best_cj = cj
          best_ck = ck
          best_mask = mask
          << "OUTER_ISOTROPY_FULL_BEST rank=" + rank.to_s() + " formula=" + formula.to_s() + " zero=" + candidate.compose_zero_terms().to_s() + " parity=" + candidate.compose_parity_reduction().to_s() + " density=" + density.to_s() + " code=" + ci.to_s() + "," + cj.to_s() + "," + ck.to_s() + " alloc-mask=" + mask.to_s()
        mask += 1
      ck += 1
    cj += 1
  ci += 1

ffoisf_expect("complete materialization", materialized == 1728)
ffoisf_expect("best exact", best_scheme != nil && ffbc_verify_exact(best_scheme) == 1)
output = "/tmp/matmul_7x7_outer_isotropy_full_best_gf2.txt"
ffoisf_expect("serialize", ffbc_write(output, best_scheme) == exact_best)
reloaded = ffbc_load_exact(output, 7, 7, 7, 320)
ffoisf_expect("reparse", reloaded != nil && reloaded.rank() == exact_best && ffbc_verify_exact(reloaded) == 1)

histogram = ""
rank = 240 ## i64
while rank < 272
  if exact_hist[rank - 240] > 0
    if histogram.size() > 0
      histogram = histogram + ","
    histogram = histogram + rank.to_s() + ":" + exact_hist[rank - 240].to_s()
  rank += 1

<< "OUTER_ISOTROPY_FULL_SUMMARY materialized=" + materialized.to_s() + " formula=" + formula_best.to_s() + ".." + formula_worst.to_s() + " exact=" + exact_best.to_s() + " best-rank-ties=" + best_rank_ties.to_s() + " zero-recipes=" + zero_recipes.to_s() + " parity-recipes=" + parity_recipes.to_s() + " max-zero=" + max_zero.to_s() + " max-parity=" + max_parity.to_s() + " density=" + best_density.to_s() + " pairs=" + best_pairs.to_s() + " novelty=" + best_novelty.to_s() + " code=" + best_ci.to_s() + "," + best_cj.to_s() + "," + best_ck.to_s() + " alloc-mask=" + best_mask.to_s() + " histogram=" + histogram + " output=" + output
