# Two-parent sector-swap crossover with a low-rank suture (move-lab move 8).
#
# Exact GF(2) content.  Let S and T be exact same-shape schemes for <n,m,p>
# and let sigma be an output-side sector selector over the C = n x p cells:
# mode 0 selects a term when its w mask intersects the sector mask, mode 1
# when its whole w support lies inside the sector mask.  With S_sigma and
# T_sigma the selected subsets, the child
#
#   child = (S minus S_sigma) XOR T_sigma XOR R
#
# has tensor MMT XOR D XOR tensor(R), where the defect
#
#   D = tensor(S_sigma) XOR tensor(T_sigma)
#
# because tensor(S minus S_sigma) = MMT XOR tensor(S_sigma).  The child is
# therefore exact precisely when the suture R rebuilds D.  R is minted by
# the shipped complete GF(2) recognizers: ffr2tr_decompose for tensor rank
# at most two, then ffr3tr_decompose for rank at most three.  When rank(D)
# exceeds that reach the move abstains (counted, never guessed).  All list
# arithmetic is XOR-multiset toggling - equal triples cancel pairwise, the
# worker's own insertion rule - so
#
#   child rank = |S| - |S_sigma| + |T_sigma| + rank(D) - 2 * cancellations.
#
# Selection is a pure function of w, so a triple present in both parents is
# either swapped for itself or left untouched; union cancellations can only
# come from suture terms colliding with surviving child terms.
#
# Admission: every non-abstained child is rebuilt in a fresh worker state
# (ffw_init_terms_cap / ffr_init_terms_cap run the exhaustive coefficient
# gate) and re-verified with ffw_verify_best_exact / ffr_verify_best_exact.
# Publication is dump -> re-parse -> re-gate, with the output file cleared
# first and on any failure.  This lane is an offline intake experiment; it
# never touches a live fleet, bank, or TUI.

use flipfleet_rect_three_term_repair

# Shape helpers: a square worker state stores dim = n*n in header word 3;
# a rectangular state stores the packed shape n + m*16 + p*256 (>= 546),
# which can never collide with a square dim (<= 49).
-> ffss_state_m(st) (i64[]) i64
  if st[3] == st[2] * st[2]
    return st[2]
  ffr_shape_m(st)

-> ffss_state_p(st) (i64[]) i64
  if st[3] == st[2] * st[2]
    return st[2]
  ffr_shape_p(st)

# Sector selector over the output side.  mode 0 = intersect (w meets the
# sector), mode 1 = inside (w support entirely within the sector).
-> ffss_selects(w, mask, mode) (i64 i64 i64) i64
  if w == 0
    return 0
  if mode == 0
    if (w & mask) != 0
      return 1
    return 0
  if (w & mask) == w
    return 1
  0

# Sector enumeration for the sweep: n*p single output cells, then p output
# columns, then n output rows.
-> ffss_sector_count(n, p) (i64 i64) i64
  n * p + p + n

-> ffss_sector_mask(n, p, index) (i64 i64 i64) i64
  cells = n * p ## i64
  if index < 0
    return 0
  if index < cells
    return 1 << index
  if index < cells + p
    k = index - cells ## i64
    mask = 0 ## i64
    i = 0 ## i64
    while i < n
      mask = mask | (1 << (i * p + k))
      i += 1
    return mask
  if index < cells + p + n
    i = index - cells - p ## i64
    mask = 0 ## i64
    k = 0 ## i64
    while k < p
      mask = mask | (1 << (i * p + k))
      k += 1
    return mask
  0

