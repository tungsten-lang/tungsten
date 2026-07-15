use flipfleet_affine_4cube

-> ffa4t_expect(label, condition) (String bool) i64
  if !condition
    << "AFFINE_4CUBE_FAIL " + label
    exit(1)
  1

# The analytic sixteen-corner identity.
du = i64[4]
dv = i64[4]
dw = i64[4]
du[0] = 1
du[1] = 2
du[2] = 4
du[3] = 8
dv[0] = 2
dv[1] = 4
dv[2] = 8
dv[3] = 16
dw[0] = 4
dw[1] = 8
dw[2] = 16
dw[3] = 32
circuit_u = i64[16]
circuit_v = i64[16]
circuit_w = i64[16]
count = ffa4_fill(16,32,64,du,dv,dw,circuit_u,circuit_v,circuit_w) ## i64
z = ffa4t_expect("sixteen corners", count == 16)
z = ffa4t_expect("zero relation", ffa4_zero_relation(circuit_u,circuit_v,circuit_w,count) == 1)

# Add a collision-free mapped zero circuit to the exact 3x3 scheme.  The
# five-anchor search must rediscover a fully live four-flat and remove it.
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,95401,0,1,1,1) ## i64
z = ffa4t_expect("base exact", base_rank == 23 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffa4t_expect("base export", ffw_export_current(base,base_u,base_v,base_w) == base_rank)

du[0] = 1
du[1] = 2
du[2] = 4
du[3] = 8
dv[0] = 1
dv[1] = 16
dv[2] = 32
dv[3] = 64
dw[0] = 1
dw[1] = 2
dw[2] = 8
dw[3] = 16
z = ffa4t_expect("mapped circuit", ffa4_fill(256,128,64,du,dv,dw,circuit_u,circuit_v,circuit_w) == 16 && ffa4_zero_relation(circuit_u,circuit_v,circuit_w,16) == 1)
table = i32[ffcis_table_capacity(base_rank)]
z = ffcis_build_table(base_u,base_v,base_w,base_rank,table)
collisions = 0 ## i64
i = 0 ## i64
while i < 16
  if ffcis_lookup(base_u,base_v,base_w,table,circuit_u[i],circuit_v[i],circuit_w[i]) >= 0
    collisions += 1
  i += 1
z = ffa4t_expect("collision free", collisions == 0)

shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = ffcis3_apply_circuit(base_u,base_v,base_w,base_rank,circuit_u,circuit_v,circuit_w,16,shoulder_u,shoulder_v,shoulder_w) ## i64
shoulder = i64[state_size]
loaded = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,capacity,95403,0,1,1,1) ## i64
z = ffa4t_expect("rank39 shoulder exact", shoulder_rank == 39 && loaded == 39 && ffw_verify_current_exact(shoulder,n) == 1)

found_u = i64[16]
found_v = i64[16]
found_w = i64[16]
meta = i64[12]
found = ffa4_search(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,0,0,found_u,found_v,found_w,meta) ## i64
z = ffa4t_expect("full cube recovered", found == 16 && meta[3] == 16 && meta[4] == 0 - 16 && ffa4_zero_relation(found_u,found_v,found_w,found) == 1)
restored_u = i64[capacity]
restored_v = i64[capacity]
restored_w = i64[capacity]
restored_rank = ffcis3_apply_circuit(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,found_u,found_v,found_w,found,restored_u,restored_v,restored_w) ## i64
restored = i64[state_size]
restored_loaded = ffw_init_terms_cap(restored,restored_u,restored_v,restored_w,restored_rank,n,capacity,95405,0,1,1,1) ## i64
z = ffa4t_expect("restored full gate", restored_rank == 23 && restored_loaded == 23 && ffw_verify_current_exact(restored,n) == 1)

<< "flipfleet_affine_4cube_test: all checks passed bases=" + meta[0].to_s() + " overlap=" + meta[3].to_s() + " delta=" + meta[4].to_s()
