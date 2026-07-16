# Planted regressions plus a bounded smoke for the symmetry-defect annealed
# walk (move 9).  Pure CPU, no solver, no GPU, no live fleet.  Run from the
# repo root (lexer tables are CWD-relative).
#
# Structure proved here, in order: naive lock structure under the campaign
# rho (3 fixed cubes + 8 free orbits on 3x3; 5 + 40 on 5x5), UNLOCK/LOCK
# round-trips, collision auto-unlock through a manual exact flip, planted
# repair-LOCK reconstituting a broken orbit at cost 1, and a bounded
# gate-every-accept annealed walk from locked naive 3x3.

use flipfleet_sym_anneal

-> ffsat_expect(label, condition) (String bool) i64
  if !condition
    << "SYM_ANNEAL_FAIL " + label
    exit(1)
  1

cap3 = 96 ## i64
sa = i64[ffsa_state_size(cap3)]
snap = i64[ffsa_state_size(cap3)]
tu = i64[64]
tv = i64[64]
tw = i64[64]
eu = i64[96]
ev = i64[96]
ew = i64[96]
gate_state = i64[ffw_state_size(ffw_default_capacity(3))]

# --- naive 3x3: init, exactness, lock structure -------------------------
r = ffsa_init_naive(sa, 3, cap3, 4001) ## i64
z = ffsat_expect("naive 3x3 rank", r == 27)
z = ffsat_expect("naive 3x3 exact", ffsa_gate_current(sa, eu, ev, ew, gate_state, 11) == 1)

made = ffsa_lock_pass(sa, 0) ## i64
z = ffsat_expect("naive 3x3 fully locks", ffsa_locked_terms(sa) == 27)
z = ffsat_expect("naive 3x3 orbit census", ffsa_locked_orbit_count(sa) == 11)
z = ffsat_expect("naive 3x3 lock invariant", ffsa_verify_locks(sa) == 1)

# --- UNLOCK round-trip ---------------------------------------------------
z = ffsa_unlock_random(sa)
z = ffsat_expect("unlock drops terms", ffsa_locked_terms(sa) < 27)
z = ffsat_expect("unlock keeps invariant", ffsa_verify_locks(sa) == 1)
z = ffsat_expect("unlock keeps rank", ffsa_rank(sa) == 27)
z = ffsat_expect("unlock keeps exactness", ffsa_gate_current(sa, eu, ev, ew, gate_state, 13) == 1)
made = ffsa_lock_pass(sa, 0)
z = ffsat_expect("relock restores 27", ffsa_locked_terms(sa) == 27)
z = ffsat_expect("relock invariant", ffsa_verify_locks(sa) == 1)

# --- collision auto-unlock through a manual exact flip -------------------
# Flip pair sharing u = A(0,1) (mask 2): naive terms (0,1,0) = (2,8,1) and
# (0,1,1) = (2,16,2) become (2,8,3) and (2,24,2).  This is the standard
# exact flip identity, so the scheme stays exact; the four toggles touch two
# locked orbits, whose six terms must auto-unlock without breaking the
# invariant.
z = ffsa_toggle(sa, 2, 8, 1)
z = ffsa_toggle(sa, 2, 16, 2)
z = ffsa_toggle(sa, 2, 8, 3)
z = ffsa_toggle(sa, 2, 24, 2)
z = ffsat_expect("flip keeps rank", ffsa_rank(sa) == 27)
z = ffsat_expect("flip keeps exactness", ffsa_gate_current(sa, eu, ev, ew, gate_state, 17) == 1)
z = ffsat_expect("collision auto-unlock", ffsa_locked_terms(sa) == 21)
z = ffsat_expect("auto-unlock invariant", ffsa_verify_locks(sa) == 1)

# --- planted repair-LOCK -------------------------------------------------
# Anchor (1,0,0) = (8, 1, 8): rho image (0,0,1) = (1, 2, 2) is live, but
# rho^2 image (0,1,0) = (2, 8, 1) was flipped away; its nearest free
# candidate is the flip child (2, 8, 3) at diff cost 1.  repair-LOCK must
# toggle the child back to (2,8,1) plus the correction term (2,8,2), lock
# the anchor orbit, spend exactly one correction, and keep the scheme exact.
anchor = ffsa_find(sa, 8, 1, 8) ## i64
z = ffsat_expect("anchor live", anchor >= 0)
fired = ffsa_repair_lock_at(sa, anchor, 4, tu, tv, tw) ## i64
z = ffsat_expect("repair fires", fired == 1)
z = ffsat_expect("repair cost one", ffsa_repair_spent(sa) == 1)
z = ffsat_expect("repair rank", ffsa_rank(sa) == 28)
z = ffsat_expect("repair exact", ffsa_gate_current(sa, eu, ev, ew, gate_state, 19) == 1)
z = ffsat_expect("repair invariant", ffsa_verify_locks(sa) == 1)
z = ffsat_expect("repair restored image", ffsa_find(sa, 2, 8, 1) >= 0)
z = ffsat_expect("repair correction term", ffsa_find(sa, 2, 8, 2) >= 0)
z = ffsat_expect("repair locked anchor orbit", ffsa_locked_terms(sa) == 24)

