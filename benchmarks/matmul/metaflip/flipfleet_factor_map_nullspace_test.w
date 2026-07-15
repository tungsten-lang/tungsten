use flipfleet_factor_map_nullspace

-> ffmfnt_expect(label, condition) (String bool) i64
  if !condition
    << "FACTOR_MAP_NULLSPACE_FAIL " + label
    exit(1)
  1

ffmfnt_expect("swap bits", ffmfn_map_factor(1, 0, 0, 2) == 4)
ffmfnt_expect("shear bit", ffmfn_map_factor(1, 1, 0, 2) == 5)
ffmfnt_expect("delete bit", ffmfn_map_factor(5, 2, 0, 0) == 4)
ffmfnt_expect("quotient fold cancels", ffmfn_map_factor(5, 3, 0, 2) == 0)

decode = i64[3]
ffmfnt_expect("family counts", ffmfn_family_operations(4, 0) == 18 && ffmfn_family_operations(4, 1) == 36 && ffmfn_family_operations(4, 2) == 12 && ffmfn_family_operations(4, 3) == 36)
ffmfnt_expect("delete decode", ffmfn_decode(4, 2, 9, decode) == 1 && decode[0] == 2 && decode[1] == 1)

# Two changed terms share their complete shear delta, planting a non-set-stable
# two-term dependency without assuming that phi is a tensor automorphism.
n = 2 ## i64
rank = 2 ## i64
us = i64[rank]
vs = i64[rank]
ws = i64[rank]
us[0] = 1
us[1] = 5
vs[0] = 1
vs[1] = 1
ws[0] = 1
ws[1] = 1
words = ffpa_tensor_words(n) ## i64
tu = i64[rank]
tv = i64[rank]
tw = i64[rank]
deltas = i64[rank * words]
built = ffmfn_build_deltas(us, vs, ws, rank, n, 0, 1, 0, 1, tu, tv, tw, deltas) ## i64
ffmfnt_expect("complete deltas built", built == words && tu[0] == 3 && tu[1] == 7)
dependencies = i64[rank * ffpan_coeff_words(rank)]
meta = i64[4]
nullity = ffpan_nullspace(deltas, rank, words, dependencies, meta) ## i64
ids = i64[rank]
made = ffpan_dependency_ids(dependencies, 0, rank, ids) ## i64
ffmfnt_expect("planted factor-map kernel", nullity == 1 && made == 2 && ffpa_relation_exact(deltas, ids, made, words) == 1)
ffmfnt_expect("planted endpoint changes set", ffpa_selected_image_same_set(us, vs, ws, tu, tv, tw, ids, made) == 0)

# Noninvertible maps may create zero terms; zeros are omitted and duplicate
# pairs cancel under GF(2) parity.
raw_u = i64[4]
raw_v = i64[4]
raw_w = i64[4]
raw_u[0] = 0
raw_v[0] = 1
raw_w[0] = 1
raw_u[1] = 3
raw_v[1] = 5
raw_w[1] = 7
raw_u[2] = 3
raw_v[2] = 5
raw_w[2] = 7
raw_u[3] = 9
raw_v[3] = 11
raw_w[3] = 13
out_u = i64[4]
out_v = i64[4]
out_w = i64[4]
compact_meta = i64[2]
compacted = ffmfn_compact_allow_zero(raw_u, raw_v, raw_w, 4, out_u, out_v, out_w, compact_meta) ## i64
ffmfnt_expect("zero and duplicate compaction", compacted == 1 && out_u[0] == 9 && compact_meta[0] == 1 && compact_meta[1] == 1)

<< "flipfleet_factor_map_nullspace_test: all checks passed nullity=" + nullity.to_s()
