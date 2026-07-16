# Planted regressions plus bounded probes for the cyclic-sandwich ansatz
# (move 3).  Pure CPU, in-process CDCL only.  Run from the repo root.
#
# Plants, in order: shift order and position-map units (g^d = id); naive
# closure under the (1,1,1) shift sandwich; the <2,2,2> (k=4, f=0) rank-8
# cell is SAT with a gated witness (naive is one); the (3,1) rank-7 cell is
# an honest verdict (a C2-sandwich-invariant rank-7 may or may not exist);
# the <3,3,3> (9,0) rank-27 encoding is validated by a pinned naive-witness
# control (unit clauses; SAT by pure propagation, gates at 27); and the
# unpinned (9,0) plus the rank-26 (8,2) cells run as budget-bounded honest
# probes.

use flipfleet_sandwich_ansatz

-> ffsat2_expect(label, condition) (String bool) i64
  if !condition
    << "SANDWICH_ANSATZ_FAIL " + label
    exit(1)
  1

# --- units ---------------------------------------------------------------------
z = ffsat2_expect("order 2", ffsan_order(2, 1, 1, 1) == 2)
z = ffsat2_expect("order 3", ffsan_order(3, 1, 1, 1) == 3)
z = ffsat2_expect("order mixed", ffsan_order(3, 1, 0, 0) == 3 && ffsan_order(2, 0, 1, 1) == 2)
mask = 141 ## i64
z = ffsat2_expect("shift round trip", ffsan_shift_mask(ffsan_shift_mask(mask, 3, 1, 1, 1), 3, 1, 1, 1) == ffsan_shift_mask(mask, 3, 2, 1, 1))
z = ffsat2_expect("full cycle identity", ffsan_shift_mask(mask, 3, 3, 1, 1) == mask)

# --- naive closure under the shift sandwich ---------------------------------------
nu = i64[16]
nv = i64[16]
nw = i64[16]
nu[0] = 1
nv[0] = 1
nw[0] = 1
nu[1] = 1
nv[1] = 2
nw[1] = 2
nu[2] = 2
nv[2] = 4
nw[2] = 1
nu[3] = 2
nv[3] = 8
nw[3] = 2
nu[4] = 4
nv[4] = 1
nw[4] = 4
nu[5] = 4
nv[5] = 2
nw[5] = 8
nu[6] = 8
nv[6] = 4
nw[6] = 4
nu[7] = 8
nv[7] = 8
nw[7] = 8
i = 0 ## i64
closed = 1 ## i64
while i < 8
  su = ffsan_shift_mask(nu[i], 2, 1, 1, 1) ## i64
  sv = ffsan_shift_mask(nv[i], 2, 1, 1, 1) ## i64
  sw = ffsan_shift_mask(nw[i], 2, 1, 1, 1) ## i64
  found = 0 ## i64
  j = 0 ## i64
  while j < 8
    if nu[j] == su && nv[j] == sv && nw[j] == sw
      found = 1
    j += 1
  if found == 0
    closed = 0
  i += 1
z = ffsat2_expect("naive 2x2 closed under g", closed == 1)

# --- <2,2,2> existence cells --------------------------------------------------------
out_u = i64[64]
out_v = i64[64]
out_w = i64[64]
meta = i64[16]
rank8 = ffsan_solve(2, 1, 1, 1, 4, 0, 200000, 6601, out_u, out_v, out_w, meta) ## i64
z = ffsat2_expect("(4,0) rank-8 SAT", meta[3] == 1)
z = ffsat2_expect("(4,0) witness gates", meta[7] == 1 && rank8 >= 7 && rank8 <= 8)
<< "ANSATZ_CELL n=2 g=(1,1,1) k=4 f=0 rank=" + rank8.to_s() + " vars=" + meta[1].to_s() + " clauses=" + meta[2].to_s() + " conflicts=" + meta[4].to_s() + " ms=" + meta[8].to_s()

rank7 = ffsan_solve(2, 1, 1, 1, 3, 1, 400000, 6603, out_u, out_v, out_w, meta) ## i64
label7 = "indeterminate" ## String
if meta[3] == 1
  label7 = "sat"
if meta[3] == 0 - 1
  label7 = "certified-unsat-cell"
z = ffsat2_expect("(3,1) probe terminates", rank7 >= 0)
if rank7 > 0
  z = ffsat2_expect("(3,1) hit gates", meta[7] == 1 && rank7 == 7)
