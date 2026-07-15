use flipfleet_block_leaf_pool

-> ffbbft_same_allocation(a, b) (i64[] i64[]) i64
  if a.size() != b.size()
    return 0
  i = 0 ## i64
  while i < a.size()
    if a[i] != b[i]
      return 0
    i += 1
  1

-> ffbbft_compare(outer, leaves, n, m, p) (FFBCScheme Array i64 i64 i64) i64
  slow = ffbc_best_bounded_recipe(outer, n, m, p, 2, 8, leaves)
  fast = ffbc_best_bounded_recipe_fast(outer, n, m, p, 2, 8, leaves)
  if slow == nil || fast == nil || slow[3] != fast[3]
    return 0
  if ffbbft_same_allocation(slow[0], fast[0]) != 1
    return 0
  if ffbbft_same_allocation(slow[1], fast[1]) != 1
    return 0
  if ffbbft_same_allocation(slow[2], fast[2]) != 1
    return 0
  1

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
if outer == nil || leaves.size() != 84
  << "FAIL bounded-fast inputs"
  exit(1)

# These exercise singleton, low-count, and genuinely unbalanced allocation
# lists while keeping the reference scorer cheap enough for every release run.
if ffbbft_compare(outer, leaves, 8, 11, 20) != 1
  << "FAIL bounded-fast 8x11x20 mismatch"
  exit(1)
if ffbbft_compare(outer, leaves, 9, 12, 19) != 1
  << "FAIL bounded-fast 9x12x19 mismatch"
  exit(1)

# The previous exhaustive implementation needed minutes on this target.  The
# fast oriented path must retain its known formula minimum and exact recipe
# layout while providing the production small-cross scan's stress case.
recipe = ffbc_best_oriented_bounded_recipe(outer, 11, 20, 25, 2, 8, leaves)
if recipe == nil || recipe[3] != 3192
  << "FAIL bounded-fast 11x20x25 expected 3192"
  exit(1)

<< "PASS block bounded fast scorer"
