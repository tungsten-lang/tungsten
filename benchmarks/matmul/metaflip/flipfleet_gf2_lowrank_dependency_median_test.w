use flipfleet_gf2_lowrank_dependency_median

-> fflrdt_expect(label, condition) (String bool) i64
  if !condition
    << "GF2_LOWRANK_DEPENDENCY_FAIL " + label
    exit(1)
  1

-> fflrdt_map7(value) (i64) i64
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

# Eight rank-two bucket matrices on a minimal eight-factor circuit.  Every
# live rank-one D has objective >=16, while D=(6x14)^(13x5) has rank two and
# lowers the complete circuit 16->13.
fixed = i64[8]
fixed[0] = 1
fixed[1] = 2
fixed[2] = 4
fixed[3] = 8
fixed[4] = 16
fixed[5] = 32
fixed[6] = 64
fixed[7] = 127
pair_left = i64[16]
pair_right = i64[16]
pair_left[0] = 13
pair_right[0] = 3
pair_left[1] = 6
pair_right[1] = 14
pair_left[2] = 11
pair_right[2] = 10
pair_left[3] = 12
pair_right[3] = 1
pair_left[4] = 13
pair_right[4] = 5
pair_left[5] = 10
pair_right[5] = 15
pair_left[6] = 3
pair_right[6] = 5
pair_left[7] = 8
pair_right[7] = 14
pair_left[8] = 5
pair_right[8] = 12
pair_left[9] = 8
pair_right[9] = 11
pair_left[10] = 9
pair_right[10] = 5
pair_left[11] = 6
pair_right[11] = 11
pair_left[12] = 11
pair_right[12] = 1
pair_left[13] = 4
pair_right[13] = 15
pair_left[14] = 13
pair_right[14] = 5
pair_left[15] = 6
pair_right[15] = 12
source_u = i64[16]
source_v = i64[16]
source_w = i64[16]
i = 0 ## i64
while i < 16
  source_u[i] = fixed[i / 2]
  source_v[i] = pair_left[i]
  source_w[i] = pair_right[i]
  i += 1

factors = i64[16]
term_bucket = i64[16]
bucket_sizes = i64[16]
bucket_count = ffgdm_group_axis(source_u,source_v,source_w,16,0,0,factors,term_bucket,bucket_sizes) ## i64
fflrdt_expect("eight buckets",bucket_count == 8)
base_ranks = i64[8]
empty_left = i64[1]
empty_right = i64[1]
bucket = 0 ## i64
while bucket < bucket_count
  out_left = i64[63]
  out_right = i64[63]
  base_ranks[bucket] = fflrd_factor_bucket(source_u,source_v,source_w,16,0,term_bucket,bucket,empty_left,empty_right,0,out_left,out_right)
  fflrdt_expect("rank-two bucket",base_ranks[bucket] == 2)
  bucket += 1

# Exhaust every distinct live rank-one control.
rank1_minimum = 1000 ## i64
atom = 0 ## i64
while atom < 16
  duplicate = 0 ## i64
  earlier = 0 ## i64
  while earlier < atom
    if pair_left[earlier] == pair_left[atom] && pair_right[earlier] == pair_right[atom]
      duplicate = 1
    earlier += 1
  if duplicate == 0
    d_left = i64[1]
    d_right = i64[1]
    d_left[0] = pair_left[atom]
    d_right[0] = pair_right[atom]
    objective = 0 ## i64
    bucket = 0
    while bucket < bucket_count
      out_left = i64[63]
      out_right = i64[63]
      objective += fflrd_factor_bucket(source_u,source_v,source_w,16,0,term_bucket,bucket,d_left,d_right,1,out_left,out_right)
      bucket += 1
    if objective < rank1_minimum
      rank1_minimum = objective
  atom += 1
fflrdt_expect("rank-one cannot drop",rank1_minimum == 16)

