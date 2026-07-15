# Exhaust the joint affine hull of the two retained <2,2,6> doors plus each
# deterministic three-Strassen block-local parent. This detects correlated
# relations spanning all three exact schemes, not only pairwise leaf swaps.

use flipfleet_rect_multi_parent_nullspace
use flipfleet_226_block_gl_parent_lib

arguments = argv()
if arguments.size() < 1 || arguments.size() > 2
  << "usage: flipfleet_226_multi_parent_batch COUNT OUTPUT"
  exit(2)
count = arguments[0].to_i() ## i64
if count < 1 || count > 65536
  << "FF226_MULTI_ERROR count"
  exit(2)
output = "/tmp/flipfleet_226_multi_parent_rank20.txt"
if arguments.size() == 2
  output = arguments[1]

root = "benchmarks/matmul/metaflip/"
baseline = ffbc_load_exact(root + "matmul_2x2x6_rank21_strassen_blocks_gf2.txt", 2, 2, 6, 32)
door = ffbc_load_exact(root + "matmul_2x2x6_rank21_d108_block_local_gl_gf2.txt", 2, 2, 6, 32)
leaf = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
outer = ff226gl_outer()
if baseline == nil || door == nil || leaf == nil || outer == nil || ffbc_verify_exact(baseline) != 1 || ffbc_verify_exact(door) != 1
  << "FF226_MULTI_ERROR seeds"
  exit(1)

base = []
base.push(baseline)
base.push(door)
stats = i64[16]
stats[1] = 0x7fffffff
stats[3] = 0x7fffffff
nullity_hist = i64[25]
t0 = ccall("__w_clock_ms") ## i64
index = 0 ## i64
while index < count
  generated = ff226gl_parent(leaf, outer, ff226gl_alloc_n(), ff226gl_alloc_m(), ff226gl_alloc_p(), index)
  if generated == nil || generated.rank() != 21 || ffbc_verify_exact(generated) != 1
    << "FF226_MULTI_ERROR parent=" + index.to_s()
    exit(1)
  parents = []
  parents.push(base[0])
  parents.push(base[1])
  parents.push(generated)
  meta = i64[13]
  child = ffrmp_search(parents, 2, 2, 6, 20, 21, meta)
  if child == nil || meta[10] != 0 || meta[12] != 1 || ffbc_verify_exact(child) != 1
    << "FF226_MULTI_ERROR search=" + index.to_s() + " nullity=" + meta[3].to_s()
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
  if meta[8] < 21
    if ffbc_write(output, child) != meta[8]
      << "FF226_MULTI_ERROR write"
      exit(1)
    replay = ffbc_load_exact(output, 2, 2, 6, 32)
    if replay == nil || replay.rank() != meta[8] || ffbc_verify_exact(replay) != 1
      << "FF226_MULTI_ERROR replay"
      exit(1)
    << "FF226_MULTI_HIT parent=" + index.to_s() + " rank=" + meta[8].to_s() + " density=" + meta[9].to_s() + " output=" + output
    exit(0)
  index += 1
stats[10] = ccall("__w_clock_ms") - t0

hist = ""
i = 0 ## i64
while i < nullity_hist.size()
  if nullity_hist[i] > 0
    if hist.size() > 0
      hist = hist + ","
    hist = hist + i.to_s() + ":" + nullity_hist[i].to_s()
  i += 1
<< "FF226_MULTI_SUMMARY parents=" + stats[0].to_s() + " union_min=" + stats[1].to_s() + " union_max=" + stats[2].to_s() + " nullity_min=" + stats[3].to_s() + " nullity_max=" + stats[4].to_s() + " nullity_hist=" + hist + " affine_solutions=" + stats[5].to_s() + " gated_le21=" + stats[6].to_s() + " rank_below21=" + stats[7].to_s() + " rank21=" + stats[8].to_s() + " best_rank=" + stats[9].to_s() + " gate_failures=0 elapsed_ms=" + stats[10].to_s()
