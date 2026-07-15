use flipfleet_leaf_conjugation

-> fflct_expect(name, condition)
  if condition
    << "PASS " + name
    return 0
  << "FAIL " + name
  exit(1)
  1

root = "benchmarks/matmul/metaflip/"
paths = ["matmul_3x3_rank23_d139_gf2.txt",
         "matmul_3x3x4_rank29_gf2.txt",
         "matmul_3x4x4_rank38_gf2.txt",
         "matmul_4x4_rank47_d450_gf2.txt"]
ns = i64[4]
ms = i64[4]
ps = i64[4]
ns[0] = 3
ms[0] = 3
ps[0] = 3
ns[1] = 3
ms[1] = 3
ps[1] = 4
ns[2] = 3
ms[2] = 4
ps[2] = 4
ns[3] = 4
ms[3] = 4
ps[3] = 4

leaves = []
images = []
i = 0 ## i64
while i < 4
  leaf = ffbc_load_exact(root + paths[i], ns[i], ms[i], ps[i], 128)
  fflct_expect("load exact leaf " + i.to_s(), leaf != nil)
  image = fflc_default_leaf_image(leaf)
  fflct_expect("conjugated leaf exact " + i.to_s(), image != nil && image.rank() == leaf.rank() && image.n() == leaf.n() && image.m() == leaf.m() && image.p() == leaf.p())
  fflct_expect("conjugated leaf changed " + i.to_s(), fflc_equal(leaf, image) == 0 && fflc_slot_distance(leaf, image) > 0)
  leaves.push(leaf)
  images.push(image)
  i += 1

# A transvection is its own inverse over GF(2).  This also guards the P/P^-T
# direction on all three logical index spaces.
axis = 0 ## i64
while axis < 3
  once = fflc_transvection(leaves[1], axis, 1, 0)
  twice = fflc_transvection(once, axis, 1, 0)
  fflct_expect("axis " + axis.to_s() + " transvection involution", once != nil && twice != nil && fflc_equal(leaves[1], twice) == 1)
  axis += 1
fflct_expect("boundary rejects high coordinate", fflc_transvection(leaves[1], 0, leaves[1].n(), 0) == nil)
fflct_expect("boundary rejects repeated coordinate", fflc_transvection(leaves[1], 1, 1, 1) == nil)

sparse_a = fflc_sparse_leaf_image(leaves[3], 424242, 6)
sparse_b = fflc_sparse_leaf_image(leaves[3], 424242, 6)
sparse_c = fflc_sparse_leaf_image(leaves[3], 424243, 6)
fflct_expect("sparse program exact", sparse_a != nil && ffbc_verify_exact(sparse_a) == 1 && sparse_a.rank() == leaves[3].rank())
fflct_expect("sparse program reproducible", fflc_equal(sparse_a, sparse_b) == 1)
fflct_expect("sparse program changes orbit representative", fflc_equal(sparse_a, leaves[3]) == 0)
fflct_expect("neighboring sparse seeds diversify", sparse_c != nil && fflc_equal(sparse_a, sparse_c) == 0)
fflct_expect("term-set novelty is permutation invariant metric", fflc_term_set_distance(leaves[3], leaves[3]) == 0 && fflc_term_set_distance(leaves[3], sparse_a) > 0)

# Reconstruct the saved 7x7 rank-248 Strassen/block composition twice: once
# with its original rectangular leaves and once with every leaf independently
# conjugated before embedding.
outer = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
alloc_n = i64[2]
alloc_m = i64[2]
alloc_p = i64[2]
alloc_n[0] = 4
alloc_n[1] = 3
alloc_m[0] = 4
alloc_m[1] = 3
alloc_p[0] = 4
alloc_p[1] = 3
baseline = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
changed = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, images)
fflct_expect("baseline full rank-248 exact", baseline != nil && baseline.rank() == 248 && ffbc_verify_exact(baseline) == 1)
fflct_expect("conjugated full rank-248 exact", changed != nil && changed.rank() == 248 && ffbc_verify_exact(changed) == 1)
fflct_expect("full placement changed", fflc_equal(baseline, changed) == 0 && fflc_slot_distance(baseline, changed) > 200)

base_density = fflc_density(baseline) ## i64
image_density = fflc_density(changed) ## i64
base_pairs = fflc_equal_factor_pairs(baseline) ## i64
image_pairs = fflc_equal_factor_pairs(changed) ## i64
fflct_expect("full support/connectivity descriptor changed", base_density != image_density || base_pairs != image_pairs)

descriptor = i64[3]
fflct_expect("descriptor accepts exact composition", fflc_descriptor(baseline, changed, descriptor) == 1 && descriptor[0] == image_density && descriptor[1] == image_pairs && descriptor[2] > 0)

# Density is minimized while connectivity and novelty are maximized. Candidate
# 1 dominates candidate 0; candidate 2 trades density for novelty and remains.
densities = i64[3]
pairs = i64[3]
novelties = i64[3]
keep = i64[3]
densities[0] = 100
pairs[0] = 5
novelties[0] = 4
densities[1] = 99
pairs[1] = 6
novelties[1] = 4
densities[2] = 101
pairs[2] = 5
novelties[2] = 20
front = fflc_pareto_mark(densities, pairs, novelties, 3, keep) ## i64
fflct_expect("pareto scorer respects three objectives", front == 2 && keep[0] == 0 && keep[1] == 1 && keep[2] == 1)
<< "leaf conjugation: rank=248 changed-slots=" + fflc_slot_distance(baseline, changed).to_s() + " density=" + base_density.to_s() + "->" + image_density.to_s() + " pairs=" + base_pairs.to_s() + "->" + image_pairs.to_s()
<< "flipfleet_leaf_conjugation_test: all checks passed"
