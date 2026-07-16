# 2-adic carry compilation of characteristic-0 (integer) matmul witnesses
# into exact GF(2) schemes.  Move-lab move 6, lane prefix ffcc_.
#
# INPUT.  An integer-coefficient bilinear scheme for <n,m,p>:
#   A*B = sum_t (u_t . A)(v_t . B) w_t
# with integer factor entries (any scalar weights lambda_t absorbed into a
# factor).  Factors are stored as flat entry arrays, row-major:
#   u_t: n*m entries, entry i*m+j multiplies A(i,j)
#   v_t: m*p entries, entry j*p+k multiplies B(j,k)
#   w_t: n*p entries, entry i*p+k contributes to C(i,k)
# This matches the ffw_/ffr_ GF(2) bit conventions exactly (bit a of a mask
# is entry a here), so emitted masks gate directly.
#
# INTEGER WITNESS FILE FORMAT (ffcc_load_int_scheme):
#   '#'-prefixed lines and blank lines are ignored anywhere.
#   First data line: "n m p r".
#   Then r terms, each as three consecutive data lines: the u entries, the v
#   entries, the w entries, space-separated decimal integers with optional
#   leading minus.  |entry| <= 32767 (ffcc_entry_cap) -- the overflow envelope
#   under which the exact verifier and descent stay inside signed i64
#   (32767^3 * 4096-term sums < 2^62).  Witnesses above the cap are rejected,
#   never wrapped; '## big' is deliberately not used per the metaflip house
#   rules.  The expected AlphaEvolve <2,4,5> rank-32 drop-in is
#   "2 4 5 32" followed by 96 data rows (8/20/10 entries).
#
# EXACT CONTENT.  Grade each term by its 2-adic level
#   level(t) = v2(content(u_t)) + v2(content(v_t)) + v2(content(w_t))
# (content = gcd of entries).  For any witness exact modulo 2, the odd-entry
# reductions of the level-0 terms ALREADY reproduce T mod 2:
#   T = sum(level-0 terms) + 2*C  with C integral,
# so T == XOR(level-0 reductions) over GF(2).  Deeper levels enter the
# integer identity with even weight and therefore contribute NO GF(2) terms;
# the emitted scheme is the parity-compacted level-0 set (S0) alone, and
# appending deeper-level reductions would break exactness.  The carry
# recursion still runs to exhaustion: defect D = target - sum(level-0 terms)
# must be even in every coordinate (odd => the witness does not reduce at
# that depth -- reported, not repaired), carry C = D/2 becomes the next
# target, surviving terms are halved once (they drop one level), and clean
# termination (no terms left, zero residual) certifies the witness exactly
# over Z, layer by layer, entirely in i64.  Per-level primitive counts are
# the conservative bound
#   R_GF2(T mod 2) <= sum_k profile[k]   (already attained by |S0| <= profile[0])
# and, with the leftover carry mass, the "vacuity" gap profile: a witness
# whose carry is as hard as T shows up as a deep or non-terminating profile,
# not as a wrong scheme.
#
# GL(Z) REBALANCE DESCENT.  The sandwich isotropy of the matmul tensor,
#   u -> Ptr u Qtr,  v -> inverse(Qtr) v Rtr,  w -> inverse(P) w inverse(R)
# for unimodular P (n x n), Q (m x m), R (p x p), fixes T while re-grading
# the witness.  ffcc_apply_transvection implements the elementary generators
# (P, Q or R an elementary transvection I + c*E(a,b)); ffcc_rebalance runs a
# greedy steepest descent over all such generators minimizing
#   objective = (#level-0 terms) * 1000000 + popcount-weight of D/2
# with a bounded step budget.  Every candidate is probed by apply/undo (the
# inverse generator), entries beyond ffcc_entry_cap reject the move.
#
# ADMISSION.  Emitted schemes only ever leave this lane through
# ffcc_gate_square / ffcc_gate_rect (fresh state + full exhaustive verify) or
# ffcc_publish_square (gate, dump, re-parse, re-gate; the file is removed on
# any failure) -- the standard fffsp_run_engine publish discipline.

use metaflip_rect_worker

