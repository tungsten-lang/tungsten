# Clause-checked monotone formula chains (Buss/Ramyaa construction).
# A selected involution permutes equal-shaped children of AND/OR gates;
# guarded leaf implications can only increase the permuted formula's value.
# Thus a true initial root cannot reach a false final root. Every selector,
# transition and endpoint condition is checked against the original CNF.
# Conservative canonical numbering/order recognition; literal order is free.
# No names, hashes or saved answers. Non-DRAT route: disable in proof mode.
use atomic_stop

# meta: 0 stop, 1 polls, 2 checked clauses, 3 units, 4 depth, 5 fanin,
# 6 transitions, 7 leaves, 8 leaf variables, 9 equivalence mode,
# 10 scratch bytes, 11 phase, 12 selector rows, 13 leaf implications,
# 14 endpoint folds, 15 elapsed ms, 16 result, 17 unit scans.
-> wassat_chain_poll(m, stop, deadline) (i64[] i64[] i64) bool
  m[1] += 1
  if wassat_stop_requested?(stop)
    m[0] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[0] = 2
  m[0] != 0

-> wassat_chain_header(lits, offs, lens, nc, nl, nv) (i64[] i64[] i64[] i64 i64 i64) bool
  return false if nv < 6 || nv > 2000000 || nc < 6 || nc > 20000000 || nl < 12 || nl > 80000000
  return false if offs.size < nc || lens.size < nc || lits.size < nl
  return false if lens[0] != 1 || offs[0] < 0 || offs[0] >= nl || lits[offs[0]] != 1
  lens[nc - 1] == 3

-> wassat_chain_pair(a, b) (i64 i64) i64
  return b * (b + 1) / 2 + a if a < b
  a * (a + 1) / 2 + b

# Expected literals are distinct. The bitset checks multiplicity as well as
# membership so a repeated literal cannot hide a missing constraint.
-> wassat_chain_match(lits, offs, lens, nc, nl, expected, len, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64 i64[] i64[] i64) bool
  ci = m[2]
  return false if ci >= nc || ci < 0 || lens[ci] != len
  return false if (ci & 1023) == 0 && wassat_chain_poll(m, stop, deadline)
  o = offs[ci]
  return false if o < 0 || o > nl - len
  mask = 0
  j = 0
  while j < len
    x = lits[o + j]
    k = 0
    while k < len && expected[k] != x
      k += 1
    return false if k == len || (mask & (1 << k)) != 0
    mask |= 1 << k
    j += 1
  m[2] += 1
  true

-> wassat_chain_decode(lits, offs, lens, nc, nl, nv, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) bool
  return false unless wassat_chain_header(lits, offs, lens, nc, nl, nv)
  return false if wassat_chain_poll(m, stop, deadline)
  m[11] = 1
  units = 0
  while units < nc && lens[units] == 1
    return false if (units & 1023) == 0 && wassat_chain_poll(m, stop, deadline)
    o = offs[units]
    return false if o < 0 || o >= nl || lits[o] == 0 || lits[o] > nv || lits[o] < 0 - nv
    units += 1
    m[17] += 1
  return false if units == nc
  f = lens[units]
  o = offs[units]
  return false if f < 2 || f > 32 || o < 0 || o > nl - f
  leafvars = nv
  j = 0
  while j < f
    x = lits[o + j]
    return false if x < 1 || x > nv
    leafvars = x - 1 if x - 1 < leafvars
    j += 1
  # Infer candidate dimensions, then establish them only by clause checks.
  powers = i64[9]
  powers[0] = 1
  d = 1
  depth = 0
  q = 0
  leaves = 0
  pairs = f * (f + 1) / 2
  while d <= 8 && powers[d - 1] <= 1000000 / f
    powers[d] = powers[d - 1] * f
    size = powers[d]
    if leafvars % size == 0 && (leafvars / size - 1) % d == 0
      steps = (leafvars / size - 1) / d
      if steps > 0 && leafvars + steps * ((size - 1) / (f - 1)) * pairs == nv
        return false if depth != 0
        depth = d
        q = steps
        leaves = size
    d += 1
  return false if depth == 0
  gates = (leaves - 1) / (f - 1)
  selector_clauses = q * gates * f * (1 + f * (f - 1) / 2)
  implications = q * depth * leaves * f
  equiv = 0
  equiv = 1 if nc == units + selector_clauses + 2 * implications
  return false if nc != units + selector_clauses + (1 + equiv) * implications
  m[3] = units
  m[4] = depth
  m[5] = f
  m[6] = q
  m[7] = leaves
  m[8] = leafvars
  m[9] = equiv
  flags = u8[2 * leaves]
  row = i64[32]
  expected = i64[32]
  m[10] = 72 + 2 * leaves + 512
  ci = 0
  lastbase = leafvars - leaves
  while ci < units
    return false if (ci & 1023) == 0 && wassat_chain_poll(m, stop, deadline)
    x = lits[offs[ci]]
    flags[x - 1] = 1 if x > 0 && x <= leaves
    if x < 0 - lastbase && x >= 0 - leafvars
      flags[leaves + (0 - x) - lastbase - 1] = 1
    ci += 1
  # First flags mean forced true, second flags mean forced false. Fold the
  # alternating tree with dual operators. Other unit values only strengthen.
  count = leaves
  level = depth - 1
  while level >= 0
    groups = count / f
    g = 0
    while g < groups
      return false if (g & 1023) == 0 && wassat_chain_poll(m, stop, deadline)
      yes = level % 2 ## i64
      no = 1 - yes ## i64
      j = 0
      while j < f
        a = flags[g * f + j] ## i64
        b = flags[leaves + g * f + j] ## i64
        if level % 2 == 0
          yes |= a
          no &= b
        else
          yes &= a
          no |= b
        j += 1
      flags[g] = yes
      flags[leaves + g] = no
      m[14] += 1
      g += 1
    count = groups
    level -= 1
  return false if flags[0] != 1 || flags[leaves] != 1
  m[2] = units
  m[11] = 2
  t = 0
  while t < q
    level = 0
    while level < depth
      g = 0
      while g < powers[level]
        base = leafvars + 1 + (t * gates + (powers[level] - 1) / (f - 1) + g) * pairs
        j = 0
        while j < f
          k = 0
          while k < f
            row[k] = base + wassat_chain_pair(j, k)
            expected[k] = row[k]
            k += 1
          return false unless wassat_chain_match(lits, offs, lens, nc, nl, expected, f, m, stop, deadline)
          m[12] += 1
          k = 0
          while k < f - 1
            b = k + 1
            while b < f
              expected[0] = 0 - row[k]
              expected[1] = 0 - row[b]
              return false unless wassat_chain_match(lits, offs, lens, nc, nl, expected, 2, m, stop, deadline)
              b += 1
            k += 1
          j += 1
        g += 1
      level += 1
    t += 1
  m[11] = 3
  t = 0
  while t < q
    level = depth - 1
    while level >= 0
      span = powers[depth - 1 - level]
      layer = t * depth + depth - 1 - level
      g = 0
      while g < powers[level]
        base = leafvars + 1 + (t * gates + (powers[level] - 1) / (f - 1) + g) * pairs
        j = 0
        while j < f
          k = 0
          while k < f
            a = 1 + layer * leaves + (g * f + j) * span
            b = 1 + (layer + 1) * leaves + (g * f + k) * span
            ell = 0
            while ell < span
              expected[0] = 0 - base - wassat_chain_pair(j, k)
              expected[1] = 0 - a - ell
              expected[2] = b + ell
              return false unless wassat_chain_match(lits, offs, lens, nc, nl, expected, 3, m, stop, deadline)
              m[13] += 1
              if equiv == 1
                expected[1] = 0 - b - ell
                expected[2] = a + ell
                return false unless wassat_chain_match(lits, offs, lens, nc, nl, expected, 3, m, stop, deadline)
                m[13] += 1
              ell += 1
            k += 1
          j += 1
        g += 1
      level -= 1
    t += 1
  m[2] == nc && !wassat_chain_poll(m, stop, deadline)

