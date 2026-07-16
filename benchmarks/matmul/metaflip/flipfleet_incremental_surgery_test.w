# Planted regressions plus bounded smokes for the incremental k-surgery
# superstructure (move 2).  Pure CPU, in-process CDCL only.  Run from the
# repo root.
#
# Plants, in order: core-subsumption unit checks; the split-above-Strassen
# anchor at k=2 (the sweep must find the split pair, apply the 2 -> 1
# replacement, and land on exact rank 7 through the publish dance); pure
# Strassen at k=2 (all 21 subsets refuted -- solved + core-killed accounting
# must close exactly, one instance build for the whole sweep, and the
# core-lift factor is reported); and split naive 3x3 at k=2 over a 28-term
# pool (the planted reduction must be found within the subset budget).

use flipfleet_incremental_surgery

-> ffist_expect(label, condition) (String bool) i64
  if !condition
    << "INCREMENTAL_SURGERY_FAIL " + label
    exit(1)
  1

# --- core subsumption unit checks ---------------------------------------------
core_terms = i64[8]
core_signs = i64[8]
in_subset = i64[8]
core_terms[0] = 2
core_signs[0] = 1
core_terms[1] = 5
core_signs[1] = 0
in_subset[2] = 1
in_subset[5] = 0
z = ffist_expect("core subsumes match", ffis_core_subsumes(core_terms, core_signs, 0, 2, in_subset) == 1)
in_subset[5] = 1
z = ffist_expect("core rejects wrong sign", ffis_core_subsumes(core_terms, core_signs, 0, 2, in_subset) == 0)
in_subset[5] = 0
in_subset[2] = 0
z = ffist_expect("core rejects missing member", ffis_core_subsumes(core_terms, core_signs, 0, 2, in_subset) == 0)

# --- planted SAT: the split pair collapses ---------------------------------------
au = i64[16]
av = i64[16]
aw = i64[16]
au[0] = 1
av[0] = 9
aw[0] = 9
au[1] = 8
av[1] = 9
aw[1] = 9
au[2] = 12
av[2] = 1
aw[2] = 12
au[3] = 1
av[3] = 10
aw[3] = 10
au[4] = 8
av[4] = 5
aw[4] = 5
au[5] = 3
av[5] = 8
aw[5] = 3
au[6] = 5
av[6] = 3
aw[6] = 8
au[7] = 10
av[7] = 12
aw[7] = 1
cap2 = ffw_default_capacity(2) ## i64
st = i64[ffw_state_size(cap2)]
z = ffist_expect("anchor init", ffw_init_terms_cap(st, au, av, aw, 8, 2, cap2, 2201, 0, 1, 1, 1) == 8)
meta = i64[20]
hit = ffis_sweep_state(st, 2, 2, 8, 64, 100000, 8, meta) ## i64
z = ffist_expect("planted hit", hit == 7)
z = ffist_expect("planted applied exact", ffw_verify_current_exact(st, 2) == 1 && meta[14] == 1)
z = ffist_expect("planted one build", meta[12] == 1)
z = ffist_expect("planted accounting", meta[4] == meta[5] + meta[9])
<< "INCREMENTAL_PLANT hit=" + hit.to_s() + " enumerated=" + meta[4].to_s() + " solved=" + meta[5].to_s() + " core_killed=" + meta[9].to_s() + " cores=" + meta[10].to_s() + " vars=" + meta[2].to_s() + " clauses=" + meta[3].to_s() + " conflicts=" + meta[11].to_s() + " ms=" + meta[15].to_s()

