use flipfleet_three_factor_map_nullspace

-> ff3mt_expect(label, condition) (String bool) i64
  if !condition
    << "THREE_FACTOR_MAP_NULLSPACE_FAIL " + label
    exit(1)
  1

-> ff3mt_fill_plan(operation, source, target, plan) (i64 i64 i64 i64[]) i64
  if plan.size() < 12
    return 0
  axis = 0 ## i64
  while axis < 3
    offset = axis * 4 ## i64
    plan[offset] = axis
    plan[offset + 1] = operation
    plan[offset + 2] = source
    plan[offset + 3] = target
    axis += 1
  1

# A five-position relation which exists only when all three raw factor maps
# act simultaneously.  Let h be the shear bit1 ^= bit0, so h exchanges 1 and
# 3 and fixes 2.  For
#
#   S = {(1,1,1), (1,1,2), (1,2,1), (1,2,2), (3,1,1)}
#
# direct expansion proves XOR(S) = XOR(h tensor h tensor h)(S).  The two
# five-term sets are disjoint.  The same selected positions are not exact for
# any of the three one-factor or three two-factor proper submaps.
n = 2 ## i64
rank = 5 ## i64
us = i64[rank]
vs = i64[rank]
ws = i64[rank]
us[0] = 1
vs[0] = 1
ws[0] = 1
us[1] = 1
vs[1] = 1
ws[1] = 2
us[2] = 1
vs[2] = 2
ws[2] = 1
us[3] = 1
vs[3] = 2
ws[3] = 2
us[4] = 3
vs[4] = 1
ws[4] = 1

words = ffpa_tensor_words(n) ## i64
plan = i64[12]
ff3mt_expect("fill triple shear plan", ff3mt_fill_plan(1, 0, 1, plan) == 1)
tu = i64[rank]
tv = i64[rank]
tw = i64[rank]
deltas = i64[rank * words]
ff3mt_expect("build complete cubic deltas", ff3m_build_deltas(us, vs, ws, rank, n, plan, tu, tv, tw, deltas) == words)
ff3mt_expect("first triple image", tu[0] == 3 && tv[0] == 3 && tw[0] == 3)
ff3mt_expect("last triple image", tu[4] == 1 && tv[4] == 3 && tw[4] == 3)

dependencies = i64[rank * ffpan_coeff_words(rank)]
nullspace_meta = i64[4]
nullity = ffpan_nullspace(deltas, rank, words, dependencies, nullspace_meta) ## i64
ids = i64[rank]
made = ffpan_dependency_ids(dependencies, 0, rank, ids) ## i64
ff3mt_expect("minimal five-position cubic relation", nullity == 1 && made == 5 && ffpa_relation_exact(deltas, ids, made, words) == 1)
ff3mt_expect("cubic image changes selected parity set", ff3m_selected_image_same_parity(us, vs, ws, tu, tv, tw, ids, made) == 0)

# Exclude every proper one/two-factor staging using the same selected support.
proper_tu = i64[rank]
proper_tv = i64[rank]
proper_tw = i64[rank]
proper_deltas = i64[rank * words]
axis = 0 ## i64
while axis < 3
  z = ffmfn_build_deltas(us, vs, ws, rank, n, axis, 1, 0, 1, proper_tu, proper_tv, proper_tw, proper_deltas) ## i64
  ff3mt_expect("not a one-factor relation " + axis.to_s(), z == words && ffpa_relation_exact(proper_deltas, ids, made, words) == 0)
  axis += 1
pair = 0 ## i64
while pair < 3
  paired_plan = i64[8]
  if pair == 0
    paired_plan[0] = 0
    paired_plan[4] = 1
  if pair == 1
    paired_plan[0] = 0
    paired_plan[4] = 2
  if pair == 2
    paired_plan[0] = 1
    paired_plan[4] = 2
  paired_plan[1] = 1
  paired_plan[2] = 0
  paired_plan[3] = 1
  paired_plan[5] = 1
  paired_plan[6] = 0
  paired_plan[7] = 1
  z = fftfn_build_deltas(us, vs, ws, rank, n, paired_plan, proper_tu, proper_tv, proper_tw, proper_deltas)
  ff3mt_expect("not a two-factor relation " + pair.to_s(), z == words && ffpa_relation_exact(proper_deltas, ids, made, words) == 0)
  pair += 1

raw_u = i64[rank]
raw_v = i64[rank]
raw_w = i64[rank]
out_u = i64[rank]
out_v = i64[rank]
out_w = i64[rank]
materialize_meta = i64[3]
endpoint_rank = ff3m_materialize(us, vs, ws, rank, tu, tv, tw, ids, made, raw_u, raw_v, raw_w, out_u, out_v, out_w, materialize_meta) ## i64
ff3mt_expect("rank-neutral five-position endpoint", endpoint_rank == 5 && materialize_meta[0] == 0 && materialize_meta[1] == 0)

