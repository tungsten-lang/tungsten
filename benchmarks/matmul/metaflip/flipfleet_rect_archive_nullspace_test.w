use flipfleet_rect_archive_nullspace

-> ffrant_expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
d919 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d919_gf2.txt", 4, 4, 5, 128)
d655 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d655_global_isotropy_gf2.txt", 4, 4, 5, 128)
d628 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt", 4, 4, 5, 128)
z = ffrant_expect("parents load exact", d919 != nil && d655 != nil && d628 != nil && ffbc_verify_exact(d919) == 1 && ffbc_verify_exact(d655) == 1 && ffbc_verify_exact(d628) == 1)

single_meta = i64[9]
single = ffran_crossover(d919, d628, 4096, single_meta)
z = ffrant_expect("d919/d628 full relation only", single == nil && single_meta[0] == 120 && single_meta[1] == 1 && single_meta[2] == 119)

proper_meta = i64[9]
proper = ffran_crossover(d655, d628, 4096, proper_meta)
z = ffrant_expect("d655/d628 proper relations", proper != nil && proper_meta[0] == 24 && proper_meta[1] == 6 && proper_meta[2] == 18 && proper_meta[8] == 1)
if proper != nil
  z = ffrant_expect("proper hybrid exact rank", proper.rank() == 60 && ffbc_verify_exact(proper) == 1)
  z = ffrant_expect("proper hybrid differs", fflc_term_set_distance(proper, d655) > 0 && fflc_term_set_distance(proper, d628) > 0)

<< "PASS flipfleet rectangular archive nullspace"
