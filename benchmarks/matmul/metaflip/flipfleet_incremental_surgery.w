# Incremental k-surgery superstructure (move 2 intake, lane prefix ffis_).
#
# EXACT CONTENT.  Classic k-surgery asks, per k-subset S of live terms,
# whether the S-partial tensor can be reproduced by k-1 fresh terms; the
# shipped external lane (flipfleet_sat_destroy_repair) builds a fresh
# solver process per subset.  This lane holds ONE incremental CDCL instance
# per (scheme, k) and reuses it across every subset:
#
#   selectors   one variable s_i per pool term (term masks are constants);
#   slots       k-1 unknown replacement triples over ambient n^2-bit
#               factors, with plain Tseitin AND products per tensor cell
#               (a slot may decode to zero factors: it is dropped, so a
#               model may even be a k -> k-2 replacement);
#   rows        one XOR row per tensor cell over [slot products] union
#               [s_i of pool terms whose rank-one tensor covers the cell],
#               rhs 0 -- under a subset assumption the selector literals
#               become the S-partial tensor, so a model is EXACTLY a local
#               replacement for the assumed subset;
#   per subset  one ffcdcl_solve under P assumption literals (s_i positive
#               for i in S, negative otherwise).  Learned clauses persist
#               across all C(P, k) subsets -- the superstructure.
#
# UNSAT-CORE LIFTING.  On UNSAT, ffcdcl_failed_assumptions returns the
# selector vars in the final conflict.  Splitting the core against S gives
# (A+, A-): every sibling subset containing A+ and avoiding A- is refuted
# without solving.  The sweep stores a bounded core bank, skips
# core-subsumed subsets, and counts them as core-killed; the lift factor is
# the measured coverage multiplier.
#
# A model can never be trivial: the XOR rows force the replacement to equal
# the sum of ALL k selected rank-one tensors, and with k-1 slots a fake
# would need one selected tensor to vanish, which nonzero factors forbid.
#
# ADMISSION.  Toggle the k selected terms out and the decoded replacement
# in (collision-aware), require ffw_verify_current_exact, roll back on any
# failure; publication is dump -> re-parse -> re-gate.

use metaflip_worker
use flipfleet_sat_cdcl

# ---------------------------------------------------------------------------
# Variable map: selectors 1..P, then slot bits, then products; XOR
# auxiliaries land above because every product is referenced before the
# first row is added.

-> ffis_sel_var(i) (i64) i64
  1 + i

-> ffis_slot_var(pool, slot, axis, pos, nn) (i64 i64 i64 i64 i64) i64
  1 + pool + slot * 3 * nn + axis * nn + pos

-> ffis_prim(pool, slots, nn) (i64 i64 i64) i64
  pool + slots * 3 * nn

-> ffis_product_var(pool, slots, nn, cell, slot) (i64 i64 i64 i64 i64) i64
  ffis_prim(pool, slots, nn) + 1 + cell * slots + slot

-> ffis_term_covers(u, v, w, cell, nn) (i64 i64 i64 i64 i64) i64
  c = cell % nn ## i64
  rest = cell / nn ## i64
  b = rest % nn ## i64
  a = rest / nn ## i64
  ((u >> a) & 1) & ((v >> b) & 1) & ((w >> c) & 1)

# Encode the persistent instance.  Returns 1, or 0 on arena failure.
-> ffis_encode(sat, pu, pv, pw, pool, n, slots) (i64[] i64[] i64[] i64[] i64 i64 i64) i64
  nn = n * n ## i64
  cells = nn * nn * nn ## i64
  lits = i64[8]
  xvars = i64[pool + slots + 2]
  # Pass 1: AND products for every (cell, slot) -- fixed numbering.
  cell = 0 ## i64
  while cell < cells
    c = cell % nn ## i64
    rest = cell / nn ## i64
    b = rest % nn ## i64
    a = rest / nn ## i64
    slot = 0 ## i64
    while slot < slots
      p = ffis_product_var(pool, slots, nn, cell, slot) ## i64
      xu = ffis_slot_var(pool, slot, 0, a, nn) ## i64
      xv = ffis_slot_var(pool, slot, 1, b, nn) ## i64
      xw = ffis_slot_var(pool, slot, 2, c, nn) ## i64
      lits[0] = 2 * p + 1
      lits[1] = 2 * xu
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[1] = 2 * xv
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[1] = 2 * xw
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[0] = 2 * p
      lits[1] = 2 * xu + 1
      lits[2] = 2 * xv + 1
      lits[3] = 2 * xw + 1
      if ffcdcl_add_clause(sat, lits, 4) != 1
        return 0
      slot += 1
    cell += 1
  # Pass 2: one XOR row per cell over slot products + covering selectors.
  cell = 0
  while cell < cells
    count = 0 ## i64
    slot = 0
    while slot < slots
      xvars[count] = ffis_product_var(pool, slots, nn, cell, slot)
      count += 1
      slot += 1
    i = 0 ## i64
    while i < pool
      if ffis_term_covers(pu[i], pv[i], pw[i], cell, nn) == 1
        xvars[count] = ffis_sel_var(i)
        count += 1
      i += 1
    if ffcdcl_add_xor(sat, xvars, count, 0) != 1
      return 0
    cell += 1
  1

