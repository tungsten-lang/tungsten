use flipfleet_projective_bucket5

-> ffpb5t_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTIVE_BUCKET5_FAIL " + label
    exit(1)
  1

-> ffpb5t_map4(value) (i64) i64
  basis = i64[4]
  basis[0] = 27
  basis[1] = 112
  basis[2] = 494
  basis[3] = 151
  mapped = 0 ## i64
  bit = 0 ## i64
  while bit < 4
    if ((value >> bit) & 1) != 0
      mapped = mapped ^ basis[bit]
    bit += 1
  mapped

# Five rank-two bucket matrices.  Their best whole-bucket median is the
# rank-two matrix in bucket three and lowers the exact subtotal 10 -> 9.
# Exhaustive representative-term search has no lowering endpoint, making this
# a regression the older one-term circuit implementation cannot express.
factors = i64[5]
factors[0] = 1
factors[1] = 2
factors[2] = 4
factors[3] = 8
factors[4] = 15
source_u = i64[10]
source_v = i64[10]
source_w = i64[10]
lefts = i64[10]
rights = i64[10]
lefts[0] = 1
rights[0] = 13
lefts[1] = 4
rights[1] = 1
lefts[2] = 2
rights[2] = 4
lefts[3] = 4
rights[3] = 10
lefts[4] = 9
rights[4] = 4
lefts[5] = 14
rights[5] = 12
lefts[6] = 3
rights[6] = 8
lefts[7] = 4
rights[7] = 4
lefts[8] = 9
rights[8] = 9
lefts[9] = 10
rights[9] = 12
i = 0 ## i64
while i < 10
  bucket = i / 2 ## i64
  source_u[i] = factors[bucket]
  source_v[i] = lefts[i]
  source_w[i] = rights[i]
  i += 1

selected = i64[10]
bucket_ids = i64[10]
captured_u = i64[10]
captured_v = i64[10]
captured_w = i64[10]
bucket_sizes = i64[5]
captured = ffpb5_capture(source_u,source_v,source_w,10,0,factors,selected,bucket_ids,captured_u,captured_v,captured_w,bucket_sizes) ## i64
ffpb5t_expect("capture all terms",captured == 10)
i = 0
while i < 5
  ffpb5t_expect("two per bucket",bucket_sizes[i] == 2)
  i += 1

replacement_u = i64[64]
replacement_v = i64[64]
replacement_w = i64[64]
local_meta = i64[18]
replacement_rank = ffpb5_optimize_circuit(captured_u,captured_v,captured_w,captured,0,factors,bucket_ids,bucket_sizes,replacement_u,replacement_v,replacement_w,local_meta) ## i64
ffpb5t_expect("whole bucket 10to9",replacement_rank == 9 && local_meta[8] == 10 && local_meta[9] == 9)
ffpb5t_expect("all subset masks",local_meta[6] == 31 && local_meta[7] == 31)
ffpb5t_expect("rank-two whole matrix",local_meta[10] == 8 && local_meta[11] == 2)
ffpb5t_expect("local exact",local_meta[12] == 1 && ffgr_replacement_exact(source_u,source_v,source_w,10,replacement_u,replacement_v,replacement_w,replacement_rank) == 1)

old_u = i64[32]
old_v = i64[32]
old_w = i64[32]
old_meta = i64[14]
old_rank = ffpc5_search(source_u,source_v,source_w,10,0,0,old_u,old_v,old_w,old_meta) ## i64
ffpb5t_expect("representative move cannot drop",old_meta[5] == 0 && (old_rank == 0 || old_rank >= 10))

# The symmetric difference of the 10-term source and 9-term replacement is a
# zero tensor.  Embed it into unused 3x3 U factors, add it ahead of the exact
# rank-23 scheme, and ensure the first whole-bucket circuit removes it under a
# fresh full n^6 gate.  The valid local replacement is empty here, exercising
# zero-subtotal parity compaction as well.
mapped_source_u = i64[10]
mapped_source_v = i64[10]
mapped_source_w = i64[10]
i = 0
while i < 10
  mapped_source_u[i] = ffpb5t_map4(source_u[i])
  mapped_source_v[i] = ffpb5t_map4(source_v[i])
  mapped_source_w[i] = ffpb5t_map4(source_w[i])
  i += 1
mapped_replacement_u = i64[64]
mapped_replacement_v = i64[64]
mapped_replacement_w = i64[64]
i = 0
while i < replacement_rank
  mapped_replacement_u[i] = ffpb5t_map4(replacement_u[i])
  mapped_replacement_v[i] = ffpb5t_map4(replacement_v[i])
  mapped_replacement_w[i] = ffpb5t_map4(replacement_w[i])
  i += 1
relation_u = i64[19]
relation_v = i64[19]
relation_w = i64[19]
i = 0
while i < 10
  relation_u[i] = mapped_source_u[i]
  relation_v[i] = mapped_source_v[i]
  relation_w[i] = mapped_source_w[i]
  i += 1
i = 0
while i < replacement_rank
  relation_u[10 + i] = mapped_replacement_u[i]
  relation_v[10 + i] = mapped_replacement_v[i]
  relation_w[10 + i] = mapped_replacement_w[i]
  i += 1
ffpb5t_expect("mapped zero relation",ffgr_replacement_exact(relation_u,relation_v,relation_w,19,replacement_u,replacement_v,replacement_w,0) == 1)

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,982001,0,1,1,1) ## i64
ffpb5t_expect("base exact",base_rank == 23 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffpb5t_expect("base export",ffw_export_current(base,base_u,base_v,base_w) == base_rank)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = ffcis3_apply_circuit(relation_u,relation_v,relation_w,19,base_u,base_v,base_w,base_rank,shoulder_u,shoulder_v,shoulder_w) ## i64
shoulder = i64[state_size]
shoulder_loaded = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,capacity,982003,0,1,1,1) ## i64
ffpb5t_expect("shoulder exact",shoulder_rank > base_rank && shoulder_loaded == shoulder_rank && ffw_verify_current_exact(shoulder,n) == 1)

restored = i64[state_size]
search_meta = i64[30]
restored_rank = ffpb5_search_state(shoulder,1,0,0,restored,search_meta) ## i64
ffpb5t_expect("full gate restored",restored_rank == 23 && ffw_verify_current_exact(restored,n) == 1)
ffpb5t_expect("first circuit whole bucket",search_meta[1] == 1 && search_meta[7] == 1 && search_meta[9] == 1)

# Corrupt one factor and independently require the local coefficient gate to
# reject it.
replacement_w[0] = replacement_w[0] ^ 16
ffpb5t_expect("negative local gate",ffgr_replacement_exact(source_u,source_v,source_w,10,replacement_u,replacement_v,replacement_w,replacement_rank) == 0)

<< "flipfleet_projective_bucket5_test: pass local=10->" + local_meta[9].to_s() + " old=" + old_rank.to_s() + " shoulder=" + shoulder_rank.to_s() + " restored=" + restored_rank.to_s()
