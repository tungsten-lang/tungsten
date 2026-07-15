use flipfleet_block_composer

-> ffbc_test_expect(name, condition)
  if condition
    << "PASS " + name
    return 0
  << "FAIL " + name
  exit(1)
  1

-> ffbc_test_arrays_equal(left, right) (i64[] i64[]) i64
  if left.size() != right.size()
    return 0
  i = 0 ## i64
  while i < left.size()
    if left[i] != right[i]
      return 0
    i += 1
  1

root = "benchmarks/matmul/metaflip/"

# Decimal conversion crosses both the signed-i64 and 128-bit boundaries.
decimal = "40564819207303340847894502572161"
wide = i64[8]
ffbc_test_expect("wide decimal parse", ffbc_decimal_to_words(decimal, wide, 0, 8))
ffbc_test_expect("wide decimal round trip", ffbc_words_to_decimal(wide, 0, 8) == decimal)
probe = FFBCScheme.new(2, 2, 2, 8)
ffbc_test_expect("typed scheme metadata", probe.uw() == 1 && probe.us().size() == 8)
ffbc_test_expect("bounded allocations total 22", ffbc_bounded_allocations(22, 4, 3, 8).size() == 146)
ffbc_test_expect("bounded allocations reject range", ffbc_bounded_allocations(11, 4, 3, 8).size() == 0)

leaf_paths = [root + "matmul_3x3_rank23_d139_gf2.txt",
              root + "matmul_3x3x4_rank29_gf2.txt",
              root + "matmul_3x4x4_rank38_gf2.txt",
              root + "matmul_4x4_rank47_d450_gf2.txt"]
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

# Generic Strassen outer composition reproduces the checked-in 7^3 rank 248.
alloc7n = i64[2]
alloc7m = i64[2]
alloc7p = i64[2]
alloc7n[0] = 4
alloc7n[1] = 3
alloc7m[0] = 4
alloc7m[1] = 3
alloc7p[0] = 4
alloc7p[1] = 3
out7 = "/tmp/flipfleet_block_7x7_rank248.txt"
probe_outer = ffbc_load(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 32)
ffbc_test_expect("Strassen load", probe_outer != nil)
probe223 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 32)
ffbc_test_expect("2x2x3 leaf load", probe223 != nil && probe223.rank() == 11)
probe334 = ffbc_load_exact(root + "matmul_3x3x4_rank29_gf2.txt", 3, 3, 4, 64)
orientation_ns = i64[6]
orientation_ms = i64[6]
orientation_ps = i64[6]
orientation_ns[0] = 3
orientation_ms[0] = 3
orientation_ps[0] = 4
orientation_ns[1] = 3
orientation_ms[1] = 4
orientation_ps[1] = 3
orientation_ns[2] = 4
orientation_ms[2] = 3
orientation_ps[2] = 3
orientation_ns[3] = 4
orientation_ms[3] = 3
orientation_ps[3] = 3
orientation_ns[4] = 3
orientation_ms[4] = 3
orientation_ps[4] = 4
orientation_ns[5] = 3
orientation_ms[5] = 4
orientation_ps[5] = 3
code = 0 ## i64
while code < 6
  probe334_oriented = ffbc_orient_scheme(probe334, code)
  ffbc_test_expect("scheme orientation code " + code.to_s() + " exact", probe334_oriented != nil && probe334_oriented.n() == orientation_ns[code] && probe334_oriented.m() == orientation_ms[code] && probe334_oriented.p() == orientation_ps[code] && probe334_oriented.rank() == 29)
  code += 1
probe344 = ffbc_load_exact(root + "matmul_3x4x4_rank38_gf2.txt", 3, 4, 4, 64)
probe344_oriented = ffbc_orient_scheme(probe344, 4)
ffbc_test_expect("scheme orientation code 4 changes dimensions", probe344_oriented != nil && probe344_oriented.n() == 4 && probe344_oriented.m() == 3 && probe344_oriented.p() == 4 && probe344_oriented.rank() == 38)
r7 = ffbc_compose_files(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2,
                        alloc7n, alloc7m, alloc7p,
                        leaf_paths, leaf_ns, leaf_ms, leaf_ps, out7) ## i64
ffbc_test_expect("7x7 composed rank 248", r7 == 248)
check7 = ffbc_load_exact(out7, 7, 7, 7, 384)
ffbc_test_expect("7x7 reload exact", check7 != nil && check7.rank() == 248)

# The two smallest exact leaves close the balanced 8--11 seam.  The all-two
# endpoint reproduces the known public GF(2) rank-329 8x8x8 construction.
small_paths = [root + "matmul_2x2_rank7_strassen_gf2.txt",
               root + "matmul_2x2x3_rank11_catalog_gf2.txt"]
small_ns = i64[2]
small_ms = i64[2]
small_ps = i64[2]
small_ns[0] = 2
small_ms[0] = 2
small_ps[0] = 2
small_ns[1] = 2
small_ms[1] = 2
small_ps[1] = 3
alloc8n = i64[4]
alloc8m = i64[4]
alloc8p = i64[4]
i = 0 ## i64
while i < 4
  alloc8n[i] = 2
  alloc8m[i] = 2
  alloc8p[i] = 2
  i += 1
