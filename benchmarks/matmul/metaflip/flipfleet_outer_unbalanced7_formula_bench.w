# Formula-only closure of every two-block decomposition of 7 through the
# complete GL(2,2)^3 Strassen outer orbit.  The scan includes 6+1, 5+2, and
# 4+3 splits in every axis and uses the best audited GF(2) bilinear ranks for
# leaves of size at most six.  Competitive recipes can then be materialised
# with explicit exact leaves; noncompetitive families need no certificate I/O.

use flipfleet_outer_isotropy
use flipfleet_block_leaf_pool

-> ffou_expect(label, condition)
  if condition != 0
    return 1
  << "OUTER_UNBALANCED7_FAIL " + label
  exit(1)
  0

-> ffou_add(leaves, n, m, p, rank)
  leaf = FFBCScheme.new(n, m, p, rank)
  leaf.set_rank(rank)
  leaves.push(leaf)
  1

-> ffou_alloc(first) (i64)
  result = i64[2]
  result[0] = first
  result[1] = 7 - first
  result

leaves = []

# Dimension-one tensors have flattening lower bound ab and the naive scheme
# attains it, hence rank <1,a,b> = a*b over every field.
a = 1 ## i64
while a <= 6
  b = a ## i64
  while b <= 6
    ffou_add(leaves, 1, a, b, a * b)
    b += 1
  a += 1

# Best audited GF(2) bilinear ranks with minimum dimension two.
ffou_add(leaves, 2, 2, 2, 7)
ffou_add(leaves, 2, 2, 3, 11)
ffou_add(leaves, 2, 2, 4, 14)
ffou_add(leaves, 2, 2, 5, 18)
ffou_add(leaves, 2, 2, 6, 21)
ffou_add(leaves, 2, 3, 3, 15)
ffou_add(leaves, 2, 3, 4, 20)
ffou_add(leaves, 2, 3, 5, 25)
ffou_add(leaves, 2, 3, 6, 30)
ffou_add(leaves, 2, 4, 4, 26)
ffou_add(leaves, 2, 4, 5, 33)
ffou_add(leaves, 2, 4, 6, 39)
ffou_add(leaves, 2, 5, 5, 40)
ffou_add(leaves, 2, 5, 6, 47)
ffou_add(leaves, 2, 6, 6, 56)

# Current exact GF(2) ranks for sorted dimensions three through six.
ffou_add(leaves, 3, 3, 3, 23)
ffou_add(leaves, 3, 3, 4, 29)
ffou_add(leaves, 3, 3, 5, 36)
ffou_add(leaves, 3, 3, 6, 42)
ffou_add(leaves, 3, 4, 4, 38)
ffou_add(leaves, 3, 4, 5, 47)
ffou_add(leaves, 3, 4, 6, 54)
ffou_add(leaves, 3, 5, 5, 58)
ffou_add(leaves, 3, 5, 6, 68)
ffou_add(leaves, 3, 6, 6, 82)
ffou_add(leaves, 4, 4, 4, 47)
ffou_add(leaves, 4, 4, 5, 60)
ffou_add(leaves, 4, 4, 6, 73)
ffou_add(leaves, 4, 5, 5, 76)
ffou_add(leaves, 4, 5, 6, 90)
ffou_add(leaves, 4, 6, 6, 105)
ffou_add(leaves, 5, 5, 5, 93)
ffou_add(leaves, 5, 5, 6, 110)
ffou_add(leaves, 5, 6, 6, 130)
ffou_add(leaves, 6, 6, 6, 153)

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
ffou_expect("outer", outer != nil && outer.rank() == 7)

best = 1 << 30 ## i64
best_ci = 0 - 1 ## i64
best_cj = 0 - 1 ## i64
best_ck = 0 - 1 ## i64
best_an = 0 - 1 ## i64
best_am = 0 - 1 ## i64
best_ap = 0 - 1 ## i64
recipes = 0 ## i64
split2_ci = i64[46656]
split2_cj = i64[46656]
split2_ck = i64[46656]
split2_an = i64[46656]
split2_am = i64[46656]
split2_ap = i64[46656]
split2_count = 0 ## i64
split_best = i64[4]
split_ci = i64[4]
split_cj = i64[4]
split_ck = i64[4]
split_an = i64[4]
split_am = i64[4]
split_ap = i64[4]
i = 0
while i < split_best.size()
  split_best[i] = 1 << 30
  i += 1

ci = 0 ## i64
while ci < 6
  cj = 0 ## i64
  while cj < 6
    ck = 0 ## i64
    while ck < 6
      image = ffois_image(outer, ci, cj, ck)
      ffou_expect("exact image", image != nil && ffbc_verify_exact(image) == 1)
      first_n = 1 ## i64
      while first_n <= 6
        first_m = 1 ## i64
        while first_m <= 6
          first_p = 1 ## i64
          while first_p <= 6
            an = ffou_alloc(first_n)
            am = ffou_alloc(first_m)
            ap = ffou_alloc(first_p)
            score = ffbc_score_allocation(image, an, am, ap, leaves) ## i64
            ffou_expect("score", score > 0)
            recipes += 1
            minimum_part = first_n ## i64
            if 7 - first_n < minimum_part
              minimum_part = 7 - first_n
            other = first_m
            if 7 - first_m < other
              other = 7 - first_m
            if other < minimum_part
              minimum_part = other
            other = first_p
            if 7 - first_p < other
              other = 7 - first_p
            if other < minimum_part
              minimum_part = other
            if score < split_best[minimum_part]
              split_best[minimum_part] = score
              split_ci[minimum_part] = ci
              split_cj[minimum_part] = cj
              split_ck[minimum_part] = ck
              split_an[minimum_part] = first_n
              split_am[minimum_part] = first_m
              split_ap[minimum_part] = first_p
            if minimum_part == 2 && score <= 256
              split2_ci[split2_count] = ci
              split2_cj[split2_count] = cj
              split2_ck[split2_count] = ck
              split2_an[split2_count] = first_n
              split2_am[split2_count] = first_m
              split2_ap[split2_count] = first_p
              split2_count += 1
            if score < best
              best = score
              best_ci = ci
              best_cj = cj
              best_ck = ck
              best_an = first_n
              best_am = first_m
              best_ap = first_p
              << "OUTER_UNBALANCED7_BEST formula=" + best.to_s() + " code=" + ci.to_s() + "," + cj.to_s() + "," + ck.to_s() + " first=" + first_n.to_s() + "," + first_m.to_s() + "," + first_p.to_s()
            first_p += 1
          first_m += 1
        first_n += 1
      ck += 1
    cj += 1
  ci += 1