# Add both disjoint sides of the relation to Strassen.  The rank-17 shoulder
# still represents 2x2 multiplication.  Applying the triple-map move to S
# makes five duplicate pairs, parity-cancels the entire planted circuit, and
# returns to independently verified rank seven.
capacity = ffw_default_capacity(n) ## i64
strassen = i64[ffw_state_size(capacity)]
strassen_rank = ffw_load_scheme_cap(strassen, "benchmarks/matmul/metaflip/matmul_2x2_rank7_strassen_gf2.txt", n, capacity, 731001, 0, 1, 1, 1) ## i64
ff3mt_expect("Strassen source exact", strassen_rank == 7 && ffw_verify_best_exact(strassen, n) == 1)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
ff3mt_expect("export Strassen", ffw_export_best(strassen, shoulder_u, shoulder_v, shoulder_w) == strassen_rank)
i = 0 ## i64
while i < rank
  shoulder_u[strassen_rank + i] = us[i]
  shoulder_v[strassen_rank + i] = vs[i]
  shoulder_w[strassen_rank + i] = ws[i]
  shoulder_u[strassen_rank + rank + i] = tu[i]
  shoulder_v[strassen_rank + rank + i] = tv[i]
  shoulder_w[strassen_rank + rank + i] = tw[i]
  i += 1
shoulder_rank = strassen_rank + rank + rank ## i64
shoulder = i64[ffw_state_size(capacity)]
loaded_shoulder = ffw_init_terms_cap(shoulder, shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, capacity, 731003, 0, 1, 1, 1) ## i64
ff3mt_expect("rank-17 shoulder full gate", loaded_shoulder == shoulder_rank && ffw_verify_best_exact(shoulder, n) == 1)

shoulder_tu = i64[capacity]
shoulder_tv = i64[capacity]
shoulder_tw = i64[capacity]
shoulder_deltas = i64[shoulder_rank * words]
ff3mt_expect("shoulder cubic deltas", ff3m_build_deltas(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, plan, shoulder_tu, shoulder_tv, shoulder_tw, shoulder_deltas) == words)
shoulder_ids = i64[rank]
i = 0
while i < rank
  shoulder_ids[i] = strassen_rank + i
  i += 1
ff3mt_expect("shoulder selected relation", ffpa_relation_exact(shoulder_deltas, shoulder_ids, rank, words) == 1)
shoulder_raw_u = i64[capacity]
shoulder_raw_v = i64[capacity]
shoulder_raw_w = i64[capacity]
recovered_u = i64[capacity]
recovered_v = i64[capacity]
recovered_w = i64[capacity]
shoulder_meta = i64[3]
recovered_rank = ff3m_materialize(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, shoulder_tu, shoulder_tv, shoulder_tw, shoulder_ids, rank, shoulder_raw_u, shoulder_raw_v, shoulder_raw_w, recovered_u, recovered_v, recovered_w, shoulder_meta) ## i64
recovered = i64[ffw_state_size(capacity)]
loaded_recovered = ffw_init_terms_cap(recovered, recovered_u, recovered_v, recovered_w, recovered_rank, n, capacity, 731007, 0, 1, 1, 1) ## i64
ff3mt_expect("cubic planted rank drop full gate", recovered_rank == 7 && shoulder_meta[1] == 5 && loaded_recovered == 7 && ffw_verify_best_exact(recovered, n) == 1)

# A singular-map parity regression. Deleting bit0 maps U factors 2 and 3 to
# the duplicate pair 2,2. Plain membership sees both images inside the source
# set and would call this unchanged; GF(2) parity correctly sees the duplicate
# cancellation and the missing source term.
collision_u = i64[2]
collision_v = i64[2]
collision_w = i64[2]
collision_u[0] = 2
collision_v[0] = 1
collision_w[0] = 1
collision_u[1] = 3
collision_v[1] = 1
collision_w[1] = 1
collision_tu = i64[2]
collision_tv = i64[2]
collision_tw = i64[2]
collision_tu[0] = 2
collision_tv[0] = 1
collision_tw[0] = 1
collision_tu[1] = 2
collision_tv[1] = 1
collision_tw[1] = 1
collision_ids = i64[2]
collision_ids[0] = 0
collision_ids[1] = 1
ff3mt_expect("membership-only singular quotient is unsafe", ffpa_selected_image_same_set(collision_u, collision_v, collision_w, collision_tu, collision_tv, collision_tw, collision_ids, 2) == 1)
ff3mt_expect("singular duplicate parity detected", ff3m_selected_image_same_parity(collision_u, collision_v, collision_w, collision_tu, collision_tv, collision_tw, collision_ids, 2) == 0)

# Singular maps are legal: deleting the selected coordinate on all axes maps
# this term to the additive zero.
zero_plan = i64[12]
ff3mt_expect("fill triple delete plan", ff3mt_fill_plan(2, 0, 0, zero_plan) == 1)
zu = i64[1]
zv = i64[1]
zw = i64[1]
zu[0] = 1
zv[0] = 1
zw[0] = 1
ztu = i64[1]
ztv = i64[1]
ztw = i64[1]
zd = i64[words]
z = ff3m_build_deltas(zu, zv, zw, 1, n, zero_plan, ztu, ztv, ztw, zd)
ff3mt_expect("triple projection creates zero", z == words && ztu[0] == 0 && ztv[0] == 0 && ztw[0] == 0)

<< "flipfleet_three_factor_map_nullspace_test: all checks passed nullity=" + nullity.to_s() + " planted_rank_drop=" + shoulder_rank.to_s() + "->" + recovered_rank.to_s()
