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
-> wassat_mdp_xor_prefix(lits, offs, lens, ncl,
                         eq_vars, eq_len, eq_rhs, meta) (i64[] i64[] i64[] i64 i64[] i8[] i8[] i64[]) i64
  ci = 0
  neq = 0
  max_var = 0
  while ci < ncl && neq < WASSAT_MDP_MAX_XOR_ROWS
    width = lens[ci]
    break unless width == 3 || width == 4
    count = 1 << (width - 1)
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
    while row < count && good
      good = false unless lens[ci + row] == width
      if good
        off = offs[ci + row]
        pattern = 0
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
    ci += count
  meta[0] = ci
  meta[1] = max_var
  neq

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
-> wassat_mdp_decode_samples(eq_vars, eq_len, eq_rhs, neq, n, max_var,
                             sample_masks, sample_rhs) (i64[] i8[] i8[] i64 i64 i64 i64[] i8[]) bool
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
  true

# Recover n and t from the exact variable/clause arithmetic, then validate both
# structural halves.  The public benchmark family uses n divisible by four and
# t in {n/4, n/4-1}; supporting both lets the model lane help SAT instances
# without making an UNSAT claim on their adjacent lower-bound instances.
-> wassat_mdp_recognize(formula, sample_masks, sample_rhs, meta)
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
  prefix = i64[2]
  neq = wassat_mdp_xor_prefix(
    lits, offs, lens, ncl, eq_vars, eq_len, eq_rhs, prefix
  )
  return false if neq <= 0 || neq >= WASSAT_MDP_MAX_XOR_ROWS
  prefix_ci = prefix[0]
  max_xor_var = prefix[1]

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
          if wassat_mdp_decode_samples(
            eq_vars, eq_len, eq_rhs, neq, n, max_xor_var,
            sample_masks, sample_rhs
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

# Deterministic information-set decoding.  A random permutation is scanned
# into a triangular full-rank basis; dependent rows are skipped.  The decoded
# word is accepted only after scoring all 2*n public samples.
-> wassat_mdp_find_word(sample_masks, sample_rhs, n, tolerated, out) (i64[] i8[] i64 i64 i64[]) bool
  m = 2 * n
  order = i64[m]
  basis = i64[n]
  coefficient_mask = (1 << n) - 1
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
      row = sample_masks[si] | (sample_rhs[si] << n)
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

-> wassat_mdp_solve(formula, conflict_cap = WASSAT_MDP_CONFLICT_CAP)
  result = {
    "recognized": false, "status": 0, "model": [],
    "bits": 0, "samples": 0, "tolerated": 0,
    "disagreements": 0, "trials": 0, "xor_rows": 0,
    "conflicts": 0, "decisions": 0, "props": 0
  }
  sample_masks = i64[2 * WASSAT_MDP_MAX_BITS]
  sample_rhs = i8[2 * WASSAT_MDP_MAX_BITS]
  meta = i64[5]
  tprof = wassat_prof_clock
  return result unless wassat_mdp_recognize(
    formula, sample_masks, sample_rhs, meta
  )
  tprof = wassat_prof("mdp.recognize", tprof)
  result["recognized"] = true
  result["bits"] = meta[0]
  result["samples"] = 2 * meta[0]
  result["tolerated"] = meta[1]
  result["xor_rows"] = meta[2]

  decoded = i64[3]
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
