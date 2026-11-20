# Syntactic Structural Pruning & Specialist Arm Preparation for Wassat:
#
#   1. Control-Variable Identification (Fanout / Clause-Cluster Bridging)
#      + Bounded 1-Literal & 2-Literal Control Probing
#   2. Cardinality / At-Most-One / Exactly-One / Sequential-Counter Extraction
#      + Domain Case-Split & Monotone Chain Cut Propagation
#   3. DETOUR Bidirectional Wavefront & Macro-Transition Portal-Balance Pruning
#   4. Clue / Sudoku Bitmask Truth-Table Arc-Consistency & Pairwise Exclusion
#
# All four passes are 100% general, syntactic, and competition-legal. Every
# unit and binary pruning clause derived by any pass is shared across all
# portfolio arms.

# Extract a normalized clause list from either a flat or boxed formula hash.
-> wassat_struct_clauses_of(formula)
  if formula.has_key?("clauses") && formula["clauses"] != nil && !formula["clauses"].empty?
    return formula["clauses"]
  out = []
  return out unless formula.has_key?("flat_ncl")
  fncl = formula["flat_ncl"]
  flits = formula["flat_lits"]
  foffs = formula["flat_offs"]
  flens = formula["flat_lens"]
  return out if fncl == nil || flits == nil || foffs == nil || flens == nil
  ci = 0
  while ci < fncl
    len = flens[ci]
    off = foffs[ci]
    c = []
    j = 0
    while j < len
      c.push(flits[off + j])
      j += 1
    out.push(c)
    ci += 1
  out

# Build a unified flat i64[] clause view without unpacking flat inputs into
# boxed Arrays. Boxed-only inputs (or explicit boxed overrides) are packed once.
-> wassat_struct_flat_view(formula)
  return formula if formula.has_key?("is_struct_view") && formula["is_struct_view"] == true
  if formula.has_key?("clauses") && formula["clauses"] != nil && !formula["clauses"].empty?
    clauses = formula["clauses"]
    ncl = clauses.size
    if ncl <= 0
      return {
        "clauses": [], "boxed": false,
        "flat_lits": i64[0], "flat_offs": i64[0], "flat_lens": i64[0],
        "flat_ncl": 0, "flat_nlits": 0,
        "packed_from_boxed": 0, "is_struct_view": true
      }
    nlits = 0
    ci = 0
    while ci < ncl
      nlits += clauses[ci].size
      ci += 1
    fla = i64[nlits]
    fcs = i64[ncl]
    fcl = i64[ncl]
    at = 0
    ci = 0
    while ci < ncl
      c = clauses[ci]
      clen = c.size
      fcs[ci] = at
      fcl[ci] = clen
      j = 0
      while j < clen
        fla[at] = c[j]
        at += 1
        j += 1
      ci += 1
    return {
      "clauses": [], "boxed": false,
      "flat_lits": fla, "flat_offs": fcs, "flat_lens": fcl,
      "flat_ncl": ncl, "flat_nlits": nlits,
      "packed_from_boxed": ncl, "is_struct_view": true
    }
  if formula.has_key?("flat_ncl") && formula["flat_ncl"] != nil && formula["flat_lits_bits"] != 32
    fncl = formula["flat_ncl"]
    flits = formula["flat_lits"]
    foffs = formula["flat_offs"]
    flens = formula["flat_lens"]
    if fncl > 0 && flits != nil && foffs != nil && flens != nil
      fnlits = formula.has_key?("flat_nlits") && formula["flat_nlits"] != nil ? formula["flat_nlits"] : flits.size
      return {
        "clauses": [], "boxed": false,
        "flat_lits": flits, "flat_offs": foffs, "flat_lens": flens,
        "flat_ncl": fncl, "flat_nlits": fnlits,
        "packed_from_boxed": 0, "is_struct_view": true
      }
  {
    "clauses": [], "boxed": false,
    "flat_lits": i64[0], "flat_offs": i64[0], "flat_lens": i64[0],
    "flat_ncl": 0, "flat_nlits": 0,
    "packed_from_boxed": 0, "is_struct_view": true
  }

# Encode literal l in -nv..nv into 0..2*nv+1
-> wassat_struct_lit_idx(l) (i64) i64
  l > 0 ? (l << 1) : (((0 - l) << 1) + 1) ## i64

-> wassat_struct_idx_lit(idx) (i64) i64
  (idx & 1) == 0 ? (idx >> 1) : (0 - (idx >> 1)) ## i64

# Open-addressed 64-bit packed-literal deduplication for binary clauses (a v b).
# Returns 1 when newly inserted, 0 when already present.
-> wassat_struct_bin_dedup(ht, hmask, a, b) (i64[] i64 i64 i64) i64
  ua = a > 0 ? (a << 1) : (((0 - a) << 1) + 1) ## i64
  ub = b > 0 ? (b << 1) : (((0 - b) << 1) + 1) ## i64
  cu = ua <= ub ? ua : ub ## i64
  cv = ua <= ub ? ub : ua ## i64
  key = (cu << 32) | cv ## i64
  h = ((cu * 1000003) ^ cv) & hmask ## i64
  while ht[h] != 0
    return 0 if ht[h] == key
    h = (h + 1) & hmask ## i64
  ht[h] = key
  1

# ---- 1. Syntactic Control-Variable Identification --------------------------
#
# Identifies variables with high clause fanout that bridge multiple variable
# stride clusters across binary/ternary/quaternary clauses with balanced
# polarity. Returns a hash:
#   "control_vars": top control variables ordered by bridging score descending
#   "scores": i64[nv + 1] bridging scores

-> wassat_identify_control_scan(nv, fla, fcs, fcl, ncl, uval, pos_occ, neg_occ, tern_occ, quad_occ, buckets, scores, cands) (i64 i64[] i64[] i64[] i64 i8[] i64[] i64[] i64[] i64[] i64[] i64[] i32[]) i64
  ci = 0
  while ci < ncl
    if fcl[ci] == 1
      l = fla[fcs[ci]]
      v = l < 0 ? 0 - l : l ## i64
      if v >= 1 && v <= nv
        if l > 0
          uval[v] = 1
        else
          uval[v] = -1
    ci += 1

  stride = nv >= 64 ? (nv / 60 + 1) : 1 ## i64
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    if clen >= 2 && clen <= 6
      off = fcs[ci]
      sat = 0
      active_len = 0
      cmask = 0 ## i64
      j = 0
      while j < clen
        l = fla[off + j]
        v = l < 0 ? 0 - l : l ## i64
        if v >= 1 && v <= nv
          uv = uval[v] ## i64
          if (l > 0 && uv > 0) || (l < 0 && uv < 0)
            sat = 1
          elsif uv == 0
            active_len += 1
            b = (v - 1) / stride
            b = 60 if b > 60
            cmask = cmask | (1 << b) ## i64
        j += 1
      if sat == 0 && active_len >= 2
        j = 0
        while j < clen
          l = fla[off + j]
          v = l < 0 ? 0 - l : l ## i64
          if v >= 1 && v <= nv && uval[v] == 0
            if l > 0
              pos_occ[v] += 1
            else
              neg_occ[v] += 1
            tern_occ[v] += 1 if active_len == 3
            quad_occ[v] += 1 if active_len == 4
            buckets[v] = buckets[v] | cmask ## i64
          j += 1
    ci += 1

  ncands = 0
  v = 1
  while v <= nv
    if uval[v] == 0
      p = pos_occ[v]
      n = neg_occ[v]
      if p >= 2 && n >= 2
        min_pn = p < n ? p : n ## i64
        bcnt = ccall_nobox("__w_bit_ctpop_u64", buckets[v]) ## i64
        if bcnt >= 2 || (tern_occ[v] + quad_occ[v]) >= 4
          sc = min_pn * (tern_occ[v] + 2 * quad_occ[v] + 1) * (bcnt + 1) ## i64
          # Selector / control-word boost: defined in a small positive domain
          # (p <= 8) and used negatively as a guard across many clauses.
          if p <= 8 && n >= 3 * p && n >= 12
            sc = sc + n * (bcnt + 2) * 100000 ## i64
          scores[v] = sc
          cands[ncands] = v
          ncands += 1
    v += 1
  ncands

-> wassat_identify_control_top(cands, ncands, scores, top_buf, max_vars) (i32[] i64 i64[] i32[] i64) i64
  return 0 if max_vars <= 0
  top_len = 0
  i = 0
  while i < ncands
    cv = cands[i] ## i64
    csc = scores[cv]
    if top_len < max_vars || csc > scores[top_buf[top_len - 1]]
      top_len += 1 if top_len < max_vars
      k = top_len - 1
      while k > 0 && scores[top_buf[k - 1]] < csc
        top_buf[k] = top_buf[k - 1]
        k -= 1
      top_buf[k] = cv
    i += 1
  top_len

-> wassat_identify_control_vars(nv, formula, max_vars = 64)
  if nv <= 0
    return { "control_vars": [], "scores": i64[1] }
  view = wassat_struct_flat_view(formula)
  fla = view["flat_lits"] ## i64[]
  fcs = view["flat_offs"] ## i64[]
  fcl = view["flat_lens"] ## i64[]
  ncl = view["flat_ncl"] ## i64

  uval = i8[nv + 1]
  pos_occ = i64[nv + 1]
  neg_occ = i64[nv + 1]
  tern_occ = i64[nv + 1]
  quad_occ = i64[nv + 1]
  buckets = i64[nv + 1]
  scores = i64[nv + 1]
  cands = i32[nv + 1]
  ncands = wassat_identify_control_scan(
    nv, fla, fcs, fcl, ncl, uval, pos_occ, neg_occ,
    tern_occ, quad_occ, buckets, scores, cands
  )
  cap_top = max_vars > 0 ? max_vars : 0
  top_buf = i32[cap_top + 1]
  top_len = wassat_identify_control_top(cands, ncands, scores, top_buf, cap_top)
  top = []
  i = 0
  while i < top_len
    top.push(top_buf[i])
    i += 1
  { "control_vars": top, "scores": scores }

# ---- 2. Cardinality / EO / AMO / Sequential-Counter Bound Propagation ------

-> wassat_struct_enqueue_unit_flat(nv, val, q, st, lit) (i64 i8[] i32[] i64[] i64) i64
  v = lit < 0 ? 0 - lit : lit ## i64
  return 0 if v < 1 || v > nv
  pol = lit > 0 ? 1 : -1 ## i64
  cur = val[v] ## i64
  return 0 - 1 if cur == 0 - pol
  if cur == 0
    val[v] = pol
    qt = st[1]
    q[qt] = lit
    st[1] = qt + 1
  1

