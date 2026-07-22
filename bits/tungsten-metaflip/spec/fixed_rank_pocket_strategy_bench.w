use ../lib/metaflip/strategies/fixed_rank_pocket

root=__DIR__+"/../lib/metaflip/seeds/gf2/"
c013_path=root+"matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt"
leader_path=root+"matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
capacity=320 ## i64
state_size=ffw_state_size(capacity) ## i64

c013=i64[state_size]
rank=ffw_load_scheme_cap(c013,c013_path,7,capacity,170001,4,1,25000000,6250000) ## i64
if rank!=247
  << "FIXED_RANK_POCKET_BENCH_FAIL C013 load"
  exit(1)
c013_meta=i64[19]
c013_applied=ffpa_apply_greedy_closure(c013,8,4,5,64,5,5,512,12,c013_meta) ## i64
if c013_applied!=1 || ffw_best_bits(c013)!=3496 || ffw_verify_best_exact(c013,7)!=1
  << "FIXED_RANK_POCKET_BENCH_FAIL C013 endpoint"
  exit(1)
<< "FIXED_RANK_POCKET_BENCH shape=7x7-c013 proposals="+c013_meta[1].to_s()+" steps="+c013_meta[6].to_s()