-> ffcc_entry_cap() i64
  32767

-> ffcc_abs(x) (i64) i64
  if x < 0
    return 0 - x
  x

-> ffcc_gcd(a, b) (i64 i64) i64
  x = ffcc_abs(a) ## i64
  y = ffcc_abs(b) ## i64
  while y > 0
    t = x % y ## i64
    x = y
    y = t
  x

# 2-adic valuation of |x|; caller guarantees x != 0.
-> ffcc_v2(x) (i64) i64
  v = ffcc_abs(x) ## i64
  e = 0 ## i64
  while v > 0 && (v & 1) == 0
    v = v / 2
    e += 1
  e

# gcd of the |entries| of one factor; 0 iff the factor is identically zero.
-> ffcc_content(entries, offset, count) (i64[] i64 i64) i64
  g = 0 ## i64
  i = 0 ## i64
  while i < count
    g = ffcc_gcd(g, entries[offset + i])
    i += 1
  g

# GF(2) reduction of one factor: bit k set iff entry k is odd.
-> ffcc_odd_mask(entries, offset, count) (i64[] i64 i64) i64
  mask = 0 ## i64
  i = 0 ## i64
  while i < count
    if (ffcc_abs(entries[offset + i]) & 1) == 1
      mask = mask | (1 << i)
    i += 1
  mask

-> ffcc_halve(entries, offset, count) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    entries[offset + i] = entries[offset + i] / 2
    i += 1
  1

# Term level = sum of the three factors' content valuations; 0-1 for a zero
# term (some factor identically zero).
-> ffcc_term_level(iu, iv, iw, t, um, vm, wm) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  cu = ffcc_content(iu, t * um, um) ## i64
  cv = ffcc_content(iv, t * vm, vm) ## i64
  cw = ffcc_content(iw, t * wm, wm) ## i64
  if cu == 0 || cv == 0 || cw == 0
    return 0 - 1
  ffcc_v2(cu) + ffcc_v2(cv) + ffcc_v2(cw)

# Halve a level >= 1 term once: divide one even-content factor by 2.
-> ffcc_halve_term(iu, iv, iw, t, um, vm, wm) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  cu = ffcc_content(iu, t * um, um) ## i64
  if cu > 0 && (cu & 1) == 0
    return ffcc_halve(iu, t * um, um)
  cv = ffcc_content(iv, t * vm, vm) ## i64
  if cv > 0 && (cv & 1) == 0
    return ffcc_halve(iv, t * vm, vm)
  cw = ffcc_content(iw, t * wm, wm) ## i64
  if cw > 0 && (cw & 1) == 0
    return ffcc_halve(iw, t * wm, wm)
  0

# Target coefficient of the <n,m,p> matmul tensor at (a, b, c) -- the exact
# convention of ffw_verify_view_error / ffr_view_error.
-> ffcc_want(a, b, c, m, p) (i64 i64 i64 i64 i64) i64
  arow = a / m ## i64
  acol = a % m ## i64
  brow = b / p ## i64
  bcol = b % p ## i64
  crow = c / p ## i64
  ccol = c % p ## i64
  if acol == brow && arow == crow && bcol == ccol
    return 1
  0

# Materialize T as a dense integer tensor, cell (a * vm + b) * wm + c.
# Returns the cell count.
-> ffcc_build_target(target, n, m, p) (i64[] i64 i64 i64) i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  a = 0 ## i64
  while a < um
    b = 0 ## i64
    while b < vm
      c = 0 ## i64
      while c < wm
        target[(a * vm + b) * wm + c] = ffcc_want(a, b, c, m, p)
        c += 1
      b += 1
    a += 1
  um * vm * wm

