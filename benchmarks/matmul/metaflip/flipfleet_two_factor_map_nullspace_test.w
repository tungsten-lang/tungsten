use flipfleet_two_factor_map_nullspace

-> fftfnt_expect(label, condition) (String bool) i64
  if !condition
    << "TWO_FACTOR_MAP_NULLSPACE_FAIL " + label
    exit(1)
  1

# A genuinely paired planted relation.  With source->target shear 0->1 on U
# and V, the two complete paired deltas agree:
#
#   (1,2,1) -> (3,2,1)
#   (2,1,1) -> (2,3,1)
#
# The XOR is exact and changes the term set.  The same two selected positions
# are not a dependency under either one-factor map, proving that the paired
# cross term exposes a distinct kernel.
n = 2 ## i64
rank = 2 ## i64
us = i64[rank]
vs = i64[rank]
ws = i64[rank]
us[0] = 1
vs[0] = 2
ws[0] = 1
us[1] = 2
vs[1] = 1
ws[1] = 1
words = ffpa_tensor_words(n) ## i64
tu = i64[rank]
tv = i64[rank]
tw = i64[rank]
deltas = i64[rank * words]
plan = i64[8]
plan[0] = 0
plan[1] = 1
plan[2] = 0
plan[3] = 1
plan[4] = 1
plan[5] = 1
plan[6] = 0
plan[7] = 1
built = fftfn_build_deltas(us, vs, ws, rank, n, plan, tu, tv, tw, deltas) ## i64
fftfnt_expect("complete paired deltas", built == words && tu[0] == 3 && tv[0] == 2 && tu[1] == 2 && tv[1] == 3)
dependencies = i64[rank * ffpan_coeff_words(rank)]
nullspace_meta = i64[4]
nullity = ffpan_nullspace(deltas, rank, words, dependencies, nullspace_meta) ## i64
ids = i64[rank]
made = ffpan_dependency_ids(dependencies, 0, rank, ids) ## i64
fftfnt_expect("paired-only kernel relation", nullity == 1 && made == 2 && ffpa_relation_exact(deltas, ids, made, words) == 1)
fftfnt_expect("paired image changes set", ffpa_selected_image_same_set(us, vs, ws, tu, tv, tw, ids, made) == 0)

single_u = i64[rank * words]
single_v = i64[rank * words]
su = i64[rank]
sv = i64[rank]
sw = i64[rank]
z = ffmfn_build_deltas(us, vs, ws, rank, n, 0, 1, 0, 1, su, sv, sw, single_u) ## i64
z = ffmfn_build_deltas(us, vs, ws, rank, n, 1, 1, 0, 1, su, sv, sw, single_v)
fftfnt_expect("not a U-only relation", ffpa_relation_exact(single_u, ids, made, words) == 0)
fftfnt_expect("not a V-only relation", ffpa_relation_exact(single_v, ids, made, words) == 0)

raw_u = i64[rank]
raw_v = i64[rank]
raw_w = i64[rank]
out_u = i64[rank]
out_v = i64[rank]
out_w = i64[rank]
materialize_meta = i64[3]
endpoint_rank = fftfn_materialize(us, vs, ws, rank, tu, tv, tw, ids, made, raw_u, raw_v, raw_w, out_u, out_v, out_w, materialize_meta) ## i64
fftfnt_expect("paired endpoint materialized", endpoint_rank == rank && out_u[0] == 3 && out_v[0] == 2 && out_u[1] == 2 && out_v[1] == 3)

# Put both sides of the planted relation beside the exact Strassen scheme.
# The rank-11 shoulder is still the 2x2 multiplication tensor.  Transforming
# only the two left-side terms creates two duplicate pairs, which cancel and
# recover rank seven behind a fresh complete tensor gate.
capacity = ffw_default_capacity(n) ## i64
strassen = i64[ffw_state_size(capacity)]
strassen_rank = ffw_load_scheme_cap(strassen, "benchmarks/matmul/metaflip/matmul_2x2_rank7_strassen_gf2.txt", n, capacity, 984001, 0, 1, 1, 1) ## i64
fftfnt_expect("Strassen source exact", strassen_rank == 7 && ffw_verify_best_exact(strassen, n) == 1)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
fftfnt_expect("Strassen export", ffw_export_best(strassen, shoulder_u, shoulder_v, shoulder_w) == strassen_rank)
shoulder_u[7] = 1
shoulder_v[7] = 2
shoulder_w[7] = 1
shoulder_u[8] = 2
shoulder_v[8] = 1
shoulder_w[8] = 1
shoulder_u[9] = 3
shoulder_v[9] = 2
shoulder_w[9] = 1
shoulder_u[10] = 2
shoulder_v[10] = 3
shoulder_w[10] = 1
shoulder_rank = 11 ## i64
shoulder = i64[ffw_state_size(capacity)]
loaded_shoulder = ffw_init_terms_cap(shoulder, shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, capacity, 984003, 0, 1, 1, 1) ## i64
fftfnt_expect("rank-11 shoulder full gate", loaded_shoulder == shoulder_rank && ffw_verify_best_exact(shoulder, n) == 1)
shoulder_tu = i64[capacity]
shoulder_tv = i64[capacity]
shoulder_tw = i64[capacity]
shoulder_deltas = i64[shoulder_rank * words]
fftfnt_expect("shoulder deltas", fftfn_build_deltas(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, plan, shoulder_tu, shoulder_tv, shoulder_tw, shoulder_deltas) == words)
shoulder_ids = i64[2]
shoulder_ids[0] = 7
shoulder_ids[1] = 8
fftfnt_expect("shoulder paired relation", ffpa_relation_exact(shoulder_deltas, shoulder_ids, 2, words) == 1)
shoulder_raw_u = i64[capacity]
shoulder_raw_v = i64[capacity]
shoulder_raw_w = i64[capacity]
shoulder_out_u = i64[capacity]
shoulder_out_v = i64[capacity]
shoulder_out_w = i64[capacity]
shoulder_meta = i64[3]
recovered_rank = fftfn_materialize(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, shoulder_tu, shoulder_tv, shoulder_tw, shoulder_ids, 2, shoulder_raw_u, shoulder_raw_v, shoulder_raw_w, shoulder_out_u, shoulder_out_v, shoulder_out_w, shoulder_meta) ## i64
recovered = i64[ffw_state_size(capacity)]
loaded_recovered = ffw_init_terms_cap(recovered, shoulder_out_u, shoulder_out_v, shoulder_out_w, recovered_rank, n, capacity, 984007, 0, 1, 1, 1) ## i64
fftfnt_expect("paired rank drop full gate", recovered_rank == 7 && shoulder_meta[1] == 2 && loaded_recovered == 7 && ffw_verify_best_exact(recovered, n) == 1)

# Singular paired maps may legitimately erase a selected rank-one term.
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
plan[1] = 2
plan[3] = 0
plan[5] = 2
plan[7] = 0
z = fftfn_build_deltas(zu, zv, zw, 1, n, plan, ztu, ztv, ztw, zd)
fftfnt_expect("paired projection creates zero", z == words && ztu[0] == 0 && ztv[0] == 0 && ztw[0] == 1)

<< "flipfleet_two_factor_map_nullspace_test: all checks passed nullity=" + nullity.to_s() + " planted_rank_drop=" + shoulder_rank.to_s() + "->" + recovered_rank.to_s()
