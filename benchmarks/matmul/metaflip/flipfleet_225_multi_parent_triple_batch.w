# Exhaust affine hulls of the five production <2,2,5> doors plus every triple
# from the deterministic 32-member maximin block-parent archive selected by
# flipfleet_225_multi_parent_pair_batch.w.

use flipfleet_rect_multi_parent_nullspace
use flipfleet_225_block_gl_parent_lib

arguments = argv()
if arguments.size() < 1 || arguments.size() > 2
  << "usage: flipfleet_225_multi_parent_triple_batch ARCHIVE_SIZE OUTPUT"
  exit(2)
archive_size = arguments[0].to_i() ## i64
if archive_size < 3 || archive_size > 32
  << "FF225_MULTI_TRIPLE_ERROR archive"
  exit(2)
output = "/tmp/flipfleet_225_multi_parent_triple_rank17.txt"
if arguments.size() == 2
  output = arguments[1]

selected_indices = i64[32]
selected_indices[0] = 2577
selected_indices[1] = 1182
selected_indices[2] = 281
selected_indices[3] = 2650
selected_indices[4] = 293
selected_indices[5] = 1097
selected_indices[6] = 3822
selected_indices[7] = 151
selected_indices[8] = 692
selected_indices[9] = 89
selected_indices[10] = 1458
selected_indices[11] = 1181
selected_indices[12] = 1213
selected_indices[13] = 3363
selected_indices[14] = 636
selected_indices[15] = 1879
selected_indices[16] = 3169
selected_indices[17] = 30
selected_indices[18] = 456
selected_indices[19] = 1359
selected_indices[20] = 1530
selected_indices[21] = 2859
selected_indices[22] = 2958
selected_indices[23] = 2830
selected_indices[24] = 667
selected_indices[25] = 1082
selected_indices[26] = 2908
selected_indices[27] = 3000
selected_indices[28] = 1449
selected_indices[29] = 3587
selected_indices[30] = 3572
selected_indices[31] = 955

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
    << "FF225_MULTI_TRIPLE_ERROR door=" + i.to_s()
    exit(1)
  base.push(door)
  i += 1

leaf3 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 16)
leaf2 = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
outer = ff225gl_outer()
if leaf3 == nil || leaf2 == nil || outer == nil
  << "FF225_MULTI_TRIPLE_ERROR seeds"
  exit(1)

chosen = []
i = 0
while i < archive_size
  parent = ff225gl_parent(leaf3, leaf2, outer, ff225gl_alloc_n(), ff225gl_alloc_m(), ff225gl_alloc_p(), selected_indices[i])
  if parent == nil || parent.rank() != 18 || ffbc_verify_exact(parent) != 1
    << "FF225_MULTI_TRIPLE_ERROR parent=" + selected_indices[i].to_s()
    exit(1)
  chosen.push(parent)
  i += 1

stats = i64[16]
stats[1] = 0x7fffffff
stats[3] = 0x7fffffff
nullity_hist = i64[25]
t0 = ccall("__w_clock_ms") ## i64
a = 0 ## i64
while a < chosen.size()
  b = a + 1 ## i64
  while b < chosen.size()
    c = b + 1 ## i64
    while c < chosen.size()
      parents = []
      i = 0
      while i < base.size()
        parents.push(base[i])
        i += 1
      parents.push(chosen[a])
      parents.push(chosen[b])
      parents.push(chosen[c])
      meta = i64[13]
      child = ffrmp_search(parents, 2, 2, 5, 20, 18, meta)
      if child == nil || meta[10] != 0 || meta[12] != 1 || ffbc_verify_exact(child) != 1
        << "FF225_MULTI_TRIPLE_ERROR search=" + a.to_s() + "/" + b.to_s() + "/" + c.to_s() + " nullity=" + meta[3].to_s()
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
          << "FF225_MULTI_TRIPLE_ERROR write"
          exit(1)
        replay = ffbc_load_exact(output, 2, 2, 5, 32)
        if replay == nil || replay.rank() != meta[8] || ffbc_verify_exact(replay) != 1
          << "FF225_MULTI_TRIPLE_ERROR replay"
          exit(1)
        << "FF225_MULTI_TRIPLE_HIT parents=" + selected_indices[a].to_s() + "/" + selected_indices[b].to_s() + "/" + selected_indices[c].to_s() + " rank=" + meta[8].to_s() + " density=" + meta[9].to_s() + " output=" + output
        exit(0)
      c += 1
    b += 1
  a += 1
stats[10] = ccall("__w_clock_ms") - t0

hist = ""
i = 0
while i < nullity_hist.size()
  if nullity_hist[i] > 0
    if hist.size() > 0
      hist = hist + ","
    hist = hist + i.to_s() + ":" + nullity_hist[i].to_s()
  i += 1
<< "FF225_MULTI_TRIPLE_SUMMARY archive=" + archive_size.to_s() + " triples=" + stats[0].to_s() + " union_min=" + stats[1].to_s() + " union_max=" + stats[2].to_s() + " nullity_min=" + stats[3].to_s() + " nullity_max=" + stats[4].to_s() + " nullity_hist=" + hist + " affine_solutions=" + stats[5].to_s() + " gated_le18=" + stats[6].to_s() + " rank_below18=" + stats[7].to_s() + " rank18=" + stats[8].to_s() + " best_rank=" + stats[9].to_s() + " gate_failures=0 elapsed_ms=" + stats[10].to_s()
