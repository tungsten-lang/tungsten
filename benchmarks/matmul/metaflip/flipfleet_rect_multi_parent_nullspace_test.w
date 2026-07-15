use flipfleet_rect_multi_parent_nullspace
use flipfleet_225_block_gl_parent_lib

-> ffrmpt_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
parents = []
paths = []
paths.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
i = 0 ## i64
while i < paths.size()
  parent = ffbc_load_exact(paths[i], 2, 2, 5, 32)
  z = ffrmpt_expect("door exact", parent != nil && ffbc_verify_exact(parent) == 1) ## i64
  parents.push(parent)
  i += 1

meta = i64[13]
best = ffrmp_search(parents, 2, 2, 5, 20, 18, meta)
z = ffrmpt_expect("five-parent complete affine hull", best != nil && meta[0] == 5 && meta[1] == 55 && meta[2] == 51 && meta[3] == 4 && meta[4] == 16 && meta[5] == 7 && meta[6] == 0 && meta[7] == 7 && meta[8] == 18 && meta[9] == 84 && meta[10] == 0 && meta[12] == 1 && ffbc_verify_exact(best) == 1)

leaf3 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 16)
leaf2 = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
generated = ff225gl_parent(leaf3, leaf2, ff225gl_outer(), ff225gl_alloc_n(), ff225gl_alloc_m(), ff225gl_alloc_p(), 1253)
z = ffrmpt_expect("generated parent exact", generated != nil && ffbc_verify_exact(generated) == 1)
parents.push(generated)
meta6 = i64[13]
best6 = ffrmp_search(parents, 2, 2, 5, 20, 18, meta6)
z = ffrmpt_expect("six-parent correlated hull", best6 != nil && meta6[0] == 6 && meta6[1] == 72 && meta6[2] == 65 && meta6[3] == 7 && meta6[4] == 128 && meta6[5] == 19 && meta6[6] == 0 && meta6[7] == 19 && meta6[8] == 18 && meta6[9] == 84 && meta6[10] == 0 && meta6[12] == 1 && ffbc_verify_exact(best6) == 1)

<< "PASS flipfleet rectangular multi-parent nullspace"
