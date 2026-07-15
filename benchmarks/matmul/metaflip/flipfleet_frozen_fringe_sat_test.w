use metaflip_worker
use flipfleet_frozen_fringe_sat
use flipfleet_parent_chord

-> fffst_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

n = 3 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
base = i64[size]
rank = ffw_init_naive_cap(base, n, cap, 401, 0, 1, 1, 1) ## i64
fffst_expect("base exact", rank == 27 && ffw_verify_current_exact(base, n) == 1)

uniform = i64[12]
clustered = i64[12]
fffst_expect("uniform selector", fffsat_select(base, 12, 17, 0, uniform) == 12)
fffst_expect("cluster selector", fffsat_select(base, 12, 17, 1, clustered) == 12)
i = 0 ## i64
while i < 12
  fffst_expect("uniform unique " + i.to_s(), fffsat_selected_contains(uniform, i, uniform[i]) == 0)
  fffst_expect("cluster unique " + i.to_s(), fffsat_selected_contains(clustered, i, clustered[i]) == 0)
  i += 1

# Split one existing term into two children, then let the internal exact rank-1
# repair recover the original term and apply the 2->1 splice globally.
us = i64[cap]
vs = i64[cap]
ws = i64[cap]
z = ffw_export_current(base, us, vs, ws) ## i64
old_u = us[0] ## i64
old_v = vs[0] ## i64
old_w = ws[0] ## i64
split = 1 ## i64
if old_u == 1
  split = 2
other = old_u ^ split ## i64
shoulder_rank = rank ## i64
shoulder_rank = ffpc_toggle_plain(us, vs, ws, shoulder_rank, cap, old_u, old_v, old_w)
shoulder_rank = ffpc_toggle_plain(us, vs, ws, shoulder_rank, cap, split, old_v, old_w)
shoulder_rank = ffpc_toggle_plain(us, vs, ws, shoulder_rank, cap, other, old_v, old_w)
shoulder = i64[size]
loaded = ffw_init_terms_cap(shoulder, us, vs, ws, shoulder_rank, n, cap, 409, 0, 1, 1, 1) ## i64
fffst_expect("split shoulder exact", loaded == 28 && ffw_verify_current_exact(shoulder, n) == 1)

cur_u = i64[cap]
cur_v = i64[cap]
cur_w = i64[cap]
z = ffw_export_current(shoulder, cur_u, cur_v, cur_w) ## i64
selected = i64[2]
found = 0 ## i64
i = 0
while i < shoulder_rank
  if cur_v[i] == old_v && cur_w[i] == old_w && (cur_u[i] == split || cur_u[i] == other)
    selected[found] = i
    found += 1
  i += 1
fffst_expect("split children located", found == 2)
su = i64[2]
sv = i64[2]
sw = i64[2]
fffst_expect("selected terms extracted", fffsat_extract(shoulder, selected, 2, su, sv, sw) == 2)
out_u = i64[2]
out_v = i64[2]
out_w = i64[2]
sat_meta = i64[12]
replacement = ffsdr_internal_rank1(su, sv, sw, 2, n * n, n * n, n * n, out_u, out_v, out_w, sat_meta) ## i64
fffst_expect("internal exact repair", replacement == 1 && out_u[0] == old_u && out_v[0] == old_v && out_w[0] == old_w)
applied = ffsdr_apply_current(shoulder, selected, 2, out_u, out_v, out_w, replacement) ## i64
fffst_expect("full splice exact", applied == 27 && ffw_verify_current_exact(shoulder, n) == 1)

# Real 4x4 window sizing exercises the intended 16->15 campaign without
# requiring an external SAT solver in the unit suite.
n4 = 4 ## i64
cap4 = ffw_default_capacity(n4) ## i64
state4 = i64[ffw_state_size(cap4)]
rank4 = ffw_load_scheme_cap(state4, "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", n4, cap4, 419, 0, 1, 1, 1) ## i64
fffst_expect("4x4 frontier exact", rank4 == 47 && ffw_verify_current_exact(state4, n4) == 1)
fringe = i64[16]
fffst_expect("clustered 4x4 fringe", fffsat_select(state4, 16, 421, 1, fringe) == 16)
dimensions = i64[8]
fffst_expect("4x4 query dimensions", fffsat_query_dimensions(state4, fringe, 16, 15, dimensions) == 1)
fffst_expect("4x4 exact CNF bounded", dimensions[0] <= 16 && dimensions[1] <= 16 && dimensions[2] <= 16 && dimensions[3] <= 4096 && dimensions[4] > 0 && dimensions[5] > 0)

<< "frozen fringe SAT tests passed 4x4-support=" + dimensions[0].to_s() + "/" + dimensions[1].to_s() + "/" + dimensions[2].to_s() + " cells=" + dimensions[3].to_s() + " vars=" + dimensions[4].to_s() + " clauses=" + dimensions[5].to_s()
