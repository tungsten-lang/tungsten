use ../lib/metaflip/strategies/rank_three_completion

-> ffroc3t_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rank-three completion: " + label
    exit(1)
  1

-> ffroc3t_position(st, u, v, w) (i64[] i64 i64 i64) i64
  position = 0 ## i64
  while position < st[6]
    slot = st[st[50]+position] ## i64
    if st[st[44]+slot] == u && st[st[45]+slot] == v && st[st[46]+slot] == w
      return position
    position += 1
  0 - 1

-> ffroc3t_has_factor(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      return 1
    i += 1
  0

-> ffroc3t_meta_has(meta, u, v, w) (i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < 3
    if meta[11+i*3] == u && meta[12+i*3] == v && meta[13+i*3] == w
      return 1
    i += 1
  0

-> ffroc3t_same(left, right, count) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    if left[i] != right[i]
      return 0
    i += 1
  1

# Reusable d<=3 recognizer workspaces for a 2x2 square factor width.
dim = 4 ## i64
rows = i64[dim*dim]
out_u = i64[3]
out_v = i64[3]
out_w = i64[3]
basis = i64[3*dim]
coeff = i64[dim]
combos = i64[8*dim]
combo_rank = i64[8]
combo_v = i64[24]
combo_w = i64[24]
matrix_work = i64[3*dim]
scratch = i64[24]
decomp = i64[6]
rebuilt = i64[dim*dim]

rank = ffroc3_decompose_slice(rows,dim,out_u,out_v,out_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp) ## i64
z = ffroc3t_expect("zero tensor", rank == 0 && ffroc3_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1) ## i64

z = ffroc_toggle_slice(rows,9,10,12,dim)
rank = ffroc3_decompose_slice(rows,dim,out_u,out_v,out_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp)
z = ffroc3t_expect("rank-one tensor", rank == 1 && ffroc3_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1)

z = ffroc_toggle_slice(rows,1,2,4,dim)
rank = ffroc3_decompose_slice(rows,dim,out_u,out_v,out_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp)
z = ffroc3t_expect("rank-two tensor", rank == 2 && ffroc3_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1)

z = ffroc_toggle_slice(rows,2,1,2,dim)
rank = ffroc3_decompose_slice(rows,dim,out_u,out_v,out_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp)
z = ffroc3t_expect("rank-three tensor", rank == 3 && ffroc3_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1)

# One U factor carrying a matrix-rank-three VxW slice exercises d=1.
z = ffroc_clear(rows,dim*dim)
z = ffroc_toggle_slice(rows,1,1,1,dim)
z = ffroc_toggle_slice(rows,1,2,2,dim)
z = ffroc_toggle_slice(rows,1,4,4,dim)
rank = ffroc3_decompose_slice(rows,dim,out_u,out_v,out_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp)
z = ffroc3t_expect("d1 matrix rank three", rank == 3 && decomp[0] == 1 && decomp[1] == 10 && ffroc3_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1)

# A genuine d=2 weight-three relation: A=X+Z, B=Y+Z, while A, B, and
# A+B all have matrix rank two.  No two-matrix direct basis can score <=3.
z = ffroc_clear(rows,dim*dim)
z = ffroc_toggle_slice(rows,1,1,1,dim)
z = ffroc_toggle_slice(rows,2,2,2,dim)
z = ffroc_toggle_slice(rows,3,4,4,dim)
rank = ffroc3_decompose_slice(rows,dim,out_u,out_v,out_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp)
z = ffroc3t_expect("d2 weight-three identity", rank == 3 && decomp[0] == 2 && decomp[1] == 29 && decomp[4] > 0 && ffroc3_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1)

# Three independent slices require the exhaustive GL(3,2) path.
z = ffroc_clear(rows,dim*dim)
z = ffroc_toggle_slice(rows,1,1,1,dim)
z = ffroc_toggle_slice(rows,2,2,2,dim)
z = ffroc_toggle_slice(rows,4,4,4,dim)
rank = ffroc3_decompose_slice(rows,dim,out_u,out_v,out_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp)
z = ffroc3t_expect("d3 GL decomposition", rank == 3 && decomp[0] == 3 && decomp[1] == 30 && decomp[3] > 0 && decomp[3] <= 168 && ffroc3_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1)

# Four independent U slices reject immediately.
z = ffroc_clear(rows,dim*dim)
z = ffroc_toggle_slice(rows,1,1,1,dim)
z = ffroc_toggle_slice(rows,2,2,2,dim)
z = ffroc_toggle_slice(rows,4,4,4,dim)
z = ffroc_toggle_slice(rows,8,8,8,dim)
rank = ffroc3_decompose_slice(rows,dim,out_u,out_v,out_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp)
z = ffroc3t_expect("rank-four flattening adversary", rank < 0 && decomp[0] == 4)

# A d=3 rank-four tensor has no rank-one GL basis.  The negative path must
# inspect all 168 ordered bases rather than trusting one presentation.
z = ffroc_clear(rows,dim*dim)
z = ffroc_toggle_slice(rows,1,1,1,dim)
z = ffroc_toggle_slice(rows,2,2,2,dim)
z = ffroc_toggle_slice(rows,4,4,4,dim)
z = ffroc_toggle_slice(rows,7,8,8,dim)
rank = ffroc3_decompose_slice(rows,dim,out_u,out_v,out_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp)
z = ffroc3t_expect("d3 exhaustive GL adversary", rank < 0 && decomp[0] == 3 && decomp[3] == 168)

# The corrected rank-one cross-rectangle identity is independent of matrix
# width.  Exercise high bits in both factors at the maximum supported width.
wide = 62 ## i64
wide_combos = i64[8*wide]
wide_combo_v = i64[24]
wide_combo_w = i64[24]
av = (1 << 61) | 1 ## i64
aw = (1 << 60) | 2 ## i64
bv = (1 << 59) | 4 ## i64
bw = (1 << 58) | 8 ## i64
row = 0 ## i64
while row < wide
  if ((av >> row) & 1) != 0
    wide_combos[wide+row] = aw
  if ((bv >> row) & 1) != 0
    wide_combos[2*wide+row] = bw
  row += 1
wide_combo_v[3] = av
wide_combo_w[3] = aw
wide_combo_v[6] = bv
wide_combo_w[6] = bw
wide_u = i64[3]
wide_v = i64[3]
wide_w = i64[3]
wide_matrix_work = i64[3*wide]
wide_scratch = i64[24]
wide_meta = i64[6]
rank = ffroc3_d2_rank_one_cross(wide_combos,1,2,1,2,wide,wide_combo_v,wide_combo_w,wide_u,wide_v,wide_w,wide_matrix_work,wide_scratch,wide_meta)
wide_rows = i64[wide*wide]
wide_rebuilt = i64[wide*wide]
z = ffroc_toggle_slice(wide_rows,1,av,aw,wide)
z = ffroc_toggle_slice(wide_rows,2,bv,bw,wide)
z = ffroc3t_expect("width-62 cross rectangle", rank == 3 && wide_meta[4] >= 1 && ffroc3_verify_slice(wide_rows,wide,wide_u,wide_v,wide_w,rank,wide_rebuilt) == 1)

# Last-leaf C(16,6) plant.  The selected ten terms are six unchanged B terms,
# q2, q3, and the two exact children of q1.  The final six pool entries are B.
# Therefore the last residual is exactly q1+q2+q3; all three base terms are
# absent from the pool and must be synthesized to recover rank 23.
root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
n3 = 3 ## i64
cap3 = ffw_default_capacity(n3) ## i64
state_size = ffw_state_size(cap3) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,root+"matmul_3x3_rank23_d139_gf2.txt",n3,cap3,97001,0,1,1,1) ## i64
z = ffroc3t_expect("3x3 source", base_rank == 23 && ffw_verify_current_exact(base,n3) == 1)
base_u = i64[cap3]
base_v = i64[cap3]
base_w = i64[cap3]
z = ffw_export_current(base,base_u,base_v,base_w)
z = ffroc3t_expect("pinned q fixtures", base_u[0] == 25 && base_v[0] == 6 && base_w[0] == 16 && base_u[1] == 7 && base_v[1] == 128 && base_w[1] == 7 && base_u[2] == 80 && base_v[2] == 22 && base_w[2] == 304)

shoulder_u = i64[cap3]
shoulder_v = i64[cap3]
shoulder_w = i64[cap3]
shoulder_rank = 0 ## i64
i = 1 ## i64
while i < base_rank
  shoulder_u[shoulder_rank] = base_u[i]
  shoulder_v[shoulder_rank] = base_v[i]
  shoulder_w[shoulder_rank] = base_w[i]
  shoulder_rank += 1
  i += 1
shoulder_u[shoulder_rank] = 1
shoulder_v[shoulder_rank] = 6
shoulder_w[shoulder_rank] = 16
shoulder_rank += 1
shoulder_u[shoulder_rank] = 24
shoulder_v[shoulder_rank] = 6
shoulder_w[shoulder_rank] = 16
shoulder_rank += 1
shoulder = i64[state_size]
loaded = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n3,cap3,97003,0,1,1,1) ## i64
z = ffroc3t_expect("single-split rank-24 shoulder", loaded == 24 && ffw_verify_current_exact(shoulder,n3) == 1)

