# Exact 7x7 block composition through a rank-23 3x3 outer and 3+2+2 splits.
# This is structurally independent of the rank-7 Strassen 4+3 construction.

use flipfleet_leaf_conjugation

-> ffo3_expect(label, condition)
  if condition != 0
    return 1
  << "OUTER_3X3_SPLIT_FAIL " + label
  exit(1)
  0

-> ffo3_alloc(position) (i64)
  result = i64[3]
  result[0] = 2
  result[1] = 2
  result[2] = 2
  result[position] = 3
  result

# Steepest exact walk in the 18 elementary generators of GL(3,2)^3.  The
# endpoint is full-gated by fflc_transvection at every accepted step.
-> ffo3_descent(source, an, am, ap, leaves, stats) (FFBCScheme i64[] i64[] i64[] Array i64[])
  current = fflc_clone(source)
  current_score = ffbc_score_allocation(current, an, am, ap, leaves) ## i64
  stats[0] = current_score
  stats[1] = current_score
  stats[2] = 0
  stats[3] = 0
  running = 1 ## i64
  while running == 1 && stats[2] < 64
    next_image = nil
    next_score = current_score ## i64
    axis = 0 ## i64
    while axis < 3
      dst = 0 ## i64
      while dst < 3
        src = 0 ## i64
        while src < 3
          if src != dst
            candidate = fflc_transvection(current, axis, dst, src)
            if candidate == nil
              return nil
            score = ffbc_score_allocation(candidate, an, am, ap, leaves) ## i64
            stats[3] += 1
            if score > 0 && score < next_score
              next_image = candidate
              next_score = score
          src += 1
        dst += 1
      axis += 1
    if next_image == nil
      running = 0
    else
      current = next_image
      current_score = next_score
      stats[1] = current_score
      stats[2] += 1
  current

root = "benchmarks/matmul/metaflip/"
paths = ["matmul_2x2_rank7_strassen_gf2.txt",
         "matmul_2x2x3_rank11_catalog_gf2.txt",
         "matmul_2x3x3_rank15_catalog_gf2.txt",
         "matmul_3x3_rank23_d139_gf2.txt"]
ns = i64[4]
ms = i64[4]
ps = i64[4]
ns[0] = 2
ms[0] = 2
ps[0] = 2
ns[1] = 2
ms[1] = 2
ps[1] = 3
ns[2] = 2
ms[2] = 3
ps[2] = 3
ns[3] = 3
ms[3] = 3
ps[3] = 3
leaves = []
i = 0 ## i64
while i < 4
  leaf = ffbc_load_exact(root + paths[i], ns[i], ms[i], ps[i], 64)
  ffo3_expect("load leaf " + i.to_s(), leaf != nil)
  leaves.push(leaf)
  i += 1

outer = ffbc_load_exact(root + "matmul_3x3_rank23_d139_gf2.txt", 3, 3, 3, 64)
ffo3_expect("load outer", outer != nil && outer.rank() == 23)

best_rank = 1 << 30 ## i64
best_formula = 1 << 30 ## i64
best_density = 1 << 30 ## i64
best_i = 0 - 1 ## i64
best_j = 0 - 1 ## i64
best_k = 0 - 1 ## i64
best = nil
rank_hist = i64[32]
recipes = 0 ## i64
best_base_formula = 1 << 30 ## i64
largest_isotropy_gain = 0 ## i64

ai = 0 ## i64
while ai < 3
  aj = 0 ## i64
  while aj < 3
    ak = 0 ## i64
    while ak < 3
      an = ffo3_alloc(ai)
      am = ffo3_alloc(aj)
      ap = ffo3_alloc(ak)
      base_formula = ffbc_score_allocation(outer, an, am, ap, leaves) ## i64
      if base_formula < best_base_formula
        best_base_formula = base_formula
      stats = i64[4]
      image = ffo3_descent(outer, an, am, ap, leaves, stats)
      ffo3_expect("isotropy descent", image != nil && ffbc_verify_exact(image) == 1)
      formula = ffbc_score_allocation(image, an, am, ap, leaves) ## i64
      if base_formula - formula > largest_isotropy_gain
        largest_isotropy_gain = base_formula - formula
      ffo3_expect("formula", formula > 0)
      candidate = ffbc_compose(image, an, am, ap, leaves)
      ffo3_expect("exact composition", candidate != nil && ffbc_verify_exact(candidate) == 1)
      ffo3_expect("audit", candidate.compose_nominal() == formula && formula - candidate.rank() == candidate.compose_zero_terms() + candidate.compose_parity_reduction())
      recipes += 1
      if candidate.rank() >= 220 && candidate.rank() < 252
        rank_hist[candidate.rank() - 220] = rank_hist[candidate.rank() - 220] + 1
      density = fflc_density(candidate) ## i64
      if candidate.rank() < best_rank || (candidate.rank() == best_rank && density < best_density)
        best = candidate
        best_rank = candidate.rank()
        best_formula = formula
        best_density = density
        best_i = ai
        best_j = aj
        best_k = ak
        << "OUTER_3X3_SPLIT_BEST rank=" + best_rank.to_s() + " formula=" + formula.to_s() + " base=" + base_formula.to_s() + " steps=" + stats[2].to_s() + " zero=" + candidate.compose_zero_terms().to_s() + " parity=" + candidate.compose_parity_reduction().to_s() + " density=" + density.to_s() + " alloc=" + ai.to_s() + "," + aj.to_s() + "," + ak.to_s()
      ak += 1
    aj += 1
  ai += 1

ffo3_expect("complete scan", recipes == 27 && best != nil)
output = "/tmp/matmul_7x7_outer3_split_best_gf2.txt"
ffo3_expect("serialize", ffbc_write(output, best) == best_rank)
reloaded = ffbc_load_exact(output, 7, 7, 7, best_rank + 8)
ffo3_expect("reparse", reloaded != nil && reloaded.rank() == best_rank && ffbc_verify_exact(reloaded) == 1)

histogram = ""
rank = 220 ## i64
while rank < 252
  if rank_hist[rank - 220] > 0
    if histogram.size() > 0
      histogram = histogram + ","
    histogram = histogram + rank.to_s() + ":" + rank_hist[rank - 220].to_s()
  rank += 1
<< "OUTER_3X3_SPLIT_SUMMARY recipes=" + recipes.to_s() + " exact=" + best_rank.to_s() + " formula=" + best_formula.to_s() + " base-formula=" + best_base_formula.to_s() + " max-isotropy-gain=" + largest_isotropy_gain.to_s() + " density=" + best_density.to_s() + " alloc=" + best_i.to_s() + "," + best_j.to_s() + "," + best_k.to_s() + " histogram=" + histogram + " output=" + output
