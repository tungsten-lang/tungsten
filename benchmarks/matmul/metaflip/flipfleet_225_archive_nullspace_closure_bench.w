# Bounded exhaustive archive-nullspace closure over the five retained
# <2,2,5> rank-18 doors.  Unlike ffran_crossover, this keeps every distinct
# exact proper child (including complementary hybrids), then allows those
# children to become parents in the next breadth-first pass.
#
# Usage:
#   flipfleet_225_archive_nullspace_closure_bench \
#     [passes=8] [max_archive=4096] [max_pairs=100000] \
#     [max_nullity=16] [relations_per_pair=65535] [provisional_output]

use flipfleet_rect_archive_nullspace

-> ff225ac_fail(message)
  << "FF225_ARCHIVE_CLOSURE_ERROR " + message
  exit(1)
  0

arguments = argv()
if arguments.size() > 6
  << "usage: flipfleet_225_archive_nullspace_closure_bench [passes] [max_archive] [max_pairs] [max_nullity] [relations_per_pair] [provisional_output]"
  exit(2)

passes = 8 ## i64
max_archive = 4096 ## i64
max_pairs = 100000 ## i64
max_nullity = 16 ## i64
relations = 65535 ## i64
output = "" ## String
if arguments.size() > 0
  passes = arguments[0].to_i()
if arguments.size() > 1
  max_archive = arguments[1].to_i()
if arguments.size() > 2
  max_pairs = arguments[2].to_i()
if arguments.size() > 3
  max_nullity = arguments[3].to_i()
if arguments.size() > 4
  relations = arguments[4].to_i()
if arguments.size() > 5
  output = arguments[5]
if passes < 1 || passes > 64 || max_archive < 6 || max_archive > 65536 || max_pairs < 1 || max_pairs > 10000000 || max_nullity < 2 || max_nullity > 20 || relations < 1
  << "FF225_ARCHIVE_CLOSURE_ERROR bounds"
  exit(2)

root = "benchmarks/matmul/metaflip/"
paths = []
labels = []
paths.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
labels.push("d84")
labels.push("d88")
labels.push("block-d92")
labels.push("splice-d84")
labels.push("gpu-tunnel-d84")

archive = []
i = 0 ## i64
while i < paths.size()
  door = ffbc_load_exact(paths[i], 2, 2, 5, 32)
  if door == nil || door.rank() != 18 || ffbc_verify_exact(door) != 1
    ff225ac_fail("load=" + labels[i])
  if ffran_archive_find(archive, door) >= 0
    ff225ac_fail("duplicate-door=" + labels[i])
  archive.push(door)
  i += 1

t0 = ccall("__w_clock_ms") ## i64
meta = i64[19]
made = ffran_archive_closure(archive, passes, max_pairs, max_nullity, relations, max_archive, meta) ## i64
elapsed = ccall("__w_clock_ms") - t0 ## i64
if made != archive.size() - paths.size() || meta[1] != archive.size() || meta[16] != 0
  ff225ac_fail("accounting")

rank17 = 0 ## i64
rank18 = 0 ## i64
minimum_rank = 0x7fffffff ## i64
best = nil
best_index = 0 - 1 ## i64
best_min_distance = 0 - 1 ## i64
best_sum_distance = 0 - 1 ## i64
best_density = 0x7fffffff ## i64
best_pairs = 0 ## i64
max_min_distance = 0 ## i64
min_min_distance = 0x7fffffff ## i64
i = paths.size()
while i < archive.size()
  child = archive[i]
  if child == nil || ffbc_verify_exact(child) != 1
    ff225ac_fail("child=" + i.to_s())
  if child.rank() < minimum_rank
    minimum_rank = child.rank()
  if child.rank() == 17
    rank17 += 1
  if child.rank() == 18
    rank18 += 1
  minimum = 0x7fffffff ## i64
  total = 0 ## i64
  j = 0 ## i64
  distance_text = "" ## String
  while j < paths.size()
    distance = fflc_term_set_distance(child, archive[j]) ## i64
    if distance < minimum
      minimum = distance
    total += distance
    if distance_text.size() > 0
      distance_text = distance_text + "/"
    distance_text = distance_text + distance.to_s()
    j += 1
  if minimum < min_min_distance
    min_min_distance = minimum
  if minimum > max_min_distance
    max_min_distance = minimum
  density = fflc_density(child) ## i64
  pair_count = fflc_equal_factor_pairs(child) ## i64
  better = 0 ## i64
  if best == nil || child.rank() < best.rank()
    better = 1
  if best != nil && child.rank() == best.rank() && minimum > best_min_distance
    better = 1
  if best != nil && child.rank() == best.rank() && minimum == best_min_distance && total > best_sum_distance
    better = 1
  if best != nil && child.rank() == best.rank() && minimum == best_min_distance && total == best_sum_distance && density < best_density
    better = 1
  if better == 1
    best = child
    best_index = i
    best_min_distance = minimum
    best_sum_distance = total
    best_density = density
    best_pairs = pair_count
  if archive.size() <= paths.size() + 64
    << "FF225_ARCHIVE_CLOSURE_CHILD index=" + i.to_s() + " rank=" + child.rank().to_s() + " density=" + density.to_s() + " pairs=" + pair_count.to_s() + " distances=" + distance_text
  i += 1

if made == 0
  minimum_rank = 18
  min_min_distance = 0

written = 0 ## i64
if output.size() > 0 && best != nil
  written = ffbc_write(output, best)
  replay = ffbc_load_exact(output, 2, 2, 5, 32)
  if written != best.rank() || replay == nil || replay.rank() != best.rank() || ffbc_verify_exact(replay) != 1 || fflc_term_set_distance(replay, best) != 0
    ff225ac_fail("write")

<< "FF225_ARCHIVE_CLOSURE_SUMMARY initial=" + meta[0].to_s() + " final=" + meta[1].to_s() + " added=" + meta[2].to_s() + " passes=" + meta[3].to_s() + " pairs=" + meta[4].to_s() + " productive_pairs=" + meta[5].to_s() + " relations=" + meta[6].to_s() + " proper=" + meta[7].to_s() + " exact=" + meta[8].to_s() + " duplicates=" + meta[9].to_s() + " minimum_rank=" + minimum_rank.to_s() + " rank17=" + rank17.to_s() + " rank18=" + rank18.to_s() + " min_door_distance=" + min_min_distance.to_s() + ".." + max_min_distance.to_s() + " nullity_max=" + meta[17].to_s() + " difference_max=" + meta[18].to_s() + " nullity_skips=" + meta[12].to_s() + " relation_caps=" + meta[13].to_s() + " pair_cap=" + meta[14].to_s() + " archive_cap=" + meta[15].to_s() + " failures=" + meta[16].to_s() + " elapsed_ms=" + elapsed.to_s()
if best != nil
  << "FF225_ARCHIVE_CLOSURE_BEST index=" + best_index.to_s() + " rank=" + best.rank().to_s() + " density=" + best_density.to_s() + " pairs=" + best_pairs.to_s() + " min_door_distance=" + best_min_distance.to_s() + " sum_door_distance=" + best_sum_distance.to_s() + " written=" + written.to_s() + " output=" + output
