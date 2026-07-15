# Independent block-local GL doors for the <2,2,6> rank-20 campaign.
#
# Usage:
#   flipfleet_226_block_gl_bank COUNT OUTPUT_PREFIX
#
# The three outputs select density-first, distance-first, and ordinary-flip
# connectivity-first rank-21 representatives.  Every generated parent and
# every written/reloaded output passes the complete FFBC exactness gate.

use flipfleet_226_block_gl_parent_lib

-> ff226bg_write_checked(path, scheme) (String FFBCScheme) i64
  if scheme == nil || scheme.rank() != 21 || ffbc_verify_exact(scheme) != 1
    return 0
  if ffbc_write(path, scheme) != 21
    return 0
  replay = ffbc_load_exact(path, 2, 2, 6, 32)
  if replay == nil || replay.rank() != 21 || ffbc_verify_exact(replay) != 1
    return 0
  if fflc_term_set_distance(replay, scheme) != 0
    return 0
  1

arguments = argv()
if arguments.size() != 2
  << "usage: flipfleet_226_block_gl_bank COUNT OUTPUT_PREFIX"
  exit(2)
count = arguments[0].to_i() ## i64
prefix = arguments[1]
if count < 1 || count > 65536
  << "FF226_BLOCK_GL_ERROR code=count"
  exit(2)

root = "benchmarks/matmul/metaflip/"
leaf = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
baseline = ffbc_load_exact(root + "matmul_2x2x6_rank21_strassen_blocks_gf2.txt", 2, 2, 6, 32)
outer = ff226gl_outer()
if leaf == nil || baseline == nil || outer == nil || ffbc_verify_exact(baseline) != 1
  << "FF226_BLOCK_GL_ERROR code=seed"
  exit(1)
alloc_n = ff226gl_alloc_n()
alloc_m = ff226gl_alloc_m()
alloc_p = ff226gl_alloc_p()

density_best = nil
novelty_best = nil
pairs_best = nil
density_score = 0x7fffffff ## i64
density_distance = 0 - 1 ## i64
novelty_score = 0 - 1 ## i64
novelty_density = 0x7fffffff ## i64
pairs_score = 0 - 1 ## i64
pairs_distance = 0 - 1 ## i64
pairs_density = 0x7fffffff ## i64
density_index = 0 - 1 ## i64
novelty_index = 0 - 1 ## i64
pairs_index = 0 - 1 ## i64
exact = 0 ## i64
changed = 0 ## i64
distance_sum = 0 ## i64
density_min = 0x7fffffff ## i64
density_max = 0 ## i64

i = 0 ## i64
while i < count
  candidate = ff226gl_parent(leaf, outer, alloc_n, alloc_m, alloc_p, i)
  if candidate == nil
    << "FF226_BLOCK_GL_ERROR code=parent index=" + i.to_s()
    exit(1)
  exact += 1
  distance = fflc_term_set_distance(candidate, baseline) ## i64
  density = fflc_density(candidate) ## i64
  pairs = fflc_equal_factor_pairs(candidate) ## i64
  distance_sum += distance
  if distance > 0
    changed += 1
  if density < density_min
    density_min = density
  if density > density_max
    density_max = density

  if density < density_score || (density == density_score && distance > density_distance)
    density_best = fflc_clone(candidate)
    density_score = density
    density_distance = distance
    density_index = i
  if distance > novelty_score || (distance == novelty_score && density < novelty_density)
    novelty_best = fflc_clone(candidate)
    novelty_score = distance
    novelty_density = density
    novelty_index = i
  if pairs > pairs_score || (pairs == pairs_score && distance > pairs_distance) || (pairs == pairs_score && distance == pairs_distance && density < pairs_density)
    pairs_best = fflc_clone(candidate)
    pairs_score = pairs
    pairs_distance = distance
    pairs_density = density
    pairs_index = i
  i += 1

if density_best == nil || novelty_best == nil || pairs_best == nil
  << "FF226_BLOCK_GL_ERROR code=no-candidate"
  exit(1)

density_path = prefix + "_density.txt"
novelty_path = prefix + "_novelty.txt"
pairs_path = prefix + "_pairs.txt"
if ff226bg_write_checked(density_path, density_best) != 1 || ff226bg_write_checked(novelty_path, novelty_best) != 1 || ff226bg_write_checked(pairs_path, pairs_best) != 1
  << "FF226_BLOCK_GL_ERROR code=write"
  exit(1)

<< "FF226_BLOCK_GL_RESULT requested=" + count.to_s() + " exact=" + exact.to_s() + " changed=" + changed.to_s() + " distance_avg_milli=" + (distance_sum * 1000 / exact).to_s() + " density_range=" + density_min.to_s() + ".." + density_max.to_s() + " density_best=" + density_score.to_s() + "/distance" + density_distance.to_s() + "/index" + density_index.to_s() + " novelty_best=" + novelty_score.to_s() + "/density" + novelty_density.to_s() + "/index" + novelty_index.to_s() + " pairs_best=" + pairs_score.to_s() + "/distance" + pairs_distance.to_s() + "/density" + pairs_density.to_s() + "/index" + pairs_index.to_s() + " exact_gate=1 outputs=" + density_path + "," + novelty_path + "," + pairs_path
