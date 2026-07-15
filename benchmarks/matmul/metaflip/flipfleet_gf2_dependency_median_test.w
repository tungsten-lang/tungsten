use flipfleet_gf2_dependency_median

-> ffgdmt_expect(label, condition) (String bool) i64
  if !condition
    << "GF2_DEPENDENCY_MEDIAN_FAIL " + label
    exit(1)
  1

-> ffgdmt_map7(value) (i64) i64
  basis = i64[7]
  basis[0] = 188
  basis[1] = 98
  basis[2] = 279
  basis[3] = 371
  basis[4] = 436
  basis[5] = 269
  basis[6] = 181
  mapped = 0 ## i64
  bit = 0 ## i64
  while bit < 7
    if ((value >> bit) & 1) != 0
      mapped = mapped ^ basis[bit]
    bit += 1
  mapped

# An eight-factor minimal dependency, beyond the fixed five/six-circuit
# operators.  D=(1 tensor 1) removes the anchor bucket.  Each of the seven
# other buckets is (1 tensor 2), and toggling D changes it to (1 tensor 3) at
# equal rank.  Elimination must therefore find the exact direct 8 -> 7 drop.
source_u = i64[8]
source_v = i64[8]
source_w = i64[8]
source_u[0] = 127
source_v[0] = 1
source_w[0] = 1
i = 1 ## i64
while i < 8
  source_u[i] = 1 << (i - 1)
  source_v[i] = 1
  source_w[i] = 2
  i += 1
factors = i64[8]
term_bucket = i64[8]
bucket_sizes = i64[8]
bucket_count = ffgdm_group_axis(source_u,source_v,source_w,8,0,0,factors,term_bucket,bucket_sizes) ## i64
ffgdmt_expect("eight buckets",bucket_count == 8)
base_ranks = i64[8]
deltas = i64[8]
bucket = 0 ## i64
while bucket < bucket_count
  base_left = i64[63]
  base_right = i64[63]
  shifted_left = i64[63]
  shifted_right = i64[63]
  base_ranks[bucket] = ffgdm_factor_bucket(source_u,source_v,source_w,8,0,term_bucket,bucket,0,0,0,base_left,base_right)
  shifted = ffgdm_factor_bucket(source_u,source_v,source_w,8,0,term_bucket,bucket,1,1,1,shifted_left,shifted_right) ## i64
  deltas[bucket] = shifted - base_ranks[bucket]
  bucket += 1
ffgdmt_expect("negative anchor",deltas[0] == -1)
i = 1
while i < 8
  ffgdmt_expect("zero bucket",deltas[i] == 0)
  i += 1
chosen = i64[8]
choice_meta = i64[4]
ffgdmt_expect("long dependency found",ffgdm_find_dependency_min(factors,deltas,bucket_count,2,6,chosen,choice_meta) == 1)
ffgdmt_expect("direct eight circuit",choice_meta[0] == -1 && choice_meta[1] == 0 && choice_meta[2] == 8)
selected = i64[8]
captured_u = i64[8]
captured_v = i64[8]
captured_w = i64[8]
captured = ffgdm_capture_choice(source_u,source_v,source_w,8,term_bucket,chosen,selected,captured_u,captured_v,captured_w) ## i64
replacement_u = i64[16]
replacement_v = i64[16]
replacement_w = i64[16]
replacement_rank = ffgdm_materialize_choice(source_u,source_v,source_w,8,0,factors,term_bucket,bucket_count,chosen,1,1,replacement_u,replacement_v,replacement_w) ## i64
ffgdmt_expect("arbitrary dependency 8to7",captured == 8 && replacement_rank == 7)
ffgdmt_expect("local exact",ffgr_replacement_exact(captured_u,captured_v,captured_w,captured,replacement_u,replacement_v,replacement_w,replacement_rank) == 1)

# There is no five-factor zero dependency in this minimal eight-circuit.
old_u = i64[16]
old_v = i64[16]
old_w = i64[16]
old_meta = i64[14]
old_rank = ffpc5_search(source_u,source_v,source_w,8,0,0,old_u,old_v,old_w,old_meta) ## i64
ffgdmt_expect("not a five circuit",old_rank == 0 && old_meta[1] == 0)

# Add the 15-term zero relation to an exact 3x3 scheme.  Its U factors are an
# injective image disjoint from the base scheme.  With the relation first, the
# anchor D is the first polynomial candidate; one full-gated iteration must
# remove the entire relation and restore rank 23.
mapped_source_u = i64[8]
mapped_source_v = i64[8]
mapped_source_w = i64[8]
i = 0
while i < 8
  mapped_source_u[i] = ffgdmt_map7(source_u[i])
  mapped_source_v[i] = ffgdmt_map7(source_v[i])
  mapped_source_w[i] = ffgdmt_map7(source_w[i])
  i += 1
mapped_replacement_u = i64[16]
mapped_replacement_v = i64[16]
mapped_replacement_w = i64[16]
i = 0
while i < replacement_rank
  mapped_replacement_u[i] = ffgdmt_map7(replacement_u[i])
  mapped_replacement_v[i] = ffgdmt_map7(replacement_v[i])
  mapped_replacement_w[i] = ffgdmt_map7(replacement_w[i])
  i += 1
relation_u = i64[15]
relation_v = i64[15]
relation_w = i64[15]
i = 0
while i < 8
  relation_u[i] = mapped_source_u[i]
  relation_v[i] = mapped_source_v[i]
  relation_w[i] = mapped_source_w[i]
  i += 1
i = 0
while i < replacement_rank
  relation_u[8 + i] = mapped_replacement_u[i]
  relation_v[8 + i] = mapped_replacement_v[i]
  relation_w[8 + i] = mapped_replacement_w[i]
  i += 1
ffgdmt_expect("mapped relation zero",ffgr_replacement_exact(relation_u,relation_v,relation_w,15,replacement_u,replacement_v,replacement_w,0) == 1)

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,992001,0,1,1,1) ## i64
ffgdmt_expect("base exact",base_rank == 23 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffgdmt_expect("base export",ffw_export_current(base,base_u,base_v,base_w) == base_rank)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = ffcis3_apply_circuit(relation_u,relation_v,relation_w,15,base_u,base_v,base_w,base_rank,shoulder_u,shoulder_v,shoulder_w) ## i64
shoulder = i64[state_size]
shoulder_loaded = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,capacity,992003,0,1,1,1) ## i64
ffgdmt_expect("shoulder exact",shoulder_rank == 38 && shoulder_loaded == 38 && ffw_verify_current_exact(shoulder,n) == 1)
restored = i64[state_size]
search_meta = i64[32]
restored_rank = ffgdm_search_state_min(shoulder,1,0,0,6,restored,search_meta) ## i64
ffgdmt_expect("full gate restored",restored_rank == 23 && ffw_verify_current_exact(restored,n) == 1)
ffgdmt_expect("polynomial direct dependency",search_meta[1] == 1 && search_meta[8] == 1 && search_meta[15] == 1 && search_meta[25] == 8)

replacement_w[0] = replacement_w[0] ^ 4
ffgdmt_expect("negative local gate",ffgr_replacement_exact(source_u,source_v,source_w,8,replacement_u,replacement_v,replacement_w,replacement_rank) == 0)

<< "flipfleet_gf2_dependency_median_test: pass local=8->7 old5=" + old_rank.to_s() + " shoulder=" + shoulder_rank.to_s() + " restored=" + restored_rank.to_s()
