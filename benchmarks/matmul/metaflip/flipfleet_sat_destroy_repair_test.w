use flipfleet_sat_destroy_repair

-> ffsdrt_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

# A planted 2->1 merge.  Joint-support compression is nontrivial on U.
su = i64[2]
sv = i64[2]
sw = i64[2]
su[0] = 1
su[1] = 2
sv[0] = 4
sv[1] = 4
sw[0] = 8
sw[1] = 8
out_u = i64[2]
out_v = i64[2]
out_w = i64[2]
meta = i64[12]
found = ffsdr_internal_rank1(su, sv, sw, 2, 4, 4, 4, out_u, out_v, out_w, meta) ## i64
z = ffsdrt_expect("deterministic planted 2->1", found == 1 && out_u[0] == 3 && out_v[0] == 4 && out_w[0] == 8) ## i64

# Two independent diagonal atoms have tensor rank two, not one.
unsat_u = i64[2]
unsat_v = i64[2]
unsat_w = i64[2]
unsat_u[0] = 1
unsat_v[0] = 1
unsat_w[0] = 1
unsat_u[1] = 2
unsat_v[1] = 2
unsat_w[1] = 2
unsat_out_u = i64[2]
unsat_out_v = i64[2]
unsat_out_w = i64[2]
unsat_meta = i64[12]
z = ffsdrt_expect("known tiny rank-one UNSAT", ffsdr_internal_rank1(unsat_u, unsat_v, unsat_w, 2, 2, 2, 2, unsat_out_u, unsat_out_v, unsat_out_w, unsat_meta) == 0)

# Inspect exact CNF dimensions: support 2x1x1, one requested term gives six
# primary bits/products and ten clauses (four AND + one parity per cell).
uc = i64[4]
vc = i64[4]
wc = i64[4]
lu = i64[2]
lv = i64[2]
lw = i64[2]
target = i64[1]
cnf_meta = i64[12]
z = ffsdrt_expect("window prepares", ffsdr_prepare_window(su, sv, sw, 2, 4, 4, 4, uc, vc, wc, lu, lv, lw, target, cnf_meta) == 1)
cnf = ffsdr_emit_cnf(target, cnf_meta[0], cnf_meta[1], cnf_meta[2], 1, 64, cnf_meta)
z = ffsdrt_expect("Brent CNF header exact", cnf != nil && cnf.starts_with?("p cnf 6 10\n") && cnf_meta[4] == 6 && cnf_meta[5] == 10)

# A real external Z3 process must recover the planted model and prove the tiny
# negative instance UNSAT.  The test machine used by the fleet ships z3; the
# deterministic checks above remain the no-solver oracle.
if system("command -v z3 >/dev/null 2>&1")
  ext_u = i64[2]
  ext_v = i64[2]
  ext_w = i64[2]
  ext_meta = i64[12]
  ext = ffsdr_solve_selected_external(su, sv, sw, 2, 1, 4, 4, 4, "z3", 10, "/tmp/ffsdr_planted", ext_u, ext_v, ext_w, ext_meta) ## i64
  z = ffsdrt_expect("external SAT recovery", ext == 1 && ext_meta[6] == 1 && ext_meta[9] == 1 && ext_u[0] == 3)
  neg_u = i64[2]
  neg_v = i64[2]
  neg_w = i64[2]
  neg_meta = i64[12]
  neg = ffsdr_solve_selected_external(unsat_u, unsat_v, unsat_w, 2, 1, 2, 2, 2, "z3", 10, "/tmp/ffsdr_unsat", neg_u, neg_v, neg_w, neg_meta) ## i64
  z = ffsdrt_expect("external known UNSAT", neg == 0 && neg_meta[6] == 0 - 1)

  # Exercise the parity-chain half of the Brent encoding with a planted 3->2
  # query, not only the degenerate one-slot unit-clause case above.
  tri_u = i64[3]
  tri_v = i64[3]
  tri_w = i64[3]
  tri_u[0] = 1
  tri_v[0] = 4
  tri_w[0] = 8
  tri_u[1] = 2
  tri_v[1] = 4
  tri_w[1] = 8
  tri_u[2] = 4
  tri_v[2] = 2
  tri_w[2] = 1
  tri_out_u = i64[3]
  tri_out_v = i64[3]
  tri_out_w = i64[3]
  tri_meta = i64[12]
  tri = ffsdr_solve_selected_external(tri_u, tri_v, tri_w, 3, 2, 4, 4, 4, "z3", 10, "/tmp/ffsdr_parity", tri_out_u, tri_out_v, tri_out_w, tri_meta) ## i64
  z = ffsdrt_expect("external 3->2 parity-chain SAT", tri == 2 && tri_meta[6] == 1 && tri_meta[9] == 1 && tri_meta[5] > 0)