# ---------------------------------------------------------------------------
# Core bank

-> ffis_core_subsumes(core_terms, core_signs, base, core_len, in_subset) (i64[] i64[] i64 i64 i64[]) i64
  j = 0 ## i64
  while j < core_len
    var_index = core_terms[base + j] ## i64
    want_in = core_signs[base + j] ## i64
    is_in = in_subset[var_index] ## i64
    if want_in == 1 && is_in == 0
      return 0
    if want_in == 0 && is_in == 1
      return 0
    j += 1
  1

# ---------------------------------------------------------------------------
# The sweep

# Enumerate k-subsets of the pool in lexicographic order (bounded by
# subset_budget), solving each under assumptions unless a banked core
# subsumes it.  On SAT, apply + gate on the live worker state and stop.
# meta (i64[20]):
#   [0] pool  [1] k  [2] vars  [3] clauses  [4] enumerated  [5] solved
#   [6] sat  [7] unsat  [8] budget-out  [9] core-killed  [10] cores banked
#   [11] total conflicts  [12] instance builds  [13] applied rank
#   [14] gate flag  [15] elapsed ms  [16] replacement count
# Returns the new rank on an applied hit, 0 when the sweep exhausts its
# budget with no hit, negative on structural errors (-1 plan, -2 encode,
# -3 seed not exact).
-> ffis_sweep_state(st, n, k, pool_size, subset_budget, conflict_budget, seed, meta) (i64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  i = 0 ## i64
  while i < 20
    meta[i] = 0
    i += 1
  started = ccall("__w_clock_ms") ## i64
  rank = ffw_current_rank(st) ## i64
  if n < 2 || n > 4 || k < 2 || k > 6 || rank < k
    return 0 - 1
  if ffw_verify_current_exact(st, n) != 1
    return 0 - 3
  pool = pool_size ## i64
  if pool > rank
    pool = rank
  if pool < k
    return 0 - 1
  nn = n * n ## i64
  cells = nn * nn * nn ## i64
  slots = k - 1 ## i64
  capacity = ffw_default_capacity(n) ## i64
  eu = i64[capacity]
  ev = i64[capacity]
  ew = i64[capacity]
  count = ffw_export_current(st, eu, ev, ew) ## i64
  if count != rank
    return 0 - 1
  # Deterministic pool: rotate the export by seed so different seeds see
  # different pools without re-clustering.
  pu = i64[pool + 1]
  pv = i64[pool + 1]
  pw = i64[pool + 1]
  offset = (seed & 32767) % rank ## i64
  i = 0
  while i < pool
    src = (offset + i) % rank ## i64
    pu[i] = eu[src]
    pv[i] = ev[src]
    pw[i] = ew[src]
    i += 1
  prim = ffis_prim(pool, slots, nn) ## i64
  aux = cells * (slots + pool + 2) ## i64
  max_vars = prim + cells * slots + aux + 64 ## i64
  learnt_words = conflict_budget * 32 ## i64
  if learnt_words > 64000000
    learnt_words = 64000000
  if learnt_words < 0
    learnt_words = 0
  clause_words = cells * slots * 30 + cells * (slots + pool + 4) * 12 + 300000 + learnt_words ## i64
  sat = i64[ffcdcl_state_size(max_vars, clause_words)]
  if ffcdcl_init(sat, max_vars, seed) != 1
    return 0 - 2
  if ffis_encode(sat, pu, pv, pw, pool, n, slots) != 1
    return 0 - 2
  meta[0] = pool
  meta[1] = k
  meta[2] = ffcdcl_top_var(sat)
  meta[3] = ffcdcl_clause_count(sat)
  meta[12] = 1
  # Core bank (bounded).
  bank_cap = 64 ## i64
  core_terms = i64[bank_cap * pool]
  core_signs = i64[bank_cap * pool]
  core_lens = i64[bank_cap]
  cores = 0 ## i64
  assumptions = i64[pool + 1]
  in_subset = i64[pool + 1]
  core_vars = i64[pool + 1]
  choose = i64[k + 2]
  rep_u = i64[k + 2]
  rep_v = i64[k + 2]
  rep_w = i64[k + 2]
  i = 0
  while i < k
    choose[i] = i
    i += 1
  running = 1 ## i64
  hit_rank = 0 ## i64
  while running == 1 && meta[4] < subset_budget && hit_rank == 0
    meta[4] = meta[4] + 1
    i = 0
    while i < pool
      in_subset[i] = 0
      i += 1
    i = 0
    while i < k
      in_subset[choose[i]] = 1
      i += 1
    # Core subsumption check.
    killed = 0 ## i64
    ci = 0 ## i64
    while ci < cores && killed == 0
      if ffis_core_subsumes(core_terms, core_signs, ci * pool, core_lens[ci], in_subset) == 1
        killed = 1
      ci += 1
    if killed == 1
      meta[9] = meta[9] + 1
    else
      i = 0
      while i < pool
        if in_subset[i] == 1
          assumptions[i] = 2 * ffis_sel_var(i)
        else
          assumptions[i] = 2 * ffis_sel_var(i) + 1
        i += 1
      status = ffcdcl_solve(sat, assumptions, pool, conflict_budget) ## i64
      meta[5] = meta[5] + 1
      meta[11] = meta[11] + ffcdcl_conflicts(sat)
      if status == 1
        meta[6] = meta[6] + 1
        # Decode replacement slots; zero slots drop.
        rep_count = 0 ## i64
        slot = 0 ## i64
        while slot < slots
          u = 0 ## i64
          v = 0 ## i64
          w = 0 ## i64
          pos = 0 ## i64
          while pos < nn
            if ffcdcl_value(sat, ffis_slot_var(pool, slot, 0, pos, nn)) == 1
              u = u | (1 << pos)
            if ffcdcl_value(sat, ffis_slot_var(pool, slot, 1, pos, nn)) == 1
              v = v | (1 << pos)
            if ffcdcl_value(sat, ffis_slot_var(pool, slot, 2, pos, nn)) == 1
              w = w | (1 << pos)
            pos += 1
          if u != 0 && v != 0 && w != 0
            rep_u[rep_count] = u
            rep_v[rep_count] = v
            rep_w[rep_count] = w
            rep_count += 1
          slot += 1
        meta[16] = rep_count
        # Apply: toggle selected out, replacement in; verify; rollback.
        r0 = ffw_current_rank(st) ## i64
        r1 = r0 ## i64
        i = 0
        while i < k
          r1 = ffw_toggle(st, pu[choose[i]], pv[choose[i]], pw[choose[i]], r1)
          i += 1
        i = 0
        while i < rep_count
          r1 = ffw_toggle(st, rep_u[i], rep_v[i], rep_w[i], r1)
          i += 1
        st[6] = r1
        if ffw_verify_current_exact(st, n) == 1 && r1 < r0
          meta[13] = r1
          meta[14] = 1
          hit_rank = r1
        else
          i = rep_count - 1
          while i >= 0
            r1 = ffw_toggle(st, rep_u[i], rep_v[i], rep_w[i], r1)
            i -= 1
          i = k - 1
          while i >= 0
            r1 = ffw_toggle(st, pu[choose[i]], pv[choose[i]], pw[choose[i]], r1)
            i -= 1
          st[6] = r1
      if status == 0 - 1
        meta[7] = meta[7] + 1
        core_len = ffcdcl_failed_assumptions(sat, core_vars, pool) ## i64
        if core_len > 0 && cores < bank_cap
          base = cores * pool ## i64
          j = 0 ## i64
          while j < core_len
            sel = core_vars[j] - 1 ## i64
            if sel >= 0 && sel < pool
              core_terms[base + j] = sel
              core_signs[base + j] = in_subset[sel]
            j += 1
          core_lens[cores] = core_len
          cores += 1
      if status == 0 - 2
        meta[8] = meta[8] + 1
    # Next lexicographic k-subset.
    pos = k - 1 ## i64
    while pos >= 0 && choose[pos] == pool - k + pos
      pos -= 1
    if pos < 0
      running = 0
    else
      choose[pos] = choose[pos] + 1
      j2 = pos + 1 ## i64
      while j2 < k
        choose[j2] = choose[j2 - 1] + 1
        j2 += 1
  meta[10] = cores
  meta[15] = ccall("__w_clock_ms") - started
  hit_rank

-> ffis_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

# Path driver with the publish dance.  Returns the applied rank on a hit
# (output written + replayed when out_path != ""), 0 miss, negatives as in
# ffis_sweep_state plus -4 load and -6 publish.
-> ffis_sweep(path, n, k, pool_size, subset_budget, conflict_budget, seed, out_path, meta) (String i64 i64 i64 i64 i64 i64 String i64[]) i64
  capacity = ffw_default_capacity(n) ## i64
  st = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(st, path, n, capacity, 88801 + (seed % 100000), 0, 1, 1, 1) ## i64
  if rank < 2
    return 0 - 4
  hit = ffis_sweep_state(st, n, k, pool_size, subset_budget, conflict_budget, seed, meta) ## i64
  if hit <= 0
    return hit
  if out_path.size() > 0
    z = system("/bin/rm -f " + ffis_shell_quote(out_path))
    written = ffw_dump_current(st, out_path) ## i64
    if written != hit
      return 0 - 6
    replay = i64[ffw_state_size(capacity)]
    reloaded = ffw_load_scheme_cap(replay, out_path, n, capacity, 88903, 0, 1, 1, 1) ## i64
    if reloaded != hit || ffw_verify_current_exact(replay, n) != 1
      z = system("/bin/rm -f " + ffis_shell_quote(out_path))
      return 0 - 6
  hit
