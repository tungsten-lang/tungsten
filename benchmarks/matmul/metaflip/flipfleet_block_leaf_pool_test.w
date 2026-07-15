use flipfleet_block_leaf_pool

-> ffblpt_expect(label, condition)
  if condition != 0
    return 1
  << "BLOCK_LEAF_POOL_FAIL " + label
  exit(1)
  0

root = "benchmarks/matmul/metaflip/"
leaves = ffbcp_stable_2_to_8(root)
ffblpt_expect("complete count", leaves.size() == 84)

# Lexicographic 2xa xb order used by `ffbcp_stable_2_to_8`.
expected = i64[28]
values = [7,11,14,18,21,25,28,15,20,25,30,35,40,26,33,39,45,51,40,47,55,63,56,66,75,76,88,100]
i = 0 ## i64
while i < values.size()
  expected[i] = values[i]
  i += 1

index = 0 ## i64
a = 2 ## i64
while a <= 8
  b = a ## i64
  while b <= 8
    leaf = leaves[index]
    ffblpt_expect("two-wide dimensions", leaf != nil && leaf.n() == 2 && leaf.m() == a && leaf.p() == b)
    ffblpt_expect("two-wide rank", leaf.rank() == expected[index])
    ffblpt_expect("two-wide exact", ffbc_verify_exact(leaf) == 1)
    index += 1
    b += 1
  a += 1
ffblpt_expect("two-wide shape count", index == 28)

# The wrapper must append the historical pool byte-for-byte in the same order;
# otherwise old 12--32 tie choices could drift even when ranks do not.
stable = ffbcp_stable_3_to_8(root)
ffblpt_expect("historical count", stable.size() == 56)
i = 0
while i < stable.size()
  left = leaves[28 + i]
  right = stable[i]
  ffblpt_expect("historical dimensions", left.n() == right.n() && left.m() == right.m() && left.p() == right.p())
  ffblpt_expect("historical rank", left.rank() == right.rank())
  i += 1

<< "flipfleet_block_leaf_pool_test: exact two-wide=28 historical=56 total=84"
