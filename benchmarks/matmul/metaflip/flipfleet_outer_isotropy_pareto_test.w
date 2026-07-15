use flipfleet_leaf_conjugation

-> ffoipt_expect(label, condition)
  if condition != 0
    return 1
  << "FAIL " + label
  exit(1)
  0

root = "benchmarks/matmul/metaflip/"
paths = ["matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt",
         "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt",
         "matmul_7x7_rank247_d3554_outer_isotropy_c021_m4_gf2.txt",
         "matmul_7x7_rank247_d3554_outer_isotropy_c024_m0_gf2.txt"]
bank = []
i = 0 ## i64
while i < paths.size()
  scheme = ffbc_load_exact(root + paths[i], 7, 7, 7, 320)
  ffoipt_expect("load exact " + i.to_s(), scheme != nil && scheme.rank() == 247 && ffbc_verify_exact(scheme) == 1)
  ffoipt_expect("density " + i.to_s(), fflc_density(scheme) == 3554)
  ffoipt_expect("connectivity " + i.to_s(), fflc_equal_factor_pairs(scheme) == 43)
  j = 0 ## i64
  while j < bank.size()
    ffoipt_expect("pairwise distance " + j.to_s() + "," + i.to_s(), fflc_term_set_distance(bank[j], scheme) == 494)
    j += 1
  bank.push(scheme)
  i += 1

<< "PASS outer isotropy Pareto bank exact=4 pairwise_distance=494 density=3554 pairs=43"