# Model parsing rejects incomplete assignments instead of defaulting missing
# variables to false.
bad_u = i64[1]
bad_v = i64[1]
bad_w = i64[1]
z = ffsdrt_expect("corrupt partial model rejected", ffsdr_decode_dimacs("s SATISFIABLE\nv 1 -2 0\n", 1, 2, 1, 1, bad_u, bad_v, bad_w) == 0)

# The alarm wrapper bounds one uncooperative external process.
timeout_meta = i64[12]
t0 = ccall("__w_clock_ms") ## i64
timed = ffsdr_run_solver("p cnf 1 1\n1 0\n", "perl -e 'sleep 3'", 1, "/tmp/ffsdr_timeout", timeout_meta)
elapsed = ccall("__w_clock_ms") - t0 ## i64
z = ffsdrt_expect("external timeout bounded", timeout_meta[6] == 0 - 2 && elapsed < 2800)

# Full exact splice and rollback on an exact 3x3 shoulder.  Split one naive
# singleton output factor into two nonzero factors, then merge it back.
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
rank = 0 ## i64
i = 0 ## i64
while i < n
  j = 0 ## i64
  while j < n
    kx = 0 ## i64
    while kx < n
      base_u[rank] = 1 << (i * n + kx)
      base_v[rank] = 1 << (kx * n + j)
      base_w[rank] = 1 << (i * n + j)
      rank += 1
      kx += 1
    j += 1
  i += 1
original_u = base_u[0] ## i64
original_v = base_v[0] ## i64
original_w = base_w[0] ## i64
i = 1
while i < rank
  base_u[i - 1] = base_u[i]
  base_v[i - 1] = base_v[i]
  base_w[i - 1] = base_w[i]
  i += 1
rank -= 1
base_u[rank] = original_u
base_v[rank] = original_v
base_w[rank] = original_w ^ 2
rank += 1
base_u[rank] = original_u
base_v[rank] = original_v
base_w[rank] = 2
rank += 1
state = i64[ffw_state_size(capacity)]
loaded = ffw_init_naive_cap(state, n, capacity, 901, 4, 2, 1000, 250) ## i64
shoulder_rank = loaded ## i64
shoulder_rank = ffw_toggle(state, original_u, original_v, original_w, shoulder_rank)
shoulder_rank = ffw_toggle(state, original_u, original_v, original_w ^ 2, shoulder_rank)
shoulder_rank = ffw_toggle(state, original_u, original_v, 2, shoulder_rank)
state[6] = shoulder_rank
z = ffsdrt_expect("exact planted shoulder", loaded == 27 && shoulder_rank == 28 && ffw_verify_current_exact(state, n) == 1)
live_u = i64[capacity]
live_v = i64[capacity]
live_w = i64[capacity]
live_rank = ffw_export_current(state, live_u, live_v, live_w) ## i64
selected = i64[2]
selected[0] = 0 - 1
selected[1] = 0 - 1
i = 0
while i < live_rank
  if live_u[i] == original_u && live_v[i] == original_v && live_w[i] == (original_w ^ 2)
    selected[0] = i
  if live_u[i] == original_u && live_v[i] == original_v && live_w[i] == 2
    selected[1] = i
  i += 1
z = ffsdrt_expect("shoulder terms located", selected[0] >= 0 && selected[1] >= 0)
merge_u = i64[1]
merge_v = i64[1]
merge_w = i64[1]
merge_u[0] = original_u
merge_v[0] = original_v
merge_w[0] = original_w
applied = ffsdr_apply_current(state, selected, 2, merge_u, merge_v, merge_w, 1) ## i64
z = ffsdrt_expect("full exact splice reduces rank", applied == 27 && ffw_verify_current_exact(state, n) == 1)

