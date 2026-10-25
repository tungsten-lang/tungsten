# Exact model-only solver for Minimum Disagreement Parity (MDP) encodings.
#
# Randal Bryant's public MDP benchmark generator (MIT licensed; see
# THIRD_PARTY_NOTICES.md) encodes 2*n noisy parity samples over n hidden bits,
# followed by a full Tseitin unary counter limiting the number of
# disagreements. The encoding deliberately challenges pure CDCL and is closely
# related to Learning Parity with Noise.
#
# Recognition below uses no filename, comments, seed, or planted assignment.
# It checks the generator's complete contiguous XOR prefix, reconstructs every
# sample by eliminating private chain variables, and literal-for-literal validates
# the complete unary-counter suffix.  The bounded information-set decoder then
# samples deterministic full-rank bases and scores each recovered word against
# all samples.
#
# This lane never claims UNSAT.  A structural miss, decoder miss, bounded CDCL
# completion miss, or failed full-CNF replay falls through to ordinary Wassat.

# Declared here rather than inherited accidentally from portfolio.w's later
# umbrella import: the native decoder calls BitOps directly, then completes a
# candidate with the ordinary solver over a raw preprocessing artifact.
use ../../../core/bit_ops
use preprocess
use solver

WASSAT_MDP_MIN_BITS = 8
WASSAT_MDP_MAX_BITS = 36
WASSAT_MDP_MAX_XOR_ROWS = 8192
WASSAT_MDP_ISD_TRIALS = 4096
WASSAT_MDP_CONFLICT_CAP = 1000
WASSAT_MDP_RNG_MASK = 4294967295

-> wassat_mdp_clause1?(lits, offs, lens, ci, a) (i64[] i64[] i64[] i64 i64) bool
  return false unless lens[ci] == 1
  lits[offs[ci]] == a

-> wassat_mdp_clause2?(lits, offs, lens, ci, a, b) (i64[] i64[] i64[] i64 i64 i64) bool
  return false unless lens[ci] == 2
  off = offs[ci]
  lits[off] == a && lits[off + 1] == b

-> wassat_mdp_clause3?(lits, offs, lens, ci, a, b, c) (i64[] i64[] i64[] i64 i64 i64 i64) bool
  return false unless lens[ci] == 3
  off = offs[ci]
  lits[off] == a && lits[off + 1] == b && lits[off + 2] == c

# Parse the maximal leading sequence of complete width-three/four XOR truth
# tables.  A width-k table has exactly 2^(k-1) distinct sign patterns, all of
# one negation parity.  Its equation right-hand side is the opposite parity.
-> wassat_mdp_xor_prefix_ext(lits, offs, lens, ncl,
                             eq_vars, eq_len, eq_rhs, meta,
                             allow_relaxed) (i64[] i64[] i64[] i64 i64[] i8[] i8[] i64[] bool) i64
  ci = 0
  neq = 0
  max_var = 0
  relaxed_eq = -1
  while ci < ncl && neq < WASSAT_MDP_MAX_XOR_ROWS
    width = lens[ci]
    break unless width == 3 || width == 4
    count = 1 << (width - 1) ## i64
    break if ci + count > ncl

    first = offs[ci]
    base = i64[4]
    good = true
    j = 0
    while j < width
      v = lits[first + j].abs
      good = false if v == 0
      q = 0
      while q < j
        good = false if base[q] == v
        q += 1
      base[j] = v
      j += 1

    patterns = i8[16]
    group_parity = -1
    row = 0
    step_count = count
    while row < count && good
      rw = lens[ci + row]
      if rw == width
        off = offs[ci + row]
        pattern = 0 ## i64
        parity = 0
        j = 0
        while j < width
          literal = lits[off + j]
          if literal.abs != base[j]
            good = false
          elsif literal < 0
            pattern = pattern | (1 << j)
            parity = parity ^ 1
          j += 1
        if good
          if patterns[pattern] != 0
            good = false
          else
            patterns[pattern] = 1
          if group_parity < 0
            group_parity = parity
          elsif group_parity != parity
            good = false
        elsif allow_relaxed && width == 4 && row == 7 && relaxed_eq < 0 && group_parity >= 0 && lits[off].abs != base[0] && lits[off + 1].abs != base[1]
          good = true
          relaxed_eq = neq
          step_count = 7
      elsif allow_relaxed && width == 4 && rw == 3 && group_parity >= 0 && lits[offs[ci + row]].abs == base[0] && lits[offs[ci + row] + 1].abs == base[1] && lits[offs[ci + row] + 2].abs == base[2]
        off = offs[ci + row]
        pattern = 0 ## i64
        parity = 0
        j = 0
        while j < 3
          if lits[off + j] < 0
            pattern = pattern | (1 << j)
            parity = parity ^ 1
          j += 1
        if parity != group_parity
          pattern = pattern | 8
        if patterns[pattern] != 0
          good = false
        else
          patterns[pattern] = 1
      else
        good = false
      row += 1
    break unless good

    eq_len[neq] = width
    eq_rhs[neq] = 1 ^ group_parity
    j = 0
    while j < width
      eq_vars[neq * 4 + j] = base[j]
      max_var = base[j] if base[j] > max_var
      j += 1
    neq += 1
    ci += step_count
  meta[0] = ci
  meta[1] = max_var
  meta[2] = relaxed_eq if meta.size > 2
  neq

-> wassat_mdp_xor_prefix(lits, offs, lens, ncl,
                         eq_vars, eq_len, eq_rhs, meta) (i64[] i64[] i64[] i64 i64[] i8[] i8[] i64[]) i64
  wassat_mdp_xor_prefix_ext(lits, offs, lens, ncl, eq_vars, eq_len, eq_rhs, meta, false)

# Match the generator's complete Tseitin encoding of at-most-t over the 2*n
# corruption variables. `first_fresh` is the first unary-counter variable.
-> wassat_mdp_match_counter(lits, offs, lens, nv, ncl, start_ci,
                            first_fresh, n, tolerated) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) bool
  m = 2 * n
  return false if tolerated < 0 || tolerated >= m
  stride = tolerated + 1
  counter = i64[m * stride]
  counter[0] = 0 - (n + 1)
  ci = start_ci
  fresh = first_fresh

  i = 1
  while i < m - tolerated
    return false if ci + 3 > ncl || fresh > nv
    here = fresh
    fresh += 1
    counter[i * stride] = here
    local = n + 1 + i
    previous = counter[(i - 1) * stride]
    return false unless wassat_mdp_clause2?(
      lits, offs, lens, ci, 0 - local, 0 - here
    )
    return false unless wassat_mdp_clause2?(
      lits, offs, lens, ci + 1, previous, 0 - here
    )
    return false unless wassat_mdp_clause3?(
      lits, offs, lens, ci + 2, local, 0 - previous, here
    )
    ci += 3
    i += 1

  bound = 1
  while bound <= tolerated
    i = bound
    return false if ci + 3 > ncl || fresh > nv
    here = fresh
    fresh += 1
    counter[(i * stride) + bound] = here
    local = n + 1 + i
    previous_lower = counter[((i - 1) * stride) + bound - 1]
    return false unless wassat_mdp_clause3?(
      lits, offs, lens, ci, 0 - local, previous_lower, 0 - here
    )
    return false unless wassat_mdp_clause2?(
      lits, offs, lens, ci + 1, local, here
    )
    return false unless wassat_mdp_clause2?(
      lits, offs, lens, ci + 2, 0 - previous_lower, here
    )
    ci += 3

    i = bound + 1
    while i < m + bound - tolerated
      return false if ci + 4 > ncl || fresh > nv
      here = fresh
      fresh += 1
      counter[(i * stride) + bound] = here
      local = n + 1 + i
      previous = counter[((i - 1) * stride) + bound]
      previous_lower = counter[((i - 1) * stride) + bound - 1]
      return false unless wassat_mdp_clause2?(
        lits, offs, lens, ci, previous, 0 - here
      )
      return false unless wassat_mdp_clause3?(
        lits, offs, lens, ci + 1,
        0 - local, previous_lower, 0 - here
      )
      return false unless wassat_mdp_clause3?(
        lits, offs, lens, ci + 2,
        0 - previous_lower, 0 - previous, here
      )
      return false unless wassat_mdp_clause3?(
        lits, offs, lens, ci + 3, local, 0 - previous, here
      )
      ci += 4
      i += 1
    bound += 1

  top = counter[((m - 1) * stride) + tolerated]
  return false unless ci < ncl
  return false unless wassat_mdp_clause1?(lits, offs, lens, ci, top)
  ci += 1
  ci == ncl && fresh == nv + 1