# Propagate queued units along sorted CSR binary adjacency (bst, bad), dynamic
# binary adjacency (dyn_head, dyn_to, dyn_next), and CSR ternary occurrences
# (tern_lits, tst, toc) in O(propagations * deg).
-> wassat_struct_propagate_units_flat(nv, val, q, st, bst, bad, dyn_head, dyn_to, dyn_next, tern_lits, tst, toc) (i64 i8[] i32[] i64[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[]) i64
  qh = st[0]
  while qh < st[1]
    lit = q[qh] ## i64
    qh += 1
    st[0] = qh
    c = lit > 0 ? (lit << 1) : (((0 - lit) << 1) + 1) ## i64
    p = bst[c] ## i64
    pe = bst[c + 1] ## i64
    while p < pe
      imp_c = bad[p] ## i64
      imp_l = (imp_c & 1) == 0 ? (imp_c >> 1) : (0 - (imp_c >> 1)) ## i64
      if wassat_struct_enqueue_unit_flat(nv, val, q, st, imp_l) < 0
        return 0 - 1
      p += 1
    e = dyn_head[c] ## i64
    while e != 0
      imp_c = dyn_to[e - 1] ## i64
      imp_l = (imp_c & 1) == 0 ? (imp_c >> 1) : (0 - (imp_c >> 1)) ## i64
      if wassat_struct_enqueue_unit_flat(nv, val, q, st, imp_l) < 0
        return 0 - 1
      e = dyn_next[e - 1] ## i64
    neg_c = c ^ 1 ## i64
    tp = tst[neg_c] ## i64
    tpe = tst[neg_c + 1] ## i64
    while tp < tpe
      ti = toc[tp] ## i64
      tbase = ti * 3 ## i64
      sat = 0
      unassigned = 0
      ul = 0 ## i64
      j = 0
      while j < 3
        tl = tern_lits[tbase + j] ## i64
        tv = tl < 0 ? 0 - tl : tl ## i64
        if tv >= 1 && tv <= nv
          tvv = val[tv] ## i64
          vv = tl > 0 ? tvv : 0 - tvv ## i64
          if vv > 0
            sat = 1
          elsif vv == 0
            unassigned += 1
            ul = tl
        j += 1
      if sat == 0
        return 0 - 1 if unassigned == 0
        if unassigned == 1
          if wassat_struct_enqueue_unit_flat(nv, val, q, st, ul) < 0
            return 0 - 1
      tp += 1
  1

# Check whether implication edge u_code => v_code exists in sorted CSR (bst, bad)
# via O(log(min(deg(u), deg(-v)))) binary search, or in dynamic edges.
-> wassat_struct_has_imp_flat(bst, bad, dyn_head, dyn_to, dyn_next, u_code, v_code) (i32[] i32[] i32[] i32[] i32[] i64 i64) i64
  deg1 = bst[u_code + 1] - bst[u_code] ## i64
  inv_v = v_code ^ 1 ## i64
  deg2 = bst[inv_v + 1] - bst[inv_v] ## i64
  src = u_code ## i64
  target = v_code ## i64
  if deg2 < deg1
    src = inv_v
    target = u_code ^ 1 ## i64
  lo = bst[src] ## i64
  hi = bst[src + 1] - 1 ## i64
  while lo <= hi
    mid = (lo + hi) >> 1 ## i64
    m = bad[mid] ## i64
    return 1 if m == target
    if m < target
      lo = mid + 1
    else
      hi = mid - 1
  e = dyn_head[u_code] ## i64
  while e != 0
    return 1 if dyn_to[e - 1] == v_code
    e = dyn_next[e - 1] ## i64
  0

-> wassat_struct_has_mutex_flat(bst, bad, dyn_head, dyn_to, dyn_next, l1, l2) (i32[] i32[] i32[] i32[] i32[] i64 i64) i64
  c1 = l1 > 0 ? (l1 << 1) : (((0 - l1) << 1) + 1) ## i64
  c2 = l2 > 0 ? (l2 << 1) : (((0 - l2) << 1) + 1) ## i64
  wassat_struct_has_imp_flat(bst, bad, dyn_head, dyn_to, dyn_next, c1, c2 ^ 1)

-> wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, a, b) (i64 i8[] i32[] i64[] i32[] i32[] i32[] i32[] i32[] i64[] i64 i64 i64) i64
  return 0 if a == b || a == 0 - b
  va = a < 0 ? 0 - a : a ## i64
  vb = b < 0 ? 0 - b : b ## i64
  return 0 if va < 1 || va > nv || vb < 1 || vb > nv
  vala = val[va] ## i64
  valb = val[vb] ## i64
  vva = a > 0 ? vala : 0 - vala ## i64
  vvb = b > 0 ? valb : 0 - valb ## i64
  return 0 if vva > 0 || vvb > 0
  return 0 - 1 if vva < 0 && vvb < 0
  return wassat_struct_enqueue_unit_flat(nv, val, q, st, b) if vva < 0
  return wassat_struct_enqueue_unit_flat(nv, val, q, st, a) if vvb < 0
  return 0 if st[3] >= 32768
  x = a < b ? a : b ## i64
  y = a < b ? b : a ## i64
  return 0 if wassat_struct_bin_dedup(seen_bin_ht, hmask, x, y) == 0
  bi = st[3]
  bin_out_a[bi] = x
  bin_out_b[bi] = y
  st[3] = bi + 1
  cx = x > 0 ? (x << 1) : (((0 - x) << 1) + 1) ## i64
  cy = y > 0 ? (y << 1) : (((0 - y) << 1) + 1) ## i64
  nx = cx ^ 1 ## i64
  ny = cy ^ 1 ## i64
  ec = st[2]
  if ec + 2 <= dyn_to.size
    dyn_to[ec] = cy
    dyn_next[ec] = dyn_head[nx]
    dyn_head[nx] = ec + 1
    dyn_to[ec + 1] = cx
    dyn_next[ec + 1] = dyn_head[ny]
    dyn_head[ny] = ec + 2
    st[2] = ec + 2
  1

# Insert an EO clique candidate active_scratch[0..n_act-1] into flat EO storage
# if its literal sequence has not been seen yet.
-> wassat_struct_eo_insert(eo_ht, eo_lits, eo_len, active_scratch, n_act, st) (i32[] i32[] i32[] i64[] i64 i64[]) i64
  neo = st[5]
  return 0 if neo >= 4096
  h = n_act ## i64
  i = 0
  while i < n_act
    h = ((h * 1000003) + active_scratch[i]) & 16383 ## i64
    i += 1
  while eo_ht[h] != 0
    gid = eo_ht[h] - 1 ## i64
    if eo_len[gid] == n_act
      same = 1
      gbase = gid * 8 ## i64
      j = 0
      while j < n_act && same == 1
        same = 0 if eo_lits[gbase + j] != active_scratch[j]
        j += 1
      return 0 if same == 1
    h = (h + 1) & 16383 ## i64
  eo_ht[h] = neo + 1
  eo_len[neo] = n_act
  gbase = neo * 8 ## i64
  j = 0
  while j < n_act
    eo_lits[gbase + j] = active_scratch[j]
    j += 1
  st[5] = neo + 1
  1

# Census pass for CSR binary adjacency, CSR ternary occurrences, and positive domains.
-> wassat_struct_card_census(nv, fla, fcs, fcl, ncl, bst, in_st, tst, counts) (i64 i64[] i64[] i64[] i64 i32[] i32[] i32[] i64[])
  nbin = 0
  ntern = 0
  npos = 0
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    off = fcs[ci]
    if clen == 2
      a = fla[off]
      b = fla[off + 1]
      va = a < 0 ? 0 - a : a ## i64
      vb = b < 0 ? 0 - b : b ## i64
      if a != b && a != 0 - b && va >= 1 && va <= nv && vb >= 1 && vb <= nv
        ca = a > 0 ? (a << 1) : (((0 - a) << 1) + 1) ## i64
        cb = b > 0 ? (b << 1) : (((0 - b) << 1) + 1) ## i64
        na = ca ^ 1 ## i64
        nb = cb ^ 1 ## i64
        bst[na + 1] += 1
        in_st[cb + 1] += 1
        bst[nb + 1] += 1
        in_st[ca + 1] += 1
        nbin += 1
        npos += 1 if a > 0 && b > 0
    elsif clen == 3
      ntern += 1
      l0 = fla[off]
      l1 = fla[off + 1]
      l2 = fla[off + 2]
      v0 = l0 < 0 ? 0 - l0 : l0 ## i64
      v1 = l1 < 0 ? 0 - l1 : l1 ## i64
      v2 = l2 < 0 ? 0 - l2 : l2 ## i64
      if v0 >= 1 && v0 <= nv
        c0 = l0 > 0 ? (l0 << 1) : (((0 - l0) << 1) + 1) ## i64
        tst[c0 + 1] += 1
      if v1 >= 1 && v1 <= nv
        c1 = l1 > 0 ? (l1 << 1) : (((0 - l1) << 1) + 1) ## i64
        tst[c1 + 1] += 1
      if v2 >= 1 && v2 <= nv
        c2 = l2 > 0 ? (l2 << 1) : (((0 - l2) << 1) + 1) ## i64
        tst[c2 + 1] += 1
      npos += 1 if l0 > 0 && l1 > 0 && l2 > 0
    elsif clen >= 4 && clen <= 8
      all_pos = 1
      j = 0
      while j < clen
        all_pos = 0 if fla[off + j] <= 0
        j += 1
      npos += 1 if all_pos == 1
    ci += 1
  counts[0] = nbin
  counts[1] = ntern
  counts[2] = npos

