use ../lib/metaflip/strategies/rank_two_completion

-> ffroc2t_expect(label, condition) (String bool) i64
  if condition == false
    << "FAIL rank-two completion: " + label
    exit(1)
  1

-> ffroc2t_position(st, u, v, w) (i64[] i64 i64 i64) i64
  position = 0 ## i64
  while position < st[6]
    slot = st[st[50]+position] ## i64
    if st[st[44]+slot] == u && st[st[45]+slot] == v && st[st[46]+slot] == w
      return position
    position += 1
  0 - 1

-> ffroc2t_has_factor(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      return 1
    i += 1
  0

n = 2 ## i64
dim = n * n ## i64
rows = i64[dim*dim]
out_u = i64[2]
out_v = i64[2]
out_w = i64[2]
workspace = i64[dim*4]
factor_work = i64[4]
decomp = i64[3]
rebuilt = i64[dim*dim]
rank = ffroc2_decompose_slice(rows,dim,out_u,out_v,out_w,workspace,factor_work,decomp) ## i64
z = ffroc2t_expect("zero tensor", rank == 0 && ffroc2_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1) ## i64
z = ffroc_toggle_slice(rows,9,10,12,dim)
rank = ffroc2_decompose_slice(rows,dim,out_u,out_v,out_w,workspace,factor_work,decomp)
z = ffroc2t_expect("rank-one tensor", rank == 1 && ffroc2_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1)
z = ffroc_toggle_slice(rows,1,2,4,dim)
rank = ffroc2_decompose_slice(rows,dim,out_u,out_v,out_w,workspace,factor_work,decomp)
z = ffroc2t_expect("rank-two tensor", rank == 2 && ffroc2_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1)

# A shared U factor exercises the matrix-rank-two reduction rather than the
# two-dimensional U-slice branch.
z = ffroc_clear(rows,dim*dim)
z = ffroc_toggle_slice(rows,5,3,5,dim)
z = ffroc_toggle_slice(rows,5,12,10,dim)
rank = ffroc2_decompose_slice(rows,dim,out_u,out_v,out_w,workspace,factor_work,decomp)
z = ffroc2t_expect("rank-one U / matrix-rank-two", rank == 2 && decomp[0] == 1 && ffroc2_verify_slice(rows,dim,out_u,out_v,out_w,rank,rebuilt) == 1)

# Three independent U slices force U-flattening rank three.
z = ffroc_clear(rows,dim*dim)
z = ffroc_toggle_slice(rows,1,1,1,dim)
z = ffroc_toggle_slice(rows,2,2,2,dim)
z = ffroc_toggle_slice(rows,4,4,4,dim)
rank = ffroc2_decompose_slice(rows,dim,out_u,out_v,out_w,workspace,factor_work,decomp)
z = ffroc2t_expect("rank-three U flattening rejected", rank < 0 && decomp[0] == 3)

# A rank-one U flattening can still carry a VxW matrix of rank three.
z = ffroc_clear(rows,dim*dim)
z = ffroc_toggle_slice(rows,1,1,1,dim)
z = ffroc_toggle_slice(rows,1,2,2,dim)
z = ffroc_toggle_slice(rows,1,4,4,dim)
rank = ffroc2_decompose_slice(rows,dim,out_u,out_v,out_w,workspace,factor_work,decomp)
z = ffroc2t_expect("rank-three matrix carrier rejected", rank < 0 && decomp[0] == 1)

# A two-dimensional U slice space for which A, B, and A+B all have matrix
# rank at least two must exhaust all three GF(2) basis variants.
z = ffroc_clear(rows,dim*dim)
z = ffroc_toggle_slice(rows,1,1,1,dim)
z = ffroc_toggle_slice(rows,1,2,2,dim)
z = ffroc_toggle_slice(rows,1,4,4,dim)
z = ffroc_toggle_slice(rows,2,1,2,dim)
z = ffroc_toggle_slice(rows,2,2,4,dim)
z = ffroc_toggle_slice(rows,2,4,1,dim)
rank = ffroc2_decompose_slice(rows,dim,out_u,out_v,out_w,workspace,factor_work,decomp)
z = ffroc2t_expect("all rank-two bases rejected", rank < 0 && decomp[0] == 2 && decomp[2] == 3)

# Last-leaf C(16,6) planted completion.  Split two terms of the 3x3 record.
# A contains four children plus five unchanged terms.  B's last six pool
# entries contain those five unchanged terms plus r=(2,6,16).  The residual
# is exactly (27,6,16)+(7,128,7), neither of which occurs in the pool, so the
# two missing terms must be synthesized and the rank-25 shoulder drops to 24.
root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
n3 = 3 ## i64
cap3 = ffw_default_capacity(n3) ## i64
base = i64[ffw_state_size(cap3)]
base_rank = ffw_load_scheme_cap(base,root+"matmul_3x3_rank23_d139_gf2.txt",n3,cap3,91001,0,1,1,1) ## i64
z = ffroc2t_expect("3x3 source", base_rank == 23 && ffw_verify_current_exact(base,n3) == 1)
base_u = i64[cap3]
base_v = i64[cap3]
base_w = i64[cap3]
z = ffw_export_current(base,base_u,base_v,base_w)
shoulder_u = i64[cap3]
shoulder_v = i64[cap3]
shoulder_w = i64[cap3]
shoulder_rank = 0 ## i64
i = 0 ## i64
while i < base_rank
  first = base_u[i] == 25 && base_v[i] == 6 && base_w[i] == 16 ## bool
  second = base_u[i] == 7 && base_v[i] == 128 && base_w[i] == 7 ## bool
  if first == false && second == false
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
shoulder_u[shoulder_rank] = 1
shoulder_v[shoulder_rank] = 128
shoulder_w[shoulder_rank] = 7
shoulder_rank += 1
shoulder_u[shoulder_rank] = 6
shoulder_v[shoulder_rank] = 128
shoulder_w[shoulder_rank] = 7
shoulder_rank += 1
shoulder = i64[ffw_state_size(cap3)]
loaded = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n3,cap3,91003,0,1,1,1) ## i64
z = ffroc2t_expect("double-split shoulder", loaded == 25 && ffw_verify_current_exact(shoulder,n3) == 1)
selected = i64[9]
selected[0] = ffroc2t_position(shoulder,1,6,16)
selected[1] = ffroc2t_position(shoulder,24,6,16)
selected[2] = ffroc2t_position(shoulder,1,128,7)
selected[3] = ffroc2t_position(shoulder,6,128,7)
i = 0
while i < 5
  selected[i+4] = ffroc2t_position(shoulder,base_u[i+2],base_v[i+2],base_w[i+2])
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
pool_u[10] = 2
pool_v[10] = 6
pool_w[10] = 16
i = 0
while i < 5
  pool_u[i+11] = base_u[i+2]
  pool_v[i+11] = base_v[i+2]
  pool_w[i+11] = base_w[i+2]
  i += 1