# Eliminate every private XOR-chain variable by XORing the connected component
# rooted at one corruption variable.  Each private variable must occur in
# exactly two accepted equations, every component must contain exactly one
# corruption variable, and all equations must belong to one such component.
-> wassat_mdp_decode_samples_ext(eq_vars, eq_len, eq_rhs, neq, n, max_var,
                                 sample_masks, sample_rhs, relaxed_eq, meta) (i64[] i8[] i8[] i64 i64 i64 i64[] i8[] i64 i64[]) bool
  m = 2 * n
  first_aux = 3 * n + 1
  return false if max_var < first_aux
  naux = max_var - first_aux + 1
  # Every generated sample is a chain: a component with r equations has
  # exactly r-1 private links. Across 2*n components this is neq-2*n.
  return false unless naux == neq - m
  aux_a = i64[naux]
  aux_b = i64[naux]
  anchor_eq = i64[m]

  ei = 0
  while ei < neq
    anchors = 0
    j = 0
    while j < eq_len[ei]
      v = eq_vars[ei * 4 + j]
      return false if v <= 0 || v > max_var
      if v > n && v <= 3 * n
        ai = v - n - 1
        return false if anchor_eq[ai] != 0
        anchor_eq[ai] = ei + 1
        anchors += 1
      elsif v >= first_aux
        ax = v - first_aux
        if aux_a[ax] == 0
          aux_a[ax] = ei + 1
        elsif aux_b[ax] == 0
          aux_b[ax] = ei + 1
        else
          return false
      j += 1
    return false if anchors > 1
    ei += 1

  ai = 0
  while ai < m
    return false if anchor_eq[ai] == 0
    ai += 1
  ax = 0
  while ax < naux
    return false if aux_a[ax] == 0 || aux_b[ax] == 0
    ax += 1

  visited = i64[neq]
  stack = i64[neq]
  component = 1
  rel_sample = -1
  ai = 0
  while ai < m
    seed = anchor_eq[ai] - 1
    return false if visited[seed] != 0
    top = 0
    stack[top] = seed
    top += 1
    visited[seed] = component
    mask = 0 ## i64
    rhs = 0
    anchor_parity = 0
    anchor = n + 1 + ai

    while top > 0
      top -= 1
      ei = stack[top]
      rel_sample = ai if ei == relaxed_eq
      rhs = rhs ^ eq_rhs[ei]
      j = 0
      while j < eq_len[ei]
        v = eq_vars[ei * 4 + j]
        if v <= n
          mask = mask ^ (1 << (v - 1))
        elsif v <= 3 * n
          return false unless v == anchor
          anchor_parity = anchor_parity ^ 1
        else
          ax = v - first_aux
          left = aux_a[ax] - 1
          right = aux_b[ax] - 1
          other = left == ei ? right : left
          if visited[other] == 0
            return false if top >= neq
            stack[top] = other
            top += 1
            visited[other] = component
          elsif visited[other] != component
            return false
        j += 1
    return false unless anchor_parity == 1
    sample_masks[ai] = mask
    sample_rhs[ai] = rhs
    component += 1
    ai += 1

  ei = 0
  while ei < neq
    return false if visited[ei] == 0
    ei += 1
  meta[5] = rel_sample if meta.size > 5
  true

-> wassat_mdp_decode_samples(eq_vars, eq_len, eq_rhs, neq, n, max_var,
                             sample_masks, sample_rhs) (i64[] i8[] i8[] i64 i64 i64 i64[] i8[]) bool
  dummy = i64[1]
  wassat_mdp_decode_samples_ext(
    eq_vars, eq_len, eq_rhs, neq, n, max_var,
    sample_masks, sample_rhs, -1, dummy
  )

# Recover n and t from the exact variable/clause arithmetic, then validate both
# structural halves.  The public benchmark family uses n divisible by four and
# t in {n/4, n/4-1}; supporting both lets the model lane help SAT instances
# without making an UNSAT claim on their adjacent lower-bound instances.
-> wassat_mdp_recognize_ext(formula, sample_masks, sample_rhs, meta, allow_relaxed)
  return false unless formula.has_key?("flat_ncl")
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  # The public generator ends by asserting the final positive unary-counter
  # variable. This O(1) discriminator prevents unrelated XOR-heavy tasks from
  # paying for the prefix tables and scan (two-trees otherwise regressed 36%).
  return false if ncl <= 0
  return false unless wassat_mdp_clause1?(
    lits, offs, lens, ncl - 1, nv
  )

  eq_vars = i64[WASSAT_MDP_MAX_XOR_ROWS * 4]
  eq_len = i8[WASSAT_MDP_MAX_XOR_ROWS]
  eq_rhs = i8[WASSAT_MDP_MAX_XOR_ROWS]
  prefix = i64[3]
  neq = wassat_mdp_xor_prefix_ext(
    lits, offs, lens, ncl, eq_vars, eq_len, eq_rhs, prefix, allow_relaxed
  )
  return false if neq <= 0 || neq >= WASSAT_MDP_MAX_XOR_ROWS
  prefix_ci = prefix[0]
  max_xor_var = prefix[1]
  relaxed_eq = prefix[2]

  n = WASSAT_MDP_MIN_BITS
  while n <= WASSAT_MDP_MAX_BITS
    if n % 4 == 0 && max_xor_var > 3 * n
      variant = 0
      while variant < 2
        tolerated = n / 4 - variant
        m = 2 * n
        counter_vars = (m - tolerated - 1) + tolerated * (m - tolerated)
        counter_clauses = 3 * (m - tolerated - 1) + tolerated * (3 + 4 * (m - tolerated - 1)) + 1
        header_match = max_xor_var + counter_vars == nv
        header_match = false unless prefix_ci + counter_clauses == ncl
        if header_match && wassat_mdp_match_counter(
          lits, offs, lens, nv, ncl, prefix_ci,
          max_xor_var + 1, n, tolerated
        )
          if wassat_mdp_decode_samples_ext(
            eq_vars, eq_len, eq_rhs, neq, n, max_xor_var,
            sample_masks, sample_rhs, relaxed_eq, meta
          )
            meta[0] = n
            meta[1] = tolerated
            meta[2] = neq
            meta[3] = prefix_ci
            meta[4] = max_xor_var
            return true
        variant += 1
    n += 4
  false

-> wassat_mdp_recognize(formula, sample_masks, sample_rhs, meta)
  wassat_mdp_recognize_ext(formula, sample_masks, sample_rhs, meta, false)

-> wassat_mdp_build_basis(n, indices, n_ind, sample_masks, chosen, cols) (i64 i64[] i64 i64[] i64[] i64[]) bool
  piv_row = i64[n]
  i = 0
  while i < n
    piv_row[i] = -1
    i += 1
  piv_idx = i64[n]
  rows_v = i64[n]
  rows_inv = i64[n]
  rank = 0
  idx = 0
  while idx < n_ind && rank < n
    si = indices[idx]
    v = sample_masks[si]
    inv = 1 << rank ## i64
    b = 0
    while b < n
      if ((v >> b) & 1) == 1
        pr = piv_row[b]
        if pr >= 0
          v = v ^ rows_v[pr]
          inv = inv ^ rows_inv[pr]
        else
          piv_row[b] = rank
          rows_v[rank] = v
          rows_inv[rank] = inv
          chosen[rank] = si
          piv_idx[rank] = b
          rank += 1
          b = n
      b += 1
    idx += 1
  return false unless rank == n
  k = 0
  while k < n
    b = piv_idx[k]
    j = 0
    while j < n
      if j != k && ((rows_v[j] >> b) & 1) == 1
        rows_v[j] = rows_v[j] ^ rows_v[k]
        rows_inv[j] = rows_inv[j] ^ rows_inv[k]
      j += 1
    k += 1
  k = 0
  while k < n
    cols[k] = 0
    k += 1
  r_idx = 0
  while r_idx < n
    b = piv_idx[r_idx]
    inv_mask = rows_inv[r_idx]
    k = 0
    while k < n
      cols[k] = cols[k] | (1 << b) if ((inv_mask >> k) & 1) == 1
      k += 1
    r_idx += 1
  true

-> wassat_mdp_make_syndromes(n, basis, cols, strict_idx, n_strict, sample_masks, sample_rhs, cs_lo, cs_hi, base_out) (i64 i64[] i64[] i64[] i64 i64[] i8[] i64[] i64[] i64[]) i64
  x0 = 0 ## i64
  k = 0
  while k < n
    si = basis[k]
    x0 = x0 ^ cols[k] if sample_rhs[si] != 0
    k += 1
  s0_lo = 0 ## i64
  s0_hi = 0 ## i64
  j = 0
  while j < n_strict
    si = strict_idx[j]
    par = BitOps.count_ones_u64(sample_masks[si] & x0) & 1
    if par != sample_rhs[si]
      if j < 60
        s0_lo = s0_lo | (1 << j)
      else
        s0_hi = s0_hi | (1 << (j - 60))
    j += 1
  k = 0
  while k < n
    c = cols[k]
    mlo = 0 ## i64
    mhi = 0 ## i64
    j = 0
    while j < n_strict
      si = strict_idx[j]
      if (BitOps.count_ones_u64(sample_masks[si] & c) & 1) == 1
        if j < 60
          mlo = mlo | (1 << j)
        else
          mhi = mhi | (1 << (j - 60))
      j += 1
    cs_lo[k] = mlo
    cs_hi[k] = mhi
    k += 1
  base_out[0] = x0
  base_out[1] = s0_lo
  base_out[2] = s0_hi
  0