# Build sorted CSR binary implication graph (bst, bad), ternary CSR (tern_lits, tst, toc),
# positive-domain clause index list (pos_dom_cids), and enqueue initial unit clauses.
-> wassat_struct_card_build_csr(nv, nl, fla, fcs, fcl, ncl, val, q, st, bst, in_st, bun, bad, fill, tern_lits, tst, toc, pos_dom_cids) (i64 i64 i64[] i64[] i64[] i64 i8[] i32[] i64[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[]) i64
  c = 0
  while c <= nl
    bst[c + 1] += bst[c]
    in_st[c + 1] += in_st[c]
    tst[c + 1] += tst[c]
    c += 1

  tfill = i32[nl + 4]
  ti = 0
  pi = 0
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    off = fcs[ci]
    if clen == 1
      if wassat_struct_enqueue_unit_flat(nv, val, q, st, fla[off]) < 0
        return 0 - 1
    elsif clen == 2
      a = fla[off]
      b = fla[off + 1]
      va = a < 0 ? 0 - a : a ## i64
      vb = b < 0 ? 0 - b : b ## i64
      if a != b && a != 0 - b && va >= 1 && va <= nv && vb >= 1 && vb <= nv
        ca = a > 0 ? (a << 1) : (((0 - a) << 1) + 1) ## i64
        cb = b > 0 ? (b << 1) : (((0 - b) << 1) + 1) ## i64
        na = ca ^ 1 ## i64
        nb = cb ^ 1 ## i64
        # Bucket directed edges (na -> cb) and (nb -> ca) by destination first
        # so the second pass emits outgoing adjacency lists sorted by target code.
        bun[in_st[cb] + fill[cb]] = na
        fill[cb] += 1
        bun[in_st[ca] + fill[ca]] = nb
        fill[ca] += 1
        if a > 0 && b > 0
          pos_dom_cids[pi] = ci
          pi += 1
    elsif clen == 3
      l0 = fla[off]
      l1 = fla[off + 1]
      l2 = fla[off + 2]
      tbase = ti * 3 ## i64
      tern_lits[tbase] = l0
      tern_lits[tbase + 1] = l1
      tern_lits[tbase + 2] = l2
      v0 = l0 < 0 ? 0 - l0 : l0 ## i64
      v1 = l1 < 0 ? 0 - l1 : l1 ## i64
      v2 = l2 < 0 ? 0 - l2 : l2 ## i64
      if v0 >= 1 && v0 <= nv
        c0 = l0 > 0 ? (l0 << 1) : (((0 - l0) << 1) + 1) ## i64
        toc[tst[c0] + tfill[c0]] = ti
        tfill[c0] += 1
      if v1 >= 1 && v1 <= nv
        c1 = l1 > 0 ? (l1 << 1) : (((0 - l1) << 1) + 1) ## i64
        toc[tst[c1] + tfill[c1]] = ti
        tfill[c1] += 1
      if v2 >= 1 && v2 <= nv
        c2 = l2 > 0 ? (l2 << 1) : (((0 - l2) << 1) + 1) ## i64
        toc[tst[c2] + tfill[c2]] = ti
        tfill[c2] += 1
      if l0 > 0 && l1 > 0 && l2 > 0
        pos_dom_cids[pi] = ci
        pi += 1
      ti += 1
    elsif clen >= 4 && clen <= 8
      all_pos = 1
      j = 0
      while j < clen
        all_pos = 0 if fla[off + j] <= 0
        j += 1
      if all_pos == 1
        pos_dom_cids[pi] = ci
        pi += 1
    ci += 1

  c = 0
  while c <= nl
    fill[c] = 0
    c += 1
  dest = 0
  while dest < nl
    p = in_st[dest] ## i64
    pe = in_st[dest + 1] ## i64
    while p < pe
      src = bun[p] ## i64
      bad[bst[src] + fill[src]] = dest
      fill[src] += 1
      p += 1
    dest += 1
  1

# Core native pipeline for Pass 2: EO domain extraction, constructive dilemma,
# sequential-counter chains, 64-bit monotone ladder cuts, and clause strengthening.
-> wassat_struct_card_run_native(nv, nl, fla, fcs, fcl, ncl, val, q, st, bst, bad, dyn_head, dyn_to, dyn_next, tern_lits, ntern, tst, toc, pos_dom_cids, npos, bin_out_a, bin_out_b, seen_bin_ht, eo_lits, eo_len, eo_order, ch3_a, ch3_b, ch3_g, lch_lits, lch_offs, var_chain, var_pos, prof_stats) (i64 i64 i64[] i64[] i64[] i64 i8[] i32[] i64[] i32[] i32[] i32[] i32[] i32[] i32[] i64 i32[] i32[] i32[] i64 i32[] i32[] i64[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i64[] i64[] i64[]) i64
  if wassat_struct_propagate_units_flat(nv, val, q, st, bst, bad, dyn_head, dyn_to, dyn_next, tern_lits, tst, toc) < 0
    return 0 - 1

  eo_ht = i32[16384]
  guard_len = i8[nv + 1]
  guard_lits = i32[4 * (nv + 1)]
  pos_occ = i64[nv + 1]
  neg_occ = i64[nv + 1]
  pos_scratch = i64[6]
  guard_scanned = 0
  guard_saved = 0
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    if clen >= 2 && clen <= 6
      off = fcs[ci]
      sat = 0
      neg_cnt = 0
      neg_v = 0 ## i64
      pos_count = 0
      guard_scanned += 1
      j = 0
      while j < clen
        l = fla[off + j]
        lv = l < 0 ? 0 - l : l ## i64
        if lv >= 1 && lv <= nv
          valv = val[lv] ## i64
          vv = l > 0 ? valv : 0 - valv ## i64
          if vv > 0
            sat = 1
          elsif vv == 0
            if l > 0
              pos_occ[lv] += 1
              pos_scratch[pos_count] = l if pos_count < 6
              pos_count += 1
            else
              neg_occ[lv] += 1
              neg_cnt += 1
              neg_v = lv
        j += 1
      if sat == 0 && neg_cnt == 1 && pos_count >= 2 && pos_count <= 4
        guard_len[neg_v] = pos_count
        gbase = neg_v * 4 ## i64
        j = 0
        while j < pos_count
          guard_lits[gbase + j] = pos_scratch[j]
          j += 1
        guard_saved += 1
    ci += 1
  prof_stats[0] = guard_scanned
  prof_stats[1] = guard_saved

  active_scratch = i64[8]
  di = 0
  while di < npos && st[5] < 4096
    dci = pos_dom_cids[di] ## i64
    off = fcs[dci]
    clen = fcl[dci]
    n_act = 0
    sat = 0
    j = 0
    while j < clen
      l = fla[off + j]
      v = l < 0 ? 0 - l : l ## i64
      if v >= 1 && v <= nv
        valv = val[v] ## i64
        vv = l > 0 ? valv : 0 - valv ## i64
        if vv > 0
          sat = 1
        elsif vv == 0
          active_scratch[n_act] = l if n_act < 8
          n_act += 1
      j += 1
    if sat == 0 && n_act == 1
      if wassat_struct_enqueue_unit_flat(nv, val, q, st, active_scratch[0]) < 0
        return 0 - 1
      if wassat_struct_propagate_units_flat(nv, val, q, st, bst, bad, dyn_head, dyn_to, dyn_next, tern_lits, tst, toc) < 0
        return 0 - 1
    elsif sat == 0 && n_act >= 2 && n_act <= 8
      is_clique = 1
      a = 0
      while a < n_act && is_clique == 1
        b = a + 1
        while b < n_act && is_clique == 1
          if wassat_struct_has_mutex_flat(bst, bad, dyn_head, dyn_to, dyn_next, active_scratch[a], active_scratch[b]) == 0
            is_clique = 0
          b += 1
        a += 1
      if is_clique == 1
        z = wassat_struct_eo_insert(eo_ht, eo_lits, eo_len, active_scratch, n_act, st)
    di += 1

  # EO-guarded domain resolution: if a 2-element EO pair (p0, p1) guards the
  # same positive tail (-p0 v t0..tk) and (-p1 v t0..tk), then (t0..tk) is an
  # implied positive domain.
  orig_eo_n = st[5]
  gi = 0
  while gi < orig_eo_n && st[5] < 4096
    if eo_len[gi] == 2
      p0 = eo_lits[gi * 8] ## i64
      p1 = eo_lits[gi * 8 + 1] ## i64
      if p0 > 0 && p1 > 0 && p0 <= nv && p1 <= nv
        gl0 = guard_len[p0] ## i64
        gl1 = guard_len[p1] ## i64
        if gl0 >= 2 && gl0 == gl1
          gb0 = p0 * 4 ## i64
          gb1 = p1 * 4 ## i64
          same = 1
          j = 0
          while j < gl0
            tlit = guard_lits[gb0 + j] ## i64
            same = 0 if tlit != guard_lits[gb1 + j]
            active_scratch[j] = tlit
            j += 1
          if same == 1
            is_clique = 1
            a = 0
            while a < gl0 && is_clique == 1
              b = a + 1
              while b < gl0 && is_clique == 1
                if wassat_struct_has_mutex_flat(bst, bad, dyn_head, dyn_to, dyn_next, active_scratch[a], active_scratch[b]) == 0
                  is_clique = 0
                b += 1
              a += 1
            if is_clique == 1
              z = wassat_struct_eo_insert(eo_ht, eo_lits, eo_len, active_scratch, gl0, st)
    gi += 1

  neo = st[5]
  eo_scores = i64[neo + 1]
  gi = 0
  while gi < neo
    eo_order[gi] = gi
    glen = eo_len[gi] ## i64
    gbase = gi * 8 ## i64
    is_sel = 1
    neg_sum = 0 ## i64
    pos_sum = 0 ## i64
    j = 0
    while j < glen
      glit = eo_lits[gbase + j] ## i64
      lv = glit < 0 ? 0 - glit : glit ## i64
      p = pos_occ[lv]
      n = neg_occ[lv]
      pos_sum += p
      neg_sum += n
      is_sel = 0 unless p >= 1 && p <= 8 && n >= 2 * p && n >= 8
      j += 1
    sc = neg_sum + pos_sum ## i64
    if is_sel == 1
      sc = sc + 10000000 + neg_sum * 100 + (8 - glen) * 10 ## i64
    eo_scores[gi] = sc
    gi += 1

  a = 1
  while a < neo
    cur_id = eo_order[a] ## i64
    cur_s = eo_scores[cur_id]
    b = a - 1
    while b >= 0 && eo_scores[eo_order[b]] < cur_s
      eo_order[b + 1] = eo_order[b]
      b -= 1
    eo_order[b + 1] = cur_id
    a += 1

  hmask = 131071 ## i64
  imp_count = i64[nl]
  imp_mask = i64[nl]
  touched = i32[nl + 2]
  gi = 0
  while gi < neo
    gid = eo_order[gi] ## i64
    k = eo_len[gid] ## i64
    gbase = gid * 8 ## i64
    ntouched = 0
    m = 0
    while m < k
      lm = eo_lits[gbase + m] ## i64
      bit = 1 << m ## i64
      lm_c = lm > 0 ? (lm << 1) : (((0 - lm) << 1) + 1) ## i64
      # Traverse both static CSR and dynamic edges for lm_c.
      pass = 0
      while pass < 2
        p = pass == 0 ? bst[lm_c] : dyn_head[lm_c] ## i64
        pe = pass == 0 ? bst[lm_c + 1] : 0 ## i64
        while (pass == 0 && p < pe) || (pass == 1 && p != 0)
          uc = pass == 0 ? bad[p] : dyn_to[p - 1] ## i64
          u = (uc & 1) == 0 ? (uc >> 1) : (0 - (uc >> 1)) ## i64
          in_grp = 0
          g2 = 0
          while g2 < k
            gl = eo_lits[gbase + g2] ## i64
            in_grp = 1 if gl == 0 - u || gl == u
            g2 += 1
          if in_grp == 0
            old = imp_mask[uc]
            if old == 0
              touched[ntouched] = u
              ntouched += 1
            if (old & bit) == 0
              imp_mask[uc] = old | bit ## i64
              imp_count[uc] = imp_count[uc] + 1
            j2 = 0
            p2 = bst[uc] ## i64
            pe2 = bst[uc + 1] ## i64
            while p2 < pe2 && j2 < 16
              wc = bad[p2] ## i64
              w = (wc & 1) == 0 ? (wc >> 1) : (0 - (wc >> 1)) ## i64
              oldw = imp_mask[wc]
              if oldw == 0
                touched[ntouched] = w
                ntouched += 1
              if (oldw & bit) == 0
                imp_mask[wc] = oldw | bit ## i64
                imp_count[wc] = imp_count[wc] + 1
              p2 += 1
              j2 += 1
            e2 = dyn_head[uc] ## i64
            while e2 != 0 && j2 < 16
              wc = dyn_to[e2 - 1] ## i64
              w = (wc & 1) == 0 ? (wc >> 1) : (0 - (wc >> 1)) ## i64
              oldw = imp_mask[wc]
              if oldw == 0
                touched[ntouched] = w
                ntouched += 1
              if (oldw & bit) == 0
                imp_mask[wc] = oldw | bit ## i64
                imp_count[wc] = imp_count[wc] + 1
              e2 = dyn_next[e2 - 1] ## i64
              j2 += 1
          if pass == 0
            p += 1
          else
            p = dyn_next[p - 1] ## i64
        pass += 1
      m += 1

    full_mask = (1 << k) - 1 ## i64
    ki = 0
    while ki < ntouched
      u = touched[ki] ## i64
      uc = u > 0 ? (u << 1) : (((0 - u) << 1) + 1) ## i64
      cnt = imp_count[uc]
      msk = imp_mask[uc]
      imp_count[uc] = 0
      imp_mask[uc] = 0
      if cnt == k
        if wassat_struct_enqueue_unit_flat(nv, val, q, st, u) < 0
          return 0 - 1
      elsif cnt == k - 1 && k >= 3
        miss_mask = full_mask ^ msk ## i64
        rem_idx = 0
        while rem_idx < k && ((miss_mask >> rem_idx) & 1) == 0
          rem_idx += 1
        if rem_idx < k
          rem_lit = eo_lits[gbase + rem_idx] ## i64
          if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, rem_lit, u) < 0
            return 0 - 1
      ki += 1
    gi += 1

  if wassat_struct_propagate_units_flat(nv, val, q, st, bst, bad, dyn_head, dyn_to, dyn_next, tern_lits, tst, toc) < 0
    return 0 - 1

  ti = 0
  while ti < ntern
    tbase = ti * 3 ## i64
    p = 0
    while p < 3
      l_neg_a = tern_lits[tbase + p] ## i64
      l_b = tern_lits[tbase + ((p + 1) % 3)] ## i64
      l_g = tern_lits[tbase + ((p + 2) % 3)] ## i64
      a = 0 - l_neg_a ## i64
      b = l_b
      if a > 0 && b > 0 && wassat_struct_has_mutex_flat(bst, bad, dyn_head, dyn_to, dyn_next, 0 - a, b) == 1
        gv = l_g < 0 ? 0 - l_g : l_g ## i64
        gval = gv >= 1 && gv <= nv ? val[gv] : 0 ## i64
        vg = l_g > 0 ? gval : 0 - gval ## i64
        if vg < 0
          if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, 0 - a, b) < 0
            return 0 - 1
        if st[4] < 2048
          ci3 = st[4]
          ch3_a[ci3] = a
          ch3_b[ci3] = b
          ch3_g[ci3] = l_g
          st[4] = ci3 + 1
      p += 1
    ti += 1

  # Multi-step monotone ladder-chain extraction & 64-bit cut-mask projection.
  next_in_chain = i64[nv + 1]
  prev_in_chain = i64[nv + 1]
  has_out_edge = i8[nv + 1]
  ci = 0
  while ci < ncl
    if fcl[ci] == 2
      off = fcs[ci]
      a = fla[off]
      b = fla[off + 1]
      va = a < 0 ? 0 - a : a ## i64
      vb = b < 0 ? 0 - b : b ## i64
      if va >= 1 && va <= nv && vb >= 1 && vb <= nv && val[va] == 0 && val[vb] == 0
        if a > 0 && b < 0
          has_out_edge[a] = 1
        elsif b > 0 && a < 0
          has_out_edge[b] = 1
    ci += 1

  ci = 0
  while ci < ncl
    if fcl[ci] == 2
      off = fcs[ci]
      a = fla[off]
      b = fla[off + 1]
      va = a < 0 ? 0 - a : a ## i64
      vb = b < 0 ? 0 - b : b ## i64
      if va >= 1 && va <= nv && vb >= 1 && vb <= nv && val[va] == 0 && val[vb] == 0
        u = 0 ## i64
        w = 0 ## i64
        if a > 0 && b < 0
          u = a
          w = 0 - b ## i64
        elsif b > 0 && a < 0
          u = b
          w = 0 - a ## i64
        if u > 0 && w > 0
          cur_w = next_in_chain[u]
          if cur_w == 0 || (has_out_edge[cur_w] == 0 && has_out_edge[w] == 1)
            prev_in_chain[cur_w] = 0 if cur_w > 0 && prev_in_chain[cur_w] == u
            next_in_chain[u] = w
            prev_in_chain[w] = u if prev_in_chain[w] == 0
    ci += 1

  visited_ch = i8[nv + 1]
  ch_scratch = i32[60]
  nch = 0
  lch_at = 0
  lch_offs[0] = 0
  v = 1
  while v <= nv && nch < 2048
    if next_in_chain[v] > 0 && prev_in_chain[v] == 0 && visited_ch[v] == 0
      ch_scratch[0] = v
      ch_len = 1
      visited_ch[v] = 1
      cur = v
      while next_in_chain[cur] > 0 && visited_ch[next_in_chain[cur]] == 0 && ch_len < 60
        cur = next_in_chain[cur]
        visited_ch[cur] = 1
        ch_scratch[ch_len] = cur
        ch_len += 1
      if ch_len >= 3
        idx = 0
        while idx < ch_len
          cv = ch_scratch[idx] ## i64
          lch_lits[lch_at] = cv
          lch_at += 1
          var_chain[cv] = nch + 1
          var_pos[cv] = idx
          idx += 1
        nch += 1
        lch_offs[nch] = lch_at
    v += 1
  st[6] = nch

  if nch > 0
    all64 = 0 - 1 ## i64
    chain_allowed = i64[nch]
    chain_ext_cnt = i32[nch]
    chain_ext_lits = i32[nch * 64]
    chain_ext_masks = i64[nch * 64]
    cid = 0
    while cid < nch
      l_len = lch_offs[cid + 1] - lch_offs[cid] ## i64
      chain_allowed[cid] = (1 << (l_len + 1)) - 1 ## i64
      cid += 1

    cl_ch_lits = i64[5]
    ci = 0
    while ci < ncl
      clen = fcl[ci]
      if clen >= 2 && clen <= 5
        off = fcs[ci]
        sat = 0
        n_chl = 0
        ext_lit = 0 ## i64
        ext_cnt = 0
        target_cid = 0 - 1
        multi_cid = 0
        j = 0
        while j < clen && sat == 0 && multi_cid == 0 && ext_cnt <= 1
          l = fla[off + j]
          lv = l < 0 ? 0 - l : l ## i64
          if lv >= 1 && lv <= nv
            valv = val[lv] ## i64
            vv = l > 0 ? valv : 0 - valv ## i64
            if vv > 0
              sat = 1
            elsif vv == 0
              vc = var_chain[lv] - 1
              if vc >= 0
                if target_cid < 0
                  target_cid = vc
                elsif target_cid != vc
                  multi_cid = 1
                cl_ch_lits[n_chl] = l
                n_chl += 1
              else
                ext_lit = l
                ext_cnt += 1
          j += 1
        if sat == 0 && multi_cid == 0 && target_cid >= 0 && n_chl > 0 && ext_cnt <= 1
          l_len = lch_offs[target_cid + 1] - lch_offs[target_cid] ## i64
          all_cuts = (1 << (l_len + 1)) - 1 ## i64
          bad_cuts = all_cuts
          k = 0
          while k < n_chl && bad_cuts != 0
            cl = cl_ch_lits[k]
            clv = cl < 0 ? 0 - cl : cl ## i64
            r = var_pos[clv]
            le_r = (1 << (r + 1)) - 1 ## i64
            if cl > 0
              bad_cuts = bad_cuts & le_r ## i64
            else
              bad_cuts = bad_cuts & (all_cuts ^ le_r) ## i64
            k += 1
          if bad_cuts != 0
            if ext_cnt == 0
              chain_allowed[target_cid] = chain_allowed[target_cid] & (all64 ^ bad_cuts) ## i64
            else
              u = 0 - ext_lit ## i64
              ebase = target_cid * 64 ## i64
              ecnt = chain_ext_cnt[target_cid] ## i64
              found_idx = 0 - 1
              k = 0
              while k < ecnt
                if chain_ext_lits[ebase + k] == u
                  found_idx = k
                  k = ecnt
                else
                  k += 1
              if found_idx >= 0
                chain_ext_masks[ebase + found_idx] = chain_ext_masks[ebase + found_idx] | bad_cuts ## i64
              elsif ecnt < 64
                chain_ext_lits[ebase + ecnt] = u
                chain_ext_masks[ebase + ecnt] = bad_cuts
                chain_ext_cnt[target_cid] = ecnt + 1
      ci += 1

    cid = 0
    while cid < nch
      c_off = lch_offs[cid] ## i64
      l_len = lch_offs[cid + 1] - c_off ## i64
      allow = chain_allowed[cid]
      return 0 - 1 if allow == 0
      cut = 0
      while cut <= l_len
        if ((allow >> cut) & 1) == 0
          if cut == 0
            first_v = lch_lits[c_off] ## i64
            if wassat_struct_enqueue_unit_flat(nv, val, q, st, first_v) < 0
              return 0 - 1
          elsif cut == l_len
            last_v = lch_lits[c_off + l_len - 1] ## i64
            if wassat_struct_enqueue_unit_flat(nv, val, q, st, 0 - last_v) < 0
              return 0 - 1
          elsif st[3] < 16384
            prev_v = lch_lits[c_off + cut - 1] ## i64
            cur_v = lch_lits[c_off + cut] ## i64
            if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, 0 - prev_v, cur_v) < 0
              return 0 - 1
        cut += 1
      ebase = cid * 64 ## i64
      ecnt = chain_ext_cnt[cid] ## i64
      ch_head = lch_lits[c_off] ## i64
      ch_tail = lch_lits[c_off + l_len - 1] ## i64
      i1 = 0
      while i1 < ecnt
        u1 = chain_ext_lits[ebase + i1] ## i64
        m1 = chain_ext_masks[ebase + i1]
        rem1 = allow & (all64 ^ m1) ## i64
        if rem1 == 0
          if wassat_struct_enqueue_unit_flat(nv, val, q, st, 0 - u1) < 0
            return 0 - 1
        elsif st[3] < 16384
          if (rem1 & 1) == 0
            if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, 0 - u1, ch_head) < 0
              return 0 - 1
          if ((rem1 >> l_len) & 1) == 0
            if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, 0 - u1, 0 - ch_tail) < 0
              return 0 - 1
          u1_abs = u1 < 0 ? 0 - u1 : u1 ## i64
          i2 = i1 + 1
          while i2 < ecnt && st[3] < 16384
            u2 = chain_ext_lits[ebase + i2] ## i64
            u2_abs = u2 < 0 ? 0 - u2 : u2 ## i64
            m2 = chain_ext_masks[ebase + i2]
            if (rem1 & (all64 ^ m2)) == 0 && u1_abs != u2_abs
              if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, 0 - u1, 0 - u2) < 0
                return 0 - 1
            i2 += 1
        i1 += 1
      # Direct flat shortcut binaries along the monotone chain.
      if l_len >= 4 && st[3] < 16384
        if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, ch_head, 0 - ch_tail) < 0
          return 0 - 1
        if l_len >= 8 && st[3] < 16384
          mid_v = lch_lits[c_off + (l_len / 2)] ## i64
          if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, ch_head, 0 - mid_v) < 0
            return 0 - 1
          if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, mid_v, 0 - ch_tail) < 0
            return 0 - 1
      cid += 1

  # Clause strengthening where one literal implies another via monotone chain or binary graph.
  rem = i64[5]
  kept = i64[4]
  dropped = i8[4]
  strength_scanned = 0
  strength_trials = 0
  strength_inactive = 0
  ci = 0
  while ci < ncl && st[3] < 16384
    clen = fcl[ci]
    if clen >= 3 && clen <= 5
      off = fcs[ci]
      sat = 0
      rem_count = 0
      strength_scanned += 1
      j = 0
      while j < clen && sat == 0
        l = fla[off + j]
        lv = l < 0 ? 0 - l : l ## i64
        if lv >= 1 && lv <= nv
          valv = val[lv] ## i64
          vv = l > 0 ? valv : 0 - valv ## i64
          if vv > 0
            sat = 1
          elsif vv == 0
            rem[rem_count] = l
            rem_count += 1
        j += 1
      if sat == 0 && rem_count >= 2 && rem_count <= 4
        kept_count = 0
        strength_trials += 1
        j = 0
        while j < rem_count
          dropped[j] = 0
          j += 1
        subsumed = 0
        i1 = 0
        while i1 < rem_count && subsumed == 0
          a = rem[i1]
          va = a < 0 ? 0 - a : a ## i64
          ca = var_chain[va]
          pa = var_pos[va]
          a_idx = a > 0 ? (a << 1) : (((0 - a) << 1) + 1) ## i64
          drop_a = 0
          if ca > 0 || bst[a_idx + 1] > bst[a_idx] || dyn_head[a_idx] != 0
            i2 = 0
            while i2 < rem_count && drop_a == 0 && subsumed == 0
              if i1 != i2 && dropped[i2] == 0
                b = rem[i2]
                vb = b < 0 ? 0 - b : b ## i64
                cb = var_chain[vb]
                pb = var_pos[vb]
                if ca > 0 && ca == cb
                  if (a > 0 && b > 0 && pa > pb) || (a < 0 && b < 0 && pa < pb)
                    drop_a = 1
                  elsif (a > 0 && b < 0 && pa <= pb) || (a < 0 && b > 0 && pa >= pb)
                    subsumed = 1
                if drop_a == 0 && subsumed == 0
                  b_idx = b > 0 ? (b << 1) : (((0 - b) << 1) + 1) ## i64
                  if wassat_struct_has_imp_flat(bst, bad, dyn_head, dyn_to, dyn_next, a_idx, b_idx) == 1
                    drop_a = 1
              i2 += 1
          else
            strength_inactive += 1
          if drop_a == 1
            dropped[i1] = 1
          else
            kept[kept_count] = a
            kept_count += 1
          i1 += 1
        if subsumed == 0 && kept_count < rem_count
          if kept_count == 1
            if wassat_struct_enqueue_unit_flat(nv, val, q, st, kept[0]) < 0
              return 0 - 1
          elsif kept_count == 2 && st[3] < 16384
            if wassat_struct_add_binary_flat(nv, val, q, st, bin_out_a, bin_out_b, dyn_head, dyn_to, dyn_next, seen_bin_ht, hmask, kept[0], kept[1]) < 0
              return 0 - 1
    ci += 1
  prof_stats[2] = strength_scanned
  prof_stats[3] = strength_trials
  prof_stats[4] = strength_inactive

  if wassat_struct_propagate_units_flat(nv, val, q, st, bst, bad, dyn_head, dyn_to, dyn_next, tern_lits, tst, toc) < 0
    return 0 - 1
  1