# --- 5x5 lock census (cheap strong invariant) ----------------------------
cap5 = 256 ## i64
sa5 = i64[ffsa_state_size(cap5)]
r5 = ffsa_init_naive(sa5, 5, cap5, 4003) ## i64
z = ffsat_expect("naive 5x5 rank", r5 == 125)
made = ffsa_lock_pass(sa5, 0)
z = ffsat_expect("naive 5x5 fully locks", ffsa_locked_terms(sa5) == 125)
z = ffsat_expect("naive 5x5 orbit census", ffsa_locked_orbit_count(sa5) == 45)
z = ffsat_expect("naive 5x5 lock invariant", ffsa_verify_locks(sa5) == 1)

# --- bounded annealed walk, every accepted state full-gated --------------
sb = i64[ffsa_state_size(cap3)]
r = ffsa_init_naive(sb, 3, cap3, 4007)
made = ffsa_lock_pass(sb, 0)
sb[13] = 2
cfg = i64[12]
cfg[0] = 50000
cfg[1] = 200
cfg[2] = 50
cfg[3] = 300
cfg[4] = 200
cfg[5] = 12
cfg[6] = 97
cfg[7] = 13
cfg[8] = 31
cfg[9] = 1
cfg[10] = 0 - 1
best = ffsa_anneal(sb, cfg, snap, tu, tv, tw, gate_state, eu, ev, ew) ## i64
z = ffsat_expect("anneal best bounded", best <= 27 && best >= 23)
z = ffsat_expect("anneal gate failures zero", sb[22] == 0)
z = ffsat_expect("anneal best exact", ffsa_gate_best(sb, eu, ev, ew, gate_state, 23) == 1)
z = ffsat_expect("anneal lock invariant", ffsa_verify_locks(sb) == 1)
<< "SYM_ANNEAL_SMOKE n=3 moves=50000 best_rank=" + best.to_s() + " accepted=" + sb[10].to_s() + " proposals=" + sb[23].to_s() + " orbit_moves=" + sb[14].to_s() + " free_moves=" + sb[15].to_s() + " unlocks=" + sb[16].to_s() + " locks=" + sb[17].to_s() + " repair_locks=" + sb[18].to_s() + " singleton_unlocks=" + sb[19].to_s() + " rank_drops=" + sb[20].to_s()

# --- one-shot engine publication dance -----------------------------------
seed_path = "/tmp/ffsa_test_seed.txt"
out_path = "/tmp/ffsa_test_out.txt"
ws = i64[ffw_state_size(ffw_default_capacity(3))]
z = ffsat_expect("seed worker init", ffw_init_naive_cap(ws, 3, ffw_default_capacity(3), 61, 0, 1, 1, 1) == 27)
z = ffsat_expect("seed dump", ffw_dump_best(ws, seed_path) == 27)
meta = i64[16]
hit = ffsa_run_engine(seed_path, out_path, 3, 60000, 4011, meta) ## i64
z = ffsat_expect("engine ran", hit >= 0)
z = ffsat_expect("engine input rank", meta[0] == 27)
z = ffsat_expect("engine best sane", meta[1] >= 23 && meta[1] <= 27)
z = ffsat_expect("engine hit flag consistent", (hit > 0 && meta[14] == 1) || (hit == 0 && meta[14] == 0))
if hit > 0
  reload = i64[ffw_state_size(ffw_default_capacity(3))]
  z = ffsat_expect("engine output reloads", ffw_load_scheme_cap(reload, out_path, 3, ffw_default_capacity(3), 67, 0, 1, 1, 1) == hit)
  z = ffsat_expect("engine output exact", ffw_verify_best_exact(reload, 3) == 1)
<< "SYM_ANNEAL_ENGINE hit=" + hit.to_s() + " best=" + meta[1].to_s() + " density=" + meta[2].to_s() + " locked_end=" + meta[3].to_s() + " repair=" + meta[6].to_s() + " ms=" + meta[15].to_s()

<< "flipfleet_sym_anneal_test: all checks passed"