-> ffss_term_in(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  at = 0 ## i64
  while at < count
    if us[at] == u && vs[at] == v && ws[at] == w
      return 1
    at += 1
  0

# XOR-multiset toggle: inserting an existing triple cancels it in pairs,
# exactly like the worker's term insertion.  Zero factors are no-ops.
-> ffss_toggle(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return count
  at = 0 ## i64
  while at < count
    if us[at] == u && vs[at] == v && ws[at] == w
      last = count - 1 ## i64
      us[at] = us[last]
      vs[at] = vs[last]
      ws[at] = ws[last]
      return last
    at += 1
  us[count] = u
  vs[count] = v
  ws[count] = w
  count + 1

# Core crossover on raw term arrays.  out_u/out_v/out_w must hold at least
# srank + trank + 3 entries.  meta needs >= 16 words:
#   0 |S_sigma|            1 |T_sigma|          2 union cancellations
#   3 defect weight        4 defect rank 0..3 (or -1 = abstain)
#   5 suture terms minted  6 sutures surviving  7 off-dictionary sutures
#   8 predicted child rank |S| - |S_sigma| + |T_sigma| + rank(D)
#   9 actual child rank   10 full-gate result  11 child density bits
#  12 recognizer used (0 none, 2 two-term, 3 three-term)
#  13 suture cancellations
#  14 code: 0 ok, 1 defect beyond rank-3 reach, 2 recognizer rebuild
#     mismatch (fail closed), 3 invalid input, 4 degenerate empty child
# Returns the raw (ungated) child rank, 0 on abstain, 0 - 1 on bad input.
# Slots 10 and 11 are filled by the state-level wrapper after the gate.
-> ffss_cross_terms(su, sv, sw, srank, tu, tv, tw, trank, n, m, p, sector_mask, sector_mode, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  uwidth = n * m ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  if n < 1 || m < 1 || p < 1 || uwidth > 62 || vwidth > 62 || wwidth > 62
    meta[14] = 3
    return 0 - 1
  if srank < 1 || trank < 1 || sector_mode < 0 || sector_mode > 1
    meta[14] = 3
    return 0 - 1
  full = (1 << wwidth) - 1 ## i64
  if sector_mask < 0 || sector_mask > full
    meta[14] = 3
    return 0 - 1

  words = ffrrw_tensor_words(n, m, p) ## i64
  carrier = i64[words]
  weight = 0 ## i64
  count = 0 ## i64
  picked_s = 0 ## i64
  picked_t = 0 ## i64
  cancels = 0 ## i64
  i = 0
  while i < srank
    if ffss_selects(sw[i], sector_mask, sector_mode) == 1
      weight = ffrrw_xor_outer_weight(carrier, su[i], sv[i], sw[i], uwidth, vwidth, wwidth, weight)
      picked_s += 1
    else
      before = count ## i64
      count = ffss_toggle(out_u, out_v, out_w, count, su[i], sv[i], sw[i])
      if count < before
        cancels += 1
    i += 1
  i = 0
  while i < trank
    if ffss_selects(tw[i], sector_mask, sector_mode) == 1
      weight = ffrrw_xor_outer_weight(carrier, tu[i], tv[i], tw[i], uwidth, vwidth, wwidth, weight)
      before = count ## i64
      count = ffss_toggle(out_u, out_v, out_w, count, tu[i], tv[i], tw[i])
      if count < before
        cancels += 1
      picked_t += 1
    i += 1
  meta[0] = picked_s
  meta[1] = picked_t
  meta[2] = cancels
  meta[3] = weight

  drank = 0 ## i64
  if weight > 0
    du = i64[3]
    dv = i64[3]
    dw = i64[3]
    two_meta = i64[3]
    used = 2 ## i64
    drank = ffr2tr_decompose(carrier, n, m, p, du, dv, dw, two_meta)
    if drank < 0
      three_meta = i64[6]
      drank = ffr3tr_decompose(carrier, n, m, p, du, dv, dw, three_meta)
      used = 3
    if drank < 0
      meta[4] = 0 - 1
      meta[14] = 1
      return 0
    rebuilt = 0 ## i64
    if used == 2
      rebuilt = ffr2tr_rebuild(du, dv, dw, drank, n, m, p, carrier)
    else
      rebuilt = ffr3tr_rebuild(du, dv, dw, drank, n, m, p, carrier)
    if rebuilt != 1
      meta[4] = 0 - 1
      meta[14] = 2
      return 0
    meta[12] = used
    offdict = 0 ## i64
    survived = 0 ## i64
    scancel = 0 ## i64
    i = 0
    while i < drank
      indict = 0 ## i64
      if ffss_term_in(su, sv, sw, srank, du[i], dv[i], dw[i]) == 1
        indict = 1
      if indict == 0 && ffss_term_in(tu, tv, tw, trank, du[i], dv[i], dw[i]) == 1
        indict = 1
      if indict == 0
        offdict += 1
      before = count ## i64
      count = ffss_toggle(out_u, out_v, out_w, count, du[i], dv[i], dw[i])
      if count > before
        survived += 1
      else
        scancel += 1
      i += 1
    meta[5] = drank
    meta[6] = survived
    meta[7] = offdict
    meta[13] = scancel

  meta[4] = drank
  meta[8] = srank - picked_s + picked_t + drank
  meta[9] = count
  if count < 1
    meta[14] = 4
    return 0
  count

# Exhaustive full-scheme gate: rebuild the term list in a fresh worker state
# (init runs the complete coefficient reconstruction) and re-verify.
# Returns the child density bits on success, 0 - 1 on any failure.
-> ffss_gate_terms(us, vs, ws, rank, n, m, p, seed) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if rank < 1
    return 0 - 1
  if n == m && m == p
    cap = ffw_default_capacity(n) ## i64
    if cap < rank + 8
      cap = rank + 8
    st = i64[ffw_state_size(cap)]
    loaded = ffw_init_terms_cap(st, us, vs, ws, rank, n, cap, seed, 0, 1, 1, 1) ## i64
    if loaded != rank
      return 0 - 1
    if ffw_verify_best_exact(st, n) != 1
      return 0 - 1
    return ffw_best_bits(st)
  rcap = ffr_default_capacity(n, m, p) ## i64
  if rcap < rank + 8
    rcap = rank + 8
  rst = i64[ffr_state_size(rcap)]
  rloaded = ffr_init_terms_cap(rst, us, vs, ws, rank, n, m, p, rcap, seed, 0, 1, 1, 1) ## i64
  if rloaded != rank
    return 0 - 1
  if ffr_verify_best_exact(rst, n, m, p) != 1
    return 0 - 1
  ffr_best_bits(rst)

# One-shot state-level crossover.  state_s / state_t are exact same-shape
# worker states (square or rectangular).  Returns the fully gated child
# rank, 0 on abstain, 0 - 1 on invalid input, 0 - 2 if the exhaustive gate
# rejected a recognized child (a bug signal, counted by callers).
-> ffss_cross(state_s, state_t, sector_mask, sector_mode, out_u, out_v, out_w, meta) (i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  if ffw_valid(state_s) != 1 || ffw_valid(state_t) != 1
    meta[14] = 3
    return 0 - 1
  if state_s[2] != state_t[2] || state_s[3] != state_t[3]
    meta[14] = 3
    return 0 - 1
  n = state_s[2] ## i64
  m = ffss_state_m(state_s) ## i64
  p = ffss_state_p(state_s) ## i64
  srank = ffw_best_rank(state_s) ## i64
  trank = ffw_best_rank(state_t) ## i64
  if srank < 1 || trank < 1
    meta[14] = 3
    return 0 - 1
  su = i64[srank + 1]
  sv = i64[srank + 1]
  sw = i64[srank + 1]
  tu = i64[trank + 1]
  tv = i64[trank + 1]
  tw = i64[trank + 1]
  if ffw_export_best(state_s, su, sv, sw) != srank
    meta[14] = 3
    return 0 - 1
  if ffw_export_best(state_t, tu, tv, tw) != trank
    meta[14] = 3
    return 0 - 1
  child = ffss_cross_terms(su, sv, sw, srank, tu, tv, tw, trank, n, m, p, sector_mask, sector_mode, out_u, out_v, out_w, meta) ## i64
  if child < 1
    return child
  bits = ffss_gate_terms(out_u, out_v, out_w, child, n, m, p, 77003 + sector_mask * 5 + sector_mode) ## i64
  if bits < 0
    meta[10] = 0
    return 0 - 2
  meta[10] = 1
  meta[11] = bits
  child

-> ffss_file_has_scheme(path) (String) i64
  content = read_file(path)
  if content == nil
    return 0
  if content.size() < 3
    return 0
  1

# Publish with the child-engine discipline: clear the output first, rebuild
# and gate in a fresh state, dump, then independently re-parse the file into
# a second state and re-gate it.  Any failure clears the output again.
-> ffss_publish(us, vs, ws, rank, n, m, p, path, seed) (i64[] i64[] i64[] i64 i64 i64 i64 String i64) i64
  if path.size() < 1 || rank < 1
    return 0 - 1
  z = write_file(path, "")
  if n == m && m == p
    cap = ffw_default_capacity(n) ## i64
    if cap < rank + 8
      cap = rank + 8
    st = i64[ffw_state_size(cap)]
    if ffw_init_terms_cap(st, us, vs, ws, rank, n, cap, seed, 0, 1, 1, 1) != rank
      return 0 - 1
    if ffw_dump_best(st, path) != rank
      z = write_file(path, "")
      return 0 - 1
    check = i64[ffw_state_size(cap)]
    if ffw_load_scheme_cap(check, path, n, cap, seed + 17, 0, 1, 1, 1) != rank
      z = write_file(path, "")
      return 0 - 1
    if ffw_verify_best_exact(check, n) != 1
      z = write_file(path, "")
      return 0 - 1
    return rank
  rcap = ffr_default_capacity(n, m, p) ## i64
  if rcap < rank + 8
    rcap = rank + 8
  rst = i64[ffr_state_size(rcap)]
  if ffr_init_terms_cap(rst, us, vs, ws, rank, n, m, p, rcap, seed, 0, 1, 1, 1) != rank
    return 0 - 1
  if ffr_dump_best(rst, path) != rank
    z = write_file(path, "")
    return 0 - 1
  rcheck = i64[ffr_state_size(rcap)]
  if ffr_load_scheme_cap(rcheck, path, n, m, p, rcap, seed + 17, 0, 1, 1, 1) != rank
    z = write_file(path, "")
    return 0 - 1
  if ffr_verify_best_exact(rcheck, n, m, p) != 1
    z = write_file(path, "")
    return 0 - 1
  rank

# Load one parent and exact-gate it before any crossover work (children
# never trust their inputs).  Returns rank or 0 - 1.
-> ffss_load_parent(st, path, n, m, p, capacity, seed) (i64[] String i64 i64 i64 i64 i64) i64
  if n == m && m == p
    rank = ffw_load_scheme_cap(st, path, n, capacity, seed, 0, 1, 1, 1) ## i64
    if rank < 1
      return 0 - 1
    if ffw_verify_best_exact(st, n) != 1
      return 0 - 1
    return rank
  rrank = ffr_load_scheme_cap(st, path, n, m, p, capacity, seed, 0, 1, 1, 1) ## i64
  if rrank < 1
    return 0 - 1
  if ffr_verify_best_exact(st, n, m, p) != 1
    return 0 - 1
  rrank

# Sweep driver: both selector modes x every cell/column/row sector x both
# parent orientations.  hist needs >= 5 words: defect rank 0..3 counts for
# non-abstained children, index 4 = abstentions.  counters needs >= 16:
#   0 attempts             1 non-abstained children  2 gated exact
#   3 gate/input failures  4 wins (rank < |S|)       5 equal-rank children
#     (should stay 0)                                  with off-dictionary
#                                                      sutures
#   6 rank-increase children  7 published wins       8 publish failures
#   9 sutures minted         10 off-dictionary minted terms
#  11 abstentions            12 defect weight sum    13 union cancellations
#  14 suture cancellations   15 elapsed ms
# publish_prefix == "" disables publication.  Returns the win count, or
# 0 - 1 when a parent fails to load/gate.
-> ffss_sweep(parent_a, parent_b, n, m, p, publish_prefix, hist, counters) (String String i64 i64 i64 String i64[] i64[]) i64
  i = 0 ## i64
  while i < 5
    hist[i] = 0
    i += 1
  i = 0
  while i < 16
    counters[i] = 0
    i += 1
  start_ms = ccall("__w_clock_ms") ## i64
  cap = 0 ## i64
  if n == m && m == p
    cap = ffw_default_capacity(n)
  else
    cap = ffr_default_capacity(n, m, p)
  size = ffw_state_size(cap) ## i64
  state_a = i64[size]
  state_b = i64[size]
  arank = ffss_load_parent(state_a, parent_a, n, m, p, cap, 88001) ## i64
  brank = ffss_load_parent(state_b, parent_b, n, m, p, cap, 88003) ## i64
  if arank < 1 || brank < 1
    return 0 - 1
  au = i64[arank + 1]
  av = i64[arank + 1]
  aw = i64[arank + 1]
  bu = i64[brank + 1]
  bv = i64[brank + 1]
  bw = i64[brank + 1]
  if ffw_export_best(state_a, au, av, aw) != arank
    return 0 - 1
  if ffw_export_best(state_b, bu, bv, bw) != brank
    return 0 - 1
  limit = arank + brank + 3 ## i64
  cu = i64[limit]
  cv = i64[limit]
  cw = i64[limit]
  meta = i64[16]
  sectors = ffss_sector_count(n, p) ## i64
  wins = 0 ## i64
  orientation = 0 ## i64
  while orientation < 2
    su = au
    sv = av
    sw = aw
    srank = arank ## i64
    tu = bu
    tv = bv
    tw = bw
    trank = brank ## i64
    if orientation == 1
      su = bu
      sv = bv
      sw = bw
      srank = brank
      tu = au
      tv = av
      tw = aw
      trank = arank
    mode = 0 ## i64
    while mode < 2
      sector = 0 ## i64
      while sector < sectors
        mask = ffss_sector_mask(n, p, sector) ## i64
        counters[0] = counters[0] + 1
        child = ffss_cross_terms(su, sv, sw, srank, tu, tv, tw, trank, n, m, p, mask, mode, cu, cv, cw, meta) ## i64
        if child < 0
          counters[3] = counters[3] + 1
        if child == 0
          hist[4] = hist[4] + 1
          counters[11] = counters[11] + 1
        if child > 0
          drank = meta[4] ## i64
          hist[drank] = hist[drank] + 1
          counters[1] = counters[1] + 1
          counters[9] = counters[9] + meta[5]
          counters[10] = counters[10] + meta[7]
          counters[12] = counters[12] + meta[3]
          counters[13] = counters[13] + meta[2]
          counters[14] = counters[14] + meta[13]
          seed = 90001 + orientation * 7919 + mode * 461 + sector * 13 ## i64
          bits = ffss_gate_terms(cu, cv, cw, child, n, m, p, seed) ## i64
          if bits < 0
            counters[3] = counters[3] + 1
          else
            counters[2] = counters[2] + 1
            if child < srank
              counters[4] = counters[4] + 1
              wins += 1
              if publish_prefix.size() > 0
                path = publish_prefix + "_o" + orientation.to_s() + "_m" + mode.to_s() + "_s" + sector.to_s() + "_r" + child.to_s() + ".txt"
                published = ffss_publish(cu, cv, cw, child, n, m, p, path, seed + 1) ## i64
                if published == child
                  counters[7] = counters[7] + 1
                else
                  counters[8] = counters[8] + 1
            if child == srank && meta[7] > 0
              counters[5] = counters[5] + 1
            if child > srank
              counters[6] = counters[6] + 1
        sector += 1
      mode += 1
    orientation += 1
  counters[15] = ccall("__w_clock_ms") - start_ms
  wins
