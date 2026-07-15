# Exact C3 x Z2 (six-image, historically called D3 in the campaign notes)
# symmetry helpers for the 6x6 FlipFleet experiment.
#
# The C3 generator is the matrix-multiplication rotation
#   rho(u,v,w) = (v, transpose(w), transpose(u)).
# The extra Z2 generator reverses both coordinates of every matrix mask:
#   sigma(u,v,w) = (reverse(u), reverse(v), reverse(w)).
# These two maps commute in this representation.  `ffd3_toggle_orbit` toggles
# the *set* orbit, rather than blindly applying six toggles, so terms fixed by
# sigma (or by a composition with rho) are handled with the correct GF(2)
# parity.

use flipfleet_escape

-> ffd3_supported(n) (i64) i64
  ok = 0 ## i64
  if n == 6
    ok = 1
  ok

-> ffd3_seed_path(n) (i64)
  if n == 6
    return "benchmarks/matmul/metaflip/matmul_6x6_rank153_d2502_gf2.txt"
  ""

-> ffd3_reverse_mask(mask, n) (i64 i64) i64
  out = 0 ## i64
  bit = 0 ## i64
  one = 1 ## i64
  width = n * n ## i64
  while bit < width
    if ((mask >> bit) & one) == one
      row = bit / n ## i64
      col = bit % n ## i64
      dst = (n - 1 - row) * n + (n - 1 - col) ## i64
      out = out | (one << dst)
    bit += 1
  out

-> ffd3_is_z2(us, vs, ws, rank, n) (i64[] i64[] i64[] i64 i64) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < rank
    ru = ffd3_reverse_mask(us[i], n) ## i64
    rv = ffd3_reverse_mask(vs[i], n) ## i64
    rw = ffd3_reverse_mask(ws[i], n) ## i64
    if ffe_has_term(us, vs, ws, rank, ru, rv, rw) == 0
      ok = 0
      i = rank
    else
      i += 1
  ok

-> ffd3_is_closed(us, vs, ws, rank, n) (i64[] i64[] i64[] i64 i64) i64
  ok = ffe_is_c3(us, vs, ws, rank, n) ## i64
  if ok == 1
    ok = ffd3_is_z2(us, vs, ws, rank, n)
  ok

# Fill three six-cell arrays with the distinct orbit of one term.  The first
# three candidates are its C3 orbit and the last three are their reversals.
-> ffd3_orbit_terms(u, v, w, n, ous, ovs, ows) (i64 i64 i64 i64 i64[] i64[] i64[]) i64
  cu = i64[6]
  cv = i64[6]
  cw = i64[6]
  cu[0] = u
  cv[0] = v
  cw[0] = w
  cu[1] = v
  cv[1] = ffe_transpose(w, n)
  cw[1] = ffe_transpose(u, n)
  cu[2] = cv[1]
  cv[2] = u
  cw[2] = ffe_transpose(v, n)
  i = 0 ## i64
  while i < 3
    cu[i + 3] = ffd3_reverse_mask(cu[i], n)
    cv[i + 3] = ffd3_reverse_mask(cv[i], n)
    cw[i + 3] = ffd3_reverse_mask(cw[i], n)
    i += 1

  count = 0 ## i64
  candidate = 0 ## i64
  while candidate < 6
    duplicate = 0 ## i64
    prior = 0 ## i64
    while prior < count
      if ous[prior] == cu[candidate] && ovs[prior] == cv[candidate] && ows[prior] == cw[candidate]
        duplicate = 1
      prior += 1
    if duplicate == 0
      ous[count] = cu[candidate]
      ovs[count] = cv[candidate]
      ows[count] = cw[candidate]
      count += 1
    candidate += 1
  count

-> ffd3_orbit_size(u, v, w, n) (i64 i64 i64 i64) i64
  ous = i64[6]
  ovs = i64[6]
  ows = i64[6]
  ffd3_orbit_terms(u, v, w, n, ous, ovs, ows)

# Toggle one complete distinct six-group orbit.  Existing terms are removed
# before absent terms are inserted, which makes the capacity failure atomic.
-> ffd3_toggle_orbit(us, vs, ws, rank, cap, u, v, w, n) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  ous = i64[6]
  ovs = i64[6]
  ows = i64[6]
  present = i64[6]
  count = ffd3_orbit_terms(u, v, w, n, ous, ovs, ows) ## i64
  existing = 0 ## i64
  i = 0 ## i64
  while i < count
    present[i] = ffe_has_term(us, vs, ws, rank, ous[i], ovs[i], ows[i])
    existing += present[i]
    i += 1
  final_rank = rank - existing + (count - existing) ## i64
  if final_rank > cap
    return 0 - rank - 1

  out = rank ## i64
  i = 0
  while i < count
    if present[i] == 1
      out = ffe_toggle(us, vs, ws, out, cap, ous[i], ovs[i], ows[i])
    i += 1
  i = 0
  while i < count
    if present[i] == 0
      out = ffe_toggle(us, vs, ws, out, cap, ous[i], ovs[i], ows[i])
    i += 1
  out

# Count terms whose reflected mate is absent.  This gives the coordinator a
# stable, exact diagnostic: zero is Z2 closed; unlike a Boolean it also shows
# how far a deliberately broken seed moved from the quotient subspace.
-> ffd3_z2_defect(us, vs, ws, rank, n) (i64[] i64[] i64[] i64 i64) i64
  defect = 0 ## i64
  i = 0 ## i64
  while i < rank
    ru = ffd3_reverse_mask(us[i], n) ## i64
    rv = ffd3_reverse_mask(vs[i], n) ## i64
    rw = ffd3_reverse_mask(ws[i], n) ## i64
    if ffe_has_term(us, vs, ws, rank, ru, rv, rw) == 0
      defect += 1
    i += 1
  defect
