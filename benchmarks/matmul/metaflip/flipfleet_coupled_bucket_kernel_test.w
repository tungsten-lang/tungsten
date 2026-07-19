use flipfleet_coupled_bucket_kernel

-> ffcbkt_expect(label, condition) (String bool) i64
  if !condition
    << "COUPLED_BUCKET_KERNEL_FAIL " + label
    exit(1)
  1

# Seven nonzero F2^3 bucket factors.  S is the source matrix list and E is the
# jointly corrected endpoint.  z1={1,2,3}, z2={1,4,5}; D1 and D2 are the two
# single-cell rank-one matrices 0x1 and 0x2.
factors = i64[7]
source_matrices = i64[7]
endpoint_matrices = i64[7]
raw_factors = [1,2,3,4,5,6,7]
raw_source = [15,7,9,3,2,15,10]
raw_endpoint = [12,6,8,1,0,15,10]
i = 0 ## i64
while i < 7
  factors[i] = raw_factors[i]
  source_matrices[i] = raw_source[i]
  endpoint_matrices[i] = raw_endpoint[i]
  i += 1

source_u = i64[32]
source_v = i64[32]
source_w = i64[32]
source_rank = ffcbk_build_raw2_subtotal(factors,source_matrices,7,0,source_u,source_v,source_w) ## i64
expected_u = i64[32]
expected_v = i64[32]
expected_w = i64[32]
expected_rank = ffcbk_build_raw2_subtotal(factors,endpoint_matrices,7,0,expected_u,expected_v,expected_w) ## i64
ffcbkt_expect("planted costs",source_rank == 9 && expected_rank == 7)
ffcbkt_expect("planted subtotal exact",ffgr_replacement_exact(source_u,source_v,source_w,source_rank,expected_u,expected_v,expected_w,expected_rank) == 1)

grouped_factors = i64[32]
term_bucket = i64[32]
bucket_sizes = i64[32]
bucket_count = ffgdm_group_axis(source_u,source_v,source_w,source_rank,0,0,grouped_factors,term_bucket,bucket_sizes) ## i64
ffcbkt_expect("seven grouped buckets",bucket_count == 7)

# Group insertion order is factor order here, but build codewords by factor
# value so the test also guards against a future grouping-order change.
z1 = i64[7]
z2 = i64[7]
bucket = 0 ## i64
while bucket < bucket_count
  f = grouped_factors[bucket] ## i64
  if f == 1 || f == 2 || f == 3
    z1[bucket] = 1
  if f == 1 || f == 4 || f == 5
    z2[bucket] = 1
  bucket += 1
ffcbkt_expect("first kernel codeword",ffcbk_codeword_valid(grouped_factors,bucket_count,z1) == 1)
ffcbkt_expect("second kernel codeword",ffcbk_codeword_valid(grouped_factors,bucket_count,z2) == 1)

zero = i64[7]
layout_z1_zero = i64[3 * bucket_count + source_rank]
layout_zero_z2 = i64[3 * bucket_count + source_rank]
layout_z1_z2 = i64[3 * bucket_count + source_rank]
ffcbkt_expect("pack first layout",ffcbk_pack_layout(grouped_factors,term_bucket,source_rank,bucket_count,z1,zero,layout_z1_zero) > 0)
ffcbkt_expect("pack second layout",ffcbk_pack_layout(grouped_factors,term_bucket,source_rank,bucket_count,zero,z2,layout_zero_z2) > 0)
ffcbkt_expect("pack joint layout",ffcbk_pack_layout(grouped_factors,term_bucket,source_rank,bucket_count,z1,z2,layout_z1_z2) > 0)
single1_u = i64[32]
single1_v = i64[32]
single1_w = i64[32]
single1_meta = i64[8]
single1_config = i64[7]
single1_config[0]=1; single1_config[1]=1; single1_config[2]=1; single1_config[3]=2; single1_config[4]=1; single1_config[5]=0; single1_config[6]=bucket_count
single1_rank = ffcbk_materialize_pair(source_u,source_v,source_w,source_rank,0,layout_z1_zero,single1_config,single1_u,single1_v,single1_w,single1_meta) ## i64
single2_u = i64[32]
single2_v = i64[32]
single2_w = i64[32]
single2_meta = i64[8]
single2_config = i64[7]
single2_config[0]=1; single2_config[1]=1; single2_config[2]=1; single2_config[3]=2; single2_config[4]=0; single2_config[5]=1; single2_config[6]=bucket_count
single2_rank = ffcbk_materialize_pair(source_u,source_v,source_w,source_rank,0,layout_zero_z2,single2_config,single2_u,single2_v,single2_w,single2_meta) ## i64
ffcbkt_expect("single corrections are exact neutral",single1_rank == 9 && single2_rank == 9 && single1_meta[5] == 1 && single2_meta[5] == 1)

joint_u = i64[32]
joint_v = i64[32]
joint_w = i64[32]
joint_meta = i64[8]
joint_config = i64[7]
joint_config[0]=1; joint_config[1]=1; joint_config[2]=1; joint_config[3]=2; joint_config[4]=1; joint_config[5]=1; joint_config[6]=bucket_count
joint_rank = ffcbk_materialize_pair(source_u,source_v,source_w,source_rank,0,layout_z1_z2,joint_config,joint_u,joint_v,joint_w,joint_meta) ## i64
ffcbkt_expect("coupled-only 9to7 drop",joint_rank == 7 && joint_meta[0] == 9 && joint_meta[2] == -2 && joint_meta[5] == 1)
ffcbkt_expect("joint endpoint expected",ffmp_same_term_set(joint_u,joint_v,joint_w,joint_rank,expected_u,expected_v,expected_w,expected_rank) == 1)

