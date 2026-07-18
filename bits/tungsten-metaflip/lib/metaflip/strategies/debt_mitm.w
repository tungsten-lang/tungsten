# Production pooled move: two-level debt MITM with honest net-rank accounting.
#
# Two kinds of shoulder are searched:
#
#   * six live terms are replaced directly by four (net rank <= -2), or
#   * five live terms are expanded by one exact controlled split, and the
#     resulting six labelled terms are replaced by four (net rank <= -1
#     relative to the unsplit input scheme).
#
# The split is a candidate generator, never rank credit: the successful four
# terms are spliced in place of the five ORIGINAL live terms.  There is no
# path in this move which calls a 5 -> 4 oracle on an R+1 scheme and reports
# merely returning to R as progress.
#
# A bounded reservoir is drawn from the six factor spans.  Four-term sums are
# found by a 2+2 MITM using two independent linear tensor fingerprints.  A
# fingerprint match is only a filter: local coefficient equality and then the
# independent complete matrix-multiplication verifier in common.w are both
# mandatory before an output is returned.
#
# Stats use the pooled-exact convention:
#   attempts, exact, rank_hits, density_hits, neutral, rejects, candidates,
#   flags.
# flags: bit 0 exact gate, bit 1 direct 6->4, bit 2 split-assisted 5->4,
#        bit 3 pair MITM, bit 4 two linear fingerprints.

use pooled_exact

FFDM_POOL_CAP = 192
FFDM_TABLE_CAP = 65536

-> ffdm_span_value(basis, count, code) (i64[] i64 i64) i64
  value = 0 ## i64
  bit = 0 ## i64
  while bit < count
    if ((code >> bit) & 1) != 0
      value = value ^ basis[bit]
    bit += 1
  value

