use flipfleet_leaf_conjugation

arguments = argv()
if arguments.size() != 1
  << "usage: flipfleet_leaf_canonical_export OUTPUT"
  exit(2)
output = arguments[0]
root = "benchmarks/matmul/metaflip/"

paths = ["matmul_3x3_rank23_d139_gf2.txt",
         "matmul_3x3x4_rank29_gf2.txt",
         "matmul_3x4x4_rank38_gf2.txt",
         "matmul_4x4_rank47_d450_gf2.txt"]
ns = i64[4]
ms = i64[4]
ps = i64[4]
ns[0] = 3
ms[0] = 3
ps[0] = 3
ns[1] = 3
ms[1] = 3
ps[1] = 4
ns[2] = 3
ms[2] = 4
ps[2] = 4
ns[3] = 4
ms[3] = 4
ps[3] = 4

leaves = []
i = 0 ## i64
while i < 4
  leaf = ffbc_load_exact(root + paths[i], ns[i], ms[i], ps[i], 128)
  if leaf == nil
    << "invalid canonical leaf " + paths[i]
    exit(1)
  leaves.push(leaf)
  i += 1

outer = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
alloc_n = i64[2]
alloc_m = i64[2]
alloc_p = i64[2]
alloc_n[0] = 4
alloc_n[1] = 3
alloc_m[0] = 4
alloc_m[1] = 3
alloc_p[0] = 4
alloc_p[1] = 3
candidate = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
if candidate == nil || candidate.rank() != 248 || ffbc_verify_exact(candidate) != 1
  << "canonical composition failed exact rank-248 gate"
  exit(1)

archive0 = ffbc_load_exact(root + "matmul_7x7_rank248_d2952_sedoglavic_gf2.txt", 7, 7, 7, 320)
archive1 = ffbc_load_exact(root + "matmul_7x7_rank248_d2958_sedoglavic_gf2.txt", 7, 7, 7, 320)
archive2 = ffbc_load_exact(root + "matmul_7x7_rank248_d3015_connectivity_sedoglavic_gf2.txt", 7, 7, 7, 320)
if archive0 == nil || archive1 == nil || archive2 == nil
  << "canonical archive reference load failed"
  exit(1)
novelty = fflc_term_set_distance(archive0, candidate) ## i64
distance = fflc_term_set_distance(archive1, candidate) ## i64
if distance < novelty
  novelty = distance
distance = fflc_term_set_distance(archive2, candidate)
if distance < novelty
  novelty = distance
density = fflc_density(candidate) ## i64
pairs = fflc_equal_factor_pairs(candidate) ## i64
if density != 2967 || pairs != 43 || novelty != 336
  << "canonical descriptor mismatch density=" + density.to_s() + " pairs=" + pairs.to_s() + " novelty=" + novelty.to_s()
  exit(1)
written = ffbc_write(output, candidate) ## i64
reloaded = ffbc_load_exact(output, 7, 7, 7, 320)
if written != 248 || reloaded == nil || fflc_equal(candidate, reloaded) != 1
  << "canonical publish/reload failed"
  exit(1)
<< "LEAF_CANONICAL rank=248 density=" + density.to_s() + " pairs=" + pairs.to_s() + " archive-novelty=" + novelty.to_s() + " output=" + output