-> wassat_struct_card_export(unsat, q, st, bin_out_a, bin_out_b, eo_lits, eo_len, eo_order, ch3_a, ch3_b, ch3_g, val, lch_lits, lch_offs, var_chain, var_pos)
  units = []
  i = 0
  nu = st[1]
  while i < nu
    units.push(q[i])
    i += 1
  binaries = []
  i = 0
  nb = st[3]
  while i < nb
    binaries.push([bin_out_a[i], bin_out_b[i]])
    i += 1
  eo_groups = []
  neo = st[5]
  i = 0
  while i < neo
    gid = eo_order[0] == 0 && neo > 1 && eo_order[1] == 0 ? i : eo_order[i]
    glen = eo_len[gid]
    gbase = gid * 8
    grp = []
    j = 0
    while j < glen
      grp.push(eo_lits[gbase + j])
      j += 1
    eo_groups.push(grp)
    i += 1
  chains = []
  nc3 = st[4]
  i = 0
  while i < nc3
    chains.push([ch3_a[i], ch3_b[i], ch3_g[i]])
    i += 1
  if unsat
    return {
      "unsat": true, "units": units, "binaries": binaries,
      "eo_groups": eo_groups, "chains": chains
    }
  ladder_chains = []
  nch = st[6]
  cid = 0
  while cid < nch
    c_off = lch_offs[cid]
    c_end = lch_offs[cid + 1]
    ch = []
    p = c_off
    while p < c_end
      ch.push(lch_lits[p])
      p += 1
    ladder_chains.push(ch)
    cid += 1
  {
    "unsat": false, "units": units, "binaries": binaries,
    "eo_groups": eo_groups, "chains": chains, "val": val,
    "ladder_chains": ladder_chains, "var_chain": var_chain, "var_pos": var_pos
  }