# Subtract one integer rank-one term from a dense tensor, in place.
-> ffcc_subtract_term(target, iu, iv, iw, t, um, vm, wm) (i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  a = 0 ## i64
  while a < um
    ua = iu[t * um + a] ## i64
    if ua != 0
      b = 0 ## i64
      while b < vm
        vb = iv[t * vm + b] ## i64
        if vb != 0
          base = (a * vm + b) * wm ## i64
          c = 0 ## i64
          while c < wm
            wc = iw[t * wm + c] ## i64
            if wc != 0
              target[base + c] = target[base + c] - ua * vb * wc
            c += 1
        b += 1
    a += 1
  1

-> ffcc_entries_ok(entries, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    if ffcc_abs(entries[i]) > ffcc_entry_cap()
      return 0
    i += 1
  1

-> ffcc_nonzero_entries(values, count) (i64[] i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count
    if values[i] != 0
      found += 1
    i += 1
  found

# Odd entries of defect/2 -- the carry-hardness proxy of the descent.
-> ffcc_carry_weight(defect, count) (i64[] i64) i64
  weight = 0 ## i64
  i = 0 ## i64
  while i < count
    half = ffcc_abs(defect[i]) / 2 ## i64
    if (half & 1) == 1
      weight += 1
    i += 1
  weight

# Parity-compacting insert: a duplicate triple cancels (XOR-set semantics).
# Returns the new count.
-> ffcc_xor_insert(out_u, out_v, out_w, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if out_u[i] == u && out_v[i] == v && out_w[i] == w
      out_u[i] = out_u[count - 1]
      out_v[i] = out_v[count - 1]
      out_w[i] = out_w[count - 1]
      return count - 1
    i += 1
  out_u[count] = u
  out_v[count] = v
  out_w[count] = w
  count + 1

# Full characteristic-0 gate: 1 iff the witness sums to T exactly over Z.
-> ffcc_verify_z_exact(iu, iv, iw, r, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  work = i64[cells]
  z = ffcc_build_target(work, n, m, p) ## i64
  t = 0 ## i64
  while t < r
    z = ffcc_subtract_term(work, iu, iv, iw, t, um, vm, wm)
    t += 1
  if ffcc_nonzero_entries(work, cells) == 0
    return 1
  0

# Compile an integer witness into its GF(2) scheme plus 2-adic carry profile.
# iu/iv/iw (>= r*um / r*vm / r*wm entries) ARE CONSUMED: surviving terms are
# halved in place level by level.  out_u/out_v/out_w (>= r slots) receive the
# parity-compacted level-0 masks -- the emitted GF(2) scheme.  acc_u/acc_v/
# acc_w/acc_level (>= r slots) receive every level's reductions tagged with
# their depth: bound accounting and compaction diagnostics, never scheme
# content.  profile (>= 64 slots): profile[k] = terms that became primitive
# at depth k.  meta (>= 16 slots):
#   meta[0] = levels processed          meta[1] = emitted compacted count
#   meta[2] = total bound sum(profile)  meta[3] = odd-defect depth (0-1 none)
#   meta[4] = leftover nonzero carry cells at exit (0 = clean)
#   meta[5] = zero terms dropped        meta[6] = 1 iff witness exact over Z
#   meta[8] = raw level-0 count         meta[9] = accounting count (= meta[2])
#   meta[10] = depth-0 carry weight (odd entries of D0/2)
# Returns the emitted compacted count (S0 is exact mod 2 by construction),
# or 0-1 malformed input, 0-2 depth-0 defect odd (the witness is not even a
# mod-2 witness; emitted masks must not be used), 0-3 depth guard exceeded.
-> ffcc_compile(iu, iv, iw, r, n, m, p, out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_level, profile, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  meta[3] = 0 - 1
  i = 0
  while i < 64
    profile[i] = 0
    i += 1
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  if r < 0 || n < 1 || m < 1 || p < 1 || um > 62 || vm > 62 || wm > 62
    return 0 - 1
  if ffcc_entries_ok(iu, r * um) == 0 || ffcc_entries_ok(iv, r * vm) == 0 || ffcc_entries_ok(iw, r * wm) == 0
    return 0 - 1
  cells = um * vm * wm ## i64
  target = i64[cells]
  z = ffcc_build_target(target, n, m, p) ## i64
  active = i64[r + 1]
  count = 0 ## i64
  dropped = 0 ## i64
  t = 0 ## i64
  while t < r
    if ffcc_term_level(iu, iv, iw, t, um, vm, wm) < 0
      dropped += 1
    else
      active[count] = t
      count += 1
    t += 1
  meta[5] = dropped
  depth = 0 ## i64
  out_count = 0 ## i64
  acc_count = 0 ## i64
  outcome = 0 ## i64
  while outcome == 0
    if count == 0 && ffcc_nonzero_entries(target, cells) == 0
      outcome = 2
    if outcome == 0 && depth >= 64
      outcome = 3
    if outcome == 0
      level0 = 0 ## i64
      keep = 0 ## i64
      idx = 0 ## i64
      while idx < count
        term = active[idx] ## i64
        if ffcc_term_level(iu, iv, iw, term, um, vm, wm) == 0
          uodd = ffcc_odd_mask(iu, term * um, um) ## i64
          vodd = ffcc_odd_mask(iv, term * vm, vm) ## i64
          wodd = ffcc_odd_mask(iw, term * wm, wm) ## i64
          acc_u[acc_count] = uodd
          acc_v[acc_count] = vodd
          acc_w[acc_count] = wodd
          acc_level[acc_count] = depth
          acc_count += 1
          if depth == 0
            out_count = ffcc_xor_insert(out_u, out_v, out_w, out_count, uodd, vodd, wodd)
          z = ffcc_subtract_term(target, iu, iv, iw, term, um, vm, wm)
          level0 += 1
        else
          active[keep] = term
          keep += 1
        idx += 1
      profile[depth] = level0
      if depth == 0
        meta[8] = level0
        meta[10] = ffcc_carry_weight(target, cells)
      odd_found = 0 ## i64
      cell = 0 ## i64
      while cell < cells
        if (ffcc_abs(target[cell]) & 1) == 1
          odd_found = 1
        cell += 1
      if odd_found == 1
        meta[3] = depth
        outcome = 1
      if outcome == 0
        cell = 0
        while cell < cells
          target[cell] = target[cell] / 2
          cell += 1
        count = keep
        idx = 0
        while idx < count
          z = ffcc_halve_term(iu, iv, iw, active[idx], um, vm, wm)
          idx += 1
        depth += 1
  meta[0] = depth
  meta[1] = out_count
  meta[2] = acc_count
  meta[9] = acc_count
  meta[4] = ffcc_nonzero_entries(target, cells)
  if meta[3] < 0 && meta[4] == 0 && outcome == 2
    meta[6] = 1
  if outcome == 3
    return 0 - 3
  if meta[3] == 0
    return 0 - 2
  out_count

# Descent objective at the current basis: (#level-0 terms) * 1000000 plus the
# carry weight of the depth-0 defect.  1152921504606846976 (2^60) rejects a
# basis whose entries exceed the cap or whose depth-0 defect is odd anywhere.
# target is the prebuilt integer T; defect is caller scratch (cells entries).
-> ffcc_objective(iu, iv, iw, r, n, m, p, target, defect) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[]) i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  if ffcc_entries_ok(iu, r * um) == 0 || ffcc_entries_ok(iv, r * vm) == 0 || ffcc_entries_ok(iw, r * wm) == 0
    return 1152921504606846976
  cell = 0 ## i64
  while cell < cells
    defect[cell] = target[cell]
    cell += 1
  level0 = 0 ## i64
  t = 0 ## i64
  while t < r
    if ffcc_term_level(iu, iv, iw, t, um, vm, wm) == 0
      z = ffcc_subtract_term(defect, iu, iv, iw, t, um, vm, wm)
      level0 += 1
    t += 1
  cell = 0
  while cell < cells
    if (ffcc_abs(defect[cell]) & 1) == 1
      return 1152921504606846976
    cell += 1
  weight = ffcc_carry_weight(defect, cells) ## i64
  if weight > 999999
    weight = 999999
  level0 * 1000000 + weight

# One elementary sandwich-isotropy generator applied to every term; T is
# fixed by construction.  With E(a,b) the matrix unit (row a, column b):
#   slot 0, P = I + c*E(a,b) (n side):  u row b += c * u row a
#                                       w row a -= c * w row b
#   slot 1, Q = I + c*E(a,b) (m side):  u col a += c * u col b
#                                       v row b -= c * v row a
#   slot 2, R = I + c*E(a,b) (p side):  v col a += c * v col b
#                                       w col b -= c * w col a
# The inverse of (slot, a, b, c) is (slot, a, b, -c).  Returns 1, or 0 on a
# malformed plan (nothing applied).
-> ffcc_apply_transvection(iu, iv, iw, r, n, m, p, slot, a, b, c) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  side = 0 ## i64
  if slot == 0
    side = n
  if slot == 1
    side = m
  if slot == 2
    side = p
  if side == 0 || a < 0 || b < 0 || a >= side || b >= side || a == b || c == 0
    return 0
  t = 0 ## i64
  while t < r
    if slot == 0
      j = 0 ## i64
      while j < m
        iu[t * um + b * m + j] = iu[t * um + b * m + j] + c * iu[t * um + a * m + j]
        j += 1
      k = 0 ## i64
      while k < p
        iw[t * wm + a * p + k] = iw[t * wm + a * p + k] - c * iw[t * wm + b * p + k]
        k += 1
    if slot == 1
      i = 0 ## i64
      while i < n
        iu[t * um + i * m + a] = iu[t * um + i * m + a] + c * iu[t * um + i * m + b]
        i += 1
      k = 0 ## i64
      while k < p
        iv[t * vm + b * p + k] = iv[t * vm + b * p + k] - c * iv[t * vm + a * p + k]
        k += 1
    if slot == 2
      j = 0 ## i64
      while j < m
        iv[t * vm + j * p + a] = iv[t * vm + j * p + a] + c * iv[t * vm + j * p + b]
        j += 1
      i = 0 ## i64
      while i < n
        iw[t * wm + i * p + b] = iw[t * wm + i * p + b] - c * iw[t * wm + i * p + a]
        i += 1
    t += 1
  1

# Sparse generator enumeration: per slot all ordered pairs (a, b), a != b,
# each with c in {+1, -1}.
-> ffcc_move_count(n, m, p) (i64 i64 i64) i64
  2 * (n * (n - 1) + m * (m - 1) + p * (p - 1))

# Decode move index into plan[0]=slot plan[1]=a plan[2]=b plan[3]=c.
# Returns 1, or 0 when the index is out of range.
-> ffcc_decode_move(n, m, p, index, plan) (i64 i64 i64 i64 i64[]) i64
  if index < 0
    return 0
  slot = 0 ## i64
  side = n ## i64
  remaining = index ## i64
  block = 2 * n * (n - 1) ## i64
  if remaining >= block
    remaining = remaining - block
    slot = 1
    side = m
    block = 2 * m * (m - 1)
  if slot == 1 && remaining >= block
    remaining = remaining - block
    slot = 2
    side = p
    block = 2 * p * (p - 1)
  if remaining >= block
    return 0
  pair = remaining / 2 ## i64
  a = pair / (side - 1) ## i64
  off = pair % (side - 1) ## i64
  b = off ## i64
  if off >= a
    b = off + 1
  c = 1 ## i64
  if remaining % 2 == 1
    c = 0 - 1
  plan[0] = slot
  plan[1] = a
  plan[2] = b
  plan[3] = c
  1

# Greedy steepest rebalance descent over the elementary sandwich generators,
# minimizing the compile objective under a bounded step budget.  iu/iv/iw are
# transformed in place (T is fixed throughout).  meta (>= 4): meta[0] = steps
# applied, meta[1] = initial objective, meta[2] = final objective, meta[3] =
# probes.  Returns the final objective.  A stall at a large carry weight is
# the vacuity report: the profile is a gap measure, never a wrong scheme.
-> ffcc_rebalance(iu, iv, iw, r, n, m, p, budget, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  target = i64[cells]
  defect = i64[cells]
  z = ffcc_build_target(target, n, m, p) ## i64
  best = ffcc_objective(iu, iv, iw, r, n, m, p, target, defect) ## i64
  meta[0] = 0
  meta[1] = best
  meta[2] = best
  meta[3] = 0
  moves = ffcc_move_count(n, m, p) ## i64
  plan = i64[4]
  steps = 0 ## i64
  probes = 0 ## i64
  improved = 1 ## i64
  while improved == 1 && steps < budget
    improved = 0
    best_move = 0 - 1 ## i64
    best_obj = best ## i64
    index = 0 ## i64
    while index < moves
      z = ffcc_decode_move(n, m, p, index, plan)
      z = ffcc_apply_transvection(iu, iv, iw, r, n, m, p, plan[0], plan[1], plan[2], plan[3])
      obj = ffcc_objective(iu, iv, iw, r, n, m, p, target, defect) ## i64
      probes += 1
      z = ffcc_apply_transvection(iu, iv, iw, r, n, m, p, plan[0], plan[1], plan[2], 0 - plan[3])
      if obj < best_obj
        best_obj = obj
        best_move = index
      index += 1
    if best_move >= 0 && best_obj < best
      z = ffcc_decode_move(n, m, p, best_move, plan)
      z = ffcc_apply_transvection(iu, iv, iw, r, n, m, p, plan[0], plan[1], plan[2], plan[3])
      best = best_obj
      steps += 1
      improved = 1
  meta[0] = steps
  meta[2] = best
  meta[3] = probes
  best

# ---------------------------------------------------------------------------
# Integer witness file parsing.

-> ffcc_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffcc_blank_line(line) (String) i64
  i = 0 ## i64
  while i < line.size()
    if line.slice(i, 1) != " "
      return 0
    i += 1
  1

-> ffcc_comment_line(line) (String) i64
  if line.size() > 0 && line.slice(0, 1) == "#"
    return 1
  0

# Parse one signed decimal entry; 4611686018427387904 (2^62) = malformed.
-> ffcc_parse_entry(text) (String) i64
  bad = 4611686018427387904 ## i64
  body = text
  neg = 0 ## i64
  if body.size() > 0 && body.slice(0, 1) == "-"
    neg = 1
    body = body.slice(1, body.size() - 1)
  if body.size() < 1 || body.size() > 5
    return bad
  i = 0 ## i64
  while i < body.size()
    digit = 0 ## i64
    if "0123456789".include?(body.slice(i, 1))
      digit = 1
    if digit == 0
      return bad
    i += 1
  value = body.to_i() ## i64
  if value > ffcc_entry_cap()
    return bad
  if neg == 1
    value = 0 - value
  value

# Parse a whitespace-separated row of exactly `expected` entries into
# out[offset..].  Returns the count parsed, or 0-1 on any malformed entry or
# count mismatch.
-> ffcc_parse_row(line, out, offset, expected) (String i64[] i64 i64) i64
  parts = line.split(" ")
  found = 0 ## i64
  i = 0 ## i64
  while i < parts.size()
    if parts[i].size() > 0
      if found >= expected
        return 0 - 1
      value = ffcc_parse_entry(parts[i]) ## i64
      if value == 4611686018427387904
        return 0 - 1
      out[offset + found] = value
      found += 1
    i += 1
  if found != expected
    return 0 - 1
  found

# Load an integer witness file (format in the module header).  dims (>= 4)
# receives n, m, p, r.  iu/iv/iw must hold capacity*um / capacity*vm /
# capacity*wm entries for the declared shape.  Returns r, or 0-1 io error,
# 0-2 bad header, 0-3 missing/extra rows, 0-4 bad entry row, 0-5 rank over
# capacity.
-> ffcc_load_int_scheme(path, dims, iu, iv, iw, capacity) (String i64[] i64[] i64[] i64[] i64) i64
  content = read_file(path)
  if content == nil
    return 0 - 1
  lines = content.split("\n")
  header = i64[4]
  have_header = 0 ## i64
  term = 0 ## i64
  row = 0 ## i64
  um = 0 ## i64
  vm = 0 ## i64
  wm = 0 ## i64
  rank = 0 ## i64
  index = 0 ## i64
  while index < lines.size()
    line = lines[index]
    if ffcc_blank_line(line) == 0 && ffcc_comment_line(line) == 0
      if have_header == 0
        if ffcc_parse_row(line, header, 0, 4) != 4
          return 0 - 2
        if header[0] < 1 || header[1] < 1 || header[2] < 1 || header[3] < 1
          return 0 - 2
        if header[0] > 7 || header[1] > 7 || header[2] > 7
          return 0 - 2
        dims[0] = header[0]
        dims[1] = header[1]
        dims[2] = header[2]
        dims[3] = header[3]
        um = header[0] * header[1]
        vm = header[1] * header[2]
        wm = header[0] * header[2]
        rank = header[3]
        if rank > capacity
          return 0 - 5
        have_header = 1
      else
        if term >= rank
          return 0 - 3
        parsed = 0 ## i64
        if row == 0
          parsed = ffcc_parse_row(line, iu, term * um, um)
        if row == 1
          parsed = ffcc_parse_row(line, iv, term * vm, vm)
        if row == 2
          parsed = ffcc_parse_row(line, iw, term * wm, wm)
        if parsed < 0
          return 0 - 4
        row += 1
        if row == 3
          row = 0
          term += 1
    index += 1
  if have_header == 0
    return 0 - 2
  if term != rank || row != 0
    return 0 - 3
  rank

# ---------------------------------------------------------------------------
# Admission gates (the campaign's only trust boundary).

# Full n^6 gate of emitted square masks in a fresh worker state.
-> ffcc_gate_square(us, vs, ws, count, n) (i64[] i64[] i64[] i64 i64) i64
  if count < 1 || n < 2 || n > 7
    return 0
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(state, us, vs, ws, count, n, capacity, 60901, 0, 1, 1, 1) ## i64
  if loaded == count && ffw_verify_current_exact(state, n) == 1
    return 1
  0

# Exhaustive rectangular gate (shape must be in the ffrp_supported allowlist).
-> ffcc_gate_rect(us, vs, ws, count, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if count < 1 || ffr_supported(n, m, p) == 0
    return 0
  capacity = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(capacity)]
  loaded = ffr_init_terms_cap(state, us, vs, ws, count, n, m, p, capacity, 60907, 0, 1, 1, 1) ## i64
  if loaded == count && ffr_verify_current_exact(state, n, m, p) == 1
    return 1
  0

# Gate, dump, re-parse, re-gate (the fffsp_run_engine publish discipline).
# Returns count on success; on any failure removes the file and returns 0-1.
-> ffcc_publish_square(us, vs, ws, count, n, path) (i64[] i64[] i64[] i64 i64 String) i64
  if count < 1 || n < 2 || n > 7 || path.size() < 1
    return 0 - 1
  z = system("/bin/rm -f " + ffcc_shell_quote(path))
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(state, us, vs, ws, count, n, capacity, 60911, 0, 1, 1, 1) ## i64
  if loaded != count || ffw_verify_current_exact(state, n) != 1
    return 0 - 1
  written = ffw_dump_current(state, path) ## i64
  if written == count
    replay = i64[ffw_state_size(capacity)]
    reloaded = ffw_load_scheme_cap(replay, path, n, capacity, 60913, 0, 1, 1, 1) ## i64
    if reloaded == count && ffw_verify_current_exact(replay, n) == 1
      return count
  z = system("/bin/rm -f " + ffcc_shell_quote(path))
  0 - 1

# ---------------------------------------------------------------------------
# Witness builders (planted regressions and bounded smokes).

-> ffcc_fill4(dst, offset, e0, e1, e2, e3) (i64[] i64 i64 i64 i64 i64) i64
  dst[offset] = e0
  dst[offset + 1] = e1
  dst[offset + 2] = e2
  dst[offset + 3] = e3
  1

# The true integer Strassen <2,2,2> witness, rank 7, entries in {-1,0,1},
# exact over Z (signs included; lambda absorbed into w).
-> ffcc_strassen_int(iu, iv, iw) (i64[] i64[] i64[]) i64
  z = ffcc_fill4(iu, 0, 1, 0, 0, 1) ## i64
  z = ffcc_fill4(iv, 0, 1, 0, 0, 1)
  z = ffcc_fill4(iw, 0, 1, 0, 0, 1)
  z = ffcc_fill4(iu, 4, 0, 0, 1, 1)
  z = ffcc_fill4(iv, 4, 1, 0, 0, 0)
  z = ffcc_fill4(iw, 4, 0, 0, 1, 0 - 1)
  z = ffcc_fill4(iu, 8, 1, 0, 0, 0)
  z = ffcc_fill4(iv, 8, 0, 1, 0, 0 - 1)
  z = ffcc_fill4(iw, 8, 0, 1, 0, 1)
  z = ffcc_fill4(iu, 12, 0, 0, 0, 1)
  z = ffcc_fill4(iv, 12, 0 - 1, 0, 1, 0)
  z = ffcc_fill4(iw, 12, 1, 0, 1, 0)
  z = ffcc_fill4(iu, 16, 1, 1, 0, 0)
  z = ffcc_fill4(iv, 16, 0, 0, 0, 1)
  z = ffcc_fill4(iw, 16, 0 - 1, 1, 0, 0)
  z = ffcc_fill4(iu, 20, 0 - 1, 0, 1, 0)
  z = ffcc_fill4(iv, 20, 1, 1, 0, 0)
  z = ffcc_fill4(iw, 20, 0, 0, 0, 1)
  z = ffcc_fill4(iu, 24, 0, 1, 0, 0 - 1)
  z = ffcc_fill4(iv, 24, 0, 0, 1, 1)
  z = ffcc_fill4(iw, 24, 1, 0, 0, 0)
  7

# Naive <n,m,p> integer witness: n*m*p all-plus-one terms, exact over Z.
-> ffcc_naive_int(iu, iv, iw, n, m, p) (i64[] i64[] i64[] i64 i64 i64) i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  t = 0 ## i64
  i = 0 ## i64
  while i < n
    j = 0 ## i64
    while j < m
      k = 0 ## i64
      while k < p
        e = 0 ## i64
        while e < um
          iu[t * um + e] = 0
          e += 1
        e = 0
        while e < vm
          iv[t * vm + e] = 0
          e += 1
        e = 0
        while e < wm
          iw[t * wm + e] = 0
          e += 1
        iu[t * um + i * m + j] = 1
        iv[t * vm + j * p + k] = 1
        iw[t * wm + i * p + k] = 1
        t += 1
        k += 1
      j += 1
    i += 1
  t

-> ffcc_copy_term(iu, iv, iw, src, dst, um, vm, wm) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  e = 0 ## i64
  while e < um
    iu[dst * um + e] = iu[src * um + e]
    e += 1
  e = 0
  while e < vm
    iv[dst * vm + e] = iv[src * vm + e]
    e += 1
  e = 0
  while e < wm
    iw[dst * wm + e] = iw[src * wm + e]
    e += 1
  1

-> ffcc_scale_factor(entries, offset, count, factor) (i64[] i64 i64 i64) i64
  e = 0 ## i64
  while e < count
    entries[offset + e] = entries[offset + e] * factor
    e += 1
  1

# Plant a 2-adic carry into an exact witness without changing its sum:
# term t (weight 1) becomes 3*t and -2*t is appended at slot r.  The carry
# recursion must emit t's reduction again at depth 1.
-> ffcc_plant_carry(iu, iv, iw, r, t, um, vm, wm) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  z = ffcc_copy_term(iu, iv, iw, t, r, um, vm, wm) ## i64
  z = ffcc_scale_factor(iu, r * um, um, 0 - 2)
  z = ffcc_scale_factor(iu, t * um, um, 3)
  r + 1

# 0/1 integer lift of GF(2) masks (a GF(2) scheme is NOT a characteristic-0
# witness; compiling a lift measures the 2-adic gap profile, the vacuity
# guard of the move-lab brief).
-> ffcc_lift_gf2(us, vs, ws, count, iu, iv, iw, um, vm, wm) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64) i64
  t = 0 ## i64
  while t < count
    e = 0 ## i64
    while e < um
      iu[t * um + e] = (us[t] >> e) & 1
      e += 1
    e = 0
    while e < vm
      iv[t * vm + e] = (vs[t] >> e) & 1
      e += 1
    e = 0
    while e < wm
      iw[t * wm + e] = (ws[t] >> e) & 1
      e += 1
    t += 1
  count