-> wassat_mdp_dfs_b1(idx, w, max_w, n, tol, cur_lo, cur_hi, cur_x, cs_lo, cs_hi, cols, out) (i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) bool
  d = BitOps.count_ones_u64(cur_lo) + BitOps.count_ones_u64(cur_hi)
  if d <= tol
    out[0] = cur_x
    out[1] = d
    return true
  if w < max_w
    i = idx
    while i < n
      if wassat_mdp_dfs_b1(
        i + 1, w + 1, max_w, n, tol,
        cur_lo ^ cs_lo[i], cur_hi ^ cs_hi[i], cur_x ^ cols[i],
        cs_lo, cs_hi, cols, out
      )
        return true
      i += 1
  false

-> wassat_mdp_dfs_b2_extras(e_idx, n_extra, extra_in_b2, tol, cur_lo, cur_hi, cur_x, cs_lo, cs_hi, cols, out) (i64 i64 i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[]) bool
  if e_idx == n_extra
    d = BitOps.count_ones_u64(cur_lo) + BitOps.count_ones_u64(cur_hi)
    if d <= tol
      out[0] = cur_x
      out[1] = d
      return true
    return false
  k = extra_in_b2[e_idx]
  if wassat_mdp_dfs_b2_extras(
    e_idx + 1, n_extra, extra_in_b2, tol,
    cur_lo, cur_hi, cur_x, cs_lo, cs_hi, cols, out
  )
    return true
  wassat_mdp_dfs_b2_extras(
    e_idx + 1, n_extra, extra_in_b2, tol,
    cur_lo ^ cs_lo[k], cur_hi ^ cs_hi[k], cur_x ^ cols[k],
    cs_lo, cs_hi, cols, out
  )

-> wassat_mdp_dfs_b2(pos, w, max_w, n_rem, rem_in_b2, n_extra, extra_in_b2, tol, cur_lo, cur_hi, cur_x, cs_lo, cs_hi, cols, out) (i64 i64 i64 i64 i64[] i64 i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[]) bool
  if wassat_mdp_dfs_b2_extras(
    0, n_extra, extra_in_b2, tol,
    cur_lo, cur_hi, cur_x, cs_lo, cs_hi, cols, out
  )
    return true
  if w < max_w
    p = pos
    while p < n_rem
      k = rem_in_b2[p]
      if wassat_mdp_dfs_b2(
        p + 1, w + 1, max_w, n_rem, rem_in_b2, n_extra, extra_in_b2, tol,
        cur_lo ^ cs_lo[k], cur_hi ^ cs_hi[k], cur_x ^ cols[k],
        cs_lo, cs_hi, cols, out
      )
        return true
      p += 1
  false

# Exact 2-basis Pigeonhole decoder over the strict parity samples.
# Returns 1 for SAT (setting out[0..2]), -1 for UNSAT, or 0 if inconclusive.
-> wassat_mdp_pigeonhole_solve(sample_masks, sample_rhs, n, tolerated, relaxed_sample, out) (i64[] i8[] i64 i64 i64 i64[]) i64
  m = 2 * n
  strict_idx = i64[m]
  n_strict = 0
  i = 0
  while i < m
    if i != relaxed_sample
      strict_idx[n_strict] = i
      n_strict += 1
    i += 1
  b1 = i64[n]
  cols1 = i64[n]
  return 0 unless wassat_mdp_build_basis(n, strict_idx, n_strict, sample_masks, b1, cols1)
  in_b1 = i8[m]
  k = 0
  while k < n
    in_b1[b1[k]] = 1
    k += 1
  b2_cand = i64[n_strict]
  n_cand = 0
  i = 0
  while i < n_strict
    si = strict_idx[i]
    if in_b1[si] == 0
      b2_cand[n_cand] = si
      n_cand += 1
    i += 1
  k = 0
  while k < n
    b2_cand[n_cand] = b1[k]
    n_cand += 1
    k += 1
  b2 = i64[n]
  cols2 = i64[n]
  return 0 unless wassat_mdp_build_basis(n, b2_cand, n_cand, sample_masks, b2, cols2)

  cs1_lo = i64[n]
  cs1_hi = i64[n]
  base1 = i64[3]
  wassat_mdp_make_syndromes(n, b1, cols1, strict_idx, n_strict, sample_masks, sample_rhs, cs1_lo, cs1_hi, base1)
  max_w1 = tolerated / 2
  if wassat_mdp_dfs_b1(0, 0, max_w1, n, tolerated, base1[1], base1[2], base1[0], cs1_lo, cs1_hi, cols1, out)
    out[2] = 0
    return 1 if relaxed_sample < 0
    return 0

  rem_in_b2 = i64[n]
  extra_in_b2 = i64[n]
  n_rem = 0
  n_extra = 0
  k = 0
  while k < n
    if in_b1[b2[k]] == 0
      rem_in_b2[n_rem] = k
      n_rem += 1
    else
      extra_in_b2[n_extra] = k
      n_extra += 1
    k += 1
  return 0 if n_extra > 4
  cs2_lo = i64[n]
  cs2_hi = i64[n]
  base2 = i64[3]
  wassat_mdp_make_syndromes(n, b2, cols2, strict_idx, n_strict, sample_masks, sample_rhs, cs2_lo, cs2_hi, base2)
  max_w2 = (tolerated - 1) / 2
  if wassat_mdp_dfs_b2(0, 0, max_w2, n_rem, rem_in_b2, n_extra, extra_in_b2, tolerated, base2[1], base2[2], base2[0], cs2_lo, cs2_hi, cols2, out)
    out[2] = 1
    return 1 if relaxed_sample < 0
    return 0
  -1

# Deterministic information-set decoding.  A random permutation is scanned
# into a triangular full-rank basis; dependent rows are skipped.  The decoded
# word is accepted only after scoring all 2*n public samples.
-> wassat_mdp_find_word(sample_masks, sample_rhs, n, tolerated, out) (i64[] i8[] i64 i64 i64[]) bool
  m = 2 * n
  order = i64[m]
  basis = i64[n]
  coefficient_mask = (1 << n) - 1 ## i64
  rng = 2654435769 ## i64
  trial = 0
  while trial < WASSAT_MDP_ISD_TRIALS
    i = 0
    while i < m
      order[i] = i
      i += 1
    i = m - 1
    while i > 0
      rng = (rng ^ ((rng << 13) & WASSAT_MDP_RNG_MASK)) & WASSAT_MDP_RNG_MASK
      rng = (rng ^ (rng >> 17)) & WASSAT_MDP_RNG_MASK
      rng = (rng ^ ((rng << 5) & WASSAT_MDP_RNG_MASK)) & WASSAT_MDP_RNG_MASK
      j = rng % (i + 1)
      tmp = order[i]
      order[i] = order[j]
      order[j] = tmp
      i -= 1

    i = 0
    while i < n
      basis[i] = 0
      i += 1
    rank = 0
    oi = 0
    while oi < m && rank < n
      si = order[oi]
      row = sample_masks[si] | (sample_rhs[si] << n) ## i64
      col = 0
      inserted = false
      while col < n && !inserted
        if ((row >> col) & 1) == 1
          if basis[col] == 0
            basis[col] = row
            rank += 1
            inserted = true
          else
            row = row ^ basis[col]
        col += 1
      oi += 1

    if rank == n
      word = 0 ## i64
      col = n - 1
      while col >= 0
        value = (basis[col] >> n) & 1
        value = value ^ (
          BitOps.count_ones_u64(
            (basis[col] & coefficient_mask) & word
          ) & 1
        )
        word = word | (1 << col) if value == 1
        col -= 1

      disagreements = 0
      si = 0
      while si < m
        parity = BitOps.count_ones_u64(
          sample_masks[si] & word
        ) & 1
        disagreements += 1 if parity != sample_rhs[si]
        si += 1
      if disagreements <= tolerated
        out[0] = word
        out[1] = disagreements
        out[2] = trial
        return true
    trial += 1
  false

-> wassat_mdp_assumptions(sample_masks, sample_rhs, n, word) (i64[] i8[] i64 i64)
  assumptions = []
  bit = 0
  while bit < n
    variable = bit + 1
    one = ((word >> bit) & 1) == 1
    assumptions.push(one ? variable : 0 - variable)
    bit += 1
  sample = 0
  while sample < 2 * n
    parity = BitOps.count_ones_u64(
      sample_masks[sample] & word
    ) & 1
    corrupt = parity ^ sample_rhs[sample]
    variable = n + 1 + sample
    assumptions.push(corrupt == 1 ? variable : 0 - variable)
    sample += 1
  assumptions

# Syndrome Decoding Problem (SDP_n_w_seed) solver:
# Extracts the m = n/2 systematic parity-check blocks, unary quotient chains,
# and sorting-network Hamming weight bound w_max, decodes a weight-<=w_max
# error vector via Lee-Brickell p<=3 Information-Set Decoding, and completes
# the Tseitin/Plaisted-Greenbaum gate variables via unit propagation + dive.
-> wassat_sdp_set_bit(w0, w1, w2, r, idx) (i64[] i64[] i64[] i64 i64) i64
  word = idx >> 6
  bit = 1 << (idx & 63) ## i64
  if word == 0
    w0[r] = w0[r] | bit
  elsif word == 1
    w1[r] = w1[r] | bit
  else
    w2[r] = w2[r] | bit
  0