-> wassat_extract_cardinality_and_propagate(nv, formula)
  if nv <= 0
    return {
      "unsat": false, "units": [], "binaries": [],
      "eo_groups": [], "chains": [], "val": i8[1],
      "ladder_chains": [], "var_chain": i64[1], "var_pos": i64[1]
    }
  view = wassat_struct_flat_view(formula)
  fla = view["flat_lits"] ## i64[]
  fcs = view["flat_offs"] ## i64[]
  fcl = view["flat_lens"] ## i64[]
  ncl = view["flat_ncl"] ## i64

  nl = 2 * nv + 2
  val = i8[nv + 1]
  q = i32[nv + 4]
  # st: [0]=q_head, [1]=q_tail, [2]=dyn_edge_cnt, [3]=bin_cnt, [4]=ch3_cnt, [5]=eo_cnt, [6]=lch_cnt
  st = i64[8]

  bst = i32[nl + 4]
  in_st = i32[nl + 4]
  tst = i32[nl + 4]
  counts = i64[4]
  wassat_struct_card_census(nv, fla, fcs, fcl, ncl, bst, in_st, tst, counts)
  nbin = counts[0]
  ntern = counts[1]
  npos = counts[2]

  bun = i32[2 * nbin + 2]
  bad = i32[2 * nbin + 2]
  fill = i32[nl + 4]
  tern_lits = i32[3 * ntern + 3]
  toc = i32[3 * ntern + 3]
  pos_dom_cids = i32[npos + 2]

  bin_out_a = i32[32768]
  bin_out_b = i32[32768]
  eo_lits = i32[4096 * 8]
  eo_len = i32[4096]
  eo_order = i32[4096]
  ch3_a = i32[2048]
  ch3_b = i32[2048]
  ch3_g = i32[2048]
  lch_lits = i32[2048 * 60]
  lch_offs = i32[2049]
  var_chain = i64[nv + 1]
  var_pos = i64[nv + 1]

  if wassat_struct_card_build_csr(nv, nl, fla, fcs, fcl, ncl, val, q, st, bst, in_st, bun, bad, fill, tern_lits, tst, toc, pos_dom_cids) < 0
    return wassat_struct_card_export(true, q, st, bin_out_a, bin_out_b, eo_lits, eo_len, eo_order, ch3_a, ch3_b, ch3_g, val, lch_lits, lch_offs, var_chain, var_pos)

  dyn_head = i32[nl + 4]
  dyn_to = i32[65536]
  dyn_next = i32[65536]
  seen_bin_ht = i64[131072]
  prof_stats = i64[6]

  rc = wassat_struct_card_run_native(
    nv, nl, fla, fcs, fcl, ncl, val, q, st, bst, bad,
    dyn_head, dyn_to, dyn_next, tern_lits, ntern, tst, toc,
    pos_dom_cids, npos, bin_out_a, bin_out_b, seen_bin_ht,
    eo_lits, eo_len, eo_order, ch3_a, ch3_b, ch3_g,
    lch_lits, lch_offs, var_chain, var_pos, prof_stats
  )
  if env("WASSAT_PROFILE") == "1"
    wassat_prof_note("struct.cardinality.guards scanned=[prof_stats[0]] retained=[prof_stats[1]] scratch_slots=6")
    wassat_prof_note("struct.cardinality.strengthen scanned=[prof_stats[2]] candidates=[prof_stats[3]] inactive_literals=[prof_stats[4]] scratch_slots=13")

  wassat_struct_card_export(
    rc < 0, q, st, bin_out_a, bin_out_b, eo_lits, eo_len, eo_order,
    ch3_a, ch3_b, ch3_g, val, lch_lits, lch_offs, var_chain, var_pos
  )

# ---- 3. DETOUR Bidirectional Wavefront & Macro-Transition Pruning -----------

# Pack short-clause occurrences once for repeated chain-free trial probes.
-> wassat_struct_trial_pack(nv, clauses)
  nl = 0
  clauses.each -> (c) nl += c.size
  fla = i64[nl]
  offs = i64[clauses.size + 1]
  at = 0
  ci = 0
  clauses.each -> (c)
    offs[ci] = at
    c.each -> (l)
      fla[at] = l
      at += 1
    ci += 1
  offs[ci] = at
  occ_off = i64[2 * nv + 3]
  occ_ids = i64[nl]
  wassat_struct_occ_index(nv, fla, offs, occ_off, occ_ids, i64[2 * nv + 2])
  [fla, offs, occ_off, occ_ids, i64[3], i64[7]]

-> wassat_struct_occ_index(nv, fla, offs, occ_off, occ_ids, cursor) (i64 i64[] i64[] i64[] i64[] i64[])
  i = 0
  while i < fla.size
    l = fla[i]
    v = l < 0 ? 0 - l : l ## i64
    if v >= 1 && v <= nv
      li = l > 0 ? v << 1 : (v << 1) + 1 ## i64
      occ_off[li + 1] += 1
    i += 1
  i = 0
  while i < 2 * nv + 2
    occ_off[i + 1] += occ_off[i]
    cursor[i] = occ_off[i]
    i += 1
  ci = 0
  while ci + 1 < offs.size
    j = offs[ci]
    while j < offs[ci + 1]
      l = fla[j]
      v = l < 0 ? 0 - l : l ## i64
      if v >= 1 && v <= nv
        li = l > 0 ? v << 1 : (v << 1) + 1 ## i64
        occ_ids[cursor[li]] = ci
        cursor[li] += 1
      j += 1
    ci += 1

