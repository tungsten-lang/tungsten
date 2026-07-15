# Exhaust joint affine hulls of the two retained <2,2,6> doors plus every
# k-subset of the deterministic 32-parent separated block archive.

use flipfleet_rect_multi_parent_nullspace
use flipfleet_226_block_gl_parent_lib

arguments = argv()
if arguments.size() < 2 || arguments.size() > 3
  << "usage: flipfleet_226_multi_parent_k_batch ORDER ARCHIVE_SIZE OUTPUT"
  exit(2)
order = arguments[0].to_i() ## i64
archive_size = arguments[1].to_i() ## i64
if order < 2 || order > 6 || archive_size < order || archive_size > 32
  << "FF226_MULTI_K_ERROR bounds"
  exit(2)
output = "/tmp/flipfleet_226_multi_parent_k_rank20.txt"
if arguments.size() == 3
  output = arguments[2]

indices = i64[32]
indices[0] = 0
indices[1] = 1
indices[2] = 2
indices[3] = 4
indices[4] = 5
indices[5] = 6
indices[6] = 7
indices[7] = 8
indices[8] = 9
indices[9] = 10
indices[10] = 11
indices[11] = 18
indices[12] = 19
indices[13] = 20
indices[14] = 21
indices[15] = 22
indices[16] = 25
indices[17] = 26
indices[18] = 28
indices[19] = 29
indices[20] = 31
indices[21] = 37
indices[22] = 40
indices[23] = 41
indices[24] = 43
indices[25] = 47
indices[26] = 51
indices[27] = 62
indices[28] = 65
indices[29] = 68
indices[30] = 93
indices[31] = 106

root = "benchmarks/matmul/metaflip/"
baseline = ffbc_load_exact(root + "matmul_2x2x6_rank21_strassen_blocks_gf2.txt", 2, 2, 6, 32)
door = ffbc_load_exact(root + "matmul_2x2x6_rank21_d108_block_local_gl_gf2.txt", 2, 2, 6, 32)
leaf = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
outer = ff226gl_outer()
if baseline == nil || door == nil || leaf == nil || outer == nil || ffbc_verify_exact(baseline) != 1 || ffbc_verify_exact(door) != 1
  << "FF226_MULTI_K_ERROR seeds"
  exit(1)
base = []
base.push(baseline)
base.push(door)
chosen = []
i = 0 ## i64
while i < archive_size
  parent = ff226gl_parent(leaf, outer, ff226gl_alloc_n(), ff226gl_alloc_m(), ff226gl_alloc_p(), indices[i])
  if parent == nil || parent.rank() != 21 || ffbc_verify_exact(parent) != 1
    << "FF226_MULTI_K_ERROR parent=" + indices[i].to_s()
    exit(1)
  chosen.push(parent)
  i += 1

choice = i64[order]
i = 0
while i < order
  choice[i] = i
  i += 1
stats = i64[16]
stats[1] = 0x7fffffff
stats[3] = 0x7fffffff
nullity_hist = i64[64]
t0 = ccall("__w_clock_ms") ## i64
running = 1 ## i64
while running == 1
  parents = []
  parents.push(base[0])
  parents.push(base[1])
  i = 0
  while i < order
    parents.push(chosen[choice[i]])
    i += 1
  meta = i64[13]
  child = ffrmp_search(parents, 2, 2, 6, 20, 21, meta)
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
  if child == nil
    if meta[3] > 20 && meta[10] == 0
      stats[11] += 1
    else
      << "FF226_MULTI_K_ERROR search nullity=" + meta[3].to_s()
      exit(1)
  if child != nil
    if meta[10] != 0 || meta[12] != 1 || ffbc_verify_exact(child) != 1
      << "FF226_MULTI_K_ERROR gate"
      exit(1)
    stats[5] += meta[4]
    stats[6] += meta[5]
    stats[7] += meta[6]
    stats[8] += meta[7]
    if meta[8] < stats[9] || stats[9] == 0
      stats[9] = meta[8]
    if meta[8] < 21
      if ffbc_write(output, child) != meta[8]
        << "FF226_MULTI_K_ERROR write"
        exit(1)
      replay = ffbc_load_exact(output, 2, 2, 6, 32)
      if replay == nil || replay.rank() != meta[8] || ffbc_verify_exact(replay) != 1
        << "FF226_MULTI_K_ERROR replay"
        exit(1)
      << "FF226_MULTI_K_HIT order=" + order.to_s() + " rank=" + meta[8].to_s() + " density=" + meta[9].to_s() + " output=" + output
      exit(0)

  position = order - 1 ## i64
  while position >= 0 && choice[position] == archive_size - order + position
    position -= 1
  if position < 0
    running = 0
  if position >= 0
    choice[position] += 1
    i = position + 1
    while i < order
      choice[i] = choice[i - 1] + 1
      i += 1
stats[10] = ccall("__w_clock_ms") - t0

hist = ""
i = 0
while i < nullity_hist.size()
  if nullity_hist[i] > 0
    if hist.size() > 0
      hist = hist + ","
    hist = hist + i.to_s() + ":" + nullity_hist[i].to_s()
  i += 1
<< "FF226_MULTI_K_SUMMARY order=" + order.to_s() + " archive=" + archive_size.to_s() + " combinations=" + stats[0].to_s() + " complete=" + (stats[0] - stats[11]).to_s() + " nullity_skips=" + stats[11].to_s() + " union_min=" + stats[1].to_s() + " union_max=" + stats[2].to_s() + " nullity_min=" + stats[3].to_s() + " nullity_max=" + stats[4].to_s() + " nullity_hist=" + hist + " affine_solutions=" + stats[5].to_s() + " gated_le21=" + stats[6].to_s() + " rank_below21=" + stats[7].to_s() + " rank21=" + stats[8].to_s() + " best_rank=" + stats[9].to_s() + " gate_failures=0 elapsed_ms=" + stats[10].to_s()
