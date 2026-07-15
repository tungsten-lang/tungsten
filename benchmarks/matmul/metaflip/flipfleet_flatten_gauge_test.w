use metaflip_worker
use flipfleet_flatten_gauge

-> ffgr_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

-> ffgr_test_pack3(us, vs, ws, packed) (i64[] i64[] i64[] i64[]) i64
  ffgr_pack(us,vs,ws,3,packed)

-> ffgr_test_exact_packed(source, old_count, replacement, new_count) (i64[] i64 i64[] i64) i64
  old_u = i64[16]
  old_v = i64[16]
  old_w = i64[16]
  new_u = i64[256]
  new_v = i64[256]
  new_w = i64[256]
  z = ffgr_unpack(source,old_count,old_u,old_v,old_w) ## i64
  z = ffgr_unpack(replacement,new_count,new_u,new_v,new_w)
  ffgr_replacement_exact(old_u,old_v,old_w,old_count,new_u,new_v,new_w,new_count)

-> ffgr_test_same_transform(left_u, left_k, right_u, right_k, k) (i64[] i64[] i64[] i64[] i64) i64
  same = 1 ## i64
  i = 0 ## i64
  while i < k
    if left_u[i] != right_u[i] || left_k[i] != right_k[i]
      same = 0
    i += 1
  same

