# Build a farthest-first archive from the deterministic <2,2,5> block-local
# GL bank, then exhaust the affine hull of the five production doors plus each
# pair of archive parents. This admits genuinely correlated three-parent
# dependencies rather than closing only pairwise chords.

use flipfleet_rect_multi_parent_nullspace
use flipfleet_225_block_gl_parent_lib

arguments = argv()
if arguments.size() < 2 || arguments.size() > 3
  << "usage: flipfleet_225_multi_parent_pair_batch BANK_COUNT ARCHIVE_SIZE OUTPUT"
  exit(2)
bank_count = arguments[0].to_i() ## i64
archive_size = arguments[1].to_i() ## i64
if bank_count < 2 || bank_count > 4096 || archive_size < 2 || archive_size > 64 || archive_size > bank_count
  << "FF225_MULTI_PAIR_ERROR bounds"
  exit(2)
output = "/tmp/flipfleet_225_multi_parent_pair_rank17.txt"
if arguments.size() == 3
  output = arguments[2]

root = "benchmarks/matmul/metaflip/"
base = []
paths = []
paths.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
i = 0 ## i64
while i < paths.size()
  door = ffbc_load_exact(paths[i], 2, 2, 5, 32)
  if door == nil || door.rank() != 18 || ffbc_verify_exact(door) != 1
    << "FF225_MULTI_PAIR_ERROR door=" + i.to_s()
    exit(1)
  base.push(door)
  i += 1

leaf3 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 16)
leaf2 = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
outer = ff225gl_outer()
if leaf3 == nil || leaf2 == nil || outer == nil
  << "FF225_MULTI_PAIR_ERROR seeds"
  exit(1)

t0 = ccall("__w_clock_ms") ## i64
bank = []
i = 0
while i < bank_count
  candidate = ff225gl_parent(leaf3, leaf2, outer, ff225gl_alloc_n(), ff225gl_alloc_m(), ff225gl_alloc_p(), i)
  if candidate == nil || candidate.rank() != 18 || ffbc_verify_exact(candidate) != 1
    << "FF225_MULTI_PAIR_ERROR bank=" + i.to_s()
    exit(1)
  bank.push(candidate)
  i += 1

# Greedy maximin term-set archive, scored first against every production door
# and then against all prior archive members.
chosen = []
chosen_indices = i64[archive_size]
used = i64[bank_count]
slot = 0 ## i64
while slot < archive_size
  best_index = 0 - 1 ## i64
  best_minimum = 0 - 1 ## i64
  best_density = 0x7fffffff ## i64
  i = 0
  while i < bank_count
    if used[i] == 0
      minimum = 0x7fffffff ## i64
      j = 0 ## i64
      while j < base.size()
        distance = fflc_term_set_distance(bank[i], base[j]) ## i64
        if distance < minimum
          minimum = distance
        j += 1
      j = 0
      while j < chosen.size()
        distance = fflc_term_set_distance(bank[i], chosen[j])
        if distance < minimum
          minimum = distance
        j += 1
      density = fflc_density(bank[i]) ## i64
      if minimum > best_minimum || (minimum == best_minimum && density < best_density)
        best_index = i
        best_minimum = minimum
        best_density = density
    i += 1
  if best_index < 0
    << "FF225_MULTI_PAIR_ERROR selection"
    exit(1)
  used[best_index] = 1
  chosen_indices[slot] = best_index
  chosen.push(bank[best_index])
  slot += 1

stats = i64[16]
stats[1] = 0x7fffffff
stats[3] = 0x7fffffff
nullity_hist = i64[25]
left = 0 ## i64
while left < chosen.size()
  right = left + 1 ## i64
  while right < chosen.size()
    parents = []
    i = 0
    while i < base.size()
      parents.push(base[i])
      i += 1
    parents.push(chosen[left])
    parents.push(chosen[right])
    meta = i64[13]
    child = ffrmp_search(parents, 2, 2, 5, 20, 18, meta)
    if child == nil || meta[10] != 0 || meta[12] != 1 || ffbc_verify_exact(child) != 1
      << "FF225_MULTI_PAIR_ERROR search=" + left.to_s() + "/" + right.to_s() + " nullity=" + meta[3].to_s()
      exit(1)
    stats[0] += 1
    if meta[1] < stats[1]
      stats[1] = meta[1]
    if meta[1] > stats[2]
      stats[2] = meta[1]
    if meta[3] < stats[3]
      stats[3] = meta[3]
    if meta[3] > stats[4]
      stats[4] = meta[3]
    if meta[3] < nullity_hist.size()
      nullity_hist[meta[3]] += 1
    stats[5] += meta[4]
    stats[6] += meta[5]
    stats[7] += meta[6]
    stats[8] += meta[7]
    if meta[8] < stats[9] || stats[9] == 0
      stats[9] = meta[8]
    if meta[8] < 18
      if ffbc_write(output, child) != meta[8]
        << "FF225_MULTI_PAIR_ERROR write"
        exit(1)
      replay = ffbc_load_exact(output, 2, 2, 5, 32)
      if replay == nil || replay.rank() != meta[8] || ffbc_verify_exact(replay) != 1
        << "FF225_MULTI_PAIR_ERROR replay"
        exit(1)
      << "FF225_MULTI_PAIR_HIT left=" + chosen_indices[left].to_s() + " right=" + chosen_indices[right].to_s() + " rank=" + meta[8].to_s() + " density=" + meta[9].to_s() + " output=" + output
      exit(0)
    right += 1
  left += 1
stats[10] = ccall("__w_clock_ms") - t0

hist = ""
i = 0
while i < nullity_hist.size()
  if nullity_hist[i] > 0
    if hist.size() > 0
      hist = hist + ","
    hist = hist + i.to_s() + ":" + nullity_hist[i].to_s()
  i += 1
indices = ""
i = 0
while i < chosen.size()
  if indices.size() > 0
    indices = indices + ","
  indices = indices + chosen_indices[i].to_s()
  i += 1
<< "FF225_MULTI_PAIR_SUMMARY bank=" + bank_count.to_s() + " archive=" + archive_size.to_s() + " selected=" + indices + " pairs=" + stats[0].to_s() + " union_min=" + stats[1].to_s() + " union_max=" + stats[2].to_s() + " nullity_min=" + stats[3].to_s() + " nullity_max=" + stats[4].to_s() + " nullity_hist=" + hist + " affine_solutions=" + stats[5].to_s() + " gated_le18=" + stats[6].to_s() + " rank_below18=" + stats[7].to_s() + " rank18=" + stats[8].to_s() + " best_rank=" + stats[9].to_s() + " gate_failures=0 elapsed_ms=" + stats[10].to_s()
