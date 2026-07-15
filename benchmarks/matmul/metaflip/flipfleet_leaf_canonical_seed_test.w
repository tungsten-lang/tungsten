use flipfleet_leaf_conjugation

-> fflcst_expect(name, condition)
  if condition
    << "PASS " + name
    return 0
  << "FAIL " + name
  exit(1)

root = "benchmarks/matmul/metaflip/"
seed_path = root + "matmul_7x7_rank248_d2967_leaf_canonical_gf2.txt"
saved = ffbc_load_exact(seed_path, 7, 7, 7, 320)
fflcst_expect("checked-in canonical seed exact rank 248", saved != nil && saved.rank() == 248 && ffbc_verify_exact(saved) == 1)
fflcst_expect("checked-in canonical density", fflc_density(saved) == 2967)
fflcst_expect("checked-in canonical connectivity", fflc_equal_factor_pairs(saved) == 43)

archive0 = ffbc_load_exact(root + "matmul_7x7_rank248_d2952_sedoglavic_gf2.txt", 7, 7, 7, 320)
archive1 = ffbc_load_exact(root + "matmul_7x7_rank248_d2958_sedoglavic_gf2.txt", 7, 7, 7, 320)
archive2 = ffbc_load_exact(root + "matmul_7x7_rank248_d3015_connectivity_sedoglavic_gf2.txt", 7, 7, 7, 320)
novelty = fflc_term_set_distance(archive0, saved) ## i64
distance = fflc_term_set_distance(archive1, saved) ## i64
if distance < novelty
  novelty = distance
distance = fflc_term_set_distance(archive2, saved)
if distance < novelty
  novelty = distance
fflcst_expect("checked-in canonical archive novelty", novelty == 336)

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
  fflcst_expect("canonical source leaf " + i.to_s(), leaf != nil)
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
reproduced = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
fflcst_expect("canonical recipe reproduces term set", reproduced != nil && fflc_equal(saved, reproduced) == 1)
temporary = "/tmp/matmul_7x7_rank248_d2967_leaf_canonical_gf2.txt"
fflcst_expect("canonical recipe writes rank 248", ffbc_write(temporary, reproduced) == 248)
fflcst_expect("checked-in bytes reproducible", read_file(temporary) == read_file(seed_path))
<< "flipfleet_leaf_canonical_seed_test: all checks passed"
