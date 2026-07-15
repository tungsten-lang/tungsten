use flipfleet_projective_circuit5

-> ffpc5t_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTIVE_CIRCUIT5_FAIL " + label
    exit(1)
  1

# A rank-four five-factor circuit whose common matrix drops 5 -> 4.
source_u = i64[5]
source_v = i64[5]
source_w = i64[5]
source_u[0] = 1
source_u[1] = 2
source_u[2] = 4
source_u[3] = 8
source_u[4] = 15
source_v[0] = 1
source_v[1] = 1
source_v[2] = 1
source_v[3] = 2
source_v[4] = 4
source_w[0] = 1
source_w[1] = 2
source_w[2] = 4
source_w[3] = 1
source_w[4] = 1
selected = i64[5]
i = 0 ## i64
while i < 5
  selected[i] = i
  i += 1
replacement_u = i64[16]
replacement_v = i64[16]
replacement_w = i64[16]
replacement_rank = ffpc5_build_endpoint(source_u,source_v,source_w,5,0,selected,1,1,replacement_u,replacement_v,replacement_w) ## i64
z = ffpc5t_expect("planted 5to4", replacement_rank == 4)

# Full search finds the reduction without being handed D.
found_u = i64[16]
found_v = i64[16]
found_w = i64[16]
small_meta = i64[14]
found_rank = ffpc5_search(source_u,source_v,source_w,5,0,0,found_u,found_v,found_w,small_meta) ## i64
z = ffpc5t_expect("small search", found_rank == 4 && small_meta[1] == 1 && small_meta[5] > 0)

# Higher-rank D regression. The best span median ties the best local objective
# at six terms but deliberately selects a rank-two D, exercising general
# matrix factorization rather than the rank-one constructor above.
span_u = i64[5]
span_v = i64[5]
span_w = i64[5]
span_u[0] = 1
span_u[1] = 2
span_u[2] = 4
span_u[3] = 8
span_u[4] = 15
span_v[0] = 6
span_v[1] = 4
span_v[2] = 2
span_v[3] = 4
span_v[4] = 6
span_w[0] = 4
span_w[1] = 2
span_w[2] = 3
span_w[3] = 4
span_w[4] = 7
span_out_u = i64[16]
span_out_v = i64[16]
span_out_w = i64[16]
span_stats = i64[5]
span_rank = ffpc5_span_median_endpoint(span_u,span_v,span_w,5,0,selected,span_out_u,span_out_v,span_out_w,span_stats) ## i64
z = ffpc5t_expect("rank-two span median", span_rank == 6 && span_stats[1] == 6 && ffmp_matrix_rank(span_stats[2],span_stats[3],span_stats[4]) == 2)
z = ffpc5t_expect("rank-two span exact", ffgr_replacement_exact(span_u,span_v,span_w,5,span_out_u,span_out_v,span_out_w,span_rank) == 1)

# Map the zero relation (five source terms XOR four replacements) into the
# 3x3 factor spaces and add it to Strassen.  The resulting exact shoulder must
# return to rank 23 under the five-circuit search and full n^6 gate.
mapped_u = i64[5]
mapped_v = i64[5]
mapped_w = i64[5]
mapped_u[0] = 256
mapped_u[1] = 128
mapped_u[2] = 64
mapped_u[3] = 32
mapped_u[4] = 480
mapped_v[0] = 256
mapped_v[1] = 256
mapped_v[2] = 256
mapped_v[3] = 128
mapped_v[4] = 64
mapped_w[0] = 256
mapped_w[1] = 128
mapped_w[2] = 64
mapped_w[3] = 256
mapped_w[4] = 256
mapped_replacement_u = i64[16]
mapped_replacement_v = i64[16]
mapped_replacement_w = i64[16]
mapped_rank = ffpc5_build_endpoint(mapped_u,mapped_v,mapped_w,5,0,selected,256,256,mapped_replacement_u,mapped_replacement_v,mapped_replacement_w) ## i64
z = ffpc5t_expect("mapped 5to4", mapped_rank == 4)

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,95801,0,1,1,1) ## i64
z = ffpc5t_expect("base exact", base_rank == 23 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffpc5t_expect("base export", ffw_export_current(base,base_u,base_v,base_w) == base_rank)
relation_u = i64[9]
relation_v = i64[9]
relation_w = i64[9]
i = 0
while i < 5
  relation_u[i] = mapped_u[i]
  relation_v[i] = mapped_v[i]
  relation_w[i] = mapped_w[i]
  i += 1
i = 0
while i < 4
  relation_u[5 + i] = mapped_replacement_u[i]
  relation_v[5 + i] = mapped_replacement_v[i]
  relation_w[5 + i] = mapped_replacement_w[i]
  i += 1
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = ffcis3_apply_circuit(base_u,base_v,base_w,base_rank,relation_u,relation_v,relation_w,9,shoulder_u,shoulder_v,shoulder_w) ## i64
shoulder = i64[state_size]
shoulder_loaded = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,capacity,95803,0,1,1,1) ## i64
z = ffpc5t_expect("rank32 shoulder exact", shoulder_rank == 32 && shoulder_loaded == 32 && ffw_verify_current_exact(shoulder,n) == 1)

restored_u = i64[capacity]
restored_v = i64[capacity]
restored_w = i64[capacity]
full_meta = i64[14]
restored_rank = ffpc5_search(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,0,0,restored_u,restored_v,restored_w,full_meta) ## i64
restored = i64[state_size]
restored_loaded = ffw_init_terms_cap(restored,restored_u,restored_v,restored_w,restored_rank,n,capacity,95805,0,1,1,1) ## i64
z = ffpc5t_expect("restored full gate", restored_rank == 23 && restored_loaded == 23 && ffw_verify_current_exact(restored,n) == 1)

<< "flipfleet_projective_circuit5_test: all checks passed circuits=" + full_meta[1].to_s() + " endpoints=" + full_meta[4].to_s() + " restored=" + restored_rank.to_s()