input_left = i64[2]
input_right = i64[2]
input_left[0] = 6
input_right[0] = 14
input_left[1] = 13
input_right[1] = 5
d_left = i64[2]
d_right = i64[2]
d_rank = fflrd_canonical(input_left,input_right,2,d_left,d_right) ## i64
fflrdt_expect("rank-two D",d_rank == 2)
deltas = i64[8]
objective = 0
bucket = 0
while bucket < bucket_count
  out_left = i64[63]
  out_right = i64[63]
  shifted = fflrd_factor_bucket(source_u,source_v,source_w,16,0,term_bucket,bucket,d_left,d_right,d_rank,out_left,out_right) ## i64
  deltas[bucket] = shifted - base_ranks[bucket]
  objective += shifted
  bucket += 1
fflrdt_expect("rank-two objective",objective == 13)
chosen = i64[8]
choice_meta = i64[4]
fflrdt_expect("eight dependency",fflrd_find_dependency(factors,deltas,bucket_count,1,6,chosen,choice_meta) == 1)
fflrdt_expect("predicted direct drop",choice_meta[0] == -3 && choice_meta[2] == 8)
selected = i64[16]
captured_u = i64[16]
captured_v = i64[16]
captured_w = i64[16]
captured = ffgdm_capture_choice(source_u,source_v,source_w,16,term_bucket,chosen,selected,captured_u,captured_v,captured_w) ## i64
replacement_u = i64[32]
replacement_v = i64[32]
replacement_w = i64[32]
replacement_rank = fflrd_materialize_choice(source_u,source_v,source_w,16,0,factors,term_bucket,bucket_count,chosen,d_left,d_right,d_rank,replacement_u,replacement_v,replacement_w) ## i64
fflrdt_expect("planted 16to13",captured == 16 && replacement_rank == 13)
fflrdt_expect("local exact",ffgr_replacement_exact(captured_u,captured_v,captured_w,captured,replacement_u,replacement_v,replacement_w,replacement_rank) == 1)

# A repeated rank-two D over the same minimal eight-circuit is a 16-term zero
# relation. Map it into unused 3x3 U factors, add it before the exact rank-23
# scheme, and require the bounded singleton+first-pair prefix to restore r23.
relation_u = i64[16]
relation_v = i64[16]
relation_w = i64[16]
bucket = 0
while bucket < 8
  term = 0 ## i64
  while term < d_rank
    position = bucket * d_rank + term ## i64
    relation_u[position] = fflrdt_map7(fixed[bucket])
    relation_v[position] = fflrdt_map7(d_left[term])
    relation_w[position] = fflrdt_map7(d_right[term])
    term += 1
  bucket += 1
fflrdt_expect("mapped zero relation",ffgr_replacement_exact(relation_u,relation_v,relation_w,16,replacement_u,replacement_v,replacement_w,0) == 1)
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,1001001,0,1,1,1) ## i64
fflrdt_expect("base exact",base_rank == 23 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
fflrdt_expect("base export",ffw_export_current(base,base_u,base_v,base_w) == base_rank)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = ffcis3_apply_circuit(relation_u,relation_v,relation_w,16,base_u,base_v,base_w,base_rank,shoulder_u,shoulder_v,shoulder_w) ## i64
shoulder = i64[state_size]
shoulder_loaded = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,capacity,1001003,0,1,1,1) ## i64
fflrdt_expect("shoulder exact",shoulder_rank == 39 && shoulder_loaded == 39 && ffw_verify_current_exact(shoulder,n) == 1)
restored = i64[state_size]
search_meta = i64[41]
restored_rank = fflrd_search_state_min(shoulder,64,1,0,6,restored,search_meta) ## i64
fflrdt_expect("full gate restored",restored_rank == 23 && ffw_verify_current_exact(restored,n) == 1)
fflrdt_expect("rank-two selected",search_meta[28] == 2 && search_meta[20] > 0 && search_meta[33] == 8)

replacement_w[0] = replacement_w[0] ^ 16
fflrdt_expect("negative local gate",ffgr_replacement_exact(source_u,source_v,source_w,16,replacement_u,replacement_v,replacement_w,replacement_rank) == 0)

<< "flipfleet_gf2_lowrank_dependency_median_test: pass local=16->13 rank1_min=" + rank1_minimum.to_s() + " shoulder=" + shoulder_rank.to_s() + " restored=" + restored_rank.to_s()