-> ffgr_test_term_in(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count
    if ffc_same_term(us[i],vs[i],ws[i],u,v,w) == 1
      found = 1
    i += 1
  found

# Identity materialization reproduces a generic three-term window exactly.
source_u = i64[3]
source_v = i64[3]
source_w = i64[3]
source_u[0] = 1
source_u[1] = 2
source_u[2] = 4
source_v[0] = 8
source_v[1] = 16
source_v[2] = 32
source_w[0] = 64
source_w[1] = 128
source_w[2] = 256
source = i64[9]
z = ffgr_test_pack3(source_u,source_v,source_w,source) ## i64
config3 = i64[4]
config3[0] = 3
config3[1] = 0
config3[2] = 2
config3[3] = 16
identity_u = i64[16]
identity_k = i64[16]
z = ffgr_identity(3,identity_u,identity_k)
identity_output = i64[27]
identity_meta = i64[7]
identity_count = ffgr_materialize_packed(source,config3,identity_u,identity_k,identity_output,identity_meta) ## i64
z = ffgr_test_expect("identity repartition", identity_count == 3 && identity_meta[3] == 1 && identity_meta[4] == 1)

# A transvection is its own inverse in both paired coefficient systems.
twice_u = i64[16]
twice_k = i64[16]
z = ffgr_identity(3,twice_u,twice_k)
z = ffgr_transvection(twice_u,twice_k,3,0,1)
z = ffgr_transvection(twice_u,twice_k,3,0,1)
z = ffgr_test_expect("transvection inverse restores identity", ffgr_test_same_transform(identity_u,identity_k,twice_u,twice_k,3) == 1)

# One transvection recovers an ordinary compatible pair flip.  The K columns
# share W, so their XOR remains rank one and rank stays two.
pair_u = i64[3]
pair_v = i64[3]
pair_w = i64[3]
pair_u[0] = 1
pair_v[0] = 4
pair_w[0] = 16
pair_u[1] = 2
pair_v[1] = 8
pair_w[1] = 16
pair_source = i64[6]
z = ffgr_pack(pair_u,pair_v,pair_w,2,pair_source)
pair_config = i64[4]
pair_config[0] = 2
pair_config[1] = 0
pair_config[2] = 2
pair_config[3] = 8
pair_gu = i64[16]
pair_gk = i64[16]
z = ffgr_identity(2,pair_gu,pair_gk)
z = ffgr_transvection(pair_gu,pair_gk,2,0,1)
pair_output = i64[12]
pair_meta = i64[7]
pair_count = ffgr_materialize_packed(pair_source,pair_config,pair_gu,pair_gk,pair_output,pair_meta) ## i64
z = ffgr_test_expect("ordinary flip materializes", pair_count == 2 && pair_meta[3] == 1 && pair_meta[4] == 0 && pair_meta[5] == 1)
z = ffgr_test_expect("ordinary flip exact", ffgr_test_exact_packed(pair_source,2,pair_output,pair_count) == 1)

# A generic pair has matrix-rank two after the same gauge operation and grows
# to three terms.  The exact factorization gate still admits it as a shoulder.
generic_w = i64[3]
generic_w[0] = 16
generic_w[1] = 32
generic_pair = i64[6]
z = ffgr_pack(pair_u,pair_v,generic_w,2,generic_pair)
generic_output = i64[12]
generic_meta = i64[7]
generic_count = ffgr_materialize_packed(generic_pair,pair_config,pair_gu,pair_gk,generic_output,generic_meta) ## i64
z = ffgr_test_expect("rank-two K column expands pair", generic_count == 3 && generic_meta[5] == 2 && generic_meta[3] == 1)
z = ffgr_test_expect("expanded pair exact", ffgr_test_exact_packed(generic_pair,2,generic_output,generic_count) == 1)

# Two sparse gauges coordinate all three terms.  Shared W keeps every reshaped
# K column rank one, yet no original rank-one term survives.
multi_u = i64[3]
multi_v = i64[3]
multi_w = i64[3]
multi_u[0] = 1
multi_u[1] = 2
multi_u[2] = 4
multi_v[0] = 8
multi_v[1] = 16
multi_v[2] = 32
multi_w[0] = 64
multi_w[1] = 64
multi_w[2] = 64
multi_source = i64[9]
z = ffgr_test_pack3(multi_u,multi_v,multi_w,multi_source)
multi_gu = i64[16]
multi_gk = i64[16]
z = ffgr_identity(3,multi_gu,multi_gk)
z = ffgr_transvection(multi_gu,multi_gk,3,0,1)
z = ffgr_transvection(multi_gu,multi_gk,3,1,2)
multi_output = i64[27]
multi_meta = i64[7]
multi_count = ffgr_materialize_packed(multi_source,config3,multi_gu,multi_gk,multi_output,multi_meta) ## i64
z = ffgr_test_expect("planted multi-term gauge", multi_count == 3 && multi_meta[3] == 1 && multi_meta[4] == 0 && multi_meta[5] == 1)
new_multi_u = i64[9]
new_multi_v = i64[9]
new_multi_w = i64[9]
z = ffgr_unpack(multi_output,multi_count,new_multi_u,new_multi_v,new_multi_w)
common = 0 ## i64
i = 0
while i < 3
  common += ffgr_test_term_in(new_multi_u,new_multi_v,new_multi_w,3,multi_u[i],multi_v[i],multi_w[i])
  i += 1
z = ffgr_test_expect("multi-term endpoint distance six", common == 0 && ffgr_test_exact_packed(multi_source,3,multi_output,multi_count) == 1)

# The bounded beam actually enumerates sparse words and returns an exact,
# non-identity candidate; it is not merely a direct-constructor façade.
beam_output = i64[27]
beam_meta = i64[7]
beam_count = ffgr_search_packed(multi_source,config3,beam_output,beam_meta) ## i64
z = ffgr_test_expect("beam enumerates gauge words", beam_count == 3 && beam_meta[1] >= 1 && beam_meta[1] <= 2 && beam_meta[2] >= 6 && beam_meta[3] == 1 && beam_meta[4] == 0)
z = ffgr_test_expect("beam endpoint exact", ffgr_test_exact_packed(multi_source,3,beam_output,beam_count) == 1)

# Malformed unpaired coefficient transforms are caught by exact comparison.
bad_k = i64[16]
bad_u = i64[16]
z = ffgr_identity(3,bad_u,bad_k)
bad_k[0] = bad_k[0] ^ bad_k[1]
bad_output = i64[27]
bad_meta = i64[7]
z = ffgr_test_expect("unpaired transform rejected", ffgr_materialize_packed(source,config3,bad_u,bad_k,bad_output,bad_meta) == 0)

# Full checked-in scheme splice using the known compatible pair at positions
# 3 and 15.  They share U, so flattening on V exposes the ordinary flip.
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
loaded = ffw_load_scheme_cap(state,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,71237,0,1,1,1) ## i64
z = ffgr_test_expect("real rank-23 scheme loads", loaded == 23 && ffw_verify_current_exact(state,n) == 1)
all_u = i64[capacity]
all_v = i64[capacity]
all_w = i64[capacity]
z = ffw_export_current(state,all_u,all_v,all_w)
selected = i64[2]
selected[0] = 3
selected[1] = 15
real_u = i64[3]
real_v = i64[3]
real_w = i64[3]
i = 0
while i < 2
  real_u[i] = all_u[selected[i]]
  real_v[i] = all_v[selected[i]]
  real_w[i] = all_w[selected[i]]
  i += 1
z = ffgr_test_expect("real pair shares U", real_u[0] == real_u[1])
real_source = i64[6]
z = ffgr_pack(real_u,real_v,real_w,2,real_source)
real_config = i64[4]
real_config[0] = 2
real_config[1] = 1
real_config[2] = 1
real_config[3] = 4
real_gu = i64[16]
real_gk = i64[16]
z = ffgr_identity(2,real_gu,real_gk)
z = ffgr_transvection(real_gu,real_gk,2,0,1)
real_output = i64[12]
real_meta = i64[7]
real_count = ffgr_materialize_packed(real_source,real_config,real_gu,real_gk,real_output,real_meta) ## i64
z = ffgr_test_expect("real compatible flip materializes", real_count == 2 && real_meta[3] == 1 && real_meta[4] == 0)
spliced = ffgr_apply_current_packed(state,selected,2,real_output,real_count) ## i64
z = ffgr_test_expect("real full-scheme gauge splice", spliced == 23 && ffw_verify_current_exact(state,n) == 1)
z = ffgr_test_expect("no-op reapply rejected safely", ffgr_apply_current_packed(state,selected,2,real_output,real_count) < 0 && state[6] == 23 && ffw_verify_current_exact(state,n) == 1)

# A locally rank-neutral replacement can be globally rank-lowering when both
# of its output terms collide with unselected live terms.  Plant a generic
# pair-flip zero circuit on the exact 3x3 frontier: the legacy nominal-rank
# splice must reject it, while the compact splice parity-cancels all four
# circuit terms and returns rank 27 to rank 23.
compact_state = i64[ffw_state_size(capacity)]
compact_rank = ffw_load_scheme_cap(compact_state,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,81239,0,1,1,1) ## i64
z = ffgr_test_expect("compact plant source loads", compact_rank == 23 && ffw_verify_current_exact(compact_state,n) == 1)
plant_a_u = i64[2]
plant_a_v = i64[2]
plant_a_w = i64[2]
plant_b_u = i64[2]
plant_b_v = i64[2]
plant_b_w = i64[2]
plant_a_u[0] = 1
plant_a_v[0] = 1
plant_a_w[0] = 1
plant_a_u[1] = 2
plant_a_v[1] = 2
plant_a_w[1] = 1
plant_b_u[0] = 3
plant_b_v[0] = 1
plant_b_w[0] = 1
plant_b_u[1] = 2
plant_b_v[1] = 3
plant_b_w[1] = 1
z = ffgr_test_expect("compact plant relation exact", ffgr_replacement_exact(plant_a_u,plant_a_v,plant_a_w,2,plant_b_u,plant_b_v,plant_b_w,2) == 1)
i = 0
while i < 2
  compact_rank = ffw_toggle(compact_state,plant_a_u[i],plant_a_v[i],plant_a_w[i],compact_rank)
  compact_rank = ffw_toggle(compact_state,plant_b_u[i],plant_b_v[i],plant_b_w[i],compact_rank)
  i += 1
compact_state[6] = compact_rank
z = ffgr_test_expect("compact zero-circuit shoulder", compact_rank == 27 && ffw_verify_current_exact(compact_state,n) == 1)
compact_selected = i64[2]
compact_slot = ffw_find_term(compact_state,plant_a_u[0],plant_a_v[0],plant_a_w[0]) ## i64
compact_selected[0] = compact_state[compact_state[51]+compact_slot]
compact_slot = ffw_find_term(compact_state,plant_a_u[1],plant_a_v[1],plant_a_w[1])
compact_selected[1] = compact_state[compact_state[51]+compact_slot]
compact_replacement = i64[6]
z = ffgr_pack(plant_b_u,plant_b_v,plant_b_w,2,compact_replacement)
z = ffgr_test_expect("legacy splice rejects external collisions", ffgr_apply_current_packed(compact_state,compact_selected,2,compact_replacement,2) < 0 && compact_state[6] == 27)
compact_result = ffgr_apply_current_packed_compact(compact_state,compact_selected,2,compact_replacement,2) ## i64
z = ffgr_test_expect("compact splice consumes external collisions", compact_result == 23 && compact_state[6] == 23 && ffw_verify_current_exact(compact_state,n) == 1)

# The context-aware beam must actively prefer such collisions rather than
# returning whichever locally cheapest transform happened to be first.
compact_source = i64[6]
z = ffgr_pack(plant_a_u,plant_a_v,plant_a_w,2,compact_source)
compact_config = i64[4]
compact_config[0] = 2
compact_config[1] = 0
compact_config[2] = 2
compact_config[3] = 8
baseline_replacement = i64[12]
baseline_meta = i64[7]
baseline_count = ffgr_search_packed(compact_source,compact_config,baseline_replacement,baseline_meta) ## i64
z = ffgr_test_expect("compact beam baseline exists", baseline_count == 2)
compact_external_u = i64[2]
compact_external_v = i64[2]
compact_external_w = i64[2]
z = ffgr_unpack(baseline_replacement,2,compact_external_u,compact_external_v,compact_external_w)
compact_beam_output = i64[12]
compact_beam_meta = i64[8]
compact_beam_count = ffgr_search_compact_packed(compact_source,compact_config,compact_external_u,compact_external_v,compact_external_w,2,compact_beam_output,compact_beam_meta) ## i64
z = ffgr_test_expect("compact beam rewards external cancellation", compact_beam_count == 2 && compact_beam_meta[6] == 2 && compact_beam_meta[3] == 1 && compact_beam_meta[4] == 0)

<< "flipfleet_flatten_gauge_test: all checks passed"