out8 = "/tmp/flipfleet_block_8x8_rank329.txt"
r8 = ffbc_compose_files(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4,
                        alloc8n, alloc8m, alloc8p,
                        small_paths, small_ns, small_ms, small_ps, out8) ## i64
ffbc_test_expect("8x8 composed rank 329", r8 == 329)
check8 = ffbc_load_exact(out8, 8, 8, 8, 384)
ffbc_test_expect("8x8 reload exact", check8 != nil && check8.rank() == 329)

# Rank-47 outer allocation for 13 = [3,4,3,3] x [4,3,3,3] x [3,4,3,3].
# Shape multiset: 10*333 + 27*334 + 9*344 + 1*444 = 1402.
alloc13n = i64[4]
alloc13m = i64[4]
alloc13p = i64[4]
alloc13n[0] = 3
alloc13n[1] = 4
alloc13n[2] = 3
alloc13n[3] = 3
alloc13m[0] = 4
alloc13m[1] = 3
alloc13m[2] = 3
alloc13m[3] = 3
alloc13p[0] = 3
alloc13p[1] = 4
alloc13p[2] = 3
alloc13p[3] = 3
out13 = "/tmp/flipfleet_block_13x13_rank1402.txt"
r13 = ffbc_compose_files(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4,
                         alloc13n, alloc13m, alloc13p,
                         leaf_paths, leaf_ns, leaf_ms, leaf_ps, out13) ## i64
ffbc_test_expect("13x13 composed rank 1402", r13 == 1402)
check13 = ffbc_load_exact(out13, 13, 13, 13, 1600)
ffbc_test_expect("13x13 reload exact", check13 != nil && check13.rank() == 1402)

# Rank-47 outer allocation for 15.  The nominal leaf sum is 2014; six rank-1
# terms map to zero on truncated block corners and are removed, leaving 2008.
alloc15n = i64[4]
alloc15m = i64[4]
alloc15p = i64[4]
i = 0 ## i64
while i < 4
  alloc15n[i] = 4
  alloc15m[i] = 4
  alloc15p[i] = 4
  i += 1
alloc15n[0] = 3
alloc15m[3] = 3
alloc15p[0] = 3
out15 = "/tmp/flipfleet_block_15x15_rank2008.txt"
r15 = ffbc_compose_files(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4,
                         alloc15n, alloc15m, alloc15p,
                         leaf_paths, leaf_ns, leaf_ms, leaf_ps, out15) ## i64
ffbc_test_expect("15x15 composed rank 2008", r15 == 2008)
check15 = ffbc_load_exact(out15, 15, 15, 15, 2200)
ffbc_test_expect("15x15 reload exact", check15 != nil && check15.rank() == 2008)

# These rectangular certificates were found by scanning every S3-equivalent
# target ordering, then materialised back under the canonical requested shape.
check151616 = ffbc_load_exact(root + "matmul_15x16x16_rank2137_block47_gf2.txt", 15, 16, 16, 2300)
ffbc_test_expect("15x16x16 oriented certificate exact", check151616 != nil && check151616.rank() == 2137)
check161619 = ffbc_load_exact(root + "matmul_16x16x19_rank2716_block47_gf2.txt", 16, 16, 19, 2900)
ffbc_test_expect("16x16x19 oriented certificate exact", check161619 != nil && check161619.rank() == 2716)

# CLI default-selection regression: all ten 3--5 leaf shapes are present, so
# scan every unique S3 target ordering and every formula-minimising tie.  The
# support-asymmetric rank-47 outer is cheapest at source <16,15,17>, then code
# 4 publishes <15,16,17>.
full_leaf_paths = [root + "matmul_3x3_rank23_d139_gf2.txt",
                   root + "matmul_3x3x4_rank29_gf2.txt",
                   root + "matmul_3x3x5_rank36_gf2.txt",
                   root + "matmul_3x4x4_rank38_gf2.txt",
                   root + "matmul_3x4x5_rank47_gf2.txt",
                   root + "matmul_3x5x5_rank58_gf2.txt",
                   root + "matmul_4x4_rank47_d450_gf2.txt",
                   root + "matmul_4x4x5_rank60_catalog_gf2.txt",
                   root + "matmul_4x5x5_rank76_catalog_gf2.txt",
                   root + "matmul_5x5_rank93_catalog_alphaevolve_gf2.txt"]
