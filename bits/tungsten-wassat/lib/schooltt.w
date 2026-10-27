# School-timetable class-slot pigeonhole refuter (schooltt-5-3-*).
#
# A recognized formula carries at least 200 disjoint positive 25-wide
# lesson blocks over consecutive variables. The refutation is a clique
# of at least 26 blocks that are pairwise in conflict at EVERY one of
# the 25 columns: for blocks B, C and column c, either the binary clause
# (-B[c] | -C[c]) is literally present, or both vars carry a room clause
# (-B[c] | r1 | r2), (-C[c] | s1 | s2) with all four cross binaries
# (-ri | -sj) present. Any model then chooses a true variable in each
# block; two clique blocks cannot choose the same column (directly, or
# because each chosen variable forces one of its rooms and every room
# pair is excluded), so 26 blocks would need 26 distinct columns out of
# 25. Contradiction.
#
# An earlier version of this lane checked exclusivity at column 0 only,
# on the assumption that the generator repeats the pattern at every
# column. That assumption is not in the clauses: a satisfiable formula
# with column-0 exclusivity and free remaining columns was refuted.
# Column 0 may suggest a candidate clique; it may never certify one.
# Every column is now verified against the literal clauses.
#
# On a refutation the lane also records the clique's variables (block
# vars plus their room vars) in result["witness_vars"], so the registry
# can ask the proof solver to refute that original-clause star and emit
# a checkable proof. Without that, this lane is fast-only.

WASSAT_SCHOOLTT_SLOTS = 25
WASSAT_SCHOOLTT_MAX_BLOCKS = 600
WASSAT_SCHOOLTT_HASH_SIZE = 2097152
WASSAT_SCHOOLTT_PAIR_CAP = 400000

-> wassat_schooltt_bin_key(u, v) (i64 i64) i64
  lo = u < v ? u : v
  hi = u < v ? v : u
  lo * 32768 + hi

-> wassat_schooltt_bin_insert(table, u, v) (i64[] i64 i64) i64
  return 1 if u == v
  key = wassat_schooltt_bin_key(u, v) + 1
  idx = key % WASSAT_SCHOOLTT_HASH_SIZE
  probes = 0
  while table[idx] != 0 && table[idx] != key
    idx = (idx + 1) % WASSAT_SCHOOLTT_HASH_SIZE
    probes += 1
    return 0 if probes > WASSAT_SCHOOLTT_HASH_SIZE
  table[idx] = key
  1

-> wassat_schooltt_bin_has(table, u, v) (i64[] i64 i64) bool
  return false if u == v || u <= 0 || v <= 0
  key = wassat_schooltt_bin_key(u, v) + 1
  idx = key % WASSAT_SCHOOLTT_HASH_SIZE
  probes = 0
  while table[idx] != 0
    return true if table[idx] == key
    idx = (idx + 1) % WASSAT_SCHOOLTT_HASH_SIZE
    probes += 1
    return false if probes > WASSAT_SCHOOLTT_HASH_SIZE
  false

# 1 when blocks b1, b2 conflict at every column, 0 when some column is
# free. col0[b] is the block's first variable; block vars are the 25
# consecutive variables from there (verified at registration).
-> wassat_schooltt_pair_conflict(table, room1, room2, col0, b1, b2) (i64[] i64[] i64[] i64[] i64 i64) i64
  c = 0
  while c < WASSAT_SCHOOLTT_SLOTS
    u = col0[b1] + c
    v = col0[b2] + c
    unless wassat_schooltt_bin_has(table, u, v)
      r1 = room1[u]
      r2 = room2[u]
      s1 = room1[v]
      s2 = room2[v]
      return 0 if r1 == 0 || s1 == 0
      return 0 unless wassat_schooltt_bin_has(table, r1, s1)
      return 0 unless wassat_schooltt_bin_has(table, r1, s2)
      return 0 unless wassat_schooltt_bin_has(table, r2, s1)
      return 0 unless wassat_schooltt_bin_has(table, r2, s2)
    c += 1
  1

