use flipfleet_matroid_circuit5

-> ffmc5t_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

# Minimal five-element rank-one outer-matrix circuit:
# (1,1) + (1,2) + (1,4) + (2,7) + (3,7) = 0.
# Put the same removable U bit on five distinct live terms.  Toggling it is an
# exact five-changed-term endpoint with density delta -5.
us = i64[5]
vs = i64[5]
ws = i64[5]
i = 0 ## i64
while i < 5
  us[i] = 3
  i += 1
vs[0] = 1
ws[0] = 1
vs[1] = 1
ws[1] = 2
vs[2] = 1
ws[2] = 4
vs[3] = 2
ws[3] = 7
vs[4] = 3
ws[4] = 7

move_capacity = 5 * 3 * (3 * 2 + 6) ## i64
terms = i64[move_capacity]
axes = i64[move_capacity]
masks = i64[move_capacity]
sketches = i64[move_capacity]
deltas = i64[move_capacity]
move_count = ffmc5_build_moves(us, vs, ws, 5, 3, move_capacity, terms, axes, masks, sketches, deltas) ## i64
z = ffmc5t_expect("bounded move neighborhood built", move_count > 30) ## i64

known = i64[5]
term = 0 ## i64
while term < 5
  move = 0 ## i64
  while move < move_count
    if terms[move] == term && axes[move] == 0 && masks[move] == 1
      known[term] = move
    move += 1
  term += 1
z = ffmc5t_expect("planted syndrome is zero", (sketches[known[0]] ^ sketches[known[1]] ^ sketches[known[2]] ^ sketches[known[3]] ^ sketches[known[4]]) == 0)
z = ffmc5t_expect("planted five-circuit exact", ffmc5_circuit_exact(us, vs, ws, terms, axes, masks, known, 5, 3) == 1)
z = ffmc5t_expect("planted five-circuit minimal", ffmc5_circuit_minimal(us, vs, ws, terms, axes, masks, sketches, known, 3) == 1)

out_u = i64[5]
out_v = i64[5]
out_w = i64[5]
meta = i64[18]
found = ffmc5_search_bounded(us, vs, ws, 5, 3, 128, 0, 17, 0, out_u, out_v, out_w, meta) ## i64
z = ffmc5t_expect("2+3 join recovers planted circuit", found == 5 && meta[5] >= 1 && meta[6] >= 1 && meta[7] >= 1)
z = ffmc5t_expect("planted endpoint exact", fftc_local_exact(us, vs, ws, 5, out_u, out_v, out_w, 5) == 1)
z = ffmc5t_expect("planted endpoint changes five terms", meta[10] >= 1)
z = ffmc5t_expect("planted endpoint improves five bits", meta[12] <= 0 - 5)
z = ffmc5t_expect("planted endpoint is outside old factor spans", meta[9] == 0)

# Multi-bit collapse and nearest-factor perturbations must actually be present;
# otherwise the implementation has silently regressed to the earlier one-bit
# audit.
multi = 0 ## i64
move = 0
while move < move_count
  if ffw_popcount(masks[move]) > 1
    multi += 1
  move += 1
z = ffmc5t_expect("multi-bit perturbations included", multi > 0)

# Full n^6 regression: add both sides of a shifted five-circuit to the exact
# 3x3 rank-23 scheme.  Their combined tensor is zero, producing an exact
# rank-33 shoulder.  Applying the five old->new edits collides with and
# cancels the five parked new terms, returning to an independently rebuilt
# and fully verified rank-23 matrix-multiplication tensor.
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base, "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt", n, capacity, 77101, 0, 1, 1, 1) ## i64
z = ffmc5t_expect("real base exact", base_rank == 23 && ffw_verify_current_exact(base, n) == 1)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
z = ffw_export_current(base, shoulder_u, shoulder_v, shoulder_w)
shift_v = i64[5]
shift_w = i64[5]
shift_v[0] = 1
shift_w[0] = 8
shift_v[1] = 1
shift_w[1] = 16
shift_v[2] = 1
shift_w[2] = 32
shift_v[3] = 2
shift_w[3] = 56
shift_v[4] = 3
shift_w[4] = 56
i = 0
while i < 5
  shoulder_u[base_rank + i] = 192
  shoulder_v[base_rank + i] = shift_v[i]
  shoulder_w[base_rank + i] = shift_w[i]
  shoulder_u[base_rank + 5 + i] = 128
  shoulder_v[base_rank + 5 + i] = shift_v[i]
  shoulder_w[base_rank + 5 + i] = shift_w[i]
  i += 1
shoulder = i64[state_size]
shoulder_rank = ffw_init_terms_cap(shoulder, shoulder_u, shoulder_v, shoulder_w, base_rank + 10, n, capacity, 77103, 0, 1, 1, 1) ## i64
z = ffmc5t_expect("planted real shoulder exact", shoulder_rank == 33 && ffw_verify_current_exact(shoulder, n) == 1)

shoulder_move_capacity = shoulder_rank * 3 * (18 + 6) ## i64
shoulder_terms = i64[shoulder_move_capacity]
shoulder_axes = i64[shoulder_move_capacity]
shoulder_masks = i64[shoulder_move_capacity]
shoulder_sketches = i64[shoulder_move_capacity]
shoulder_deltas = i64[shoulder_move_capacity]
shoulder_moves = ffmc5_build_moves(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, 9, shoulder_move_capacity, shoulder_terms, shoulder_axes, shoulder_masks, shoulder_sketches, shoulder_deltas) ## i64
shoulder_circuit = i64[5]
i = 0
while i < shoulder_moves
  term = shoulder_terms[i]
  if term >= base_rank && term < base_rank + 5 && shoulder_axes[i] == 0 && shoulder_masks[i] == 64
    shoulder_circuit[term - base_rank] = i
  i += 1
z = ffmc5t_expect("real shoulder circuit exact", ffmc5_circuit_exact(shoulder_u, shoulder_v, shoulder_w, shoulder_terms, shoulder_axes, shoulder_masks, shoulder_circuit, 5, 9) == 1)
returned_u = i64[capacity]
returned_v = i64[capacity]
returned_w = i64[capacity]
returned_rank = ffmc5_materialize(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, shoulder_terms, shoulder_axes, shoulder_masks, shoulder_circuit, 5, returned_u, returned_v, returned_w) ## i64
returned = i64[state_size]
reloaded_rank = ffw_init_terms_cap(returned, returned_u, returned_v, returned_w, returned_rank, n, capacity, 77105, 0, 1, 1, 1) ## i64
z = ffmc5t_expect("five-circuit full gate", returned_rank == base_rank && reloaded_rank == base_rank && ffw_verify_current_exact(returned, n) == 1)

<< "flipfleet_matroid_circuit5_test: all checks passed moves=" + move_count.to_s() + " exact=" + meta[5].to_s() + " minimal=" + meta[6].to_s() + " full_rank=" + returned_rank.to_s()