-> ffdm_add_candidate(cu, cv, cw, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if count >= FFDM_POOL_CAP || u == 0 || v == 0 || w == 0
    return count
  i = 0 ## i64
  while i < count
    if cu[i] == u && cv[i] == v && cw[i] == w
      return count
    i += 1
  cu[count] = u
  cv[count] = v
  cw[count] = w
  count + 1

# The reservoir keeps useful algebraic closures ahead of broad span samples:
# live terms, every exact one-axis merge, then rotating one-axis and full
# Cartesian span points.  Across attempts the cursor covers different parts
# of the 63^3 product without making any single attempt unbounded.
-> ffdm_fill_pool(su, sv, sw, attempt, cu, cv, cw) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < 6
    count = ffdm_add_candidate(cu, cv, cw, count, su[i], sv[i], sw[i])
    i += 1

  # Two closure rounds matter for a catalyst shoulder: the first can undo the
  # controlled split, and the second can combine that recovered child with a
  # pre-existing split sibling.  This is still bounded by the fixed reservoir.
  closure_round = 0 ## i64
  while closure_round < 2 && count < FFDM_POOL_CAP
    limit = count ## i64
    i = 0
    while i < limit && count < FFDM_POOL_CAP
      j = i + 1 ## i64
      while j < limit && count < FFDM_POOL_CAP
        if cv[i] == cv[j] && cw[i] == cw[j]
          count = ffdm_add_candidate(cu, cv, cw, count, cu[i] ^ cu[j], cv[i], cw[i])
        if cu[i] == cu[j] && cw[i] == cw[j]
          count = ffdm_add_candidate(cu, cv, cw, count, cu[i], cv[i] ^ cv[j], cw[i])
        if cu[i] == cu[j] && cv[i] == cv[j]
          count = ffdm_add_candidate(cu, cv, cw, count, cu[i], cv[i], cw[i] ^ cw[j])
        j += 1
      i += 1
    closure_round += 1

  # Balanced one-axis span sampling.  These points often preserve a useful
  # complementary pair while changing one mode much more broadly than a
  # pairwise closure.
  round = 0 ## i64
  while round < 4 && count < FFDM_POOL_CAP
    i = 0
    while i < 6 && count < FFDM_POOL_CAP
      code = 1 + ((attempt * 11 + round * 17 + i * 5) % 63) ## i64
      count = ffdm_add_candidate(cu, cv, cw, count, ffdm_span_value(su, 6, code), sv[i], sw[i])
      code = 1 + ((attempt * 19 + round * 13 + i * 7) % 63)
      count = ffdm_add_candidate(cu, cv, cw, count, su[i], ffdm_span_value(sv, 6, code), sw[i])
      code = 1 + ((attempt * 23 + round * 11 + i * 9) % 63)
      count = ffdm_add_candidate(cu, cv, cw, count, su[i], sv[i], ffdm_span_value(sw, 6, code))
      i += 1
    round += 1

  cursor = (attempt * 7919 + 97) % 250047 ## i64
  probes = 0 ## i64
  while count < FFDM_POOL_CAP && probes < FFDM_POOL_CAP * 12
    uc = 1 + (cursor % 63) ## i64
    vc = 1 + ((cursor / 63) % 63) ## i64
    wc = 1 + ((cursor / 3969) % 63) ## i64
    count = ffdm_add_candidate(cu, cv, cw, count, ffdm_span_value(su, 6, uc), ffdm_span_value(sv, 6, vc), ffdm_span_value(sw, 6, wc))
    cursor = (cursor + 104729) % 250047
    probes += 1
  count

-> ffdm_hash(key0, key1) (i64 i64) i64
  (key0 ^ (key0 >> 19) ^ (key1 << 7) ^ (key1 >> 13)) & (FFDM_TABLE_CAP - 1)

# Fast decomposable dual projections.  Each signature bit evaluates a term
# against phi_U (x) phi_V (x) phi_W, so XORing signatures is exactly linear in
# the represented tensor.  This avoids scanning all n^6 ambient cells and
# keeps 7x7 attempts in the same broad cost class as small rectangular ones.
-> ffdm_mix(value) (i64) i64
  value = value ^ (value << 13)
  value = value ^ (value >> 7)
  value = value ^ (value << 17)
  value

-> ffdm_term_fingerprint(u, v, w, salt) (i64 i64 i64 i64) i64
  signature = 0 ## i64
  bit = 0 ## i64
  while bit < 61
    seed = (bit + 1) * 193 + salt * 1009 ## i64
    umask = ffdm_mix(seed * 109 + 17) ## i64
    vmask = ffdm_mix(seed * 239 + 31) ## i64
    wmask = ffdm_mix(seed * 431 + 47) ## i64
    up = ffw_popcount(u & umask) & 1 ## i64
    vp = ffw_popcount(v & vmask) & 1 ## i64
    wp = ffw_popcount(w & wmask) & 1 ## i64
    if up != 0 && vp != 0 && wp != 0
      signature = signature | (1 << bit)
    bit += 1
  signature

# Find four DISTINCT reservoir terms whose tensor XOR is the six-term target.
# The two decomposable-projection fingerprints are exactly linear under tensor
# XOR.  Exact local equality is still checked for every fingerprint hit.
-> ffdm_pair_search(su, sv, sw, cu, cv, cw, count, uw, vw, ww, ru, rv, rep_w, table0, table1, table_pair) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if count < 4
    return 0
  sig0 = i64[FFDM_POOL_CAP]
  sig1 = i64[FFDM_POOL_CAP]
  ambient = uw * vw * ww ## i64
  i = 0 ## i64
  while i < count
    if ambient <= 8192
      sig0[i] = ffpe_term_fingerprint(cu[i], cv[i], cw[i], uw, vw, ww, 41)
      sig1[i] = ffpe_term_fingerprint(cu[i], cv[i], cw[i], uw, vw, ww, 137)
    else
      sig0[i] = ffdm_term_fingerprint(cu[i], cv[i], cw[i], 41)
      sig1[i] = ffdm_term_fingerprint(cu[i], cv[i], cw[i], 137)
    i += 1

  target0 = 0 ## i64
  target1 = 0 ## i64
  i = 0
  while i < 6
    if ambient <= 8192
      target0 = target0 ^ ffpe_term_fingerprint(su[i], sv[i], sw[i], uw, vw, ww, 41)
      target1 = target1 ^ ffpe_term_fingerprint(su[i], sv[i], sw[i], uw, vw, ww, 137)
    else
      target0 = target0 ^ ffdm_term_fingerprint(su[i], sv[i], sw[i], 41)
      target1 = target1 ^ ffdm_term_fingerprint(su[i], sv[i], sw[i], 137)
    i += 1

  i = 0
  while i < FFDM_TABLE_CAP
    table_pair[i] = 0 - 1
    i += 1

  i = 0
  while i < count
    j = i + 1 ## i64
    while j < count
      key0 = sig0[i] ^ sig0[j] ## i64
      key1 = sig1[i] ^ sig1[j] ## i64
      slot = ffdm_hash(key0, key1) ## i64
      while table_pair[slot] >= 0
        slot = (slot + 1) & (FFDM_TABLE_CAP - 1)
      table0[slot] = key0
      table1[slot] = key1
      table_pair[slot] = i * FFDM_POOL_CAP + j
      j += 1
    i += 1

  i = 0
  while i < count
    j = i + 1 ## i64
    while j < count
      need0 = target0 ^ sig0[i] ^ sig0[j] ## i64
      need1 = target1 ^ sig1[i] ^ sig1[j] ## i64
      slot = ffdm_hash(need0, need1) ## i64
      while table_pair[slot] >= 0
        if table0[slot] == need0 && table1[slot] == need1
          encoded = table_pair[slot] ## i64
          a = encoded / FFDM_POOL_CAP ## i64
          b = encoded % FFDM_POOL_CAP ## i64
          if a != i && a != j && b != i && b != j
            ru[0] = cu[a]
            rv[0] = cv[a]
            rep_w[0] = cw[a]
            ru[1] = cu[b]
            rv[1] = cv[b]
            rep_w[1] = cw[b]
            ru[2] = cu[i]
            rv[2] = cv[i]
            rep_w[2] = cw[i]
            ru[3] = cu[j]
            rv[3] = cv[j]
            rep_w[3] = cw[j]
            if ffpe_local_equal(su, sv, sw, 6, ru, rv, rep_w, 4, uw, vw, ww) != 0
              return 1
        slot = (slot + 1) & (FFDM_TABLE_CAP - 1)
      j += 1
    i += 1
  0

-> ffdm_overlap(us, vs, ws, left, right) (i64[] i64[] i64[] i64 i64) i64
  score = 0 ## i64
  if us[left] == us[right]
    score += 8
  if vs[left] == vs[right]
    score += 8
  if ws[left] == ws[right]
    score += 8
  score += ffw_popcount(us[left] & us[right])
  score += ffw_popcount(vs[left] & vs[right])
  score += ffw_popcount(ws[left] & ws[right])
  score

# Three deterministic window families: cyclic coverage, dispersed sampling,
# and factor-connected shoulders.  Attempt zero deliberately selects 0..k-1
# so a small explicit fixture exercises the public entry point directly.
-> ffdm_choose(us, vs, ws, rank, wanted, nonce, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if wanted > rank
    return 0
  mode = nonce % 3 ## i64
  if mode == 0
    start = ((nonce / 3) * 5) % rank ## i64
    i = 0 ## i64
    while i < wanted
      selected[i] = (start + i) % rank
      i += 1
    return wanted
  if mode == 1
    cursor = (nonce * 17 + 3) % rank ## i64
    stride = 1 + ((nonce * 29 + 7) % rank) ## i64
    used = 0 ## i64
    probes = 0 ## i64
    while used < wanted && probes < rank * 3
      duplicate = 0 ## i64
      j = 0 ## i64
      while j < used
        if selected[j] == cursor
          duplicate = 1
        j += 1
      if duplicate == 0
        selected[used] = cursor
        used += 1
      cursor = (cursor + stride) % rank
      probes += 1
    cursor = 0
    while used < wanted
      duplicate = 0
      j = 0
      while j < used
        if selected[j] == cursor
          duplicate = 1
        j += 1
      if duplicate == 0
        selected[used] = cursor
        used += 1
      cursor += 1
    return wanted

  anchor = (nonce * 31 + 1) % rank ## i64
  selected[0] = anchor
  used = 1
  while used < wanted
    best = 0 - 1 ## i64
    best_score = 0 - 1000000 ## i64
    candidate = 0 ## i64
    while candidate < rank
      duplicate = 0
      j = 0
      while j < used
        if selected[j] == candidate
          duplicate = 1
        j += 1
      if duplicate == 0
        score = 0 ## i64
        j = 0
        while j < used
          score += ffdm_overlap(us, vs, ws, selected[j], candidate)
          j += 1
        # Rotate ties instead of selecting the same low-index shoulder.
        score = score * rank - ((candidate + rank - nonce) % rank)
        if score > best_score
          best_score = score
          best = candidate
      candidate += 1
    if best < 0
      return 0
    selected[used] = best
    used += 1
  wanted

# Expand five selected ORIGINAL terms into a six-term labelled shoulder by
# splitting one nontrivial factor.  Return zero if no legal split exists.
-> ffdm_make_split_shoulder(us, vs, ws, selected, nonce, su, sv, sw) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  pass = 0 ## i64
  while pass < 15
    local = (nonce + pass * 7) % 5 ## i64
    axis = (nonce + pass) % 3 ## i64
    source = selected[local] ## i64
    factor = ffpe_axis_get(us, vs, ws, source, axis) ## i64
    if ffw_popcount(factor) >= 2
      first = factor & (0 - factor) ## i64
      second = factor ^ first ## i64
      if first != 0 && second != 0
        out = 0 ## i64
        i = 0 ## i64
        while i < 5
          position = selected[i] ## i64
          if i == local
            su[out] = us[position]
            sv[out] = vs[position]
            sw[out] = ws[position]
            z = ffpe_axis_set(su, sv, sw, out, axis, first) ## i64
            out += 1
            su[out] = us[position]
            sv[out] = vs[position]
            sw[out] = ws[position]
            z = ffpe_axis_set(su, sv, sw, out, axis, second)
            out += 1
          else
            su[out] = us[position]
            sv[out] = vs[position]
            sw[out] = ws[position]
            out += 1
          i += 1
        return out
    pass += 1
  0

# `budget` is an attempt count, not wall-clock time, and `nonce` offsets the
# deterministic window/reservoir stream. Input arrays are never modified. A
# positive return is an independently verified lower-rank scheme; zero means
# no hit within the bounded shoulder/reservoir sample.
-> ffdm_search(us, vs, ws, rank, n, m, p, budget, nonce, out_u, out_v, out_w, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if stats.size() < 8
    return 0
  z = ffpe_clear(stats) ## i64
  stats[7] = 31
  if rank < 5 || budget < 1
    return 0
  if us.size() < rank || vs.size() < rank || ws.size() < rank || out_u.size() < rank || out_v.size() < rank || out_w.size() < rank
    stats[5] = 1
    stats[7] = stats[7] | 32
    return 0
  uw = n * m ## i64
  vw = m * p ## i64
  ww = n * p ## i64
  if uw < 1 || vw < 1 || ww < 1 || uw > 63 || vw > 63 || ww > 63
    stats[7] = stats[7] | 64
    return 0

  selected = i64[6]
  su = i64[6]
  sv = i64[6]
  sw = i64[6]
  cu = i64[FFDM_POOL_CAP]
  cv = i64[FFDM_POOL_CAP]
  cw = i64[FFDM_POOL_CAP]
  ru = i64[4]
  rv = i64[4]
  rep_w = i64[4]
  table0 = i64[FFDM_TABLE_CAP]
  table1 = i64[FFDM_TABLE_CAP]
  table_pair = i64[FFDM_TABLE_CAP]

  attempt = 0 ## i64
  while attempt < budget
    logical_attempt = nonce + attempt ## i64
    stats[0] += 1
    original_count = 6 ## i64
    shoulder_ok = 0 ## i64
    # Even attempts are direct 6 -> 4.  Odd attempts create one labelled
    # shoulder from five originals, but successful output replaces those five.
    if (logical_attempt & 1) == 0 && rank >= 6
      if ffdm_choose(us, vs, ws, rank, 6, logical_attempt / 2, selected) == 6
        i = 0 ## i64
        while i < 6
          su[i] = us[selected[i]]
          sv[i] = vs[selected[i]]
          sw[i] = ws[selected[i]]
          i += 1
        shoulder_ok = 1
    else
      original_count = 5
      if ffdm_choose(us, vs, ws, rank, 5, logical_attempt / 2, selected) == 5
        if ffdm_make_split_shoulder(us, vs, ws, selected, logical_attempt * 13 + 5, su, sv, sw) == 6
          shoulder_ok = 1

    if shoulder_ok != 0
      count = ffdm_fill_pool(su, sv, sw, logical_attempt, cu, cv, cw) ## i64
      if ffdm_pair_search(su, sv, sw, cu, cv, cw, count, uw, vw, ww, ru, rv, rep_w, table0, table1, table_pair) != 0
        candidate_u = i64[rank]
        candidate_v = i64[rank]
        candidate_w = i64[rank]
        candidate_rank = ffpe_splice(us, vs, ws, rank, selected, original_count, ru, rv, rep_w, 4, candidate_u, candidate_v, candidate_w) ## i64
        # Explicit accounting guard.  Direct shoulders must save >=2; split
        # shoulders must save >=1 against the unsplit input scheme.
        maximum = rank - 1 ## i64
        if original_count == 6
          maximum = rank - 2
        if candidate_rank <= maximum
          if ffpe_note(us, vs, ws, rank, candidate_u, candidate_v, candidate_w, candidate_rank, n, m, p, stats) != 0
            z = ffpe_copy(candidate_u, candidate_v, candidate_w, candidate_rank, out_u, out_v, out_w)
            return candidate_rank
        else
          stats[5] += 1
    attempt += 1
  0

# Explicit 6 -> 4 algebraic control for the reservoir, two-fingerprint MITM,
# and exact local gate.  The first two source terms have each been split on a
# different axis; the expected solution merges both pairs and retains the two
# untouched terms.  Full-scheme verification is exercised by the public smoke
# test, which embeds the same construction in an exact MMT certificate.
-> ffdm_debt_mitm_selftest() i64
  su = i64[6]
  sv = i64[6]
  sw = i64[6]
  su[0] = 1
  sv[0] = 3
  sw[0] = 5
  su[1] = 2
  sv[1] = 3
  sw[1] = 5
  su[2] = 5
  sv[2] = 2
  sw[2] = 3
  su[3] = 5
  sv[3] = 4
  sw[3] = 3
  su[4] = 6
  sv[4] = 5
  sw[4] = 4
  su[5] = 7
  sv[5] = 1
  sw[5] = 6
  cu = i64[FFDM_POOL_CAP]
  cv = i64[FFDM_POOL_CAP]
  cw = i64[FFDM_POOL_CAP]
  count = ffdm_fill_pool(su, sv, sw, 0, cu, cv, cw) ## i64
  ru = i64[4]
  rv = i64[4]
  rep_w = i64[4]
  table0 = i64[FFDM_TABLE_CAP]
  table1 = i64[FFDM_TABLE_CAP]
  table_pair = i64[FFDM_TABLE_CAP]
  ffdm_pair_search(su, sv, sw, cu, cv, cw, count, 3, 3, 3, ru, rv, rep_w, table0, table1, table_pair)