# state: last status/trail length; cumulative trials, occurrences, literal
# inspections, assignments and copied implications. Scratch is reused.
-> wassat_struct_trial_native(base, val, trail, fla, offs, occ_off, occ_ids, assumptions, na, state) (i8[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[])
  ts = 0
  ok = 1
  i = 0
  visits = 0
  inspections = 0
  while i < na && ok == 1
    l = assumptions[i]
    v = l < 0 ? 0 - l : l ## i64
    pol = l > 0 ? 1 : -1 ## i64
    cur = base[v] != 0 ? base[v] : val[v] ## i64
    if cur == 0 - pol
      ok = 0
    elsif cur == 0
      val[v] = pol
      trail[ts] = l
      ts += 1
    i += 1
  qh = 0
  while qh < ts && ok == 1 && ts < 2048
    l = trail[qh]
    qh += 1
    li = l > 0 ? (l << 1) + 1 : (0 - l) << 1 ## i64
    oi = occ_off[li]
    oe = occ_off[li + 1]
    while oi < oe && ok == 1 && ts < 2048
      ci = occ_ids[oi]
      visits += 1
      sat = 0
      unassigned = 0
      ul = 0 ## i64
      k = offs[ci]
      while k < offs[ci + 1]
        cl = fla[k]
        v = cl < 0 ? 0 - cl : cl ## i64
        cur = base[v] != 0 ? base[v] : val[v] ## i64
        vv = cl > 0 ? cur : 0 - cur ## i64
        if vv > 0
          sat = 1
        elsif vv == 0
          unassigned += 1
          ul = cl
        inspections += 1
        k += 1
      if sat == 0
        if unassigned == 0
          ok = 0
        elsif unassigned == 1
          v = ul < 0 ? 0 - ul : ul ## i64
          if ul > 0
            val[v] = 1
          else
            val[v] = -1
          trail[ts] = ul
          ts += 1
      oi += 1
  i = 0
  while i < ts
    l = trail[i]
    v = l < 0 ? 0 - l : l ## i64
    val[v] = 0
    i += 1
  state[0] = ok
  state[1] = ts
  state[2] += 1
  state[3] += visits
  state[4] += inspections
  state[5] += ts

# Unified native trial BCP with flat monotone ladder-chain jumps:
#   +x_r => (x_{r-1} .. x_0) and -x_r => (-x_{r+1} .. -x_{L-1})
-> wassat_struct_trial_ladder_native(base, val, trail, fla, offs, occ_off, occ_ids, chain_lits, chain_offs, lit_chain, lit_cpos, assumptions, na, state) (i8[] i8[] i64[] i64[] i64[] i64[] i64[] i32[] i32[] i32[] i32[] i64[] i64 i64[])
  ts = 0
  ok = 1
  i = 0
  visits = 0
  inspections = 0
  while i < na && ok == 1
    l = assumptions[i]
    v = l < 0 ? 0 - l : l ## i64
    pol = l > 0 ? 1 : -1 ## i64
    cur = base[v] != 0 ? base[v] : val[v] ## i64
    if cur == 0 - pol
      ok = 0
    elsif cur == 0
      val[v] = pol
      trail[ts] = l
      ts += 1
    i += 1
  qh = 0
  while qh < ts && ok == 1 && ts < 2048
    l = trail[qh]
    qh += 1
    lv = l < 0 ? 0 - l : l ## i64
    li_pos = l > 0 ? (lv << 1) : ((lv << 1) + 1) ## i64
    cid_plus = lit_chain[li_pos] ## i64
    if cid_plus > 0
      cid = cid_plus - 1
      c_start = chain_offs[cid] ## i64
      c_end = chain_offs[cid + 1] ## i64
      pos = lit_cpos[li_pos] ## i64
      if l > 0
        k = pos - 1
        while k >= 0 && ok == 1 && ts < 2048
          cv_var = chain_lits[c_start + k] ## i64
          cur_c = base[cv_var] != 0 ? base[cv_var] : val[cv_var] ## i64
          if cur_c == -1
            ok = 0
          elsif cur_c == 0
            val[cv_var] = 1
            trail[ts] = cv_var
            ts += 1
          else
            k = 0
          k -= 1
      else
        l_len = c_end - c_start
        k = pos + 1
        while k < l_len && ok == 1 && ts < 2048
          cv_var = chain_lits[c_start + k] ## i64
          cur_c = base[cv_var] != 0 ? base[cv_var] : val[cv_var] ## i64
          if cur_c == 1
            ok = 0
          elsif cur_c == 0
            val[cv_var] = -1
            trail[ts] = 0 - cv_var ## i64
            ts += 1
          else
            k = l_len
          k += 1
    li_neg = li_pos ^ 1 ## i64
    oi = occ_off[li_neg]
    oe = occ_off[li_neg + 1]
    while oi < oe && ok == 1 && ts < 2048
      ci = occ_ids[oi]
      visits += 1
      sat = 0
      unassigned = 0
      ul = 0 ## i64
      k = offs[ci]
      while k < offs[ci + 1]
        cl = fla[k]
        v = cl < 0 ? 0 - cl : cl ## i64
        cur = base[v] != 0 ? base[v] : val[v] ## i64
        vv = cl > 0 ? cur : 0 - cur ## i64
        if vv > 0
          sat = 1
        elsif vv == 0
          unassigned += 1
          ul = cl
        inspections += 1
        k += 1
      if sat == 0
        if unassigned == 0
          ok = 0
        elsif unassigned == 1
          v = ul < 0 ? 0 - ul : ul ## i64
          if ul > 0
            val[v] = 1
          else
            val[v] = -1
          trail[ts] = ul
          ts += 1
      oi += 1
  i = 0
  while i < ts
    l = trail[i]
    v = l < 0 ? 0 - l : l ## i64
    val[v] = 0
    i += 1
  state[0] = ok
  state[1] = ts
  state[2] += 1
  state[3] += visits
  state[4] += inspections
  state[5] += ts

-> wassat_struct_trial_propagate(base_val, tval, trail, pos_occ, neg_occ, short_clauses, assump, ladder_chains = nil, var_chain = nil, var_pos = nil, packed = nil, collect_implied = true)
  if packed != nil && assump.size <= 3
    if packed.size == 10
      args = packed[4] ## i64[]
      state = packed[5] ## i64[]
      i = 0
      while i < assump.size
        args[i] = assump[i]
        i += 1
      wassat_struct_trial_ladder_native(
        base_val, tval, trail, packed[0], packed[1], packed[2], packed[3],
        packed[6], packed[7], packed[8], packed[9], args, assump.size, state
      )
      implied = nil
      implied = [] if collect_implied
      if collect_implied && state[0] == 1
        i = 0
        while i < state[1]
          implied.push(trail[i])
          i += 1
        state[6] += state[1]
      return [state[0], state[1], implied]
    elsif ladder_chains == nil || ladder_chains.empty?
      args = packed[4] ## i64[]
      state = packed[5] ## i64[]
      i = 0
      while i < assump.size
        args[i] = assump[i]
        i += 1
      wassat_struct_trial_native(base_val, tval, trail, packed[0], packed[1], packed[2], packed[3], args, assump.size, state)
      implied = nil
      implied = [] if collect_implied
      if collect_implied && state[0] == 1
        i = 0
        while i < state[1]
          implied.push(trail[i])
          i += 1
        state[6] += state[1]
      return [state[0], state[1], implied]
  ts = 0
  ok = 1
  i = 0
  while i < assump.size && ok == 1
    l = assump[i]
    lv = l.abs
    pol = l > 0 ? 1 : -1
    bv = base_val[lv]
    cv = bv != 0 ? bv : tval[lv]
    if cv == 0 - pol
      ok = 0
    elsif cv == 0
      tval[lv] = pol
      trail[ts] = l
      ts += 1
    i += 1
  qh = 0
  while qh < ts && ok == 1 && ts < 2048
    lit = trail[qh]
    qh += 1
    lv = lit.abs
    if var_chain != nil && var_chain[lv] > 0
      cid = var_chain[lv] - 1
      ch = ladder_chains[cid]
      pos = var_pos[lv]
      if lit > 0
        k = pos - 1
        while k >= 0 && ok == 1 && ts < 2048
          cv_var = ch[k]
          bv_c = base_val[cv_var]
          cur_c = bv_c != 0 ? bv_c : tval[cv_var]
          if cur_c == -1
            ok = 0
          elsif cur_c == 0
            tval[cv_var] = 1
            trail[ts] = cv_var
            ts += 1
          else
            k = 0
          k -= 1
      else
        k = pos + 1
        l_len = ch.size
        while k < l_len && ok == 1 && ts < 2048
          cv_var = ch[k]
          bv_c = base_val[cv_var]
          cur_c = bv_c != 0 ? bv_c : tval[cv_var]
          if cur_c == 1
            ok = 0
          elsif cur_c == 0
            tval[cv_var] = -1
            trail[ts] = 0 - cv_var
            ts += 1
          else
            k = l_len
          k += 1
    occ = lit > 0 ? neg_occ[lv] : pos_occ[lv]
    j = 0
    while j < occ.size && ok == 1 && ts < 2048
      sc = short_clauses[occ[j]]
      sat = false
      unassigned = 0
      ul = 0
      k = 0
      while k < sc.size
        cl = sc[k]
        clv = cl.abs
        bv2 = base_val[clv]
        cv2 = bv2 != 0 ? bv2 : tval[clv]
        vv = cl > 0 ? cv2 : (0 - cv2)
        if vv > 0
          sat = true
        elsif vv == 0
          unassigned += 1
          ul = cl
        k += 1
      if !sat
        if unassigned == 0
          ok = 0
        elsif unassigned == 1
          ulv = ul.abs
          upol = ul > 0 ? 1 : -1
          tval[ulv] = upol
          trail[ts] = ul
          ts += 1
      j += 1
  out_lits = nil
  out_lits = [] if collect_implied
  i = 0
  while i < ts
    l = trail[i]
    out_lits.push(l) if ok == 1 && collect_implied
    tval[l.abs] = 0
    i += 1
  [ok, ts, out_lits]

-> wassat_struct_short_count(fcl, ncl, out) (i64[] i64 i64[])
  nshort = 0
  nlits = 0
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    if clen >= 2 && clen <= 4
      nshort += 1
      nlits += clen
    ci += 1
  out[0] = nshort
  out[1] = nlits

-> wassat_struct_short_fill(fla, fcs, fcl, ncl, s_fla, s_offs, out) (i64[] i64[] i64[] i64 i64[] i64[] i64[])
  at = 0
  sci = 0
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    if clen >= 2 && clen <= 4
      off = fcs[ci]
      s_offs[sci] = at
      j = 0
      while j < clen
        s_fla[at] = fla[off + j]
        at += 1
        j += 1
      sci += 1
    ci += 1
  out[0] = sci
  out[1] = at

# Pack short clauses directly from flat formula buffers + derived binaries + ladder chains.
-> wassat_struct_trial_pack_flat(nv, fla, fcs, fcl, ncl, binaries, ladder_chains)
  sc = i64[2]
  wassat_struct_short_count(fcl, ncl, sc)
  nbins = binaries.size
  total_cl = sc[0] + nbins
  total_lits = sc[1] + 2 * nbins
  s_fla = i64[total_lits]
  s_offs = i64[total_cl + 1]
  wassat_struct_short_fill(fla, fcs, fcl, ncl, s_fla, s_offs, sc)
  sci = sc[0]
  at = sc[1]
  bi = 0
  while bi < nbins
    pair = binaries[bi]
    s_offs[sci] = at
    s_fla[at] = pair[0]
    s_fla[at + 1] = pair[1]
    at += 2
    sci += 1
    bi += 1
  s_offs[sci] = at

  occ_off = i64[2 * nv + 3]
  occ_ids = i64[total_lits]
  wassat_struct_occ_index(nv, s_fla, s_offs, occ_off, occ_ids, i64[2 * nv + 2])

  nch = ladder_chains == nil ? 0 : ladder_chains.size
  total_ch = 0
  cid = 0
  while cid < nch
    total_ch += ladder_chains[cid].size
    cid += 1
  chain_lits = i32[total_ch + 1]
  chain_offs = i32[nch + 1]
  lit_chain = i32[2 * nv + 2]
  lit_cpos = i32[2 * nv + 2]
  cat = 0
  cid = 0
  while cid < nch
    ch = ladder_chains[cid]
    clen = ch.size
    chain_offs[cid] = cat
    idx = 0
    while idx < clen
      cv = ch[idx]
      chain_lits[cat] = cv
      cat += 1
      if cv >= 1 && cv <= nv
        pos_c = cv << 1
        neg_c = pos_c + 1
        lit_chain[pos_c] = cid + 1
        lit_cpos[pos_c] = idx
        lit_chain[neg_c] = cid + 1
        lit_cpos[neg_c] = idx
      idx += 1
    cid += 1
  chain_offs[nch] = cat

  [s_fla, s_offs, occ_off, occ_ids, i64[3], i64[7], chain_lits, chain_offs, lit_chain, lit_cpos]

-> wassat_detour_run_native(nv, m_layers, layer_len, layer_lits, base_val, tval, trail, s_fla, s_offs, occ_off, occ_ids, chain_lits, chain_offs, lit_chain, lit_cpos, args, state, det_units, det_bin_a, det_bin_b, det_witness, det_st) (i64 i64 i32[] i64[] i8[] i8[] i64[] i64[] i64[] i64[] i64[] i32[] i32[] i32[] i32[] i64[] i64[] i32[] i32[] i32[] i32[] i64[]) i64
  max_imp = nv < 2048 ? (nv + 1) : 2048 ## i64
  alive = i8[m_layers * 6]
  imp_off = i32[m_layers * 6]
  imp_len = i32[m_layers * 6]
  imp_buf = i32[m_layers * 6 * max_imp + 1]
  imp_at = 0

  r = 0
  while r < m_layers
    glen = layer_len[r] ## i64
    rbase = r * 6 ## i64
    s = 0
    while s < glen
      lit = layer_lits[rbase + s]
      args[0] = lit
      wassat_struct_trial_ladder_native(
        base_val, tval, trail, s_fla, s_offs, occ_off, occ_ids,
        chain_lits, chain_offs, lit_chain, lit_cpos, args, 1, state
      )
      if state[0] == 1
        alive[rbase + s] = 1
        ts = state[1]
        imp_off[rbase + s] = imp_at
        imp_len[rbase + s] = ts
        i = 0
        while i < ts
          imp_buf[imp_at + i] = trail[i]
          i += 1
        imp_at += ts
        state[6] += ts
      else
        alive[rbase + s] = 0
        imp_off[rbase + s] = imp_at
        imp_len[rbase + s] = 0
        ui = det_st[1]
        det_units[ui] = 0 - lit ## i64
        det_st[1] = ui + 1
        lv = lit < 0 ? 0 - lit : lit ## i64
        if lv >= 1 && lv <= nv
          if lit > 0
            base_val[lv] = -1
          else
            base_val[lv] = 1
      s += 1
    r += 1

  trans = i64[m_layers * 36]
  r = 0
  while r < m_layers - 1
    g1_len = layer_len[r] ## i64
    g2_len = layer_len[r + 1] ## i64
    rb1 = r * 6 ## i64
    rb2 = (r + 1) * 6 ## i64
    tbase = r * 36 ## i64
    s1 = 0
    while s1 < g1_len
      s2 = 0
      while s2 < g2_len
        if alive[rb1 + s1] == 1 && alive[rb2 + s2] == 1
          args[0] = layer_lits[rb1 + s1]
          args[1] = layer_lits[rb2 + s2]
          wassat_struct_trial_ladder_native(
            base_val, tval, trail, s_fla, s_offs, occ_off, occ_ids,
            chain_lits, chain_offs, lit_chain, lit_cpos, args, 2, state
          )
          if state[0] == 1
            trans[tbase + s1 * 6 + s2] = 1 + state[1]
        s2 += 1
      s1 += 1
    r += 1

  r = 0
  while r < m_layers - 2
    g1_len = layer_len[r] ## i64
    g2_len = layer_len[r + 1] ## i64
    g3_len = layer_len[r + 2] ## i64
    rb1 = r * 6 ## i64
    rb2 = (r + 1) * 6 ## i64
    rb3 = (r + 2) * 6 ## i64
    tb1 = r * 36 ## i64
    tb2 = (r + 1) * 36 ## i64
    s1 = 0
    while s1 < g1_len
      if alive[rb1 + s1] == 1
        s2 = 0
        while s2 < g2_len
          if trans[tb1 + s1 * 6 + s2] > 0
            macro_ok = 0
            s3 = 0
            while s3 < g3_len && macro_ok == 0
              if trans[tb2 + s2 * 6 + s3] > 0
                args[0] = layer_lits[rb1 + s1]
                args[1] = layer_lits[rb2 + s2]
                args[2] = layer_lits[rb3 + s3]
                wassat_struct_trial_ladder_native(
                  base_val, tval, trail, s_fla, s_offs, occ_off, occ_ids,
                  chain_lits, chain_offs, lit_chain, lit_cpos, args, 3, state
                )
                macro_ok = 1 if state[0] == 1
              s3 += 1
            if macro_ok == 0
              trans[tb1 + s1 * 6 + s2] = 0
              bi = det_st[2]
              det_bin_a[bi] = 0 - layer_lits[rb1 + s1] ## i64
              det_bin_b[bi] = 0 - layer_lits[rb2 + s2] ## i64
              det_st[2] = bi + 1
          s2 += 1
      s1 += 1
    r += 1

  fwd_cost = i64[m_layers * 6]
  fwd_parent = i32[m_layers * 6]
  bwd_ok = i8[m_layers * 6]
  r = 0
  while r < m_layers
    glen = layer_len[r] ## i64
    rbase = r * 6 ## i64
    s = 0
    while s < glen
      fwd_cost[rbase + s] = r == 0 && alive[s] == 1 ? 1 : 0 ## i64
      fwd_parent[rbase + s] = 0 - 1
      if r == m_layers - 1 && alive[rbase + s] == 1
        bwd_ok[rbase + s] = 1
      else
        bwd_ok[rbase + s] = 0
      s += 1
    r += 1

  r = 0
  while r < m_layers - 1
    g1_len = layer_len[r] ## i64
    g2_len = layer_len[r + 1] ## i64
    rb1 = r * 6 ## i64
    rb2 = (r + 1) * 6 ## i64
    tbase = r * 36 ## i64
    s1 = 0
    while s1 < g1_len
      c1 = fwd_cost[rb1 + s1]
      if c1 > 0
        s2 = 0
        while s2 < g2_len
          step_c = trans[tbase + s1 * 6 + s2]
          if step_c > 0
            nc = c1 + step_c ## i64
            if fwd_cost[rb2 + s2] == 0 || nc < fwd_cost[rb2 + s2]
              fwd_cost[rb2 + s2] = nc
              fwd_parent[rb2 + s2] = s1
          s2 += 1
      s1 += 1
    r += 1

  r = m_layers - 2
  while r >= 0
    g1_len = layer_len[r] ## i64
    g2_len = layer_len[r + 1] ## i64
    rb1 = r * 6 ## i64
    rb2 = (r + 1) * 6 ## i64
    tbase = r * 36 ## i64
    s1 = 0
    while s1 < g1_len
      if fwd_cost[rb1 + s1] > 0
        ok_bwd = 0
        s2 = 0
        while s2 < g2_len
          if trans[tbase + s1 * 6 + s2] > 0 && bwd_ok[rb2 + s2] == 1
            ok_bwd = 1
          s2 += 1
        bwd_ok[rb1 + s1] = ok_bwd
      s1 += 1
    r -= 1

  # Linear O(sum |imps|) surviving-state implication intersection via hit_count.
  hit_count = i32[2 * nv + 2]
  surviving = i32[6]
  r = 0
  while r < m_layers
    glen = layer_len[r] ## i64
    rbase = r * 6 ## i64
    nsurv = 0
    s = 0
    while s < glen
      if fwd_cost[rbase + s] > 0 && bwd_ok[rbase + s] == 1
        surviving[nsurv] = s
        nsurv += 1
      elsif alive[rbase + s] == 1
        alive[rbase + s] = 0
        ui = det_st[1]
        det_units[ui] = 0 - layer_lits[rbase + s] ## i64
        det_st[1] = ui + 1
      s += 1
    if nsurv == 0
      det_st[0] = 1
      return 0 - 1
    if nsurv == 1
      s0 = surviving[0] ## i64
      ui = det_st[1]
      det_units[ui] = layer_lits[rbase + s0]
      ui += 1
      ioff = imp_off[rbase + s0] ## i64
      ilen = imp_len[rbase + s0] ## i64
      k = 0
      while k < ilen
        det_units[ui] = imp_buf[ioff + k]
        ui += 1
        k += 1
      det_st[1] = ui
    else
      s0 = surviving[0] ## i64
      off0 = imp_off[rbase + s0] ## i64
      len0 = imp_len[rbase + s0] ## i64
      fi = 0
      while fi < len0
        cand = imp_buf[off0 + fi] ## i64
        cidx = cand > 0 ? (cand << 1) : (((0 - cand) << 1) + 1) ## i64
        hit_count[cidx] = 1 if hit_count[cidx] == 0
        fi += 1
      si = 1
      while si < nsurv
        ss = surviving[si] ## i64
        offs_s = imp_off[rbase + ss] ## i64
        lens_s = imp_len[rbase + ss] ## i64
        k = 0
        while k < lens_s
          il = imp_buf[offs_s + k] ## i64
          iidx = il > 0 ? (il << 1) : (((0 - il) << 1) + 1) ## i64
          hit_count[iidx] = si + 1 if hit_count[iidx] == si
          k += 1
        si += 1
      ui = det_st[1]
      fi = 0
      while fi < len0
        cand = imp_buf[off0 + fi] ## i64
        cidx = cand > 0 ? (cand << 1) : (((0 - cand) << 1) + 1) ## i64
        if hit_count[cidx] == nsurv
          det_units[ui] = cand
          ui += 1
        hit_count[cidx] = 0
        fi += 1
      det_st[1] = ui
    r += 1

  best_end = 0 - 1
  best_val = 0 ## i64
  last_r = m_layers - 1
  last_base = last_r * 6 ## i64
  last_len = layer_len[last_r] ## i64
  s = 0
  while s < last_len
    fc = fwd_cost[last_base + s]
    if fc > 0 && bwd_ok[last_base + s] == 1
      if best_end < 0 || fc < best_val
        best_end = s
        best_val = fc
    s += 1

  if best_end >= 0
    wi = 0
    cur = best_end
    r = m_layers - 1
    while r >= 0 && cur >= 0
      rbase = r * 6 ## i64
      det_witness[wi] = layer_lits[rbase + cur]
      wi += 1
      ioff = imp_off[rbase + cur] ## i64
      ilen = imp_len[rbase + cur] ## i64
      k = 0
      while k < ilen
        det_witness[wi] = imp_buf[ioff + k]
        wi += 1
        k += 1
      cur = fwd_parent[rbase + cur] ## i64
      r -= 1
    det_st[3] = wi
  1

-> wassat_detour_prune(nv, formula, card_info = nil)
  view = wassat_struct_flat_view(formula)
  cinfo = card_info == nil ? wassat_extract_cardinality_and_propagate(nv, view) : card_info
  if cinfo["unsat"]
    return { "unsat": true, "units": cinfo["units"], "binaries": cinfo["binaries"], "witness_phases": [] }

  units = []
  cinfo["units"].each -> (u)
    units.push(u)
  binaries = []
  cinfo["binaries"].each -> (b)
    binaries.push(b)

  eo_groups = cinfo["eo_groups"]
  ladder_chains = cinfo["ladder_chains"]

  layers = []
  if eo_groups.size >= 2
    i = 0
    while i < eo_groups.size && layers.size < 32
      layers.push(eo_groups[i]) if eo_groups[i].size >= 2 && eo_groups[i].size <= 6
      i += 1
  if layers.size < 2
    ctrl = wassat_identify_control_vars(nv, view, 16)["control_vars"]
    i = 0
    while i < ctrl.size && layers.size < 16
      v = ctrl[i]
      if cinfo["val"][v] == 0
        layers.push([v, 0 - v])
      i += 1

  return { "unsat": false, "units": units, "binaries": binaries, "witness_phases": [] } if layers.size < 2

  fla = view["flat_lits"] ## i64[]
  fcs = view["flat_offs"] ## i64[]
  fcl = view["flat_lens"] ## i64[]
  ncl = view["flat_ncl"] ## i64

  packed = wassat_struct_trial_pack_flat(nv, fla, fcs, fcl, ncl, binaries, ladder_chains)
  base_val = cinfo["val"] ## i8[]
  tval = i8[nv + 1]
  trail_cap = nv > 2048 ? (nv + 4) : 2052
  trail = i64[trail_cap]

  m_layers = layers.size
  layer_len = i32[m_layers]
  layer_lits = i64[m_layers * 6]
  r = 0
  while r < m_layers
    grp = layers[r]
    glen = grp.size
    layer_len[r] = glen
    s = 0
    while s < glen
      layer_lits[r * 6 + s] = grp[s]
      s += 1
    r += 1

  det_units = i32[m_layers * 2080 + 32]
  det_bin_a = i32[m_layers * 36 + 16]
  det_bin_b = i32[m_layers * 36 + 16]
  det_witness = i32[m_layers * 2080 + 32]
  det_st = i64[4]

  s_fla = packed[0] ## i64[]
  s_offs = packed[1] ## i64[]
  occ_off = packed[2] ## i64[]
  occ_ids = packed[3] ## i64[]
  args = packed[4] ## i64[]
  work = packed[5] ## i64[]
  chain_lits = packed[6] ## i32[]
  chain_offs = packed[7] ## i32[]
  lit_chain = packed[8] ## i32[]
  lit_cpos = packed[9] ## i32[]

  wassat_detour_run_native(
    nv, m_layers, layer_len, layer_lits, base_val, tval, trail,
    s_fla, s_offs, occ_off, occ_ids, chain_lits, chain_offs, lit_chain, lit_cpos,
    args, work, det_units, det_bin_a, det_bin_b, det_witness, det_st
  )

  nu = det_st[1]
  i = 0
  while i < nu
    units.push(det_units[i])
    i += 1
  nb = det_st[2]
  i = 0
  while i < nb
    binaries.push([det_bin_a[i], det_bin_b[i]])
    i += 1
  if det_st[0] == 1
    return { "unsat": true, "units": units, "binaries": binaries, "witness_phases": [] }

  witness_phases = []
  nw = det_st[3]
  i = 0
  while i < nw
    witness_phases.push(det_witness[i])
    i += 1

  if env("WASSAT_PROFILE") == "1"
    wassat_prof_note("struct.detour.work trials=[work[2]] occurrences=[work[3]] literals=[work[4]] assignments=[work[5]] copied_implications=[work[6]]")
  { "unsat": false, "units": units, "binaries": binaries, "witness_phases": witness_phases }

# ---- 4. Clue / Sudoku Bitmask Truth-Table Pruning ---------------------------

-> wassat_truth_table_solve_native(nv, fla, fcs, fcl, ncl, max_tables, val, cl_vars, cl_size, cl_ht, cl_hmask, head, next_e, tbl_id, u_out, b_out_a, b_out_b, h_out, st) (i64 i64[] i64[] i64[] i64 i64 i8[] i32[] i32[] i32[] i64 i32[] i32[] i32[] i32[] i32[] i32[] i32[] i64[]) i64
  cmask = i64[6]
  m0 = 0xAAAAAAAA ## i64
  m1 = 0xCCCCCCCC ## i64
  m2 = 0xF0F0F0F0 ## i64
  m3 = 0xFF00FF00 ## i64
  m4 = 0xFFFF0000 ## i64
  m5 = 0xFFFFFFFF ## i64
  cmask[0] = (m0 << 32) | m0 ## i64
  cmask[1] = (m1 << 32) | m1 ## i64
  cmask[2] = (m2 << 32) | m2 ## i64
  cmask[3] = (m3 << 32) | m3 ## i64
  cmask[4] = (m4 << 32) | m4 ## i64
  cmask[5] = m5 << 32 ## i64
  all64 = 0 - 1 ## i64

  vars_buf = i32[16]
  nclusters = 0
  nsmall = 0
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    off = fcs[ci]
    if clen == 1
      l = fla[off]
      v = l < 0 ? 0 - l : l ## i64
      if v >= 1 && v <= nv
        pol = l > 0 ? 1 : -1 ## i64
        cur = val[v] ## i64
        if cur == 0 - pol
          st[3] = 1
          return 0 - 1
        elsif cur == 0
          val[v] = pol
          ui = st[0]
          u_out[ui] = l
          st[0] = ui + 1
    elsif clen >= 2 && clen <= 6
      nsmall += 1
      if clen >= 3 && nclusters < max_tables
        vlen = 0
        j = 0
        while j < clen
          lit = fla[off + j]
          v = lit < 0 ? 0 - lit : lit ## i64
          if v >= 1 && v <= nv
            dup = 0
            k = 0
            while k < vlen
              dup = 1 if vars_buf[k] == v
              k += 1
            if dup == 0
              vars_buf[vlen] = v
              vlen += 1
          j += 1
        if vlen >= 3 && vlen <= 6
          a = 1
          while a < vlen
            x = vars_buf[a] ## i64
            b = a - 1
            while b >= 0 && vars_buf[b] > x
              vars_buf[b + 1] = vars_buf[b]
              b -= 1
            vars_buf[b + 1] = x
            a += 1
          h = vlen ## i64
          k = 0
          while k < vlen
            h = ((h * 1000003) + vars_buf[k]) & cl_hmask ## i64
            k += 1
          found = 0
          while cl_ht[h] != 0 && found == 0
            ti2 = cl_ht[h] - 1 ## i64
            if cl_size[ti2] == vlen
              same = 1
              tbase2 = ti2 * 6 ## i64
              k = 0
              while k < vlen && same == 1
                same = 0 if cl_vars[tbase2 + k] != vars_buf[k]
                k += 1
              found = 1 if same == 1
            if found == 0
              h = (h + 1) & cl_hmask ## i64
          if found == 0
            cl_ht[h] = nclusters + 1
            cl_size[nclusters] = vlen
            tbase = nclusters * 6 ## i64
            k = 0
            while k < vlen
              cl_vars[tbase + k] = vars_buf[k]
              k += 1
            nclusters += 1
    ci += 1

  if nclusters < 16 && nsmall >= 2
    vlen = 0
    ci = 0
    while ci < ncl && nclusters < 32
      clen = fcl[ci]
      if clen >= 2 && clen <= 6
        off = fcs[ci]
        j = 0
        while j < clen
          lit = fla[off + j]
          v = lit < 0 ? 0 - lit : lit ## i64
          if v >= 1 && v <= nv
            dup = 0
            k = 0
            while k < vlen
              dup = 1 if vars_buf[k] == v
              k += 1
            if dup == 0
              vars_buf[vlen] = v
              vlen += 1
          j += 1
        if vlen >= 4
          take = vlen > 6 ? 6 : vlen ## i64
          cl_size[nclusters] = take
          tbase = nclusters * 6 ## i64
          k = 0
          while k < take
            cl_vars[tbase + k] = vars_buf[k]
            k += 1
          nclusters += 1
          vlen = 0
      ci += 1
    if vlen >= 2 && vlen <= 6 && nclusters < cl_size.size
      cl_size[nclusters] = vlen
      tbase = nclusters * 6 ## i64
      k = 0
      while k < vlen
        cl_vars[tbase + k] = vars_buf[k]
        k += 1
      nclusters += 1

  return 0 if nclusters == 0

  # Flat variable -> cluster incidence lists (head / next_e / tbl_id).
  ecnt = 0
  ti = nclusters - 1
  while ti >= 0
    k = cl_size[ti] ## i64
    tbase = ti * 6 ## i64
    j = 0
    while j < k
      v = cl_vars[tbase + j] ## i64
      tbl_id[ecnt] = ti
      next_e[ecnt] = head[v]
      head[v] = ecnt + 1
      ecnt += 1
      j += 1
    ti -= 1

  table_masks = i64[nclusters]
  ti = 0
  while ti < nclusters
    k = cl_size[ti] ## i64
    table_masks[ti] = k == 6 ? all64 : ((1 << (1 << k)) - 1) ## i64
    ti += 1

  # Clause masking via 64-bit cofactor masks (replaces 64-row inner loops).
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    if clen >= 2 && clen <= 6
      off = fcs[ci]
      l0 = fla[off]
      v0 = l0 < 0 ? 0 - l0 : l0 ## i64
      if v0 >= 1 && v0 <= nv
        e = head[v0] ## i64
        while e != 0
          ti = tbl_id[e - 1] ## i64
          e = next_e[e - 1] ## i64
          k = cl_size[ti] ## i64
          tbase = ti * 6 ## i64
          all_in = 1
          bad_rows = k == 6 ? all64 : ((1 << (1 << k)) - 1) ## i64
          j = 0
          while j < clen && all_in == 1
            l = fla[off + j]
            lv = l < 0 ? 0 - l : l ## i64
            bit_idx = 0 - 1
            m = 0
            while m < k
              if cl_vars[tbase + m] == lv
                bit_idx = m
                m = k
              else
                m += 1
            if bit_idx < 0
              all_in = 0
            else
              if l > 0
                bad_rows = bad_rows & (all64 ^ cmask[bit_idx]) ## i64
              else
                bad_rows = bad_rows & cmask[bit_idx] ## i64
            j += 1
          if all_in == 1 && bad_rows != 0
            table_masks[ti] = table_masks[ti] & (all64 ^ bad_rows) ## i64
    ci += 1

  seen_bin_ht = i64[8192]
  cand_a = i64[4]
  cand_b = i64[4]
  changed = 1
  rounds = 0
  while changed == 1 && rounds < 8
    changed = 0
    rounds += 1
    ti = 0
    while ti < nclusters
      k = cl_size[ti] ## i64
      tbase = ti * 6 ## i64
      mask = table_masks[ti]

      # Apply known units in 1 bitwise AND per assigned variable.
      m = 0
      while m < k
        vv = val[cl_vars[tbase + m]] ## i64
        if vv > 0
          mask = mask & cmask[m] ## i64
        elsif vv < 0
          mask = mask & (all64 ^ cmask[m]) ## i64
        m += 1
      table_masks[ti] = mask
      if mask == 0
        st[3] = 1
        return 0 - 1

      # Extract forced units via cofactor masks.
      m = 0
      while m < k
        v = cl_vars[tbase + m] ## i64
        if val[v] == 0
          if (mask & (all64 ^ cmask[m])) == 0
            val[v] = 1
            ui = st[0]
            u_out[ui] = v
            st[0] = ui + 1
            changed = 1
          elsif (mask & cmask[m]) == 0
            val[v] = -1
            ui = st[0]
            u_out[ui] = 0 - v ## i64
            st[0] = ui + 1
            changed = 1
        m += 1

      # C(k, 2) pairwise binary implication / equivalence checks via cofactor masks.
      if rounds == 1 && st[1] < 2048
        m1_idx = 0
        while m1_idx < k
          v1 = cl_vars[tbase + m1_idx] ## i64
          if val[v1] == 0
            p1 = cmask[m1_idx]
            n1 = all64 ^ p1 ## i64
            m2_idx = m1_idx + 1
            while m2_idx < k
              v2 = cl_vars[tbase + m2_idx] ## i64
              if val[v2] == 0
                p2 = cmask[m2_idx]
                n2 = all64 ^ p2 ## i64
                ncands = 0
                if (mask & n1 & n2) == 0
                  cand_a[ncands] = v1
                  cand_b[ncands] = v2
                  ncands += 1
                if (mask & n1 & p2) == 0
                  cand_a[ncands] = v1
                  cand_b[ncands] = 0 - v2 ## i64
                  ncands += 1
                if (mask & p1 & n2) == 0
                  cand_a[ncands] = 0 - v1 ## i64
                  cand_b[ncands] = v2
                  ncands += 1
                if (mask & p1 & p2) == 0
                  cand_a[ncands] = 0 - v1 ## i64
                  cand_b[ncands] = 0 - v2 ## i64
                  ncands += 1
                ci2 = 0
                while ci2 < ncands
                  pa = cand_a[ci2]
                  pb = cand_b[ci2]
                  xa = pa < pb ? pa : pb ## i64
                  xb = pa < pb ? pb : pa ## i64
                  if wassat_struct_bin_dedup(seen_bin_ht, 8191, xa, xb) == 1
                    bi = st[1]
                    b_out_a[bi] = xa
                    b_out_b[bi] = xb
                    st[1] = bi + 1
                  ci2 += 1
              m2_idx += 1
          m1_idx += 1
      ti += 1

  # Phase-hint extraction via hardware 64-bit popcount.
  seen_hint = i8[nv + 1]
  hi = 0
  ti = 0
  while ti < nclusters
    k = cl_size[ti] ## i64
    tbase = ti * 6 ## i64
    mask = table_masks[ti]
    total = ccall_nobox("__w_bit_ctpop_u64", mask) ## i64
    m = 0
    while m < k
      v = cl_vars[tbase + m] ## i64
      if seen_hint[v] == 0
        seen_hint[v] = 1
        if total > 0
          ones = ccall_nobox("__w_bit_ctpop_u64", mask & cmask[m]) ## i64
          zeros = total - ones ## i64
          h_out[hi] = ones >= zeros ? v : (0 - v) ## i64
          hi += 1
      m += 1
    ti += 1
  st[2] = hi
  1

-> wassat_truth_table_prune(nv, formula, max_tables = 256, seed_units = nil)
  if nv <= 0
    return { "unsat": false, "units": [], "binaries": [], "phase_hints": [] }
  view = wassat_struct_flat_view(formula)
  fla = view["flat_lits"] ## i64[]
  fcs = view["flat_offs"] ## i64[]
  fcl = view["flat_lens"] ## i64[]
  ncl = view["flat_ncl"] ## i64

  val = i8[nv + 1]
  u_out = i32[nv + 2]
  b_out_a = i32[2200]
  b_out_b = i32[2200]
  h_out = i32[nv + 2]
  # st: [0]=unit_cnt, [1]=bin_cnt, [2]=hint_cnt, [3]=unsat
  st = i64[4]

  if seed_units != nil
    si = 0
    while si < seed_units.size
      sl = seed_units[si]
      sv = sl.abs
      if sv >= 1 && sv <= nv
        spol = sl > 0 ? 1 : -1
        if val[sv] == 0 - spol
          return { "unsat": true, "units": [], "binaries": [], "phase_hints": [] }
        elsif val[sv] == 0
          val[sv] = spol
      si += 1

  cap_tables = (max_tables > 32 ? max_tables : 32) + 4
  cl_hcap = 1024
  while cl_hcap < cap_tables * 4
    cl_hcap = cl_hcap << 1
  cl_vars = i32[cap_tables * 6]
  cl_size = i32[cap_tables]
  cl_ht = i32[cl_hcap]
  head = i32[nv + 2]
  inc_cap = 6 * cap_tables + 8
  inc_cap = 1024 if inc_cap < 1024
  next_e = i32[inc_cap]
  tbl_id = i32[inc_cap]

  wassat_truth_table_solve_native(
    nv, fla, fcs, fcl, ncl, max_tables, val,
    cl_vars, cl_size, cl_ht, cl_hcap - 1, head, next_e, tbl_id,
    u_out, b_out_a, b_out_b, h_out, st
  )

  units = []
  i = 0
  while i < st[0]
    units.push(u_out[i])
    i += 1
  binaries = []
  i = 0
  while i < st[1]
    binaries.push([b_out_a[i], b_out_b[i]])
    i += 1
  if st[3] == 1
    return { "unsat": true, "units": units, "binaries": binaries, "phase_hints": [] }
  phase_hints = []
  i = 0
  while i < st[2]
    phase_hints.push(h_out[i])
    i += 1
  { "unsat": false, "units": units, "binaries": binaries, "phase_hints": phase_hints }

# ---- 5. Combined Structural Pruning Coordinator ----------------------------

-> wassat_structural_prune(nv, formula)
  if nv <= 0 || formula["flat_ncl"] != nil && formula["flat_ncl"] > 1000000
    return {
      "unsat": false, "units": [], "binaries": [],
      "control_vars": [], "detour_phases": [], "tt_phases": []
    }
  if formula.has_key?("clauses") && formula["clauses"] != nil && formula["clauses"].size > 1000000
    return {
      "unsat": false, "units": [], "binaries": [],
      "control_vars": [], "detour_phases": [], "tt_phases": []
    }
  tp = wassat_prof_clock
  # Share one flat i64[] clause view across all passes without unpacking flat
  # formulas into boxed clause Arrays or mutating the caller's formula hash.
  view = wassat_struct_flat_view(formula)
  tp = wassat_prof("struct.clauses", tp)
  if tp != 0
    wassat_prof_note("struct.input clauses=[view["flat_ncl"]] materialized_clauses=[view["packed_from_boxed"]]")
  ctrl = wassat_identify_control_vars(nv, view, 64)
  tp = wassat_prof("struct.control", tp)
  card = wassat_extract_cardinality_and_propagate(nv, view)
  tp = wassat_prof("struct.cardinality", tp)
  wassat_prof_note("struct.cardinality.work units=[card["units"].size] binaries=[card["binaries"].size] groups=[card["eo_groups"].size] chains=[card["chains"].size]") if tp != 0
  if card["unsat"]
    return {
      "unsat": true, "units": card["units"], "binaries": card["binaries"],
      "control_vars": ctrl["control_vars"], "detour_phases": [], "tt_phases": []
    }
  det = wassat_detour_prune(nv, view, card)
  tp = wassat_prof("struct.detour", tp)
  if det["unsat"]
    return {
      "unsat": true, "units": det["units"], "binaries": det["binaries"],
      "control_vars": ctrl["control_vars"], "detour_phases": [], "tt_phases": []
    }
  tt = wassat_truth_table_prune(nv, view, 128, det["units"])
  tp = wassat_prof("struct.truth_table", tp)
  if tt["unsat"]
    return {
      "unsat": true, "units": tt["units"], "binaries": tt["binaries"],
      "control_vars": ctrl["control_vars"], "detour_phases": [], "tt_phases": []
    }

  seen_u = i8[nv + 1]
  merged_units = []
  unsat = false
  du = det["units"]
  i = 0
  while i < du.size
    l = du[i]
    v = l.abs
    if v >= 1 && v <= nv
      pol = l > 0 ? 1 : -1
      if seen_u[v] == 0 - pol
        unsat = true
      elsif seen_u[v] == 0
        seen_u[v] = pol
        merged_units.push(l)
    i += 1
  tu = tt["units"]
  i = 0
  while i < tu.size
    l = tu[i]
    v = l.abs
    if v >= 1 && v <= nv
      pol = l > 0 ? 1 : -1
      if seen_u[v] == 0 - pol
        unsat = true
      elsif seen_u[v] == 0
        seen_u[v] = pol
        merged_units.push(l)
    i += 1

  seen_b_ht = i64[65536]
  merged_bins = []
  db = det["binaries"]
  i = 0
  while i < db.size
    pair = db[i]
    a = pair[0] < pair[1] ? pair[0] : pair[1] ## i64
    b = pair[0] < pair[1] ? pair[1] : pair[0] ## i64
    if a != b && a != 0 - b && merged_bins.size < 16384
      if wassat_struct_bin_dedup(seen_b_ht, 65535, a, b) == 1
        merged_bins.push([a, b])
    i += 1
  tb = tt["binaries"]
  i = 0
  while i < tb.size
    pair = tb[i]
    a = pair[0] < pair[1] ? pair[0] : pair[1] ## i64
    b = pair[0] < pair[1] ? pair[1] : pair[0] ## i64
    if a != b && a != 0 - b && merged_bins.size < 16384
      if wassat_struct_bin_dedup(seen_b_ht, 65535, a, b) == 1
        merged_bins.push([a, b])
    i += 1

  tp = wassat_prof("struct.merge", tp)
  wassat_prof_note("struct.output units=[merged_units.size] binaries=[merged_bins.size] controls=[ctrl["control_vars"].size] detour_phases=[det["witness_phases"].size] tt_phases=[tt["phase_hints"].size]") if tp != 0
  {
    "unsat": unsat,
    "units": merged_units,
    "binaries": merged_bins,
    "control_vars": ctrl["control_vars"],
    "detour_phases": det["witness_phases"],
    "tt_phases": tt["phase_hints"]
  }

# Apply shared pruning clauses (units & binaries) to a solver `s`, and
# optionally configure `s` as the DETOUR arm (mode == 1), the Clue/Sudoku
# Truth-Table arm (mode == 2), the Control-Inverted Focused arm (mode == 3),
# or the Reluctant Control-EVSIDS arm (mode == 4).
-> wassat_apply_structural_pruning(s, prune_info, mode = 0, publish_ring = false)
  return 0 if prune_info == nil
  units = prune_info["units"]
  i = 0
  while i < units.size
    rc = s.install_pruning_clause([units[i]], publish_ring)
    return 0 - 1 if rc < 0
    i += 1
  bins = prune_info["binaries"]
  i = 0
  while i < bins.size
    rc = s.install_pruning_clause(bins[i], publish_ring)
    return 0 - 1 if rc < 0
    i += 1
  if mode == 1
    s.enable_focused_only
    s.promote_control_vars(prune_info["control_vars"]) unless prune_info["control_vars"].empty?
    s.set_phases(prune_info["detour_phases"]) unless prune_info["detour_phases"].empty?
  elsif mode == 2
    s.enable_chrono
    s.promote_control_vars(prune_info["control_vars"]) unless prune_info["control_vars"].empty?
    s.set_phases(prune_info["tt_phases"]) unless prune_info["tt_phases"].empty?
  elsif mode == 3
    s.enable_focused_only
    s.enable_shrink
    s.promote_control_vars(prune_info["control_vars"]) unless prune_info["control_vars"].empty?
    unless prune_info["detour_phases"].empty?
      inv = []
      j = 0
      dp = prune_info["detour_phases"]
      while j < dp.size
        inv.push(0 - dp[j])
        j += 1
      s.set_phases(inv)
  elsif mode == 4
    s.enable_stable_only
    s.promote_control_vars(prune_info["control_vars"]) unless prune_info["control_vars"].empty?
  0