# A malformed non-kernel selection must fail closed.
bad = i64[7]
bad[0] = 1
bad[1] = 1
bad_u = i64[32]
bad_v = i64[32]
bad_w = i64[32]
bad_meta = i64[8]
bad_layout = i64[3 * bucket_count + source_rank]
ffcbkt_expect("pack bad layout",ffcbk_pack_layout(grouped_factors,term_bucket,source_rank,bucket_count,bad,z2,bad_layout) > 0)
bad_rank = ffcbk_materialize_pair(source_u,source_v,source_w,source_rank,0,bad_layout,joint_config,bad_u,bad_v,bad_w,bad_meta) ## i64
ffcbkt_expect("nonkernel rejected",bad_rank < 0)

# Real 5x5 frontier: two overlapping triangle corrections have individual
# deltas 0 and +1, while their coupled nonlinear refactor is rank-neutral.
# This is a new exact door rather than only a planted solver control.
n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
real_state = i64[ffw_state_size(capacity)]
real_rank = ffw_load_scheme_cap(real_state,"benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt",n,capacity,1049001,0,1,1,1) ## i64
ffcbkt_expect("real source exact",real_rank == 93 && ffw_verify_current_exact(real_state,n) == 1)
real_u = i64[capacity]
real_v = i64[capacity]
real_w = i64[capacity]
ffcbkt_expect("real source export",ffw_export_current(real_state,real_u,real_v,real_w) == real_rank)
real_factors = i64[capacity]
real_bucket = i64[capacity]
real_sizes = i64[capacity]
real_bucket_count = ffgdm_group_axis(real_u,real_v,real_w,real_rank,0,0,real_factors,real_bucket,real_sizes) ## i64
real_z1 = i64[capacity]
real_z2 = i64[capacity]
bucket = 0
while bucket < real_bucket_count
  f = real_factors[bucket] ## i64
  if f == 168965 || f == 5248005 || f == 5406720
    real_z1[bucket] = 1
  if f == 5248005 || f == 26240025 || f == 29388828
    real_z2[bucket] = 1
  bucket += 1
ffcbkt_expect("real first triangle",ffcbk_codeword_valid(real_factors,real_bucket_count,real_z1) == 1)
ffcbkt_expect("real second triangle",ffcbk_codeword_valid(real_factors,real_bucket_count,real_z2) == 1)
real_layout = i64[3 * real_bucket_count + real_rank]
ffcbkt_expect("pack real layout",ffcbk_pack_layout(real_factors,real_bucket,real_rank,real_bucket_count,real_z1,real_z2,real_layout) > 0)
real_single1_u = i64[capacity]
real_single1_v = i64[capacity]
real_single1_w = i64[capacity]
real_single1_meta = i64[8]
real_single1_config = i64[7]
real_single1_config[0]=8; real_single1_config[1]=8388608; real_single1_config[2]=820000; real_single1_config[3]=8388608; real_single1_config[4]=1; real_single1_config[5]=0; real_single1_config[6]=real_bucket_count
real_single1_rank = ffcbk_materialize_pair(real_u,real_v,real_w,real_rank,0,real_layout,real_single1_config,real_single1_u,real_single1_v,real_single1_w,real_single1_meta) ## i64
real_single2_u = i64[capacity]
real_single2_v = i64[capacity]
real_single2_w = i64[capacity]
real_single2_meta = i64[8]
real_single2_config = i64[7]
real_single2_config[0]=8; real_single2_config[1]=8388608; real_single2_config[2]=820000; real_single2_config[3]=8388608; real_single2_config[4]=0; real_single2_config[5]=1; real_single2_config[6]=real_bucket_count
real_single2_rank = ffcbk_materialize_pair(real_u,real_v,real_w,real_rank,0,real_layout,real_single2_config,real_single2_u,real_single2_v,real_single2_w,real_single2_meta) ## i64
real_joint_u = i64[capacity]
real_joint_v = i64[capacity]
real_joint_w = i64[capacity]
real_joint_meta = i64[8]
real_joint_config = i64[7]
real_joint_config[0]=8; real_joint_config[1]=8388608; real_joint_config[2]=820000; real_joint_config[3]=8388608; real_joint_config[4]=1; real_joint_config[5]=1; real_joint_config[6]=real_bucket_count
real_joint_rank = ffcbk_materialize_pair(real_u,real_v,real_w,real_rank,0,real_layout,real_joint_config,real_joint_u,real_joint_v,real_joint_w,real_joint_meta) ## i64
ffcbkt_expect("real nonlinear synergy",real_single1_rank == 93 && real_single2_rank == 94 && real_joint_rank == 93)
real_child = i64[ffw_state_size(capacity)]
real_loaded = ffw_init_terms_cap(real_child,real_joint_u,real_joint_v,real_joint_w,real_joint_rank,n,capacity,1049003,0,1,1,1) ## i64
ffcbkt_expect("real full n6 gate",real_loaded == 93 && ffw_verify_current_exact(real_child,n) == 1)
real_distance = ffmp_term_set_distance(real_u,real_v,real_w,real_rank,real_joint_u,real_joint_v,real_joint_w,real_joint_rank) ## i64
real_density_delta = ffcis_density(real_joint_u,real_joint_v,real_joint_w,real_joint_rank) - ffcis_density(real_u,real_v,real_w,real_rank) ## i64
ffcbkt_expect("real door changes support",real_distance > 0)

<< "flipfleet_coupled_bucket_kernel_test: pass source=" + source_rank.to_s() + " single=" + single1_rank.to_s() + "/" + single2_rank.to_s() + " joint=" + joint_rank.to_s() + " real=93/" + real_single1_rank.to_s() + "/" + real_single2_rank.to_s() + "/" + real_joint_rank.to_s() + " distance=" + real_distance.to_s() + " density_delta=" + real_density_delta.to_s()
