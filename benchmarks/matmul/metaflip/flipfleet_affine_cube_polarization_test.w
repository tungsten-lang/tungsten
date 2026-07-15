use flipfleet_affine_cube_polarization

-> ffacpt_expect(label, condition) (String bool) i64
  if !condition
    << "AFFINE_CUBE_POLARIZATION_FAIL " + label
    exit(1)
  1

-> ffacpt_same_tensor(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  width_u = ffc_max_width(left_u,left_count) ## i64
  candidate = ffc_max_width(right_u,right_count) ## i64
  if candidate > width_u
    width_u = candidate
  width_v = ffc_max_width(left_v,left_count) ## i64
  candidate = ffc_max_width(right_v,right_count)
  if candidate > width_v
    width_v = candidate
  width_w = ffc_max_width(left_w,left_count) ## i64
  candidate = ffc_max_width(right_w,right_count)
  if candidate > width_w
    width_w = candidate
  ui = 0 ## i64
  while ui < width_u
    vi = 0 ## i64
    while vi < width_v
      wi = 0 ## i64
      while wi < width_w
        parity = 0 ## i64
        term = 0 ## i64
        while term < left_count
          if ((left_u[term] >> ui) & 1) != 0 && ((left_v[term] >> vi) & 1) != 0 && ((left_w[term] >> wi) & 1) != 0
            parity = parity ^ 1
          term += 1
        term = 0
        while term < right_count
          if ((right_u[term] >> ui) & 1) != 0 && ((right_v[term] >> vi) & 1) != 0 && ((right_w[term] >> wi) & 1) != 0
            parity = parity ^ 1
          term += 1
        if parity != 0
          return 0
        wi += 1
      vi += 1
    ui += 1
  1

du = i64[3]
dv = i64[3]
dw = i64[3]
du[0] = 1
du[1] = 2
du[2] = 4
dv[0] = 1
dv[1] = 2
dv[2] = 4
dw[0] = 1
dw[1] = 2
dw[2] = 4
circuit_u = i64[14]
circuit_v = i64[14]
circuit_w = i64[14]
circuit_count = ffacp_fill_circuit(8,8,8,du,dv,dw,circuit_u,circuit_v,circuit_w) ## i64
z = ffacpt_expect("fourteen terms", circuit_count == 14)
relation_meta = i64[3]
z = ffacpt_expect("primitive exact circuit", ffacp_relation_analyze(circuit_u,circuit_v,circuit_w,14,relation_meta) == 13 && relation_meta[1] == 1 && ffacp_is_primitive(circuit_u,circuit_v,circuit_w,14) == 1)
correction_u = i64[6]
correction_v = i64[6]
correction_w = i64[6]
i = 0 ## i64
while i < 6
  correction_u[i] = circuit_u[8 + i]
  correction_v[i] = circuit_v[8 + i]
  correction_w[i] = circuit_w[8 + i]
  i += 1
z = ffacpt_expect("eight equals six", ffacpt_same_tensor(circuit_u,circuit_v,circuit_w,8,correction_u,correction_v,correction_w,6) == 1)

# No pair in the primitive relation agrees on two axes.  Thus an ordinary
# compatible-pair flip cannot be the first step of this planted exchange.
compatible = 0 ## i64
i = 0
while i < 13
  j = i + 1 ## i64
  while j < 14
    equal_axes = 0 ## i64
    if circuit_u[i] == circuit_u[j]
      equal_axes += 1
    if circuit_v[i] == circuit_v[j]
      equal_axes += 1
    if circuit_w[i] == circuit_w[j]
      equal_axes += 1
    if equal_axes >= 2
      compatible += 1
    j += 1
  i += 1
z = ffacpt_expect("no ordinary first flip", compatible == 0)

# The repeated-difference closure must discover the direct eight-corner to
# six-permutation rank reduction without being handed its directions.
corners_u = i64[8]
corners_v = i64[8]
corners_w = i64[8]
i = 0
while i < 8
  corners_u[i] = circuit_u[i]
  corners_v[i] = circuit_v[i]
  corners_w[i] = circuit_w[i]
  i += 1
found_u = i64[14]
found_v = i64[14]
found_w = i64[14]
search_meta = i64[24]
found = ffacp_search(corners_u,corners_v,corners_w,8,0,1,0,0,found_u,found_v,found_w,search_meta) ## i64
z = ffacpt_expect("cube discovered", found == 14 && search_meta[16] > 0 && search_meta[9] == 0 - 2 && search_meta[11] == 8 && search_meta[20] == 2)
reduced_u = i64[24]
reduced_v = i64[24]
reduced_w = i64[24]
reduced_rank = ffcis3_apply_circuit(corners_u,corners_v,corners_w,8,found_u,found_v,found_w,found,reduced_u,reduced_v,reduced_w) ## i64
z = ffacpt_expect("planted 8-to-6", reduced_rank == 6 && ffacpt_same_tensor(corners_u,corners_v,corners_w,8,reduced_u,reduced_v,reduced_w,6) == 1)

# A full n^6 regression: add a collision-free mapped circuit to the exact
# 3x3 rank-23 scheme, then recover the base through the frame closure.
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,94501,0,1,1,1) ## i64
z = ffacpt_expect("base exact", base_rank == 23 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffw_export_current(base,base_u,base_v,base_w)

mapped_du = i64[3]
mapped_dv = i64[3]
mapped_dw = i64[3]
mapped_du[0] = 1
mapped_du[1] = 2
mapped_du[2] = 4
mapped_dv[0] = 8
mapped_dv[1] = 16
mapped_dv[2] = 32
mapped_dw[0] = 64
mapped_dw[1] = 1
mapped_dw[2] = 2
mapped_u = i64[14]
mapped_v = i64[14]
mapped_w = i64[14]
mapped_count = ffacp_fill_circuit(256,128,32,mapped_du,mapped_dv,mapped_dw,mapped_u,mapped_v,mapped_w) ## i64
z = ffacpt_expect("mapped circuit", mapped_count == 14 && ffacp_is_primitive(mapped_u,mapped_v,mapped_w,14) == 1)
base_table = i32[ffcis_table_capacity(base_rank)]
z = ffcis_build_table(base_u,base_v,base_w,base_rank,base_table)
collisions = 0 ## i64
i = 0
while i < 14
  if ffcis_lookup(base_u,base_v,base_w,base_table,mapped_u[i],mapped_v[i],mapped_w[i]) >= 0
    collisions += 1
  i += 1
z = ffacpt_expect("collision-free map", collisions == 0)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = ffcis3_apply_circuit(base_u,base_v,base_w,base_rank,mapped_u,mapped_v,mapped_w,14,shoulder_u,shoulder_v,shoulder_w) ## i64
z = ffacpt_expect("rank-37 shoulder", shoulder_rank == 37)
shoulder = i64[state_size]
loaded = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,capacity,94503,0,1,1,1) ## i64
z = ffacpt_expect("shoulder full gate", loaded == 37 && ffw_verify_current_exact(shoulder,n) == 1)
return_u = i64[14]
return_v = i64[14]
return_w = i64[14]
return_meta = i64[24]
return_count = ffacp_search(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,0,1,0,3,return_u,return_v,return_w,return_meta) ## i64
z = ffacpt_expect("full circuit recovered", return_count == 14 && return_meta[9] == 0 - 14 && return_meta[11] == 14)
restored_u = i64[capacity]
restored_v = i64[capacity]
restored_w = i64[capacity]
restored_rank = ffcis3_apply_circuit(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,return_u,return_v,return_w,14,restored_u,restored_v,restored_w) ## i64
restored = i64[state_size]
restored_loaded = ffw_init_terms_cap(restored,restored_u,restored_v,restored_w,restored_rank,n,capacity,94505,0,1,1,1) ## i64
z = ffacpt_expect("restored full gate", restored_rank == 23 && restored_loaded == 23 && ffw_verify_current_exact(restored,n) == 1)

<< "flipfleet_affine_cube_polarization_test: all checks passed primitive_rank=" + relation_meta[0].to_s() + " cubes=" + search_meta[16].to_s() + " planted_delta=" + search_meta[9].to_s() + " full_delta=" + return_meta[9].to_s()