-> wassat_chain_refute(formula, m, stop, deadline = 0)
  return 0 if m.size < 32 || stop.size < 2 || formula["flat_lits_bits"] == 32
  i = 0
  while i < 32
    m[i] = 0
    i += 1
  start = clock_ms()
  hit = 0
  if wassat_chain_decode(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], formula["flat_ncl"], formula["flat_nlits"], formula["nvars"], m, stop, deadline)
    hit = -1
  m[15] = clock_ms() - start
  m[16] = hit
  hit

# This experimental scout is opt-in while end-to-end qualification is pending.
-> wassat_chain_enabled?
  env("WASSAT_FORMULA_CHAIN") == "1"

-> wassat_chain_plan(formula, workers, cdcl, sls, pre, extra)
  return nil unless wassat_chain_enabled?
  return nil if formula == nil || formula["flat_lits_bits"] == 32 || formula["formula_chain_done"] == true
  return nil if wassat_race_round1_conflicts != 0
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  nl = formula["flat_nlits"]
  return nil if nv == nil || nc == nil || nl == nil
  return nil if formula["flat_lits"] == nil || formula["flat_offs"] == nil || formula["flat_lens"] == nil
  return nil unless wassat_chain_header(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nc, nl, nv)
  bytes = 2001024 + 8 * (nv + 8)
  return nil if bytes > System.physical_memory_bytes / 32
  estimate = wassat_cdcl_arena_bytes(formula) * cdcl + wassat_sls_arena_bytes(formula) * sls
  estimate += wassat_preprocess_arena_bytes(formula) * pre + extra + bytes
  memory = System.physical_memory_bytes ## i64
  ceiling = memory / 3
  ceiling = 6442450944 if ceiling > 6442450944
  wassat_prof_note("race.formula_chain_plan estimate=[estimate] ceiling=[ceiling] scratch=[bytes] existing_workers=[workers]")
  return nil if estimate > ceiling
  { "formula_chain": true, "meta": i64[32], "scratch": bytes }

-> wassat_chain_arm(formula, plan, stop, res, base, nv)
  m = plan["meta"]
  start = clock_ms()
  hit = wassat_chain_refute(formula, m, stop, start + 5000)
  res[base + nv + 6] = start
  res[base + nv + 5] = clock_ms()
  return 0 if hit != -1 || wassat_stop_load(stop) != 0 || clock_ms() >= start + 5000
  z = ccall("__w_arr_store_rel", res, base, -1)
  z = wassat_stop_publish(stop, -1)
  -1

-> wassat_chain_finish_scout(formula, plan)
  m = plan["meta"]
  formula["formula_chain_done"] = m[0] != 1 && m[16] != -1
  0

-> wassat_chain_profile(m, label = "race.formula_chain")
  wassat_prof_note("[label] status=[m[16]] depth=[m[4]] fanin=[m[5]] transitions=[m[6]] leaves=[m[7]] checked_clauses=[m[2]] unit_scans=[m[17]] selector_rows=[m[12]] implications=[m[13]] folds=[m[14]] polls=[m[1]] stop=[m[0]] phase=[m[11]] scratch_bytes=[m[10]] ms=[m[15]]")