# Collision-aware arbitrary-k admission.  Add a two-term flip zero circuit to
# the exact rank-23 scheme and split one live term.  The selected four-term
# subtotal has a three-term replacement containing both unselected circuit
# terms; parity compaction therefore turns nominal 4->3 into rank 28->23.
collision_state = i64[ffw_state_size(capacity)]
collision_rank = ffw_load_scheme_cap(collision_state,"benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt",n,capacity,905,0,1,1,1) ## i64
z = ffsdrt_expect("SAT compact base exact", collision_rank == 23 && ffw_verify_current_exact(collision_state,n) == 1)
split_source_u = 80 ## i64
split_source_v = 22 ## i64
split_source_w = 304 ## i64
split_child_w0 = 16 ## i64
split_child_w1 = 288 ## i64
collision_rank = ffw_toggle(collision_state,split_source_u,split_source_v,split_source_w,collision_rank)
collision_rank = ffw_toggle(collision_state,split_source_u,split_source_v,split_child_w0,collision_rank)
collision_rank = ffw_toggle(collision_state,split_source_u,split_source_v,split_child_w1,collision_rank)
collision_rank = ffw_toggle(collision_state,1,1,1,collision_rank)
collision_rank = ffw_toggle(collision_state,2,2,1,collision_rank)
collision_rank = ffw_toggle(collision_state,3,1,1,collision_rank)
collision_rank = ffw_toggle(collision_state,2,3,1,collision_rank)
collision_state[6] = collision_rank
z = ffsdrt_expect("SAT compact shoulder exact", collision_rank == 28 && ffw_verify_current_exact(collision_state,n) == 1)
collision_live_u = i64[capacity]
collision_live_v = i64[capacity]
collision_live_w = i64[capacity]
collision_live_rank = ffw_export_current(collision_state,collision_live_u,collision_live_v,collision_live_w) ## i64
collision_selected = i64[4]
collision_selected[0] = ffsr_find_candidate_term(collision_live_u,collision_live_v,collision_live_w,collision_live_rank,1,1,1)
collision_selected[1] = ffsr_find_candidate_term(collision_live_u,collision_live_v,collision_live_w,collision_live_rank,2,2,1)
collision_selected[2] = ffsr_find_candidate_term(collision_live_u,collision_live_v,collision_live_w,collision_live_rank,split_source_u,split_source_v,split_child_w0)
collision_selected[3] = ffsr_find_candidate_term(collision_live_u,collision_live_v,collision_live_w,collision_live_rank,split_source_u,split_source_v,split_child_w1)
z = ffsdrt_expect("SAT compact source located", collision_selected[0] >= 0 && collision_selected[1] >= 0 && collision_selected[2] >= 0 && collision_selected[3] >= 0)
collision_out_u = i64[3]
collision_out_v = i64[3]
collision_out_w = i64[3]
collision_out_u[0] = 3
collision_out_v[0] = 1
collision_out_w[0] = 1
collision_out_u[1] = 2
collision_out_v[1] = 3
collision_out_w[1] = 1
collision_out_u[2] = split_source_u
collision_out_v[2] = split_source_v
collision_out_w[2] = split_source_w
collision_applied = ffsdr_apply_current(collision_state,collision_selected,4,collision_out_u,collision_out_v,collision_out_w,3) ## i64
z = ffsdrt_expect("SAT compact external cancellations", collision_applied == 23 && ffw_verify_current_exact(collision_state,n) == 1)

# Rebuild the shoulder, submit a unique but false replacement, and prove the
# post-gate restored byte-equivalent tensor/rank state.
rollback = i64[ffw_state_size(capacity)]
loaded = ffw_init_naive_cap(rollback, n, capacity, 903, 4, 2, 1000, 250)
shoulder_rank = loaded
shoulder_rank = ffw_toggle(rollback, original_u, original_v, original_w, shoulder_rank)
shoulder_rank = ffw_toggle(rollback, original_u, original_v, original_w ^ 2, shoulder_rank)
shoulder_rank = ffw_toggle(rollback, original_u, original_v, 2, shoulder_rank)
rollback[6] = shoulder_rank
live_rank = ffw_export_current(rollback, live_u, live_v, live_w)
selected[0] = 0 - 1
selected[1] = 0 - 1
i = 0
while i < live_rank
  if live_u[i] == original_u && live_v[i] == original_v && live_w[i] == (original_w ^ 2)
    selected[0] = i
  if live_u[i] == original_u && live_v[i] == original_v && live_w[i] == 2
    selected[1] = i
  i += 1
wrong_u = i64[1]
wrong_v = i64[1]
wrong_w = i64[1]
wrong_u[0] = 15
wrong_v[0] = 15
wrong_w[0] = 15
rejected = ffsdr_apply_current(rollback, selected, 2, wrong_u, wrong_v, wrong_w, 1) ## i64
z = ffsdrt_expect("corrupt replacement rolls back", rejected == 0 - 1 && rollback[6] == 28 && ffw_verify_current_exact(rollback, n) == 1)

<< "PASS flipfleet SAT destroy-repair"
