use flipfleet_rect_archive_nullspace

-> ff225bgft_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
d84 = ffbc_load_exact(root + "matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, 32)
d88 = ffbc_load_exact(root + "matmul_2x2x5_rank18_d88_gf2.txt", 2, 2, 5, 32)
block = ffbc_load_exact(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt", 2, 2, 5, 32)
splice = ffbc_load_exact(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt", 2, 2, 5, 32)
gpu_tunnel = ffbc_load_exact(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt", 2, 2, 5, 32)
z = ff225bgft_expect("all five exact", d84 != nil && d88 != nil && block != nil && splice != nil && gpu_tunnel != nil && ffbc_verify_exact(d84) == 1 && ffbc_verify_exact(d88) == 1 && ffbc_verify_exact(block) == 1 && ffbc_verify_exact(splice) == 1 && ffbc_verify_exact(gpu_tunnel) == 1) ## i64
z = ff225bgft_expect("rank and densities", d84.rank() == 18 && d88.rank() == 18 && block.rank() == 18 && splice.rank() == 18 && gpu_tunnel.rank() == 18 && fflc_density(d84) == 84 && fflc_density(d88) == 88 && fflc_density(block) == 92 && fflc_density(splice) == 84 && fflc_density(gpu_tunnel) == 84)
z = ff225bgft_expect("zero-overlap core and block doors", fflc_term_set_distance(d84,d88) == 36 && fflc_term_set_distance(block,d84) == 36 && fflc_term_set_distance(block,d88) == 36)
z = ff225bgft_expect("block connectivity", fflc_equal_factor_pairs(block) == 16)
z = ff225bgft_expect("GPU tunnel distances", fflc_term_set_distance(gpu_tunnel,d84) == 28 && fflc_term_set_distance(gpu_tunnel,d88) == 36 && fflc_term_set_distance(gpu_tunnel,block) == 10 && fflc_term_set_distance(gpu_tunnel,splice) == 14)

meta = i64[9]
derived = ffran_crossover(block,d84,4096,meta)
z = ff225bgft_expect("proper nullity-two splice", derived != nil && meta[0] == 36 && meta[1] == 2 && meta[2] == 34 && meta[5] == 22 && meta[6] == 11 && meta[7] == 11)
z = ff225bgft_expect("saved splice replay", derived.rank() == 18 && fflc_density(derived) == 84 && fflc_term_set_distance(derived,splice) == 0 && ffbc_verify_exact(derived) == 1)

core_meta = i64[9]
none = ffran_crossover(d84,d88,4096,core_meta)
z = ff225bgft_expect("core pair has only full relation", none == nil && core_meta[0] == 36 && core_meta[1] == 1 && core_meta[2] == 35)

<< "PASS flipfleet 225 block-local GL frontier"