z = ffroc2t_expect("last-leaf pool valid", ffroc_pool_valid(pool_u,pool_v,pool_w,16,9) == 1)
z = ffroc2t_expect("first synthesized term absent", ffroc2t_has_factor(pool_u,pool_v,pool_w,16,27,6,16) == 0)
z = ffroc2t_expect("second synthesized term absent", ffroc2t_has_factor(pool_u,pool_v,pool_w,16,7,128,7) == 0)
before_digest = shoulder[37] ## i64
completion = i64[ffw_state_size(cap3)]
meta = i64[19]
hit = ffroc2_search(shoulder,selected,9,pool_u,pool_v,pool_w,16,8008,completion,cap3,91007,meta) ## i64
z = ffroc2t_expect("C(16,6) last-leaf completion", hit == 24 && meta[0] == 8008 && meta[4] == 1 && meta[7] == 1 && meta[8] == 1)
has_first = 0 ## i64
has_second = 0 ## i64
if meta[10] == 27 && meta[11] == 6 && meta[12] == 16
  has_first = 1
if meta[13] == 27 && meta[14] == 6 && meta[15] == 16
  has_first = 1
if meta[10] == 7 && meta[11] == 128 && meta[12] == 7
  has_second = 1
if meta[13] == 7 && meta[14] == 128 && meta[15] == 7
  has_second = 1
z = ffroc2t_expect("both missing factors synthesized", has_first == 1 && has_second == 1)
z = ffroc2t_expect("completion full-gated", ffw_verify_current_exact(completion,n3) == 1 && ffw_verify_best_exact(completion,n3) == 1)
z = ffroc2t_expect("source immutable", shoulder[6] == 25 && shoulder[37] == before_digest && ffw_verify_current_exact(shoulder,n3) == 1)

# Duplicate selections and duplicate pool triples reject before enumeration.
bad_selected = i64[9]
i = 0
while i < 9
  bad_selected[i] = selected[i]
  i += 1
bad_selected[8] = bad_selected[7]
bad_meta = i64[19]
bad_out = i64[ffw_state_size(cap3)]
hit = ffroc2_search(shoulder,bad_selected,9,pool_u,pool_v,pool_w,16,8008,bad_out,cap3,91009,bad_meta)
z = ffroc2t_expect("duplicate selected rejected", hit == 0 && bad_meta[0] == 0 && bad_meta[7] == 0)
pool_u[9] = pool_u[8]
pool_v[9] = pool_v[8]
pool_w[9] = pool_w[8]
hit = ffroc2_search(shoulder,selected,9,pool_u,pool_v,pool_w,16,8008,bad_out,cap3,91011,bad_meta)
z = ffroc2t_expect("duplicate pool rejected", hit == 0 && bad_meta[0] == 0 && bad_meta[7] == 0)
z = ffroc2t_expect("adversaries preserve source", shoulder[6] == 25 && shoulder[37] == before_digest && ffw_verify_current_exact(shoulder,n3) == 1)

<< "PASS rank-two completion rank0/1/2=1 shared-U=1 rank3-adversaries=3 last-leaf=8008 synthesized=2 duplicates=2 immutable=1"