# --- planted UNSAT: pure Strassen is 2-locally minimal ----------------------------
su = i64[16]
sv = i64[16]
sw = i64[16]
su[0] = 9
sv[0] = 9
sw[0] = 9
su[1] = 12
sv[1] = 1
sw[1] = 12
su[2] = 1
sv[2] = 10
sw[2] = 10
su[3] = 8
sv[3] = 5
sw[3] = 5
su[4] = 3
sv[4] = 8
sw[4] = 3
su[5] = 5
sv[5] = 3
sw[5] = 8
su[6] = 10
sv[6] = 12
sw[6] = 1
st2 = i64[ffw_state_size(cap2)]
z = ffist_expect("strassen init", ffw_init_terms_cap(st2, su, sv, sw, 7, 2, cap2, 2203, 0, 1, 1, 1) == 7)
meta2 = i64[20]
hit2 = ffis_sweep_state(st2, 2, 2, 7, 64, 100000, 7, meta2) ## i64
z = ffist_expect("strassen no hit", hit2 == 0)
z = ffist_expect("strassen still exact", ffw_verify_current_exact(st2, 2) == 1 && ffw_current_rank(st2) == 7)
z = ffist_expect("strassen all subsets covered", meta2[4] == 21)
z = ffist_expect("strassen refutation closes", meta2[7] + meta2[9] == 21 && meta2[6] == 0 && meta2[8] == 0)
z = ffist_expect("strassen one build", meta2[12] == 1)
<< "INCREMENTAL_STRASSEN enumerated=" + meta2[4].to_s() + " solved=" + meta2[5].to_s() + " unsat=" + meta2[7].to_s() + " core_killed=" + meta2[9].to_s() + " cores=" + meta2[10].to_s() + " conflicts=" + meta2[11].to_s() + " ms=" + meta2[15].to_s()

# --- split naive 3x3 over a 28-term pool -------------------------------------------
cap3 = ffw_default_capacity(3) ## i64
st3 = i64[ffw_state_size(cap3)]
r3 = ffw_init_naive_cap(st3, 3, cap3, 2205, 0, 1, 1, 1) ## i64
z = ffist_expect("naive 3x3 rank", r3 == 27)
# Split naive term (0,0,0) = (1,1,1): u = 1 has one bit, split v = 1?  v has
# one bit too -- split w?  All naive factors are single-bit, so split u of a
# composite... instead plant the split by replacing (1,1,1) with the exact
# pair (1,1,3) + (1,1,2): w = 3 ^ 2 = 1.
r3 = ffw_toggle(st3, 1, 1, 1, r3)
r3 = ffw_toggle(st3, 1, 1, 3, r3)
r3 = ffw_toggle(st3, 1, 1, 2, r3)
st3[6] = r3
z = ffist_expect("split naive rank", r3 == 28)
z = ffist_expect("split naive exact", ffw_verify_current_exact(st3, 3) == 1)
meta3 = i64[20]
hit3 = ffis_sweep_state(st3, 3, 2, 28, 400, 100000, 28, meta3) ## i64
z = ffist_expect("split naive hit", hit3 == 27)
z = ffist_expect("split naive exact after", ffw_verify_current_exact(st3, 3) == 1)
<< "INCREMENTAL_NAIVE33 hit=" + hit3.to_s() + " enumerated=" + meta3[4].to_s() + " solved=" + meta3[5].to_s() + " core_killed=" + meta3[9].to_s() + " cores=" + meta3[10].to_s() + " vars=" + meta3[2].to_s() + " clauses=" + meta3[3].to_s() + " conflicts=" + meta3[11].to_s() + " ms=" + meta3[15].to_s()

# --- path driver + publish dance ------------------------------------------------------
anchor_path = "/tmp/ffis_test_anchor.txt"
out_path = "/tmp/ffis_test_out.txt"
stp = i64[ffw_state_size(cap2)]
z = ffist_expect("publish anchor init", ffw_init_terms_cap(stp, au, av, aw, 8, 2, cap2, 2207, 0, 1, 1, 1) == 8)
z = ffist_expect("publish anchor dump", ffw_dump_best(stp, anchor_path) == 8)
metap = i64[20]
hitp = ffis_sweep(anchor_path, 2, 2, 8, 64, 100000, 8, out_path, metap) ## i64
z = ffist_expect("driver hit", hitp == 7)
reload = i64[ffw_state_size(cap2)]
z = ffist_expect("driver output reloads", ffw_load_scheme_cap(reload, out_path, 2, cap2, 2209, 0, 1, 1, 1) == 7)
z = ffist_expect("driver output exact", ffw_verify_best_exact(reload, 2) == 1)

<< "flipfleet_incremental_surgery_test: all checks passed"