<< "ANSATZ_CELL n=2 g=(1,1,1) k=3 f=1 rank7 verdict=" + label7 + " rank=" + rank7.to_s() + " conflicts=" + meta[4].to_s() + " ms=" + meta[8].to_s()

# --- <3,3,3> pinned naive-witness encoding control -----------------------------------
# Orbit representatives of naive 3x3 under (1,1,1): the nine terms (0,j,k):
# u = 1 << j, v = 1 << (j*3 + k), w = 1 << k.
sat_pin = i64[ffcdcl_state_size(70000, 1800000)]
z = ffsat2_expect("pin init", ffcdcl_init(sat_pin, 70000, 6605) == 1)
z = ffsat2_expect("pin encode", ffsan_encode(sat_pin, 3, 1, 1, 1, 3, 9, 0) == 1)
unit = i64[2]
rep = 0 ## i64
while rep < 9
  j = rep / 3 ## i64
  k = rep % 3 ## i64
  axis = 0 ## i64
  while axis < 3
    want_mask = 1 << j ## i64
    if axis == 1
      want_mask = 1 << (j * 3 + k)
    if axis == 2
      want_mask = 1 << k
    pos = 0 ## i64
    while pos < 9
      unit[0] = 2 * ffsan_rep_var(rep, axis, pos, 9) + 1
      if ((want_mask >> pos) & 1) == 1
        unit[0] = 2 * ffsan_rep_var(rep, axis, pos, 9)
      z = ffcdcl_add_clause(sat_pin, unit, 1)
      pos += 1
    axis += 1
  rep += 1
none = i64[1]
pinned = ffcdcl_solve(sat_pin, none, 0, 100000) ## i64
z = ffsat2_expect("pinned naive witness SAT", pinned == 1)
raw = ffsan_decode(sat_pin, 3, 1, 1, 1, 3, 9, 0, out_u, out_v, out_w) ## i64
z = ffsat2_expect("pinned decode count", raw == 27)
cap3 = ffw_default_capacity(3) ## i64
gate3 = i64[ffw_state_size(cap3)]
z = ffsat2_expect("pinned witness loads", ffw_init_terms_cap(gate3, out_u, out_v, out_w, 27, 3, cap3, 6607, 0, 1, 1, 1) == 27)
z = ffsat2_expect("pinned witness exact", ffw_verify_current_exact(gate3, 3) == 1)
<< "ANSATZ_333 pinned-naive control sat=" + pinned.to_s() + " terms=" + raw.to_s()

# --- <3,3,3> honest probes -------------------------------------------------------------
rank27 = ffsan_solve(3, 1, 1, 1, 9, 0, 30000, 6609, out_u, out_v, out_w, meta) ## i64
label27 = "indeterminate" ## String
if meta[3] == 1
  label27 = "sat"
if meta[3] == 0 - 1
  label27 = "certified-unsat-cell"
z = ffsat2_expect("(9,0) probe terminates", rank27 >= 0)
if rank27 > 0
  z = ffsat2_expect("(9,0) hit gates", meta[7] == 1 && rank27 <= 27)
<< "ANSATZ_CELL n=3 g=(1,1,1) k=9 f=0 verdict=" + label27 + " rank=" + rank27.to_s() + " vars=" + meta[1].to_s() + " clauses=" + meta[2].to_s() + " conflicts=" + meta[4].to_s() + " ms=" + meta[8].to_s()

rank26 = ffsan_solve(3, 1, 1, 1, 8, 2, 30000, 6611, out_u, out_v, out_w, meta) ## i64
label26 = "indeterminate" ## String
if meta[3] == 1
  label26 = "sat"
if meta[3] == 0 - 1
  label26 = "certified-unsat-cell"
z = ffsat2_expect("(8,2) probe terminates", rank26 >= 0)
if rank26 > 0
  z = ffsat2_expect("(8,2) hit gates", meta[7] == 1 && rank26 <= 26)
<< "ANSATZ_CELL n=3 g=(1,1,1) k=8 f=2 rank26 verdict=" + label26 + " rank=" + rank26.to_s() + " conflicts=" + meta[4].to_s() + " ms=" + meta[8].to_s()

<< "flipfleet_sandwich_ansatz_test: all checks passed"