full_leaf_ns = i64[10]
full_leaf_ms = i64[10]
full_leaf_ps = i64[10]
full_leaf_ns[0] = 3
full_leaf_ms[0] = 3
full_leaf_ps[0] = 3
full_leaf_ns[1] = 3
full_leaf_ms[1] = 3
full_leaf_ps[1] = 4
full_leaf_ns[2] = 3
full_leaf_ms[2] = 3
full_leaf_ps[2] = 5
full_leaf_ns[3] = 3
full_leaf_ms[3] = 4
full_leaf_ps[3] = 4
full_leaf_ns[4] = 3
full_leaf_ms[4] = 4
full_leaf_ps[4] = 5
full_leaf_ns[5] = 3
full_leaf_ms[5] = 5
full_leaf_ps[5] = 5
full_leaf_ns[6] = 4
full_leaf_ms[6] = 4
full_leaf_ps[6] = 4
full_leaf_ns[7] = 4
full_leaf_ms[7] = 4
full_leaf_ps[7] = 5
full_leaf_ns[8] = 4
full_leaf_ms[8] = 5
full_leaf_ps[8] = 5
full_leaf_ns[9] = 5
full_leaf_ms[9] = 5
full_leaf_ps[9] = 5
full_leaves = []
i = 0
while i < full_leaf_paths.size()
  full_leaf = ffbc_load_exact(full_leaf_paths[i], full_leaf_ns[i], full_leaf_ms[i], full_leaf_ps[i], 128)
  ffbc_test_expect("full-pool leaf " + i.to_s() + " exact", full_leaf != nil)
  full_leaves.push(full_leaf)
  i += 1
outer47 = full_leaves[6]
best151617 = ffbc_best_exact_oriented_balanced_recipe(outer47, 15, 16, 17, full_leaves)
ffbc_test_expect("S3 default recipe exists", best151617 != nil)
ffbc_test_expect("S3 default selects 16x15x17 rank 2329", best151617[3] == 2329 && best151617[8] == 2329 && best151617[4] == 16 && best151617[5] == 15 && best151617[6] == 17 && best151617[7] == 4 && best151617[0].join(",") == "4,4,4,4" && best151617[1].join(",") == "4,4,4,3" && best151617[2].join(",") == "4,5,4,4")
composed151617 = ffbc_compose_oriented_recipe(outer47, 15, 16, 17, full_leaves, best151617)
ffbc_test_expect("S3 default emits canonical rank 2329", composed151617 != nil && composed151617.n() == 15 && composed151617.m() == 16 && composed151617.p() == 17 && composed151617.rank() == 2329)

# The first formula-minimising 12x18x18 recipe has exact rank 2342.  A later
# allocation tie cancels two terms; the production selector must find it.
best121818 = ffbc_best_exact_oriented_balanced_recipe(outer47, 12, 18, 18, full_leaves)
ffbc_test_expect("exact tie scan improves 12x18x18 to 2340", best121818 != nil && best121818[3] == 2342 && best121818[8] == 2340 && best121818[4] == 12 && best121818[5] == 18 && best121818[6] == 18 && best121818[7] == 0 && best121818[0].join(",") == "3,3,3,3" && best121818[1].join(",") == "5,4,4,5" && best121818[2].join(",") == "4,5,4,5")
composed121818 = ffbc_compose_oriented_recipe(outer47, 12, 18, 18, full_leaves, best121818)
ffbc_test_expect("exact tie scan emits rank 2340", composed121818 != nil && composed121818.rank() == 2340)
# A distinct, S3-equivalent rank-60 445 scheme models an equal-rank mutable
# checkpoint after the stable catalog leaf.  Strict rank-only replacement must
# leave the complete emitted certificate byte-for-byte unchanged.
tie445 = ffbc_orient_scheme(full_leaves[7], 4)
ffbc_test_expect("equal-rank 445 tie leaf exact", tie445 != nil && tie445.rank() == 60)
tie_pool = []
i = 0
while i < full_leaves.size()
  tie_pool.push(full_leaves[i])
  i += 1
tie_pool.push(tie445)
tie_best151617 = ffbc_best_exact_oriented_balanced_recipe(outer47, 15, 16, 17, tie_pool)
tie_composed151617 = ffbc_compose_oriented_recipe(outer47, 15, 16, 17, tie_pool, tie_best151617)
same_certificate = 1 ## i64
if tie_composed151617 == nil || tie_composed151617.rank() != composed151617.rank()
  same_certificate = 0
if same_certificate == 1 && ffbc_test_arrays_equal(composed151617.us(), tie_composed151617.us()) != 1
  same_certificate = 0
if same_certificate == 1 && ffbc_test_arrays_equal(composed151617.vs(), tie_composed151617.vs()) != 1
  same_certificate = 0
if same_certificate == 1 && ffbc_test_arrays_equal(composed151617.ws(), tie_composed151617.ws()) != 1
  same_certificate = 0
ffbc_test_expect("equal-rank checkpoint preserves stable certificate", same_certificate == 1)
out151617 = "/tmp/flipfleet_block_15x16x17_rank2329.txt"
ffbc_test_expect("S3 default certificate write", ffbc_write(out151617, composed151617) == 2329)
check151617 = ffbc_load_exact(out151617, 15, 16, 17, 2400)
ffbc_test_expect("S3 default certificate reload exact", check151617 != nil && check151617.rank() == 2329)
saved151617 = ffbc_load_exact(root + "matmul_15x16x17_rank2329_block47_gf2.txt", 15, 16, 17, 2400)
ffbc_test_expect("saved 15x16x17 rank 2329 exact", saved151617 != nil && saved151617.rank() == 2329)

<< "flipfleet_block_composer_test: all checks passed"
