use flipfleet_matroid_circuit

-> ffmct_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

# The known real 5x5 triangle relation, isolated as three live terms.  The
# three elementary deltas are e3 (x) v4 (x) w4 and two copies with e24 on V.
old_u = i64[3]
old_v = i64[3]
old_w = i64[3]
old_u[0] = 17
old_v[0] = 16777216
old_w[0] = 21525
old_u[1] = 8
old_v[1] = 11337728
old_w[1] = 13325
old_u[2] = 8
old_v[2] = 524288
old_w[2] = 24600

edit_capacity = 3 * 3 * 25 ## i64
terms = i64[edit_capacity]
axes = i64[edit_capacity]
bits = i64[edit_capacity]
sketches = i64[edit_capacity]
deltas = i64[edit_capacity]
edit_count = ffmc_build_edits(old_u, old_v, old_w, 3, 25, terms, axes, bits, sketches, deltas) ## i64
z = ffmct_expect("three-term edits generated", edit_count > 200) ## i64

known = i64[3]
i = 0 ## i64
while i < edit_count
  if terms[i] == 0 && axes[i] == 0 && bits[i] == 3
    known[0] = i
  if terms[i] == 1 && axes[i] == 1 && bits[i] == 24
    known[1] = i
  if terms[i] == 2 && axes[i] == 1 && bits[i] == 24
    known[2] = i
  i += 1
z = ffmct_expect("known circuit sketch is zero", (sketches[known[0]] ^ sketches[known[1]] ^ sketches[known[2]]) == 0)
z = ffmct_expect("known circuit exact", ffmc_circuit_exact(old_u, old_v, old_w, terms, axes, bits, known, 3, 25) == 1)

out_u = i64[3]
out_v = i64[3]
out_w = i64[3]
meta3 = i64[13]
found3 = ffmc_search3_bounded(old_u, old_v, old_w, 3, 25, 0, out_u, out_v, out_w, meta3) ## i64
z = ffmct_expect("2+1 MITM recovers circuit", found3 == 3 && meta3[3] >= 1 && meta3[4] >= 1)
z = ffmct_expect("recovered exchange exact", fftc_local_exact(old_u, old_v, old_w, 3, out_u, out_v, out_w, 3) == 1)
z = ffmct_expect("recovered exchange is complete span-3", meta3[6] >= 1 && meta3[7] == 0)
z = ffmct_expect("real triangle worsens density by three", meta3[8] == 3)

# Four distinct negative edits whose columns form a minimal outer-matrix
# circuit.  With a=1,b=2,c=1,d=2, the fixed pairs are
# (a,c),(b,d),(a,c+d),(a+b,d); their XOR is zero.  Every U factor contains
# bit zero, so the exchange improves this synthetic local tensor by four bits.
four_u = i64[4]
four_v = i64[4]
four_w = i64[4]
four_u[0] = 3
four_v[0] = 1
four_w[0] = 1
four_u[1] = 5
four_v[1] = 2
four_w[1] = 2
four_u[2] = 9
four_v[2] = 1
four_w[2] = 3
four_u[3] = 7
four_v[3] = 3
four_w[3] = 2
four_out_u = i64[4]
four_out_v = i64[4]
four_out_w = i64[4]
meta4 = i64[13]
found4 = ffmc_search4_improving_bounded(four_u, four_v, four_w, 4, 4, 1024, 4096, four_out_u, four_out_v, four_out_w, meta4) ## i64
z = ffmct_expect("NN MITM recovers planted four-circuit", found4 == 4 && meta4[6] >= 1 && meta4[7] >= 1)
z = ffmct_expect("planted four-circuit exact", fftc_local_exact(four_u, four_v, four_w, 4, four_out_u, four_out_v, four_out_w, 4) == 1)
z = ffmct_expect("planted four-circuit improves density", meta4[10] <= 0 - 4)

# Removing the only bit of a factor is never admitted as a rank-one candidate.
single_u = i64[1]
single_v = i64[1]
single_w = i64[1]
single_u[0] = 1
single_v[0] = 2
single_w[0] = 4
single_terms = i64[9]
single_axes = i64[9]
single_bits = i64[9]
single_sketches = i64[9]
single_deltas = i64[9]
single_count = ffmc_build_edits(single_u, single_v, single_w, 1, 3, single_terms, single_axes, single_bits, single_sketches, single_deltas) ## i64
z = ffmct_expect("three zero-factor edits excluded", single_count == 6)

<< "flipfleet_matroid_circuit_test: all checks passed three_hits=" + meta3[3].to_s() + " four_hits=" + meta4[6].to_s()