selected = i64[10]
selected[0] = ffroc3t_position(shoulder,1,6,16)
selected[1] = ffroc3t_position(shoulder,24,6,16)
selected[2] = ffroc3t_position(shoulder,base_u[1],base_v[1],base_w[1])
selected[3] = ffroc3t_position(shoulder,base_u[2],base_v[2],base_w[2])
i = 0
while i < 6
  selected[4+i] = ffroc3t_position(shoulder,base_u[3+i],base_v[3+i],base_w[3+i])
  i += 1
i = 0
while i < 10
  z = ffroc3t_expect("selected position " + i.to_s(), selected[i] >= 0)
  i += 1

pool_u = i64[16]
pool_v = i64[16]
pool_w = i64[16]
i = 0
while i < 10
  pool_u[i] = ((i*37+67) & 511) | 1
  pool_v[i] = ((i*53+197) & 511) | 1
  pool_w[i] = ((i*71+263) & 511) | 1
  i += 1
i = 0
while i < 6
  pool_u[10+i] = base_u[3+i]
  pool_v[10+i] = base_v[3+i]
  pool_w[10+i] = base_w[3+i]
  i += 1
z = ffroc3t_expect("last-leaf pool valid", ffroc_pool_valid(pool_u,pool_v,pool_w,16,9) == 1)
z = ffroc3t_expect("q1 absent", ffroc3t_has_factor(pool_u,pool_v,pool_w,16,base_u[0],base_v[0],base_w[0]) == 0)
z = ffroc3t_expect("q2 absent", ffroc3t_has_factor(pool_u,pool_v,pool_w,16,base_u[1],base_v[1],base_w[1]) == 0)
z = ffroc3t_expect("q3 absent", ffroc3t_has_factor(pool_u,pool_v,pool_w,16,base_u[2],base_v[2],base_w[2]) == 0)