-> wassat_schooltt_refute(formula, result)
  return result unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return result if nv < 10000 || nv > 22000 || ncl < 150000 || ncl > 300000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  col0_vars = i64[WASSAT_SCHOOLTT_MAX_BLOCKS]
  var_block = i64[nv + 1]
  nb = 0
  shape_ok = true
  ci = 0
  while ci < ncl && shape_ok
    n = fcl[ci]
    if n > 3
      off = fcs[ci]
      pos_only = true
      j = 0
      while j < n
        if fla[off + j] < 0
          pos_only = false
          break
        j += 1
      if pos_only
        if n != WASSAT_SCHOOLTT_SLOTS || nb >= WASSAT_SCHOOLTT_MAX_BLOCKS
          shape_ok = false
        else
          v0 = fla[off]
          exact = v0 >= 1 && v0 + WASSAT_SCHOOLTT_SLOTS - 1 <= nv
          j = 0
          while exact && j < WASSAT_SCHOOLTT_SLOTS
            exact = false if fla[off + j] != v0 + j || var_block[v0 + j] != 0
            j += 1
          if exact
            col0_vars[nb] = v0
            j = 0
            while j < WASSAT_SCHOOLTT_SLOTS
              var_block[v0 + j] = nb + 1
              j += 1
            nb += 1
          else
            shape_ok = false
    ci += 1
  return result unless shape_ok && nb >= 200

  table = i64[WASSAT_SCHOOLTT_HASH_SIZE]
  room1 = i64[nv + 1]
  room2 = i64[nv + 1]
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    if n == 2
      l0 = fla[off]
      l1 = fla[off + 1]
      if l0 < 0 && l1 < 0
        u = 0 - l0
        v = 0 - l1
        if u >= 1 && u <= nv && v >= 1 && v <= nv
          return result if wassat_schooltt_bin_insert(table, u, v) == 0
    elsif n == 3
      l0 = fla[off]
      l1 = fla[off + 1]
      l2 = fla[off + 2]
      if l0 < 0 && l1 > 0 && l2 > 0
        v = 0 - l0
        if v >= 1 && v <= nv && var_block[v] != 0 && room1[v] == 0
          room1[v] = l1
          room2[v] = l2
    ci += 1

  # Greedy clique from each start block; pair verdicts are memoized in
  # pair_state (0 unknown, 1 conflict, 2 free column exists).
  pair_state = i8[nb * nb]
  pair_checks = 0
  clique = i64[nb]
  b1 = 0
  while b1 < nb
    clique[0] = b1
    csz = 1
    b2 = b1 + 1
    while b2 < nb && csz <= WASSAT_SCHOOLTT_SLOTS
      all_adj = true
      k = 0
      while k < csz
        cb = clique[k]
        lo = cb < b2 ? cb : b2
        hi = cb < b2 ? b2 : cb
        st = pair_state[lo * nb + hi]
        if st == 0
          pair_checks += 1
          return result if pair_checks > WASSAT_SCHOOLTT_PAIR_CAP
          pc = wassat_schooltt_pair_conflict(
            table, room1, room2, col0_vars, lo, hi
          )
          st = pc == 1 ? 1 : 2
          pair_state[lo * nb + hi] = st
        if st != 1
          all_adj = false
          break
        k += 1
      if all_adj
        clique[csz] = b2
        csz += 1
      b2 += 1
    if csz > WASSAT_SCHOOLTT_SLOTS
      witness = []
      k = 0
      while k < csz
        v0 = col0_vars[clique[k]]
        c = 0
        while c < WASSAT_SCHOOLTT_SLOTS
          v = v0 + c
          witness.push(v)
          witness.push(room1[v]) if room1[v] > 0
          witness.push(room2[v]) if room2[v] > 0
          c += 1
        k += 1
      result["recognized"] = true
      result["bits"] = WASSAT_SCHOOLTT_SLOTS
      result["samples"] = csz
      result["trials"] = 1
      result["status"] = -1
      result["witness_vars"] = witness
      return result
    b1 += 1
  result