ffou_expect("complete", recipes == 46656)
<< "OUTER_UNBALANCED7_SUMMARY recipes=" + recipes.to_s() + " formula=" + best.to_s() + " code=" + best_ci.to_s() + "," + best_cj.to_s() + "," + best_ck.to_s() + " first=" + best_an.to_s() + "," + best_am.to_s() + "," + best_ap.to_s() + " minpart1=" + split_best[1].to_s() + " minpart2=" + split_best[2].to_s() + " minpart3=" + split_best[3].to_s()

# Materialise the best formula recipe through independently exact leaves.  Its
# 2x3x3/2x3x4/2x4x4 requirements are all catalog-gated in this repository.
exact_leaves = ffbcp_stable_3_to_8(root)
ffbcp_add(root, "matmul_2x3x3_rank15_catalog_gf2.txt", 2, 3, 3, exact_leaves)
ffbcp_add(root, "matmul_2x3x4_rank20_catalog_gf2.txt", 2, 3, 4, exact_leaves)
ffbcp_add(root, "matmul_2x4x4_rank26_catalog_gf2.txt", 2, 4, 4, exact_leaves)
best_image = ffois_image(outer, best_ci, best_cj, best_ck)
best_candidate = ffbc_compose(best_image, ffou_alloc(best_an), ffou_alloc(best_am), ffou_alloc(best_ap), exact_leaves)
ffou_expect("materialized best", best_candidate != nil && ffbc_verify_exact(best_candidate) == 1)
ffou_expect("materialized formula", best_candidate.compose_nominal() == best)
output = "/tmp/matmul_7x7_unbalanced_outer_best_gf2.txt"
ffou_expect("serialize best", ffbc_write(output, best_candidate) == best_candidate.rank())
reloaded = ffbc_load_exact(output, 7, 7, 7, best_candidate.rank() + 8)
ffou_expect("reparse best", reloaded != nil && reloaded.rank() == best_candidate.rank() && ffbc_verify_exact(reloaded) == 1)
<< "OUTER_UNBALANCED7_EXACT formula=" + best.to_s() + " exact=" + best_candidate.rank().to_s() + " zero=" + best_candidate.compose_zero_terms().to_s() + " parity=" + best_candidate.compose_parity_reduction().to_s() + " output=" + output

split2_image = ffois_image(outer, split_ci[2], split_cj[2], split_ck[2])
split2_candidate = ffbc_compose(split2_image, ffou_alloc(split_an[2]), ffou_alloc(split_am[2]), ffou_alloc(split_ap[2]), exact_leaves)
ffou_expect("materialized minpart2", split2_candidate != nil && ffbc_verify_exact(split2_candidate) == 1 && split2_candidate.compose_nominal() == split_best[2])
<< "OUTER_UNBALANCED7_MINPART2 formula=" + split_best[2].to_s() + " exact=" + split2_candidate.rank().to_s() + " zero=" + split2_candidate.compose_zero_terms().to_s() + " parity=" + split2_candidate.compose_parity_reduction().to_s() + " code=" + split_ci[2].to_s() + "," + split_cj[2].to_s() + "," + split_ck[2].to_s() + " first=" + split_an[2].to_s() + "," + split_am[2].to_s() + "," + split_ap[2].to_s()

split2_exact = 1 << 30 ## i64
split2_zero_max = 0 ## i64
split2_parity_max = 0 ## i64
i = 0
while i < split2_count
  image = ffois_image(outer, split2_ci[i], split2_cj[i], split2_ck[i])
  candidate = ffbc_compose(image, ffou_alloc(split2_an[i]), ffou_alloc(split2_am[i]), ffou_alloc(split2_ap[i]), exact_leaves)
  ffou_expect("minpart2 tie exact", candidate != nil && ffbc_verify_exact(candidate) == 1 && candidate.compose_nominal() <= 256)
  if candidate.rank() < split2_exact
    split2_exact = candidate.rank()
  if candidate.compose_zero_terms() > split2_zero_max
    split2_zero_max = candidate.compose_zero_terms()
  if candidate.compose_parity_reduction() > split2_parity_max
    split2_parity_max = candidate.compose_parity_reduction()
  i += 1
<< "OUTER_UNBALANCED7_MINPART2_CLOSURE recipes=" + split2_count.to_s() + " exact=" + split2_exact.to_s() + " max-zero=" + split2_zero_max.to_s() + " max-parity=" + split2_parity_max.to_s()
