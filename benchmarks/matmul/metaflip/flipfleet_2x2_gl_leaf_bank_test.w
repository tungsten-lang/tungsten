# Smoke-load the curated 2x2 GL leaf bank and prove each member is exact
# rank 7.  Also compose a trivial 2-block 4x4 using each leaf in isolation so
# alternate presentations stay composition-ready.
use flipfleet_block_composer
use flipfleet_leaf_conjugation

-> ff22t_expect(label, condition)
  if condition != 0
    return 1
  << "FF22_GL_BANK_TEST_FAIL " + label
  exit(1)
  0

-> ff22t_paths()
  paths = []
  paths.push("matmul_2x2_rank7_strassen_gf2.txt")
  paths.push("matmul_2x2_rank7_d36_gl120_gf2.txt")
  paths.push("matmul_2x2_rank7_d36_gl190_gf2.txt")
  paths.push("matmul_2x2_rank7_d40_gl01_gf2.txt")
  paths.push("matmul_2x2_rank7_d40_gl108_gf2.txt")
  paths.push("matmul_2x2_rank7_d40_gl214_gf2.txt")
  paths.push("matmul_2x2_rank7_d42_gl08_gf2.txt")
  paths.push("matmul_2x2_rank7_d42_gl110_gf2.txt")
  paths.push("matmul_2x2_rank7_d42_gl207_gf2.txt")
  paths

root = "benchmarks/matmul/metaflip/"
paths = ff22t_paths()
leaves = []
i = 0 ## i64
while i < paths.size()
  leaf = ffbc_load_exact(root + paths[i], 2, 2, 2, 16)
  ff22t_expect("load " + paths[i], leaf != nil && leaf.rank() == 7 && ffbc_verify_exact(leaf) == 1)
  leaves.push(leaf)
  i += 1

seed = leaves[0]
# At least one curated door differs from the seed in term-set distance.
distinct = 0 ## i64
i = 1
while i < leaves.size()
  if fflc_term_set_distance(seed, leaves[i]) > 0
    distinct += 1
  i += 1
ff22t_expect("at least 6 distinct GL doors", distinct >= 6)

# Densities cover the three observed orbit classes.
has36 = 0 ## i64
has40 = 0 ## i64
has42 = 0 ## i64
i = 0
while i < leaves.size()
  d = fflc_density(leaves[i]) ## i64
  if d == 36
    has36 = 1
  if d == 40
    has40 = 1
  if d == 42
    has42 = 1
  i += 1
ff22t_expect("density class 36", has36 == 1)
ff22t_expect("density class 40", has40 == 1)
ff22t_expect("density class 42", has42 == 1)

# Composition smoke: each leaf alone must build exact <4,4,4> via two 2+2 splits.
# Outer is Strassen on 2x2 blocks of size 2.
outer = seed
alloc = [2, 2]
i = 0
while i < leaves.size()
  only = []
  only.push(leaves[i])
  composed = ffbc_compose(outer, alloc, alloc, alloc, only)
  ff22t_expect("compose 4x4 with " + paths[i], composed != nil && composed.rank() == 49 && ffbc_verify_exact(composed) == 1)
  i += 1

<< "flipfleet_2x2_gl_leaf_bank_test: all checks passed members=" + leaves.size().to_s() + " distinct=" + distinct.to_s()
