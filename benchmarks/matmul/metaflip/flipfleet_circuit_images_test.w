use metaflip_worker
use flipfleet_circuit_images

-> ffc_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

-> ffc_test_identity_maps(dimension, maps) (i64 i64[]) i64
  i = 0 ## i64
  while i < 9
    maps[i] = 0
    i += 1
  axis = 0 ## i64
  while axis < 3
    bit = 0 ## i64
    while bit < dimension
      maps[axis * 3 + bit] = 1 << bit
      bit += 1
    axis += 1
  1

-> ffc_test_pack_terms(us, vs, ws, count, packed) (i64[] i64[] i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < count
    packed[i*3] = us[i]
    packed[i*3+1] = vs[i]
    packed[i*3+2] = ws[i]
    i += 1
  count

-> ffc_test_term_in(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count
    if ffc_same_term(us[i],vs[i],ws[i],u,v,w) == 1
      found = 1
    i += 1
  found

# Every bank member covers its advertised cardinality and is an exact
# primitive circuit under the identity embedding.
template_id = 0 ## i64
while template_id < 8
  dimension = ffc_template_dimension(template_id) ## i64
  expected = template_id + 5 ## i64
  maps = i64[9]
  z = ffc_test_identity_maps(dimension,maps) ## i64
  cu = i64[12]
  cv = i64[12]
  cw = i64[12]
  meta = i64[9]
  made = ffc_map_template(template_id,maps,cu,cv,cw,meta) ## i64
  z = ffc_test_expect("template count " + expected.to_s(), made == expected)
  z = ffc_test_expect("template exact primitive " + expected.to_s(), meta[2] == expected-1 && meta[3] == 1 && meta[4] == 1 && meta[5] == 1)
  template_id += 1

# Arbitrary non-coordinate injective maps preserve a five-term circuit.
maps5 = i64[9]
maps5[0] = 5
maps5[1] = 10
maps5[3] = 17
maps5[4] = 34
maps5[6] = 65
maps5[7] = 130
c5u = i64[12]
c5v = i64[12]
c5w = i64[12]
m5 = i64[9]
made5 = ffc_map_template(0,maps5,c5u,c5v,c5w,m5) ## i64
z = ffc_test_expect("arbitrary linear image stays primitive", made5 == 5 && m5[6] == 2 && m5[7] == 2 && m5[8] == 2)

# Recover those maps from corresponding term anchors.  Supplying all circuit
# terms overdetermines the tiny linear systems and checks consistency.
slots5 = i64[5]
packed5 = i64[15]
i = 0 ## i64
while i < 5
  slots5[i] = i
  i += 1
z = ffc_test_pack_terms(c5u,c5v,c5w,5,packed5)
recovered5 = i64[9]
recovered_meta5 = i64[9]
fit5 = ffc_fit_anchors(0,slots5,packed5,5,recovered5,recovered_meta5) ## i64
fit5u = i64[12]
fit5v = i64[12]
fit5w = i64[12]
fit_meta5 = i64[9]
remade5 = ffc_map_template(0,recovered5,fit5u,fit5v,fit5w,fit_meta5) ## i64
same5 = 1 ## i64
i = 0
while i < 5
  if ffc_same_term(c5u[i],c5v[i],c5w[i],fit5u[i],fit5v[i],fit5w[i]) == 0
    same5 = 0
  i += 1
z = ffc_test_expect("anchor fitting recovers complete image", fit5 == 5 && remade5 == 5 && same5 == 1)
packed5[0] = packed5[0] ^ 256
z = ffc_test_expect("inconsistent anchors rejected", ffc_fit_anchors(0,slots5,packed5,5,recovered5,recovered_meta5) == 0)

# A genuinely rank-deficient P image of the eleven-term source circuit remains
# primitive.  This is why singular maps are admitted rather than discarded.
maps11 = i64[9]
maps11[0] = 1
maps11[1] = 2
maps11[2] = 1
maps11[3] = 4
maps11[4] = 8
maps11[5] = 16
maps11[6] = 32
maps11[7] = 64
maps11[8] = 128
c11u = i64[12]
c11v = i64[12]
c11w = i64[12]
m11 = i64[9]
made11 = ffc_map_template(6,maps11,c11u,c11v,c11w,m11) ## i64
z = ffc_test_expect("rank-deficient image can remain primitive", made11 == 11 && m11[6] == 2 && m11[2] == 10)

# The primitive gate rejects a relation containing two proper zero subsets.
# Both halves are valid five-circuits, embedded into disjoint factor bits.
maps5b = i64[9]
maps5b[0] = 256
maps5b[1] = 512
maps5b[3] = 1024
maps5b[4] = 2048
maps5b[6] = 4096
maps5b[7] = 8192
c5bu = i64[12]
c5bv = i64[12]
c5bw = i64[12]
m5b = i64[9]
z = ffc_map_template(0,maps5b,c5bu,c5bv,c5bw,m5b)
nonprim_u = i64[12]
nonprim_v = i64[12]
nonprim_w = i64[12]
i = 0
while i < 5
  nonprim_u[i] = c5u[i]
  nonprim_v[i] = c5v[i]
  nonprim_w[i] = c5w[i]
  nonprim_u[i+5] = c5bu[i]
  nonprim_v[i+5] = c5bv[i]
  nonprim_w[i+5] = c5bw[i]
  i += 1
nonprim_meta = i64[3]
nonprim_rank = ffc_relation_analyze(nonprim_u,nonprim_v,nonprim_w,10,nonprim_meta) ## i64
z = ffc_test_expect("proper-subset circuit rejected", nonprim_meta[1] == 1 && nonprim_meta[2] == 1 && nonprim_rank == 8 && ffc_is_primitive_circuit(nonprim_u,nonprim_v,nonprim_w,10) == 0)

# Full-scheme splice.  Replace one term of the checked-in rank-23 3x3 scheme
# by the three-term side of template 0, producing an exact rank-25 shoulder;
# the circuit operator then replaces those three terms with its two-term side.
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
base = i64[ffw_state_size(capacity)]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,9173,0,1,1,1) ## i64
z = ffc_test_expect("rank-23 base loads", base_rank == 23 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffw_export_current(base,base_u,base_v,base_w)

shoulder_maps = i64[9]
shoulder_maps[0] = base_u[0]
shoulder_maps[1] = 1
if shoulder_maps[1] == base_u[0]
  shoulder_maps[1] = 2
shoulder_maps[3] = base_v[0]
shoulder_maps[4] = 1
shoulder_maps[6] = 1
if shoulder_maps[6] == base_w[0]
  shoulder_maps[6] = 2
shoulder_maps[7] = base_w[0]
shoulder_cu = i64[12]
shoulder_cv = i64[12]
shoulder_cw = i64[12]
shoulder_meta = i64[9]
shoulder_circuit = ffc_map_template(0,shoulder_maps,shoulder_cu,shoulder_cv,shoulder_cw,shoulder_meta) ## i64
z = ffc_test_expect("planted five-circuit materializes", shoulder_circuit == 5)

shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = 0 ## i64
i = 1
while i < base_rank
  shoulder_u[shoulder_rank] = base_u[i]
  shoulder_v[shoulder_rank] = base_v[i]
  shoulder_w[shoulder_rank] = base_w[i]
  shoulder_rank += 1
  i += 1
i = 2
while i < 5
  shoulder_u[shoulder_rank] = shoulder_cu[i]
  shoulder_v[shoulder_rank] = shoulder_cv[i]
  shoulder_w[shoulder_rank] = shoulder_cw[i]
  shoulder_rank += 1
  i += 1
shoulder = i64[ffw_state_size(capacity)]
loaded_shoulder = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,capacity,81173,0,1,1,1) ## i64
z = ffc_test_expect("rank-25 circuit shoulder exact", loaded_shoulder == 25 && ffw_verify_current_exact(shoulder,n) == 1)
spliced_rank = ffc_apply_circuit_current(shoulder,shoulder_cu,shoulder_cv,shoulder_cw,5,28) ## i64
z = ffc_test_expect("five-circuit full splice drops one term", spliced_rank == 24 && ffw_verify_current_exact(shoulder,n) == 1)
z = ffc_test_expect("missing old side rejected without damage", ffc_apply_circuit_current(shoulder,shoulder_cu,shoulder_cv,shoulder_cw,5,28) < 0 && shoulder[6] == 24 && ffw_verify_current_exact(shoulder,n) == 1)

<< "flipfleet_circuit_images_test: all checks passed"
