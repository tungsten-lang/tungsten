# Independent block-local GL doors for the certified <2,2,5> rank-17 gap.
#
# The exact rank-18 upper construction is the direct 3+2 column split of
# rank-11 <2,2,3> and rank-7 <2,2,2> leaves.  Applying unrelated tensor
# isotropies to the two leaves before embedding is still exact, but it need
# not be one whole-scheme GL action on the combined tensor.  This enumerator
# keeps density-, novelty-, and flip-connectivity-first representatives for
# subsequent matched FlipFleet continuations.
#
# Usage:
#   flipfleet_225_block_gl_bank COUNT OUTPUT_PREFIX

use flipfleet_leaf_conjugation

-> ff225bg_write_checked(path, scheme) (String FFBCScheme) i64
  if scheme == nil || scheme.rank() != 18 || ffbc_verify_exact(scheme) != 1
    return 0
  if ffbc_write(path, scheme) != 18
    return 0
  replay = ffbc_load_exact(path, 2, 2, 5, 32)
  if replay == nil || replay.rank() != 18 || ffbc_verify_exact(replay) != 1
    return 0
  if fflc_term_set_distance(replay, scheme) != 0
    return 0
  1

arguments = argv()
if arguments.size() != 2
  << "usage: flipfleet_225_block_gl_bank COUNT OUTPUT_PREFIX"
  exit(2)
count = arguments[0].to_i() ## i64
prefix = arguments[1]
if count < 1 || count > 16384
  << "FF225_BLOCK_GL_ERROR code=count"
  exit(2)

root = "benchmarks/matmul/metaflip/"
leaf3 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 16)
leaf2 = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
d84 = ffbc_load_exact(root + "matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, 32)
d88 = ffbc_load_exact(root + "matmul_2x2x5_rank18_d88_gf2.txt", 2, 2, 5, 32)
if leaf3 == nil || leaf2 == nil || d84 == nil || d88 == nil
  << "FF225_BLOCK_GL_ERROR code=seed"
  exit(1)

# The rank-2 schoolbook <1,1,2> outer chooses one independently transformed
# leaf for each output-column block.
outer = FFBCScheme.new(1, 1, 2, 2)
outer.us()[0] = 1
outer.vs()[0] = 1
outer.ws()[0] = 1
outer.us()[1] = 1
outer.vs()[1] = 2
outer.ws()[1] = 2
outer.set_rank(2)
if ffbc_verify_exact(outer) != 1
  << "FF225_BLOCK_GL_ERROR code=outer"
  exit(1)

alloc_n = i64[1]
alloc_m = i64[1]
alloc_p = i64[2]
alloc_n[0] = 2
alloc_m[0] = 2
alloc_p[0] = 3
alloc_p[1] = 2

density_best = nil
novelty_best = nil
pairs_best = nil
density_score = 0x7fffffff ## i64
density_novelty = 0 - 1 ## i64
novelty_score = 0 - 1 ## i64
novelty_density = 0x7fffffff ## i64
pairs_score = 0 - 1 ## i64
pairs_novelty = 0 - 1 ## i64
pairs_density = 0x7fffffff ## i64
exact = 0 ## i64
changed = 0 ## i64
max_distance84 = 0 ## i64
max_distance88 = 0 ## i64

i = 0 ## i64
while i < count
  moves3 = 2 + (i % 11) ## i64
  moves2 = 2 + ((i / 11) % 11) ## i64
  image3 = fflc_sparse_leaf_image(leaf3, 2250001 + i * 104729, moves3)
  image2 = fflc_sparse_leaf_image(leaf2, 2257001 + i * 130363, moves2)
  if image3 != nil && image2 != nil
    leaves = []
    leaves.push(image3)
    leaves.push(image2)
    candidate = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
    if candidate != nil && candidate.rank() == 18 && ffbc_verify_exact(candidate) == 1
      exact += 1
      distance84 = fflc_term_set_distance(candidate, d84) ## i64
      distance88 = fflc_term_set_distance(candidate, d88) ## i64
      if distance84 > max_distance84
        max_distance84 = distance84
      if distance88 > max_distance88
        max_distance88 = distance88
      if distance84 > 0 && distance88 > 0
        changed += 1
      novelty = distance84 ## i64
      if distance88 < novelty
        novelty = distance88
      density = fflc_density(candidate) ## i64
      pairs = fflc_equal_factor_pairs(candidate) ## i64

      if density < density_score || (density == density_score && novelty > density_novelty)
        density_best = fflc_clone(candidate)
        density_score = density
        density_novelty = novelty
      if novelty > novelty_score || (novelty == novelty_score && density < novelty_density)
        novelty_best = fflc_clone(candidate)
        novelty_score = novelty
        novelty_density = density
      if pairs > pairs_score || (pairs == pairs_score && novelty > pairs_novelty) || (pairs == pairs_score && novelty == pairs_novelty && density < pairs_density)
        pairs_best = fflc_clone(candidate)
        pairs_score = pairs
        pairs_novelty = novelty
        pairs_density = density
  i += 1

if density_best == nil || novelty_best == nil || pairs_best == nil
  << "FF225_BLOCK_GL_ERROR code=no-candidate exact=" + exact.to_s()
  exit(1)

density_path = prefix + "_density.txt"
novelty_path = prefix + "_novelty.txt"
pairs_path = prefix + "_pairs.txt"
if ff225bg_write_checked(density_path, density_best) != 1 || ff225bg_write_checked(novelty_path, novelty_best) != 1 || ff225bg_write_checked(pairs_path, pairs_best) != 1
  << "FF225_BLOCK_GL_ERROR code=write"
  exit(1)

<< "FF225_BLOCK_GL_RESULT requested=" + count.to_s() + " exact=" + exact.to_s() + " changed=" + changed.to_s() + " max_distance_d84=" + max_distance84.to_s() + " max_distance_d88=" + max_distance88.to_s() + " density_best=" + density_score.to_s() + "/novelty" + density_novelty.to_s() + " novelty_best=" + novelty_score.to_s() + "/density" + novelty_density.to_s() + " pairs_best=" + pairs_score.to_s() + "/novelty" + pairs_novelty.to_s() + "/density" + pairs_density.to_s() + " exact_gate=1 outputs=" + density_path + "," + novelty_path + "," + pairs_path