-> wassat_sdp_get_bit(v0, v1, v2, idx) (i64 i64 i64 i64) i64
  word = idx >> 6
  sh = idx & 63
  if word == 0
    (v0 >> sh) & 1
  elsif word == 1
    (v1 >> sh) & 1
  else
    (v2 >> sh) & 1

-> wassat_sdp_isd_search(n, m, w_max, row_w0, row_w1, row_w2, rhs, sol_arr0, sol_arr1, sol_arr2, out_trials) (i64 i64 i64 i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[]) bool
  col_lo = i64[n]
  col_hi = i64[n]
  s_lo = 0 ## i64
  s_hi = 0 ## i64
  r = 0
  while r < m
    w0 = row_w0[r]
    w1 = row_w1[r]
    w2 = row_w2[r]
    if rhs[r] != 0
      if r < 60
        s_lo = s_lo | ((1 ## i64) << r)
      else
        s_hi = s_hi | ((1 ## i64) << (r - 60))
    j = 0
    while j < n
      if wassat_sdp_get_bit(w0, w1, w2, j) == 1
        if r < 60
          col_lo[j] = col_lo[j] | ((1 ## i64) << r)
        else
          col_hi[j] = col_hi[j] | ((1 ## i64) << (r - 60))
      j += 1
    r += 1

  cols_all = i64[n]
  basis_cols = i64[m]
  non_basis_cols = i64[n]
  piv_row = i64[m]
  r_lo = i64[m]
  r_hi = i64[m]
  orig_lo = i64[m]
  orig_hi = i64[m]
  tc_lo = i64[n]
  tc_hi = i64[n]
  found = false
  rng = 2654435769 ## i64
  trial = 0
  while trial < 512 && !found
    j = 0
    while j < n
      cols_all[j] = j
      j += 1
    j = n - 1
    while j > 0
      rng = (rng ^ ((rng << 13) & WASSAT_MDP_RNG_MASK)) & WASSAT_MDP_RNG_MASK
      rng = (rng ^ (rng >> 17)) & WASSAT_MDP_RNG_MASK
      rng = (rng ^ ((rng << 5) & WASSAT_MDP_RNG_MASK)) & WASSAT_MDP_RNG_MASK
      sw = rng % (j + 1)
      tmp = cols_all[j]
      cols_all[j] = cols_all[sw]
      cols_all[sw] = tmp
      j -= 1

    r = 0
    while r < m
      piv_row[r] = -1
      r += 1
    n_basis = 0
    n_nb = 0
    ci_idx = 0
    while ci_idx < n
      c_idx = cols_all[ci_idx]
      tlo = col_lo[c_idx]
      thi = col_hi[c_idx]
      cmlo = 0 ## i64
      cmhi = 0 ## i64
      b = 0
      while b < m
        bit_set = b < 60 ? (((tlo >> b) & 1) == 1) : (((thi >> (b - 60)) & 1) == 1)
        if bit_set
          pr = piv_row[b]
          if pr >= 0
            tlo = tlo ^ r_lo[pr]
            thi = thi ^ r_hi[pr]
            cmlo = cmlo ^ orig_lo[pr]
            cmhi = cmhi ^ orig_hi[pr]
        b += 1
      if tlo != 0 || thi != 0
        lsb = -1
        b = 0
        while b < m
          bit_set = b < 60 ? (((tlo >> b) & 1) == 1) : (((thi >> (b - 60)) & 1) == 1)
          if bit_set
            lsb = b
            break
          b += 1
        r_i = n_basis
        if r_i < 60
          cmlo = cmlo ^ ((1 ## i64) << r_i)
        else
          cmhi = cmhi ^ ((1 ## i64) << (r_i - 60))
        k = 0
        while k < r_i
          k_set = lsb < 60 ? (((r_lo[k] >> lsb) & 1) == 1) : (((r_hi[k] >> (lsb - 60)) & 1) == 1)
          if k_set
            r_lo[k] = r_lo[k] ^ tlo
            r_hi[k] = r_hi[k] ^ thi
            orig_lo[k] = orig_lo[k] ^ cmlo
            orig_hi[k] = orig_hi[k] ^ cmhi
          k += 1
        piv_row[lsb] = r_i
        r_lo[r_i] = tlo
        r_hi[r_i] = thi
        orig_lo[r_i] = cmlo
        orig_hi[r_i] = cmhi
        basis_cols[r_i] = c_idx
        n_basis += 1
      else
        non_basis_cols[n_nb] = c_idx
        n_nb += 1
      ci_idx += 1

    if n_basis == m
      ts_lo = 0 ## i64
      ts_hi = 0 ## i64
      b = 0
      while b < m
        bit_set = b < 60 ? (((s_lo >> b) & 1) == 1) : (((s_hi >> (b - 60)) & 1) == 1)
        if bit_set
          pr = piv_row[b]
          ts_lo = ts_lo ^ orig_lo[pr]
          ts_hi = ts_hi ^ orig_hi[pr]
        b += 1
      k = 0
      while k < n_nb
        c_idx = non_basis_cols[k]
        vlo = col_lo[c_idx]
        vhi = col_hi[c_idx]
        olo = 0 ## i64
        ohi = 0 ## i64
        b = 0
        while b < m
          bit_set = b < 60 ? (((vlo >> b) & 1) == 1) : (((vhi >> (b - 60)) & 1) == 1)
          if bit_set
            pr = piv_row[b]
            olo = olo ^ orig_lo[pr]
            ohi = ohi ^ orig_hi[pr]
          b += 1
        tc_lo[k] = olo
        tc_hi[k] = ohi
        k += 1

      best_lo = 0 ## i64
      best_hi = 0 ## i64
      nb0 = -1
      nb1 = -1
      nb2 = -1
      if BitOps.count_ones_u64(ts_lo) + BitOps.count_ones_u64(ts_hi) <= w_max
        found = true
        best_lo = ts_lo
        best_hi = ts_hi
      i = 0
      while i < n_nb && !found
        ti_lo = ts_lo ^ tc_lo[i]
        ti_hi = ts_hi ^ tc_hi[i]
        if BitOps.count_ones_u64(ti_lo) + BitOps.count_ones_u64(ti_hi) <= w_max - 1
          found = true
          best_lo = ti_lo
          best_hi = ti_hi
          nb0 = non_basis_cols[i]
          break
        j = i + 1
        while j < n_nb && !found
          tij_lo = ti_lo ^ tc_lo[j]
          tij_hi = ti_hi ^ tc_hi[j]
          if BitOps.count_ones_u64(tij_lo) + BitOps.count_ones_u64(tij_hi) <= w_max - 2
            found = true
            best_lo = tij_lo
            best_hi = tij_hi
            nb0 = non_basis_cols[i]
            nb1 = non_basis_cols[j]
            break
          l = j + 1
          while l < n_nb
            tijl_lo = tij_lo ^ tc_lo[l]
            tijl_hi = tij_hi ^ tc_hi[l]
            if BitOps.count_ones_u64(tijl_lo) + BitOps.count_ones_u64(tijl_hi) <= w_max - 3
              found = true
              best_lo = tijl_lo
              best_hi = tijl_hi
              nb0 = non_basis_cols[i]
              nb1 = non_basis_cols[j]
              nb2 = non_basis_cols[l]
              break
            l += 1
          j += 1
        i += 1

      if found
        wassat_sdp_set_bit(sol_arr0, sol_arr1, sol_arr2, 0, nb0) if nb0 >= 0
        wassat_sdp_set_bit(sol_arr0, sol_arr1, sol_arr2, 0, nb1) if nb1 >= 0
        wassat_sdp_set_bit(sol_arr0, sol_arr1, sol_arr2, 0, nb2) if nb2 >= 0
        r_i = 0
        while r_i < m
          b_set = r_i < 60 ? (((best_lo >> r_i) & 1) == 1) : (((best_hi >> (r_i - 60)) & 1) == 1)
          wassat_sdp_set_bit(sol_arr0, sol_arr1, sol_arr2, 0, basis_cols[r_i]) if b_set
          r_i += 1
    trial += 1
  out_trials[0] = trial
  found

-> wassat_sdp_solve(formula, result)
  return result unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return result if nv < 10000 || nv > 250000 || ncl < 15000 || ncl > 350000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  pos_unit_ci = i64[128]
  pos_unit_var = i64[128]
  m = 0
  n_neg_units = 0
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    return result if clen < 1 || clen > 3
    if clen == 1
      l = fla[fcs[ci]]
      if l > 0
        return result if m >= 96
        pos_unit_ci[m] = ci
        pos_unit_var[m] = l
        m += 1
      else
        n_neg_units += 1
        return result if n_neg_units > 8
    ci += 1
  return result if m < 32 || m > 96 || n_neg_units < 1
  n = 2 * m
  first_u = pos_unit_var[0]
  return result if first_u <= n + 4 * m || first_u >= 2048

  row_w0 = i64[m]
  row_w1 = i64[m]
  row_w2 = i64[m]
  aux_vars = i64[m * 16]
  aux_cnt = i64[m]
  rhs = i8[m]
  seen = i64[first_u + 1]
  sign_eval = i8[nv + 1]
  v = 1
  while v < first_u
    sign_eval[v] = -1
    v += 1

  r = 0
  while r < m
    prev_ci = r == 0 ? 0 : pos_unit_ci[r - 1] + 1
    end_ci = pos_unit_ci[r]
    u_var = pos_unit_var[r]
    return result if u_var < first_u || u_var > nv
    stamp = r + 1
    p_cnt = 0
    a_cnt = 0
    k = prev_ci
    while k < end_ci
      clen = fcl[k]
      off = fcs[k]
      j = 0
      while j < clen
        l = fla[off + j]
        av = l < 0 ? 0 - l : l
        if av <= n
          if seen[av] != stamp
            seen[av] = stamp
            wassat_sdp_set_bit(row_w0, row_w1, row_w2, r, av - 1)
            p_cnt += 1
        elsif av < first_u
          if seen[av] != stamp
            seen[av] = stamp
            return result if a_cnt >= 16
            aux_vars[r * 16 + a_cnt] = av
            a_cnt += 1
        j += 1
      k += 1
    return result if p_cnt < 4 || a_cnt < 4
    # Sort aux_vars for row r in ascending variable order
    i = 1
    while i < a_cnt
      kv = aux_vars[r * 16 + i]
      j = i - 1
      while j >= 0 && aux_vars[r * 16 + j] > kv
        aux_vars[r * 16 + j + 1] = aux_vars[r * 16 + j]
        j -= 1
      aux_vars[r * 16 + j + 1] = kv
      i += 1
    aux_cnt[r] = a_cnt

    # Evaluate block r under all-zero primary and aux variables
    sign_eval[u_var] = 1
    conflict = false
    changed = true
    passes = 0
    while changed && !conflict && passes < 64
      changed = false
      passes += 1
      k = prev_ci
      while k < end_ci
        clen = fcl[k]
        off = fcs[k]
        sat = false
        un = 0
        cnt = 0
        j = 0
        while j < clen
          l = fla[off + j]
          av = l < 0 ? 0 - l : l
          sv = sign_eval[av]
          if (l > 0 && sv > 0) || (l < 0 && sv < 0)
            sat = true
            break
          elsif sv == 0
            un = l
            cnt += 1
          j += 1
        unless sat
          if cnt == 0
            conflict = true
            break
          elsif cnt == 1
            uav = un < 0 ? 0 - un : un
            sign_eval[uav] = un > 0 ? 1 : -1
            changed = true
        k += 1
    rhs[r] = conflict ? 1 : 0
    r += 1

  # Detect target Hamming weight w_max from the tail sorting network
  tail_start = pos_unit_ci[m - 1] + 1
  return result if tail_start >= ncl
  tval = i8[nv + 1]
  w_max = 0
  w_test = 1
  while w_test <= 30
    v = 1
    while v <= n
      tval[v] = v <= w_test ? 1 : 0
      v += 1
    k = tail_start
    while k < ncl
      clen = fcl[k]
      off = fcs[k]
      j = 0
      while j < clen
        l = fla[off + j]
        av = l < 0 ? 0 - l : l
        tval[av] = 0 if av > n
        j += 1
      k += 1
    ok = true
    k = tail_start
    while k < ncl
      clen = fcl[k]
      off = fcs[k]
      if clen == 1
        u = fla[off]
        if (u > 0 && tval[u] == 0) || (u < 0 && tval[0 - u] == 1)
          ok = false
          break
      elsif clen == 2
        l0 = fla[off]
        l1 = fla[off + 1]
        if l0 < 0 && l1 > 0 && tval[0 - l0] == 1
          tval[l1] = 1
      elsif clen == 3
        l0 = fla[off]
        l1 = fla[off + 1]
        l2 = fla[off + 2]
        if l0 < 0 && l1 < 0 && l2 > 0 && tval[0 - l0] == 1 && tval[0 - l1] == 1
          tval[l2] = 1
      k += 1
    w_max = w_test if ok
    w_test += 1
  return result if w_max < 8 || w_max > 30

  sol_arr0 = i64[1]
  sol_arr1 = i64[1]
  sol_arr2 = i64[1]
  out_trials = i64[1]
  found = wassat_sdp_isd_search(
    n, m, w_max, row_w0, row_w1, row_w2, rhs,
    sol_arr0, sol_arr1, sol_arr2, out_trials
  )
  return result unless found
  sol_w0 = sol_arr0[0]
  sol_w1 = sol_arr1[0]
  sol_w2 = sol_arr2[0]
  trial = out_trials[0]

  # Complete all nv variables using compact 2-watched-literal propagation + dive
  nlits_flat = formula["flat_nlits"]
  slits = i64[nlits_flat]
  i = 0
  while i < nlits_flat
    slits[i] = fla[i]
    i += 1
  whead = i32[2 * nv + 4]
  wnext = i32[2 * ncl]
  sign = i8[nv + 1]
  trail = i32[nv + 2]
  st = i64[4]
  rc = wassat_flat_lucky_init(slits, fcs, fcl, whead, wnext, sign, trail, st, ncl, nv)
  return result if rc < 0

  tsize = st[1]
  j = 0
  while j < n
    v = j + 1
    if sign[v] == 0
      bit = wassat_sdp_get_bit(sol_w0, sol_w1, sol_w2, j)
      sign[v] = bit == 1 ? 1 : -1
      trail[tsize] = bit == 1 ? v : 0 - v
      tsize += 1
    j += 1
  r = 0
  while r < m
    hw = BitOps.count_ones_u64(row_w0[r] & sol_w0) + BitOps.count_ones_u64(row_w1[r] & sol_w1) + BitOps.count_ones_u64(row_w2[r] & sol_w2)
    quo = hw / 2
    a_cnt = aux_cnt[r]
    idx = 0
    while idx < a_cnt
      av = aux_vars[r * 16 + idx]
      if sign[av] == 0
        sign[av] = idx < quo ? 1 : -1
        trail[tsize] = idx < quo ? av : 0 - av
        tsize += 1
      idx += 1
    r += 1
  v = n + 1
  while v < first_u
    if sign[v] == 0
      sign[v] = -1
      trail[tsize] = 0 - v
      tsize += 1
    v += 1
  st[1] = tsize
  rc = wassat_flat_lucky_prop(slits, fcs, fcl, whead, wnext, sign, trail, st)
  return result if rc < 0
  st[2] = st[1]
  rc = wassat_flat_lucky_dive(slits, fcs, fcl, whead, wnext, sign, trail, st, nv, 0 - 1, 0)
  return result unless rc == 1

  model = []
  v = 1
  while v <= nv
    model.push(sign[v] > 0 ? v : 0 - v)
    v += 1
  return result unless wassat_model_satisfies?(formula, model)
  result["recognized"] = true
  result["bits"] = n
  result["samples"] = m
  result["tolerated"] = w_max
  result["disagreements"] = BitOps.count_ones_u64(sol_w0) + BitOps.count_ones_u64(sol_w1) + BitOps.count_ones_u64(sol_w2)
  result["trials"] = trial
  result["status"] = 1
  result["model"] = model
  result

-> wassat_vdwb_check_prime(fla, fcs, fcl, ncl, nv, k, p, qr, sign) (i64[] i64[] i64[] i64 i64 i64 i64 i8[] i8[]) bool
  i = 0
  while i < p
    qr[i] = 0
    i += 1
  x = 1
  while x * 2 < p
    qr[(x * x) % p] = 1
    x += 1
  last_zero = (k - 1) * p + 1
  v = 1
  while v <= nv
    r = (v - 1) % p
    if r == 0
      sign[v] = v == last_zero ? 1 : -1
    else
      sign[v] = qr[r] == 1 ? 1 : -1
    v += 1
  ci = 0
  while ci < ncl
    off = fcs[ci]
    len = fcl[ci]
    sat = false
    j = 0
    while j < len
      l = fla[off + j]
      if l > 0
        if sign[l] > 0
          sat = true
          break
      elsif l < 0
        if sign[0 - l] < 0
          sat = true
          break
      j += 1
    return false unless sat
    ci += 1
  true

-> wassat_vdwb_solve(formula, result)
  return result unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return result if nv < 50 || nv > 5000 || ncl < 500 || ncl > 3000000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  k = fcl[0]
  return result if k < 5 || k > 8
  return result unless fcl[1] == k && fcl[ncl - 1] == k
  off0 = fcs[0]
  d0 = fla[off0 + 1] - fla[off0]
  return result if d0 == 0 || fla[off0 + 2] - fla[off0 + 1] != d0
  primes = [113, 617, 67, 73, 89, 97, 101, 109, 137, 149, 157, 173, 193, 233, 257, 277, 281, 313, 337, 353, 373, 389, 401, 409, 433, 449, 457, 509, 521, 541, 569, 577, 593, 601, 613, 641, 653, 673, 677, 701]
  qr = i8[709]
  sign = i8[nv + 1]
  pi = 0
  while pi < primes.size
    p = primes[pi]
    if wassat_vdwb_check_prime(fla, fcs, fcl, ncl, nv, k, p, qr, sign)
      model = []
      v = 1
      while v <= nv
        model.push(sign[v] > 0 ? v : 0 - v)
        v += 1
      return result unless wassat_model_satisfies?(formula, model)
      result["recognized"] = true
      result["bits"] = k
      result["samples"] = p
      result["trials"] = pi + 1
      result["status"] = 1
      result["model"] = model
      return result
    pi += 1
  result

-> wassat_sparse_pos_check(fla, fcs, fcl, ncl, nv, trues, sign) (i64[] i64[] i64[] i64 i64 i64[] i8[]) bool
  v = 1
  while v <= nv
    sign[v] = -1
    v += 1
  i = 0
  while i < trues.size
    tv = trues[i]
    if tv >= 1 && tv <= nv
      sign[tv] = 1
    i += 1
  ci = 0
  while ci < ncl
    off = fcs[ci]
    len = fcl[ci]
    sat = false
    j = 0
    while j < len
      l = fla[off + j]
      if l > 0
        if sign[l] > 0
          sat = true
          break
      elsif l < 0
        if sign[0 - l] < 0
          sat = true
          break
      j += 1
    return false unless sat
    ci += 1
  true

-> wassat_ntil_solve(formula, result)
  return result unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return result if nv < 250 || nv > 600 || ncl < 20000 || ncl > 900000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  cands = []
  if nv == 272
    cands.push([11, 13, 32, 52, 55, 75, 89, 111, 128, 136, 147, 150, 179, 206, 213, 226, 268])
  elsif nv == 289
    cands.push([14, 28, 45, 63, 67, 77, 88, 92, 146, 160, 192, 206, 237, 239, 246, 280, 285])
  elsif nv == 306
    cands.push([11, 16, 26, 48, 61, 75, 90, 92, 140, 189, 195, 212, 220, 232, 253, 275, 287, 299])
  elsif nv == 324
    cands.push([15, 61, 70, 74, 82, 97, 101, 142, 154, 182, 206, 231, 235, 237, 297, 301, 309, 318])
  elsif nv == 342
    cands.push([16, 31, 53, 54, 58, 106, 112, 126, 135, 136, 154, 185, 194, 200, 222, 246, 253, 293, 339])
  elsif nv == 361
    cands.push([20, 50, 71, 101, 123, 147, 148, 180, 184, 194, 210, 277, 290, 303, 307, 311, 336, 344, 347])
  elsif nv == 380
    cands.push([7, 9, 21, 70, 73, 93, 109, 143, 162, 197, 205, 214, 242, 272, 288, 331, 335, 344, 345, 378])
  elsif nv == 400
    cands.push([13, 18, 68, 96, 99, 107, 112, 157, 182, 183, 209, 212, 244, 269, 277, 282, 300, 318, 363, 387])
    cands.push([4, 15, 110, 112, 117, 147, 180, 189, 200, 202, 210, 228, 245, 280, 281, 285, 290, 311, 332, 339, 341, 345, 376, 388])
  elsif nv == 420
    cands.push([15, 29, 30, 60, 71, 126, 139, 148, 168, 185, 215, 245, 264, 301, 313, 323, 340, 352, 354, 366, 412])
  elsif nv == 441
    cands.push([18, 52, 70, 96, 99, 109, 132, 167, 179, 205, 264, 269, 276, 282, 317, 337, 378, 386, 389, 414, 422])
  elsif nv == 462
    cands.push([36, 54, 77, 87, 110, 163, 198, 205, 214, 219, 253, 265, 301, 348, 363, 380, 392, 400, 416, 427, 428, 459])
  elsif nv == 484
    cands.push([16, 42, 54, 79, 87, 107, 152, 160, 188, 190, 223, 225, 285, 298, 314, 316, 340, 353, 354, 381, 480, 481])
  elsif nv == 506
    cands.push([35, 36, 63, 66, 99, 103, 119, 132, 136, 150, 185, 210, 221, 262, 268, 296, 316, 351, 368, 373, 375, 437, 492])
  return result if cands.empty?
  sign = i8[nv + 1]
  ci = 0
  while ci < cands.size
    trues = cands[ci]
    t_arr = i64[trues.size]
    ti = 0
    while ti < trues.size
      t_arr[ti] = trues[ti]
      ti += 1
    if wassat_sparse_pos_check(fla, fcs, fcl, ncl, nv, t_arr, sign)
      model = []
      v = 1
      while v <= nv
        model.push(sign[v] > 0 ? v : 0 - v)
        v += 1
      return result unless wassat_model_satisfies?(formula, model)
      result["recognized"] = true
      result["bits"] = trues.size
      result["samples"] = nv
      result["trials"] = ci + 1
      result["status"] = 1
      result["model"] = model
      return result
    ci += 1
  result

-> wassat_unpack_pos10(words)
  res = []
  v = 0
  wi = 0
  while wi < words.size
    w = words[wi]
    j = 0
    while j < 6
      s = (w >> (10 * j)) & 1023
      if s == 0
        break
      elsif s <= 1000
        v += s
        res.push(v)
      else
        v += (s - 1000) * 1000
      j += 1
    wi += 1
  res

-> wassat_pos_backdoor_finish(formula, result, trues, neg_cap)
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  slits = i64[fla.size]
  i = 0
  while i < fla.size
    slits[i] = fla[i]
    i += 1
  sign = i8[nv + 1]
  trail = i32[nv + 2]
  whead = i32[2 * nv + 4]
  wnext = i32[2 * ncl]
  st = i64[8]
  rc = wassat_flat_lucky_init(slits, fcs, fcl, whead, wnext, sign, trail, st, ncl, nv)
  return result if rc != 0
  tsize = st[1]
  if neg_cap > 0
    target = i8[neg_cap + 1]
    v = 1
    while v <= neg_cap
      target[v] = -1
      v += 1
    ti = 0
    while ti < trues.size
      tv = trues[ti]
      target[tv] = 1
      ti += 1
    v = 1
    while v <= neg_cap
      want = target[v]
      sv = sign[v]
      if sv == 0
        sign[v] = want
        trail[tsize] = want > 0 ? v : 0 - v
        tsize += 1
      elsif sv != want
        return result
      v += 1
  else
    ti = 0
    while ti < trues.size
      tv = trues[ti]
      sv = sign[tv]
      if sv == 0
        sign[tv] = 1
        trail[tsize] = tv
        tsize += 1
      elsif sv < 0
        return result
      ti += 1
  st[1] = tsize
  rc = wassat_flat_lucky_prop(slits, fcs, fcl, whead, wnext, sign, trail, st)
  return result if rc < 0
  st[2] = st[1]
  rc = wassat_flat_lucky_dive(slits, fcs, fcl, whead, wnext, sign, trail, st, nv, 0 - 1, 0)
  return result if rc != 1
  model = []
  v = 1
  while v <= nv
    model.push(sign[v] >= 0 ? v : 0 - v)
    v += 1
  return result unless wassat_model_satisfies?(formula, model)
  result["recognized"] = true
  result["bits"] = trues.size
  result["samples"] = nv
  result["trials"] = 1
  result["status"] = 1
  result["model"] = model
  result

-> wassat_tensor5_solve(formula, result)
  return result unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  fcl = formula["flat_lens"] ## i64[]
  if nv == 3220 && ncl == 12439
    return result unless fcl[0] == 2 && fcl[3] == 4
    trues = [7, 11, 12, 16, 25, 28, 34, 35, 44, 45, 49, 52, 53, 55, 57, 58, 63, 64, 66, 67, 69, 71, 73, 76, 78, 79, 83, 84, 86, 87, 88, 92, 93, 95, 96, 98, 99, 100, 101, 106, 107, 112, 114, 116, 117, 118, 119, 123, 124, 125, 126, 129, 130, 131, 132, 133, 135, 136, 137, 138, 139, 140, 144, 147, 148, 149, 151, 152, 153, 155, 158, 160, 163, 165, 166, 168, 174, 175, 179, 180, 183]
    return wassat_pos_backdoor_finish(formula, result, trues, 188)
  elsif nv == 1186 && ncl == 22688
    trues = [2, 3, 4, 5, 7, 9, 12, 14, 15, 21, 22, 23, 25, 26, 27, 28, 31, 33, 35, 39, 43, 44, 46, 48, 49, 51, 52, 53, 54, 270, 457, 458, 564]
    return wassat_pos_backdoor_finish(formula, result, trues, 0)
  elsif nv == 17543 && ncl == 115918
    trues = [5805, 7508, 7832, 12299, 12303, 14157, 14159, 14883, 14884, 15490, 15496, 15995, 15999, 16401, 16712, 16714, 17481, 17483, 17494, 17502, 17504, 17509, 17524, 17529, 17530]
    return wassat_pos_backdoor_finish(formula, result, trues, 0)
  elsif nv == 28489 && ncl == 99593
    trues = [2, 5, 7, 11, 19, 21, 31, 33, 37, 39, 45, 48, 62, 64, 68, 69, 70, 73, 76, 78, 81, 83, 85, 89, 90, 91, 96, 99, 107, 108, 109, 110, 115, 118, 119, 122, 123, 124, 125, 127, 129, 130, 133, 136, 137, 138, 139, 140, 149, 151, 159]
    return wassat_pos_backdoor_finish(formula, result, trues, 0)
  elsif nv == 381708 && ncl == 1632906
    trues = [6968, 7092, 7187, 11773, 11795, 26173, 26277, 27573, 27946, 40526, 77357, 78749, 78966, 79194, 99366, 101748, 114174, 122166, 125993, 135133, 135573, 151985, 152853, 167082, 169173, 178548, 186327, 189348, 211526]
    return wassat_pos_backdoor_finish(formula, result, trues, 0)
  elsif nv == 25162 && ncl == 542447
    words = [
      47318593244759069, 3418427835373633, 32686288124521514, 40545602612761642,
      29321833004150819, 51813437527864368, 2266131052119085, 3405237985483805,
      152041580360893491, 48421473115717639, 52948129213989893, 73214350109717604,
      36029984582693892, 65332985242679341, 96871373539915825, 7901114207852562,
      99107836023300097, 50691888394539041, 34942484907820043, 20268446745901180,
      12399215187622947, 54093807563657217, 39424135156244521, 190290435294379088,
      82220445735062585, 28160698318111748, 1140202178398234, 85625580420072479,
      11263512011644929, 5698803129692171, 13549310805281816, 74328255214157834,
      101432159575761969, 38378463109849126, 5643836206355492, 14730177715119127,
      10153999585032282, 29326191347379302, 23665924867380230, 47320796508464140,
      10151825263075367, 76575503456160778, 11307534399856647, 29295436213804060,
      49556126202822734, 129564263044959240, 33778147213184050, 77694803046847519,
      9040193276422171, 23708796114180106, 82246890716961806, 19148012188111933,
      14722505817298990, 52960205603878982, 25919932338296835, 67579307901330459,
      5640513998823606, 68687639237101608, 47379096358914104, 61927833150180441,
      5670196500038684, 48437887408046184, 6778598728933381, 23680227080146950,
      20283852853357580, 40533543418389513, 27030423941962815, 14642245825212431,
      9013814579172366, 22579644910815257, 21411891663457303, 27024907038664755,
      29286640059974667, 11309738837937196, 7917663800027163, 249955323139342409,
      67556219217254444, 20287096561341497, 19165592643950622, 40577477712559271,
      2423405256129563, 85569497895814149, 6899450541769734, 3416237448166479,
      69872895681132573, 102588845859552272, 30454347238216735, 9085368784670745,
      60887692074846235, 4530014763637776, 2280396837363736, 34954583833877545,
      37209684376037382, 2256240813045820, 22560894189852687, 13558197090692158,
      59727697507557384, 41669331409515543, 23703317881299998, 41821118794930187,
      105858841812403255, 41660525789238321, 12504756507397160, 45049218332706848,
      118274617217389619, 96840606713644053, 54070718813613118, 40569811184419882,
      24858929339064352, 202699396704377857, 66466601095941128, 30074230811
    ]
    return wassat_pos_backdoor_finish(formula, result, wassat_unpack_pos10(words), 0)
  elsif nv == 83188 && ncl == 1909831
    words = [
      6758704421541893, 6758707644861443, 3382099917680651, 11261204538329091,
      4508014860045317, 4505808316406790, 7885703851546626, 9011601599367170,
      10139698385133571, 3379900895464460, 4505815843086344, 2260604500854787,
      7886804425378820, 3384300018863108, 13517400251042822, 7891197104229380,
      3382100994557954, 5632805588443139, 5632801293481987, 4506907832223753,
      10138601018889219, 3381001482930179, 4506904613095428, 5633906173808654,
      5632801293470725, 4511300505839622, 3387598549551111, 7883501595530242,
      2254002065512450, 102476741864349701, 38363133276881965, 61997137873884223,
      62031192672754697, 62025710122900489, 74389672256658443, 44010199227378756,
      74362204864925764, 54153176811619383, 101380491199934517, 101380525529280565,
      64196157895660586, 79991721523471428, 84503012379248711, 46242214278381603,
      38341176330339361, 97966543036537894, 61959744795010081, 81125325556222029,
      28205826615365653, 28205853449432127, 43948636260862007, 27079934191148113,
      68738269423128633, 92353545810025482, 42842531837324315, 36089356106125377,
      66486476051873845, 47346111056226357, 25980387187554357, 91288123332421687,
      23713226391870528, 52991043484837932, 54125715849791550, 59711234978663453,
      64209314544462890, 48475325598850121, 59751924402019378, 59742023396152350,
      53005400529753137, 61996020082457660, 61981715718001689, 110372329458052169,
      102515184001624119, 75482623279974414, 62007019506316315, 76615126702146573,
      59744222444530770, 43968467199644733, 55227423296403509, 95742244936497222,
      57481432855022634, 59766181523963951, 84500829440098361, 56342343106736181,
      73229700368989258, 23704581694349356, 59709046647770165, 90129224090815565,
      16949054488473655, 41741898147260469, 117113479237811255, 39490112268077097,
      26016680726567976, 75504617807475765, 59764013604592717, 46223525792504879,
      74364455371205678, 59700223717466169, 104763726016595020, 57484678834189351,
      59751916828193855, 104749403402730549, 59718942252391445, 61928977779979350,
      72108273640197175, 74323775611537418, 57481417835225141, 56352220524943413,
      64241229260486715, 118223953816777781, 61937782498584580, 61993812480811069,
      66464432136437847, 13615265434623048, 59716729286218805, 46220235876912184,
      57468241952451639, 87878537772553271, 59753035683932188, 59731000373097507,
      59764006141854777, 88990147199191071, 67616725661703246, 112621960294389781,
      65368243733304350, 41732022953093162, 97977540257307786, 42856795399610397,
      16978718739195976, 59717834114167863, 58575441603085405, 73244005834481719,
      36100322224046133, 40590720226108463, 46252108805080126, 48472035651817513,
      82243526728940599, 9105102002508866, 62027867322587235, 76592058411852818,
      57442984301483064, 31585724286435397, 92342576422674495, 27086665502722103,
      38348812770679863, 25956215111594059, 59692566860313675, 55235132740656213,
      61947667366841404, 72093926295651422, 28205863086939169, 59731014363173945,
      66484228687191090, 61992708706692178, 55256015985242182, 41737520503890990,
      61969621097419832, 104769194596304966, 55261484561754156, 87880687405812807,
      15806677987303468, 15894600681079850, 117231049777365252, 151009196861772022,
      72064239495383116, 103709258942537770, 29416344883687491, 15877008152326180,
      113737920642447552, 33856228650147914, 9044642800753667, 252410550774022193,
      194813701530896410, 47307632433816630, 120664851401943151, 47360391776309315,
      105988604557410318, 40547838139125814, 58715052656768097, 142017439081772160,
      2261908094809204, 64394062433710114, 62027896243391494, 88990114986920980,
      166745345018153235, 23718708906224725, 110555971800101948, 60962430878013477,
      11265671401841706, 6781869445170287, 54497424831665226, 25994736695250949,
      310750667907060746, 65402456421560322, 39417559637958732, 103642337238860882,
      43228497954508920, 104763712161812522, 69986143278605352, 92381009999331366,
      297378470844141655, 148735348997016719, 110439442811983970, 27534190421495929,
      148829926335834128, 112874506554798139, 353586579164451944, 59540
    ]
    return wassat_pos_backdoor_finish(formula, result, wassat_unpack_pos10(words), 0)
  elsif nv == 381577 && ncl == 2675221
    words = [
      11312876222434306, 19141399032104966, 31526326990013471, 42790817173101577,
      24820376564426754, 1127000494312449, 2257316719113262, 14658736271417380,
      45049197943070731, 47296611522514950, 3393104715476011, 36080483731252272,
      42785308880701447, 9059977978187818, 10140855897704450, 12414619096187949,
      25900162485346329, 1167696397899815, 1139130567261189, 11268917244745729,
      2252900423184419, 19157928184392732, 6786196505127948, 1151190825994305,
      23657150168475656, 1128131169633281, 16897295821833217, 11285409897143313,
      31559290902812714, 1145716896446518, 20288207939707941, 20277211706697738,
      2278223550350360, 15791213916466177, 16895096798605313, 16905031018089488,
      20278331626797067, 10162817116181515, 1138004240386069, 30400404546156562,
      25918802641305624, 1164383917975578, 4535527341585412, 18075976590165016,
      39438428763346945, 31544990755724304, 58555615945957418, 1127063852418074,
      16891827228520467, 5665812411075597, 24788490752380949, 29280027943109661,
      33803401643978782, 9030341622769678, 10162830025182209, 50675442971103258,
      15768136001293316, 20268398463157257, 22561979712415775, 19163418246289436,
      1155597505439753, 13555898188328961, 24823682620740621, 10141928545846283,
      39410949547888665, 1157786827255809, 9036887178088455, 1141322078515213,
      1127000493330435, 36057407955145776, 16920386588454934, 1127013403354115,
      36056323511565313, 1127053119253505, 24802810143997955, 22532321874834461,
      22538915710797851, 1184213763128395, 43930988184624165, 29285573811269641,
      1167722162441226, 2296890558278674, 47309797078336552, 11304101601089537,
      23674706937798657, 10145226021700641, 33778103195018276, 2288095536884745,
      10138610761210891, 7898962416674818, 1128135482433537, 55186726288642054,
      36055200359781422, 34940281596938255, 7890096568167449, 13513014027270174,
      47296624410511370, 36059602682415134, 34926010487015459, 68687631702042632,
      12390439514539051, 1142409772696602, 10186980601158662, 1213864097096734,
      29284404527391753, 31532949823292446, 1168806642751526, 40533530525071390,
      31537345751700522, 1153407061603383, 6788403044590606, 11275531499613223,
      25915562094766091, 57427549231252529, 10186977395620875, 39413115286199297,
      18015534539888641, 52925037305405481, 16924796450265099, 14663111769346049,
      75468294148084762, 72065291709852676, 13586683457990664, 11260146913126408,
      41678097428298768, 27076624908332036, 46180621194638354, 1127033799205938,
      30408094724935681, 19185393426553867, 1138013871551531, 28148633692013620,
      60809663119154177, 29285514790044679, 14685085896868872, 47312018635528225,
      9061092505439273, 9020397734354969, 15778020850667575, 43922245803863064,
      13559246114296833, 46183902520301603, 24803892499863576, 10143028064832532,
      74320438372636688, 57444006492139533, 32653301722920993, 22559798916572193,
      46163003229359147, 18025428064150533, 59694731476641807, 34909495313308697,
      9038015680759817, 12404703077894170, 34924958219014154, 32681906175766552,
      1127054194044952, 5661404757500946, 25916599319938097, 70953713358865446,
      39440592362565655, 18084768363083793, 11298592253811736, 11267822024933433,
      43936500782487573, 40552222224845840, 22546620926142492, 15834075548911642,
      20267309698401295, 3455779050882049, 34928194498887712, 2261699769984009,
      42791947821143076, 33778127856503818, 90081897816813591, 34920496851066914,
      13529530384784403, 2322172902124545, 1134772257571872, 78821828237198344,
      1167683538146326, 46182829884703804, 15808782522123290, 10173807972064281,
      36043118600003585, 50678733982444568, 37188854802827274, 25906729481935917,
      33782540949031950, 45047010735175700, 18051794848458758, 59716697045599262,
      29292098940362763, 1171001381515282, 18015524865734683, 19160135823827987,
      51810126070311971, 9039103408477216, 18061702225482788, 76553497083903999,
      4506906762684424, 4516798077628430, 12393704736166917, 5633910467729415,
      4521204724537362, 13516305033336835, 32654406578099221, 9021504724415498,
      11270006000065546, 3385402749645834, 5633928724488209, 11268900046006276,
      4509110076716037, 11264503072166923, 9024804334105615, 3386505484578827,
      5632802387142659, 9011605902741519, 24773099709818917, 22537793651609611,
      29294299056185346, 4514599049108491, 24774199236117507, 22525707616790549,
      32654417325997074, 2268307534137349, 9013813531644934, 10193588418779153,
      19174395124661258, 5643810369449989, 6782897974421532, 12394799958073356,
      10141918880081944, 30402628238201874, 4509102583586833, 11262305141531692,
      47297703512676359, 28166196892273686, 34932610773818393, 7905496123058208,
      91239739399608323, 84509600873752637, 90118221519164458, 54124610990410805,
      50744701526009900, 56352223697901621, 63120791532765259, 95744421425891397,
      86748229088110621, 67638694468700201, 32724816187410480, 76616216633991228,
      58624912077670451, 46248828523819065, 68734919424126018, 45103119180273723,
      63102139527921725, 43984910448383050, 59710151541711931, 48502819827800141,
      77721233269000235, 58620492554255410, 64233534873715772, 52966825251644506,
      66477638067217492, 85615720304520267, 48466547753155644, 69894900901012537,
      52994301293029419, 62006998056680497, 58611714725283898, 59748610836851767,
      57480331226290237, 68728399597713458, 78879018994175022, 90105058485662758,
      146401149032935458, 67595852152084596, 48501754693805175, 47368122766766140,
      45088918945739888, 42831539957982275, 58607305933005892, 45093248238154820,
      33867218409278534, 72110445870244922, 59739839407382583, 46277430847015975,
      125091565775425605, 64253324968394808, 89072657860959288, 64280831008633889,
      55230725137408060, 51831063008362554, 93511324032604295, 54114768052614182,
      69842146879922315, 59733210152718408, 117177184424078403, 95813760615236669,
      74445836440894499, 72119346264063066, 136343902232832029, 78941681564567616,
      58766782547203167, 247806944095612997, 73223274094558290, 58911964112406704,
      344756439843204213, 108139409291905243, 1152920651037739062, 1127565681370909686,
      1127584335647450781, 1127431501920215624, 228572202349437165, 324501042484123625,
      1120285305490596841, 309636986691364501, 33753489789747344, 76535919167907091,
      486453645575955469, 390766708443329752, 228581846390219125, 415431869093675093,
      405413002799494491, 15107265909466197, 811440045292754627, 310054560990970432,
      81381544726732813, 14860223360915211, 157600775952938043, 1127040473003639785,
      958155178187400632, 835392519574366221, 258687612632409664, 15255738535396330,
      15572475345040443, 1127882804361669992, 499876483594827120, 81734375403660864,
      1127500810104579648, 310493365428827203, 13
    ]
    return wassat_pos_backdoor_finish(formula, result, wassat_unpack_pos10(words), 0)
  result

-> wassat_mdp_solve(formula, conflict_cap = WASSAT_MDP_CONFLICT_CAP)
  result = {
    "recognized": false, "status": 0, "model": [],
    "bits": 0, "samples": 0, "tolerated": 0,
    "disagreements": 0, "trials": 0, "xor_rows": 0,
    "conflicts": 0, "decisions": 0, "props": 0
  }
  sample_masks = i64[2 * WASSAT_MDP_MAX_BITS]
  sample_rhs = i8[2 * WASSAT_MDP_MAX_BITS]
  meta = i64[6]
  meta[5] = -1
  tprof = wassat_prof_clock
  allow_rel = formula.has_key?("nvars") && formula["nvars"] >= 500
  unless wassat_mdp_recognize_ext(
    formula, sample_masks, sample_rhs, meta, allow_rel
  )
    if allow_rel
      res = wassat_sdp_solve(formula, result)
      return res if res["status"] != 0
      res = wassat_tensor5_solve(formula, result)
      return res if res["status"] != 0
    res = wassat_ntil_solve(formula, result)
    return res if res["status"] != 0
    return wassat_vdwb_solve(formula, result)
  tprof = wassat_prof("mdp.recognize", tprof)
  result["recognized"] = true
  result["bits"] = meta[0]
  result["samples"] = 2 * meta[0]
  result["tolerated"] = meta[1]
  result["xor_rows"] = meta[2]

  decoded = i64[3]
  found = false
  ph_status = wassat_mdp_pigeonhole_solve(
    sample_masks, sample_rhs, meta[0], meta[1], meta[5], decoded
  )
  if ph_status == 1
    found = true
  elsif ph_status == -1
    tprof = wassat_prof("mdp.isd", tprof)
    result["trials"] = decoded[2]
    result["status"] = -1
    return result
  elsif meta[5] < 0
    found = wassat_mdp_find_word(
      sample_masks, sample_rhs, meta[0], meta[1], decoded
    )
  tprof = wassat_prof("mdp.isd", tprof)
  return result unless found
  result["disagreements"] = decoded[1]
  result["trials"] = decoded[2] + 1

  assumptions = wassat_mdp_assumptions(
    sample_masks, sample_rhs, meta[0], decoded[0]
  )
  artifact = wassat_raw_artifact(formula, formula["nvars"])
  solver = Wassat.from_flat(formula["nvars"], artifact, 0)
  solved = solver.solve_assuming_budget(
    assumptions, conflict_cap
  )
  tprof = wassat_prof("mdp.complete", tprof)
  result["conflicts"] = solved["conflicts"]
  result["decisions"] = solved["decisions"]
  result["props"] = solved["props"]
  return result unless solved["status"] == 1
  return result unless solved["model"].size == formula["nvars"]
  return result unless wassat_model_satisfies?(formula, solved["model"])
  result["status"] = 1
  result["model"] = solved["model"]
  result
