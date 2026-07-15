use flipfleet_projective_circuit6

-> ffpc6t_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTIVE_CIRCUIT6_FAIL " + label
    exit(1)
  1

# A rank-five six-factor circuit whose common matrix drops 6 -> 5.
source_u = i64[6]
source_v = i64[6]
source_w = i64[6]
source_u[0] = 1
source_u[1] = 2
source_u[2] = 4
source_u[3] = 8
source_u[4] = 16
source_u[5] = 31
source_v[0] = 1
source_v[1] = 1
source_v[2] = 1
source_v[3] = 2
source_v[4] = 4
source_v[5] = 8
source_w[0] = 1
source_w[1] = 2
source_w[2] = 4
source_w[3] = 1
source_w[4] = 1
source_w[5] = 1
selected = i64[6]
i = 0 ## i64
while i < 6
  selected[i] = i
  i += 1
replacement_u = i64[20]
replacement_v = i64[20]
replacement_w = i64[20]
replacement_rank = ffpc6_build_endpoint(source_u,source_v,source_w,6,0,selected,1,1,replacement_u,replacement_v,replacement_w) ## i64
z = ffpc6t_expect("planted 6to5",replacement_rank == 5)

found_u = i64[20]
found_v = i64[20]
found_w = i64[20]
small_meta = i64[18]
found_rank = ffpc6_search(source_u,source_v,source_w,6,0,1,0,found_u,found_v,found_w,small_meta) ## i64
z = ffpc6t_expect("small search",found_rank == 5 && small_meta[3] == 1 && small_meta[7] > 0)
z = ffpc6t_expect("minimality reject",ffpc6_independent5(1,2,3,4,8) == 0)
capped_meta = i64[18]
capped_rank = ffpc6_search(source_u,source_v,source_w,6,1,0,0,found_u,found_v,found_w,capped_meta) ## i64
z = ffpc6t_expect("triple cap",capped_rank == 0 && capped_meta[14] == 1 && capped_meta[0] == 3)

# Put the eleven-term zero relation before a rank-23 3x3 scheme.  Its six
# source terms then form the first canonical triple pair, so the bounded
# circuit_cap=1 regression must undo the planted shoulder.  The independent
# n^6 gate verifies both the shoulder and restored endpoint.
mapped_u = i64[6]
mapped_v = i64[6]
mapped_w = i64[6]
mapped_u[0] = 256
mapped_u[1] = 128
mapped_u[2] = 64
mapped_u[3] = 32
mapped_u[4] = 16
mapped_u[5] = 496
mapped_v[0] = 256
mapped_v[1] = 256
mapped_v[2] = 256
mapped_v[3] = 128
mapped_v[4] = 64
mapped_v[5] = 32
mapped_w[0] = 256
mapped_w[1] = 128
mapped_w[2] = 64
mapped_w[3] = 256
mapped_w[4] = 256
mapped_w[5] = 256
mapped_replacement_u = i64[20]
mapped_replacement_v = i64[20]
mapped_replacement_w = i64[20]
mapped_rank = ffpc6_build_endpoint(mapped_u,mapped_v,mapped_w,6,0,selected,256,256,mapped_replacement_u,mapped_replacement_v,mapped_replacement_w) ## i64
z = ffpc6t_expect("mapped 6to5",mapped_rank == 5)

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,96801,0,1,1,1) ## i64
z = ffpc6t_expect("base exact",base_rank == 23 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffpc6t_expect("base export",ffw_export_current(base,base_u,base_v,base_w) == base_rank)

relation_u = i64[11]
relation_v = i64[11]
relation_w = i64[11]
i = 0
while i < 6
  relation_u[i] = mapped_u[i]
  relation_v[i] = mapped_v[i]
  relation_w[i] = mapped_w[i]
  i += 1
i = 0
while i < 5
  relation_u[6 + i] = mapped_replacement_u[i]
  relation_v[6 + i] = mapped_replacement_v[i]
  relation_w[6 + i] = mapped_replacement_w[i]
  i += 1
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = ffcis3_apply_circuit(relation_u,relation_v,relation_w,11,base_u,base_v,base_w,base_rank,shoulder_u,shoulder_v,shoulder_w) ## i64
shoulder = i64[state_size]
shoulder_loaded = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,capacity,96803,0,1,1,1) ## i64
z = ffpc6t_expect("rank34 shoulder exact",shoulder_rank == 34 && shoulder_loaded == 34 && ffw_verify_current_exact(shoulder,n) == 1)

restored_u = i64[capacity]
restored_v = i64[capacity]
restored_w = i64[capacity]
full_meta = i64[18]
restored_rank = ffpc6_search(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,0,1,0,restored_u,restored_v,restored_w,full_meta) ## i64
restored = i64[state_size]
restored_loaded = ffw_init_terms_cap(restored,restored_u,restored_v,restored_w,restored_rank,n,capacity,96805,0,1,1,1) ## i64
z = ffpc6t_expect("restored full gate",restored_rank == 23 && restored_loaded == 23 && ffw_verify_current_exact(restored,n) == 1)

<< "flipfleet_projective_circuit6_test: all checks passed circuits=" + full_meta[3].to_s() + " endpoints=" + full_meta[6].to_s() + " restored=" + restored_rank.to_s()