source_snapshot = i64[state_size]
i = 0
while i < state_size
  source_snapshot[i] = shoulder[i]
  i += 1
completion = i64[state_size]
meta = i64[28]
hit = ffroc3_search(shoulder,selected,10,pool_u,pool_v,pool_w,16,8008,completion,cap3,97007,meta) ## i64
z = ffroc3t_expect("C(16,6) last-leaf completion", hit == 23 && meta[0] == 8008 && meta[5] >= 1 && meta[8] >= 1 && meta[9] == 1 && meta[10] == 23)
z = ffroc3t_expect("q1 synthesized", ffroc3t_meta_has(meta,base_u[0],base_v[0],base_w[0]) == 1)
z = ffroc3t_expect("q2 synthesized", ffroc3t_meta_has(meta,base_u[1],base_v[1],base_w[1]) == 1)
z = ffroc3t_expect("q3 synthesized", ffroc3t_meta_has(meta,base_u[2],base_v[2],base_w[2]) == 1)
z = ffroc3t_expect("completion independently full-gated", ffw_verify_current_exact(completion,n3) == 1 && ffw_verify_best_exact(completion,n3) == 1)
z = ffroc3t_expect("source byte-for-byte immutable", ffroc3t_same(shoulder,source_snapshot,state_size) == 1)

# Duplicate selections and duplicate pool triples reject before tuple work or
# a full gate, and leave the source byte-for-byte unchanged.
bad_selected = i64[10]
i = 0
while i < 10
  bad_selected[i] = selected[i]
  i += 1
bad_selected[9] = bad_selected[8]
bad_meta = i64[28]
bad_out = i64[state_size]
hit = ffroc3_search(shoulder,bad_selected,10,pool_u,pool_v,pool_w,16,8008,bad_out,cap3,97009,bad_meta)
z = ffroc3t_expect("duplicate selected rejected", hit == 0 && bad_meta[0] == 0 && bad_meta[8] == 0)
pool_u[9] = pool_u[8]
pool_v[9] = pool_v[8]
pool_w[9] = pool_w[8]
hit = ffroc3_search(shoulder,selected,10,pool_u,pool_v,pool_w,16,8008,bad_out,cap3,97011,bad_meta)
z = ffroc3t_expect("duplicate pool rejected", hit == 0 && bad_meta[0] == 0 && bad_meta[8] == 0)
z = ffroc3t_expect("adversaries preserve source", ffroc3t_same(shoulder,source_snapshot,state_size) == 1 && ffw_verify_view_exact(shoulder,shoulder[44],shoulder[45],shoulder[46],shoulder[50],shoulder[6],n3) == 1)

<< "PASS rank-three completion rank0/1/2/3=1 d1=1 d2-cross62=1 d2-weight3=1 d3-GL=168 last-leaf=8008 synthesized=3 duplicates=2 immutable=1"
