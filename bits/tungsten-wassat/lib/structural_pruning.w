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

# Encode literal l in -nv..nv into 0..2*nv+1
-> wassat_struct_lit_idx(l) (i64) i64
  l > 0 ? (l << 1) : (((0 - l) << 1) + 1)

-> wassat_struct_idx_lit(idx) (i64) i64
  (idx & 1) == 0 ? (idx >> 1) : (0 - (idx >> 1))

# ---- 1. Syntactic Control-Variable Identification --------------------------
#
# Identifies variables with high clause fanout that bridge multiple variable
# stride clusters across binary/ternary/quaternary clauses with balanced
# polarity. Returns a hash:
#   "control_vars": top control variables ordered by bridging score descending
#   "scores": i64[nv + 1] bridging scores
-> wassat_identify_control_vars(nv, formula, max_vars = 64)
  uval = i8[nv + 1]
  clauses = wassat_struct_clauses_of(formula)
  ncl = clauses.size
  ci = 0
  while ci < ncl
    c = clauses[ci]
    if c.size == 1
      l = c[0]
      v = l.abs
      if v >= 1 && v <= nv
        uval[v] = l > 0 ? 1 : -1
    ci += 1

  pos_occ = i64[nv + 1]
  neg_occ = i64[nv + 1]
  tern_occ = i64[nv + 1]
  quad_occ = i64[nv + 1]
  buckets = i64[nv + 1]
  stride = nv >= 64 ? (nv / 60 + 1) : 1
  ci = 0
  while ci < ncl
    c = clauses[ci]
    if c.size >= 2 && c.size <= 6
      sat = false
      active_len = 0
      cmask = 0 ## i64
      j = 0
      while j < c.size
        l = c[j]
        v = l.abs
        if v >= 1 && v <= nv
          uv = uval[v]
          if (l > 0 && uv > 0) || (l < 0 && uv < 0)
            sat = true
          elsif uv == 0
            active_len += 1
            b = (v - 1) / stride
            b = 60 if b > 60
            cmask = cmask | (1 << b)
        j += 1
      if !sat && active_len >= 2
        j = 0
        while j < c.size
          l = c[j]
          v = l.abs
          if v >= 1 && v <= nv && uval[v] == 0
            if l > 0
              pos_occ[v] += 1
            else
              neg_occ[v] += 1
            tern_occ[v] += 1 if active_len == 3
            quad_occ[v] += 1 if active_len == 4
            buckets[v] = buckets[v] | cmask
          j += 1
    ci += 1

  scores = i64[nv + 1]
  candidates = []
  v = 1
  while v <= nv
    if uval[v] == 0
      p = pos_occ[v]
      n = neg_occ[v]
      if p >= 2 && n >= 2
        min_pn = p < n ? p : n
        bmask = buckets[v] ## i64
        bcnt = 0 ## i64
        while bmask != 0
          bmask = bmask & (bmask - 1)
          bcnt += 1
        if bcnt >= 2 || (tern_occ[v] + quad_occ[v]) >= 4
          sc = min_pn * (tern_occ[v] + 2 * quad_occ[v] + 1) * (bcnt + 1)
          # Selector / control-word boost: defined in a small positive domain
          # (p <= 8) and used negatively as a guard across many clauses.
          if p <= 8 && n >= 3 * p && n >= 12
            sc += n * (bcnt + 2) * 100000
          scores[v] = sc
          candidates.push(v)
    v += 1

  top = []
  i = 0
  while i < candidates.size
    cv = candidates[i]
    csc = scores[cv]
    pos = top.size
    if pos < max_vars || csc > scores[top[pos - 1]]
      top.push(cv) if pos < max_vars
      k = top.size - 1
      while k > 0 && scores[top[k - 1]] < csc
        top[k] = top[k - 1]
        k -= 1
      top[k] = cv
    i += 1
  { "control_vars": top, "scores": scores }

# ---- 2. Cardinality / EO / AMO / Sequential-Counter Bound Propagation ------

-> wassat_struct_enqueue_unit(nv, val, units, q, lit)
  v = lit.abs
  return 0 if v < 1 || v > nv
  pol = lit > 0 ? 1 : -1
  return 0 - 1 if val[v] == 0 - pol
  if val[v] == 0
    val[v] = pol
    units.push(lit)
    q.push(lit)
  1

-> wassat_struct_propagate_units(nv, val, units, q, bin_adj, ternaries)
  qh = 0
  while qh < q.size
    lit = q[qh]
    qh += 1
    idx = wassat_struct_lit_idx(lit)
    adj = bin_adj[idx]
    j = 0
    while j < adj.size
      rc = wassat_struct_enqueue_unit(nv, val, units, q, adj[j])
      return 0 - 1 if rc < 0
      j += 1
  changed = true
  while changed
    changed = false
    ti = 0
    while ti < ternaries.size
      tc = ternaries[ti]
      sat = false
      unassigned = 0
      ul = 0
      j = 0
      while j < 3
        l = tc[j]
        v = l.abs
        vv = l > 0 ? val[v] : (0 - val[v])
        if vv > 0
          sat = true
        elsif vv == 0
          unassigned += 1
          ul = l
        j += 1
      if !sat
        return 0 - 1 if unassigned == 0
        if unassigned == 1
          rc = wassat_struct_enqueue_unit(nv, val, units, q, ul)
          return 0 - 1 if rc < 0
          changed = true
          while qh < q.size
            lit = q[qh]
            qh += 1
            idx = wassat_struct_lit_idx(lit)
            adj = bin_adj[idx]
            k = 0
            while k < adj.size
              rc2 = wassat_struct_enqueue_unit(nv, val, units, q, adj[k])
              return 0 - 1 if rc2 < 0
              k += 1
      ti += 1
  1

-> wassat_struct_has_mutex(bin_adj, l1, l2)
  idx1 = wassat_struct_lit_idx(l1)
  neg2 = 0 - l2
  adj = bin_adj[idx1]
  j = 0
  while j < adj.size
    return true if adj[j] == neg2
    j += 1
  false

-> wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, a, b)
  return 0 if a == b || a == 0 - b
  va = a.abs
  vb = b.abs
  return 0 if va < 1 || va > nv || vb < 1 || vb > nv
  vva = a > 0 ? val[va] : (0 - val[va])
  vvb = b > 0 ? val[vb] : (0 - val[vb])
  return 0 if vva > 0 || vvb > 0
  return 0 - 1 if vva < 0 && vvb < 0
  return wassat_struct_enqueue_unit(nv, val, units, q, b) if vva < 0
  return wassat_struct_enqueue_unit(nv, val, units, q, a) if vvb < 0
  x = a < b ? a : b
  y = a < b ? b : a
  key = "[x]:[y]"
  return 0 if seen_bin.has_key?(key)
  seen_bin[key] = true
  binaries.push([x, y])
  bin_adj[wassat_struct_lit_idx(0 - x)].push(y)
  bin_adj[wassat_struct_lit_idx(0 - y)].push(x)
  1

-> wassat_extract_cardinality_and_propagate(nv, formula)
  clauses = wassat_struct_clauses_of(formula)
  nl = 2 * nv + 2
  val = i8[nv + 1]
  units = []
  binaries = []
  bin_adj = []
  i = 0
  while i < nl
    bin_adj.push([])
    i += 1
  q = []
  ternaries = []
  pos_domains = []
  ci = 0
  while ci < clauses.size
    c = clauses[ci]
    if c.size == 1
      rc = wassat_struct_enqueue_unit(nv, val, units, q, c[0])
      return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": [], "chains": [] } if rc < 0
    elsif c.size == 2
      a = c[0]
      b = c[1]
      if a != 0 - b && a != b
        na = wassat_struct_lit_idx(0 - a)
        nb = wassat_struct_lit_idx(0 - b)
        bin_adj[na].push(b)
        bin_adj[nb].push(a)
        pos_domains.push(c) if a > 0 && b > 0
    elsif c.size == 3
      ternaries.push(c)
      if c[0] > 0 && c[1] > 0 && c[2] > 0
        pos_domains.push(c)
    elsif c.size >= 4 && c.size <= 8
      all_pos = true
      j = 0
      while j < c.size
        all_pos = false if c[j] < 0
        j += 1
      pos_domains.push(c) if all_pos
    ci += 1

  if wassat_struct_propagate_units(nv, val, units, q, bin_adj, ternaries) < 0
    return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": [], "chains": [] }

  eo_groups = []
  seen_eo = {}
  guarded_pos = []
  v = 0
  while v <= nv
    guarded_pos.push(nil)
    v += 1
  pos_occ = i64[nv + 1]
  neg_occ = i64[nv + 1]
  ci = 0
  while ci < clauses.size
    c = clauses[ci]
    if c.size >= 2 && c.size <= 6
      sat = false
      neg_cnt = 0
      neg_v = 0
      pos_lits = []
      j = 0
      while j < c.size
        l = c[j]
        lv = l.abs
        vv = l > 0 ? val[lv] : (0 - val[lv])
        if vv > 0
          sat = true
        elsif vv == 0
          if l > 0
            pos_occ[lv] += 1
            pos_lits.push(l)
          else
            neg_occ[lv] += 1
            neg_cnt += 1
            neg_v = lv
        j += 1
      if !sat && neg_cnt == 1 && pos_lits.size >= 2 && pos_lits.size <= 4
        guarded_pos[neg_v] = pos_lits
    ci += 1

  di = 0
  while di < pos_domains.size && eo_groups.size < 4096
    dom = pos_domains[di]
    active = []
    sat = false
    j = 0
    while j < dom.size
      l = dom[j]
      v = l.abs
      vv = l > 0 ? val[v] : (0 - val[v])
      if vv > 0
        sat = true
      elsif vv == 0
        active.push(l)
      j += 1
    if !sat && active.size == 1
      rc = wassat_struct_enqueue_unit(nv, val, units, q, active[0])
      return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": [], "chains": [] } if rc < 0
      if wassat_struct_propagate_units(nv, val, units, q, bin_adj, ternaries) < 0
        return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": [], "chains": [] }
    elsif !sat && active.size >= 2 && active.size <= 8
      is_clique = true
      a = 0
      while a < active.size && is_clique
        b = a + 1
        while b < active.size && is_clique
          is_clique = false unless wassat_struct_has_mutex(bin_adj, active[a], active[b])
          b += 1
        a += 1
      if is_clique
        key = active.join(",")
        unless seen_eo.has_key?(key)
          seen_eo[key] = true
          eo_groups.push(active)
    di += 1

  # EO-guarded domain resolution: if a 2-element EO pair (p0, p1) guards the
  # same positive tail (-p0 v t0..tk) and (-p1 v t0..tk), then (t0..tk) is an
  # implied positive domain (e.g., recovering the 22 T-word triples from the
  # 22 P-word pairs in hierarchical selector encodings).
  orig_eo_n = eo_groups.size
  gi = 0
  while gi < orig_eo_n && eo_groups.size < 4096
    grp = eo_groups[gi]
    if grp.size == 2 && grp[0] > 0 && grp[1] > 0
      t0 = guarded_pos[grp[0]]
      t1 = guarded_pos[grp[1]]
      if t0 != nil && t1 != nil && t0.size == t1.size
        same = true
        j = 0
        while j < t0.size
          same = false if t0[j] != t1[j]
          j += 1
        if same
          is_clique = true
          a = 0
          while a < t0.size && is_clique
            b = a + 1
            while b < t0.size && is_clique
              is_clique = false unless wassat_struct_has_mutex(bin_adj, t0[a], t0[b])
              b += 1
            a += 1
          if is_clique
            key = t0.join(",")
            unless seen_eo.has_key?(key)
              seen_eo[key] = true
              eo_groups.push(t0)
    gi += 1

  # Prioritize EO groups: selector / control-word EO groups (defined in small
  # positive domains pos_occ <= 8 and used negatively as guards neg_occ >= 2*pos)
  # sort to the very front so DETOUR and domain case-splits inspect them first.
  eo_scores = i64[eo_groups.size]
  gi = 0
  while gi < eo_groups.size
    grp = eo_groups[gi]
    is_sel = true
    neg_sum = 0 ## i64
    pos_sum = 0 ## i64
    j = 0
    while j < grp.size
      lv = grp[j].abs
      p = pos_occ[lv]
      n = neg_occ[lv]
      pos_sum += p
      neg_sum += n
      is_sel = false unless p >= 1 && p <= 8 && n >= 2 * p && n >= 8
      j += 1
    sc = neg_sum + pos_sum
    if is_sel
      sc += 10000000 + neg_sum * 100 + (8 - grp.size) * 10
    eo_scores[gi] = sc
    gi += 1

  a = 1
  while a < eo_groups.size
    cur_g = eo_groups[a]
    cur_s = eo_scores[a]
    b = a - 1
    while b >= 0 && eo_scores[b] < cur_s
      eo_groups[b + 1] = eo_groups[b]
      eo_scores[b + 1] = eo_scores[b]
      b -= 1
    eo_groups[b + 1] = cur_g
    eo_scores[b + 1] = cur_s
    a += 1

  seen_bin = {}
  imp_count = i64[nl]
  imp_mask = i64[nl]
  gi = 0
  while gi < eo_groups.size
    grp = eo_groups[gi]
    k = grp.size
    touched = []
    m = 0
    while m < k
      lm = grp[m]
      bit = 1 << m
      adj1 = bin_adj[wassat_struct_lit_idx(lm)]
      j = 0
      while j < adj1.size
        u = adj1[j]
        in_grp = false
        g2 = 0
        while g2 < k
          in_grp = true if grp[g2] == 0 - u || grp[g2] == u
          g2 += 1
        unless in_grp
          uidx = wassat_struct_lit_idx(u)
          old = imp_mask[uidx]
          if old == 0
            touched.push(u)
          if (old & bit) == 0
            imp_mask[uidx] = old | bit
            imp_count[uidx] = imp_count[uidx] + 1
          adj2 = bin_adj[uidx]
          j2 = 0
          while j2 < adj2.size && j2 < 16
            w = adj2[j2]
            widx = wassat_struct_lit_idx(w)
            oldw = imp_mask[widx]
            if oldw == 0
              touched.push(w)
            if (oldw & bit) == 0
              imp_mask[widx] = oldw | bit
              imp_count[widx] = imp_count[widx] + 1
            j2 += 1
        j += 1
      m += 1

    full_mask = (1 << k) - 1
    ki = 0
    while ki < touched.size
      u = touched[ki]
      uidx = wassat_struct_lit_idx(u)
      cnt = imp_count[uidx]
      msk = imp_mask[uidx]
      imp_count[uidx] = 0
      imp_mask[uidx] = 0
      if cnt == k
        rc = wassat_struct_enqueue_unit(nv, val, units, q, u)
        return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": [] } if rc < 0
      elsif cnt == k - 1 && k >= 3
        miss_mask = full_mask ^ msk
        rem_idx = 0
        while rem_idx < k && ((miss_mask >> rem_idx) & 1) == 0
          rem_idx += 1
        if rem_idx < k
          rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, grp[rem_idx], u)
          return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": [] } if rc < 0
      ki += 1
    gi += 1

  if wassat_struct_propagate_units(nv, val, units, q, bin_adj, ternaries) < 0
    return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": [] }

  chains = []
  ti = 0
  while ti < ternaries.size
    tc = ternaries[ti]
    p = 0
    while p < 3
      l_neg_a = tc[p]
      l_b = tc[(p + 1) % 3]
      l_g = tc[(p + 2) % 3]
      a = 0 - l_neg_a
      b = l_b
      if a > 0 && b > 0 && wassat_struct_has_mutex(bin_adj, 0 - a, b)
        vg = l_g > 0 ? val[l_g.abs] : (0 - val[l_g.abs])
        if vg < 0
          rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, 0 - a, b)
          return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
        chains.push([a, b, l_g]) if chains.size < 2048
      p += 1
    ti += 1

  # Multi-step monotone ladder-chain extraction & 64-bit cut-mask projection:
  # Extract chains x_0 <- x_1 <- ... <- x_{L-1} from binary clauses (x_r v -x_{r+1}),
  # map clauses with <= 1 external guard onto the (L+1)-bit cut space, and project
  # transitive chain-cut units and binary clauses across the ladder.
  next_in_chain = i64[nv + 1]
  prev_in_chain = i64[nv + 1]
  has_out_edge = i8[nv + 1]
  ci = 0
  while ci < clauses.size
    c = clauses[ci]
    if c.size == 2
      a = c[0]
      b = c[1]
      if val[a.abs] == 0 && val[b.abs] == 0
        if a > 0 && b < 0
          has_out_edge[a] = 1
        elsif b > 0 && a < 0
          has_out_edge[b] = 1
    ci += 1

  ci = 0
  while ci < clauses.size
    c = clauses[ci]
    if c.size == 2
      a = c[0]
      b = c[1]
      if val[a.abs] == 0 && val[b.abs] == 0
        u = 0
        w = 0
        if a > 0 && b < 0
          u = a
          w = 0 - b
        elsif b > 0 && a < 0
          u = b
          w = 0 - a
        if u > 0 && w > 0
          cur_w = next_in_chain[u]
          if cur_w == 0 || (has_out_edge[cur_w] == 0 && has_out_edge[w] == 1)
            prev_in_chain[cur_w] = 0 if cur_w > 0 && prev_in_chain[cur_w] == u
            next_in_chain[u] = w
            prev_in_chain[w] = u if prev_in_chain[w] == 0
    ci += 1

  ladder_chains = []
  var_chain = i64[nv + 1]
  var_pos = i64[nv + 1]
  visited_ch = i8[nv + 1]
  v = 1
  while v <= nv && ladder_chains.size < 2048
    if next_in_chain[v] > 0 && prev_in_chain[v] == 0 && visited_ch[v] == 0
      ch = [v]
      visited_ch[v] = 1
      cur = v
      while next_in_chain[cur] > 0 && visited_ch[next_in_chain[cur]] == 0 && ch.size < 60
        cur = next_in_chain[cur]
        visited_ch[cur] = 1
        ch.push(cur)
      if ch.size >= 3
        cid = ladder_chains.size
        ladder_chains.push(ch)
        idx = 0
        while idx < ch.size
          cv = ch[idx]
          var_chain[cv] = cid + 1
          var_pos[cv] = idx
          idx += 1
    v += 1

  if !ladder_chains.empty?
    nch = ladder_chains.size
    chain_allowed = i64[nch]
    chain_ext_lits = []
    chain_ext_masks = []
    cid = 0
    while cid < nch
      l_len = ladder_chains[cid].size
      chain_allowed[cid] = (1 << (l_len + 1)) - 1
      chain_ext_lits.push([])
      chain_ext_masks.push([])
      cid += 1

    ci = 0
    while ci < clauses.size
      c = clauses[ci]
      if c.size >= 2 && c.size <= 5
        sat = false
        ch_lits = []
        ext_lit = 0
        ext_cnt = 0
        target_cid = 0 - 1
        multi_cid = false
        j = 0
        while j < c.size && !sat && !multi_cid && ext_cnt <= 1
          l = c[j]
          lv = l.abs
          vv = l > 0 ? val[lv] : (0 - val[lv])
          if vv > 0
            sat = true
          elsif vv == 0
            vc = var_chain[lv] - 1
            if vc >= 0
              if target_cid < 0
                target_cid = vc
              elsif target_cid != vc
                multi_cid = true
              ch_lits.push(l)
            else
              ext_lit = l
              ext_cnt += 1
          j += 1
        if !sat && !multi_cid && target_cid >= 0 && !ch_lits.empty? && ext_cnt <= 1
          l_len = ladder_chains[target_cid].size
          bad = 0 ## i64
          cut = 0
          while cut <= l_len
            all_false = true
            k = 0
            while k < ch_lits.size && all_false
              cl = ch_lits[k]
              r = var_pos[cl.abs]
              v_true = r < cut
              l_true = cl > 0 ? v_true : !v_true
              all_false = false if l_true
              k += 1
            bad = bad | (1 << cut) if all_false
            cut += 1
          if bad != 0
            if ext_cnt == 0
              chain_allowed[target_cid] = chain_allowed[target_cid] & (0 - 1 - bad)
            else
              u = 0 - ext_lit
              elits = chain_ext_lits[target_cid]
              emasks = chain_ext_masks[target_cid]
              found_idx = 0 - 1
              k = 0
              while k < elits.size
                if elits[k] == u
                  found_idx = k
                  k = elits.size
                else
                  k += 1
              if found_idx >= 0
                emasks[found_idx] = emasks[found_idx] | bad
              elsif elits.size < 64
                elits.push(u)
                emasks.push(bad)
      ci += 1

    cid = 0
    while cid < nch
      ch = ladder_chains[cid]
      l_len = ch.size
      allow = chain_allowed[cid]
      return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if allow == 0
      cut = 0
      while cut <= l_len
        if ((allow >> cut) & 1) == 0
          if cut == 0
            rc = wassat_struct_enqueue_unit(nv, val, units, q, ch[0])
            return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
          elsif cut == l_len
            rc = wassat_struct_enqueue_unit(nv, val, units, q, 0 - ch[l_len - 1])
            return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
          elsif binaries.size < 16384
            rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, 0 - ch[cut - 1], ch[cut])
            return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
        cut += 1
      elits = chain_ext_lits[cid]
      emasks = chain_ext_masks[cid]
      i1 = 0
      while i1 < elits.size
        u1 = elits[i1]
        m1 = emasks[i1]
        rem1 = allow & (0 - 1 - m1)
        if rem1 == 0
          rc = wassat_struct_enqueue_unit(nv, val, units, q, 0 - u1)
          return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
        elsif binaries.size < 16384
          if (rem1 & 1) == 0
            rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, 0 - u1, ch[0])
            return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
          if ((rem1 >> l_len) & 1) == 0
            rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, 0 - u1, 0 - ch[l_len - 1])
            return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
          i2 = i1 + 1
          while i2 < elits.size && binaries.size < 16384
            u2 = elits[i2]
            m2 = emasks[i2]
            if (rem1 & (0 - 1 - m2)) == 0 && u1.abs != u2.abs
              rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, 0 - u1, 0 - u2)
              return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
            i2 += 1
        i1 += 1
      # Direct flat shortcut binaries along the monotone chain (tail => head
      # and midpoint jumps) so CDCL BCP and 1-UIP conflict analysis jump across
      # the chain in 1-2 hops instead of resolving through all L intermediates.
      if l_len >= 4 && binaries.size < 16384
        rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, ch[0], 0 - ch[l_len - 1])
        return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
        if l_len >= 8 && binaries.size < 16384
          mid = l_len / 2
          rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, ch[0], 0 - ch[mid])
          return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
          rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, ch[mid], 0 - ch[l_len - 1])
          return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
      cid += 1

  # Clause strengthening where one literal implies another (either via a
  # flat monotone chain x_r => x_s for r > s, or via binary implications):
  # in (a v b v R), if a => b then a is redundant and can be dropped.
  ci = 0
  while ci < clauses.size && binaries.size < 16384
    c = clauses[ci]
    if c.size >= 3 && c.size <= 5
      sat = false
      rem = []
      j = 0
      while j < c.size && !sat
        l = c[j]
        vv = l > 0 ? val[l.abs] : (0 - val[l.abs])
        if vv > 0
          sat = true
        elsif vv == 0
          rem.push(l)
        j += 1
      if !sat && rem.size >= 2 && rem.size <= 4
        # Check if any literal in `rem` implies another surviving literal in `rem`
        kept = []
        dropped = i8[rem.size]
        subsumed = false
        i1 = 0
        while i1 < rem.size && !subsumed
          a = rem[i1]
          va = a.abs
          ca = var_chain[va]
          pa = var_pos[va]
          a_idx = wassat_struct_lit_idx(a)
          adj = bin_adj[a_idx]
          drop_a = false
          i2 = 0
          while i2 < rem.size && !drop_a && !subsumed
            if i1 != i2 && dropped[i2] == 0
              b = rem[i2]
              vb = b.abs
              cb = var_chain[vb]
              pb = var_pos[vb]
              if ca > 0 && ca == cb
                if (a > 0 && b > 0 && pa > pb) || (a < 0 && b < 0 && pa < pb)
                  drop_a = true
                elsif (a > 0 && b < 0 && pa <= pb) || (a < 0 && b > 0 && pa >= pb)
                  subsumed = true
              unless drop_a || subsumed
                k = 0
                while k < adj.size
                  if adj[k] == b
                    drop_a = true
                    k = adj.size
                  else
                    k += 1
            i2 += 1
          if drop_a
            dropped[i1] = 1
          else
            kept.push(a)
          i1 += 1
        if !subsumed && kept.size < rem.size
          if kept.size == 1
            rc = wassat_struct_enqueue_unit(nv, val, units, q, kept[0])
            return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
          elsif kept.size == 2 && binaries.size < 16384
            rc = wassat_struct_add_binary(nv, val, units, q, binaries, bin_adj, seen_bin, kept[0], kept[1])
            return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains } if rc < 0
    ci += 1

  if wassat_struct_propagate_units(nv, val, units, q, bin_adj, ternaries) < 0
    return { "unsat": true, "units": units, "binaries": binaries, "eo_groups": eo_groups, "chains": chains }
  {
    "unsat": false, "units": units, "binaries": binaries,
    "eo_groups": eo_groups, "chains": chains, "val": val,
    "ladder_chains": ladder_chains, "var_chain": var_chain, "var_pos": var_pos
  }

# ---- 3. DETOUR Bidirectional Wavefront & Macro-Transition Pruning -----------

-> wassat_struct_trial_propagate(base_val, tval, trail, pos_occ, neg_occ, short_clauses, assump, ladder_chains = nil, var_chain = nil, var_pos = nil)
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
    # Single-hop flat monotone chain propagation:
    #   +x_r => (x_{r-1} .. x_0) and -x_r => (-x_{r+1} .. -x_{L-1})
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
            # Already +1; earlier prefix is already +1 as well
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
            # Already -1; later suffix is already -1 as well
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
  out_lits = []
  i = 0
  while i < ts
    l = trail[i]
    out_lits.push(l) if ok == 1
    tval[l.abs] = 0
    i += 1
  [ok, ts, out_lits]

-> wassat_detour_prune(nv, formula, card_info = nil)
  cinfo = card_info == nil ? wassat_extract_cardinality_and_propagate(nv, formula) : card_info
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
  var_chain = cinfo["var_chain"]
  var_pos = cinfo["var_pos"]
  clauses = wassat_struct_clauses_of(formula)

  layers = []
  if eo_groups.size >= 2
    i = 0
    while i < eo_groups.size && layers.size < 32
      layers.push(eo_groups[i]) if eo_groups[i].size >= 2 && eo_groups[i].size <= 6
      i += 1
  if layers.size < 2
    ctrl = wassat_identify_control_vars(nv, formula, 16)["control_vars"]
    i = 0
    while i < ctrl.size && layers.size < 16
      v = ctrl[i]
      if cinfo["val"][v] == 0
        layers.push([v, 0 - v])
      i += 1

  return { "unsat": false, "units": units, "binaries": binaries, "witness_phases": [] } if layers.size < 2

  short_clauses = []
  pos_occ = []
  neg_occ = []
  v = 0
  while v <= nv
    pos_occ.push([])
    neg_occ.push([])
    v += 1
  ci = 0
  while ci < clauses.size
    c = clauses[ci]
    if c.size >= 2 && c.size <= 4
      idx = short_clauses.size
      short_clauses.push(c)
      j = 0
      while j < c.size
        l = c[j]
        lv = l.abs
        if lv >= 1 && lv <= nv
          if l > 0
            pos_occ[lv].push(idx)
          else
            neg_occ[lv].push(idx)
        j += 1
    ci += 1
  bi = 0
  while bi < binaries.size
    b = binaries[bi]
    idx = short_clauses.size
    short_clauses.push(b)
    j = 0
    while j < 2
      l = b[j]
      lv = l.abs
      if lv >= 1 && lv <= nv
        if l > 0
          pos_occ[lv].push(idx)
        else
          neg_occ[lv].push(idx)
      j += 1
    bi += 1

  base_val = cinfo["val"]
  tval = i8[nv + 1]
  trail = i64[nv + 1]

  m_layers = layers.size
  alive = []
  state_implied = []
  r = 0
  while r < m_layers
    grp = layers[r]
    ralive = []
    rimp = []
    s = 0
    while s < grp.size
      lit = grp[s]
      res = wassat_struct_trial_propagate(base_val, tval, trail, pos_occ, neg_occ, short_clauses, [lit], ladder_chains, var_chain, var_pos)
      if res[0] == 1
        ralive.push(1)
        rimp.push(res[2])
      else
        ralive.push(0)
        rimp.push([])
        units.push(0 - lit)
        lv = lit.abs
        base_val[lv] = lit > 0 ? -1 : 1
      s += 1
    alive.push(ralive)
    state_implied.push(rimp)
    r += 1

  trans = []
  r = 0
  while r < m_layers - 1
    g1 = layers[r]
    g2 = layers[r + 1]
    rmat = []
    s1 = 0
    while s1 < g1.size
      row = []
      s2 = 0
      while s2 < g2.size
        if alive[r][s1] == 1 && alive[r + 1][s2] == 1
          res = wassat_struct_trial_propagate(base_val, tval, trail, pos_occ, neg_occ, short_clauses, [g1[s1], g2[s2]], ladder_chains, var_chain, var_pos)
          row.push(res[0] == 1 ? (1 + res[1]) : 0)
        else
          row.push(0)
        s2 += 1
      rmat.push(row)
      s1 += 1
    trans.push(rmat)
    r += 1

  r = 0
  while r < m_layers - 2
    g1 = layers[r]
    g2 = layers[r + 1]
    g3 = layers[r + 2]
    s1 = 0
    while s1 < g1.size
      if alive[r][s1] == 1
        s2 = 0
        while s2 < g2.size
          if trans[r][s1][s2] > 0
            macro_ok = false
            s3 = 0
            while s3 < g3.size && !macro_ok
              if trans[r + 1][s2][s3] > 0
                res = wassat_struct_trial_propagate(base_val, tval, trail, pos_occ, neg_occ, short_clauses, [g1[s1], g2[s2], g3[s3]], ladder_chains, var_chain, var_pos)
                macro_ok = true if res[0] == 1
              s3 += 1
            if !macro_ok
              trans[r][s1][s2] = 0
              binaries.push([0 - g1[s1], 0 - g2[s2]])
          s2 += 1
      s1 += 1
    r += 1

  fwd_cost = []
  fwd_parent = []
  bwd_ok = []
  r = 0
  while r < m_layers
    g = layers[r]
    fc = []
    fp = []
    bo = []
    s = 0
    while s < g.size
      fc.push(r == 0 && alive[0][s] == 1 ? 1 : 0)
      fp.push(0 - 1)
      bo.push(r == m_layers - 1 && alive[r][s] == 1 ? 1 : 0)
      s += 1
    fwd_cost.push(fc)
    fwd_parent.push(fp)
    bwd_ok.push(bo)
    r += 1

  r = 0
  while r < m_layers - 1
    g1 = layers[r]
    g2 = layers[r + 1]
    s1 = 0
    while s1 < g1.size
      c1 = fwd_cost[r][s1]
      if c1 > 0
        s2 = 0
        while s2 < g2.size
          step_c = trans[r][s1][s2]
          if step_c > 0
            nc = c1 + step_c
            if fwd_cost[r + 1][s2] == 0 || nc < fwd_cost[r + 1][s2]
              fwd_cost[r + 1][s2] = nc
              fwd_parent[r + 1][s2] = s1
          s2 += 1
      s1 += 1
    r += 1

  r = m_layers - 2
  while r >= 0
    g1 = layers[r]
    g2 = layers[r + 1]
    s1 = 0
    while s1 < g1.size
      if fwd_cost[r][s1] > 0
        ok_bwd = 0
        s2 = 0
        while s2 < g2.size
          if trans[r][s1][s2] > 0 && bwd_ok[r + 1][s2] == 1
            ok_bwd = 1
          s2 += 1
        bwd_ok[r][s1] = ok_bwd
      s1 += 1
    r -= 1

  r = 0
  while r < m_layers
    g = layers[r]
    surviving = []
    s = 0
    while s < g.size
      if fwd_cost[r][s] > 0 && bwd_ok[r][s] == 1
        surviving.push(s)
      elsif alive[r][s] == 1
        alive[r][s] = 0
        units.push(0 - g[s])
      s += 1
    if surviving.empty?
      return { "unsat": true, "units": units, "binaries": binaries, "witness_phases": [] }
    if surviving.size == 1
      sole_lit = g[surviving[0]]
      units.push(sole_lit)
      state_implied[r][surviving[0]].each -> (imp_l)
        units.push(imp_l)
    else
      first_imps = state_implied[r][surviving[0]]
      fi = 0
      while fi < first_imps.size
        cand = first_imps[fi]
        all_have = true
        si = 1
        while si < surviving.size && all_have
          imps2 = state_implied[r][surviving[si]]
          found = false
          k = 0
          while k < imps2.size && !found
            found = true if imps2[k] == cand
            k += 1
          all_have = false unless found
          si += 1
        units.push(cand) if all_have
        fi += 1
    r += 1

  best_end = 0 - 1
  best_val = 0
  g_last = layers[m_layers - 1]
  s = 0
  while s < g_last.size
    if fwd_cost[m_layers - 1][s] > 0 && bwd_ok[m_layers - 1][s] == 1
      if best_end < 0 || fwd_cost[m_layers - 1][s] < best_val
        best_end = s
        best_val = fwd_cost[m_layers - 1][s]
    s += 1

  witness_phases = []
  if best_end >= 0
    cur = best_end
    r = m_layers - 1
    while r >= 0 && cur >= 0
      witness_phases.push(layers[r][cur])
      state_implied[r][cur].each -> (imp_l)
        witness_phases.push(imp_l)
      cur = fwd_parent[r][cur]
      r -= 1

  { "unsat": false, "units": units, "binaries": binaries, "witness_phases": witness_phases }

# ---- 4. Clue / Sudoku Bitmask Truth-Table Pruning ---------------------------

-> wassat_truth_table_prune(nv, formula, max_tables = 256)
  clauses = wassat_struct_clauses_of(formula)
  val = i8[nv + 1]
  units = []
  binaries = []
  seen_bin = {}

  clusters = []
  cluster_map = {}
  small_clauses = []

  ci = 0
  while ci < clauses.size
    c = clauses[ci]
    if c.size == 1
      l = c[0]
      v = l.abs
      if v >= 1 && v <= nv
        pol = l > 0 ? 1 : -1
        return { "unsat": true, "units": units, "binaries": binaries, "phase_hints": [] } if val[v] == 0 - pol
        if val[v] == 0
          val[v] = pol
          units.push(l)
    elsif c.size >= 2 && c.size <= 6
      small_clauses.push(c)
      if c.size >= 3 && clusters.size < max_tables
        vars = []
        j = 0
        while j < c.size
          v = c[j].abs
          if v >= 1 && v <= nv
            dup = false
            k = 0
            while k < vars.size
              dup = true if vars[k] == v
              k += 1
            vars.push(v) unless dup
          j += 1
        if vars.size >= 3 && vars.size <= 6
          a = 1
          while a < vars.size
            x = vars[a]
            b = a - 1
            while b >= 0 && vars[b] > x
              vars[b + 1] = vars[b]
              b -= 1
            vars[b + 1] = x
            a += 1
          key = vars.join(",")
          unless cluster_map.has_key?(key)
            cluster_map[key] = clusters.size
            clusters.push(vars)
    ci += 1

  if clusters.size < 16 && small_clauses.size >= 2
    vars = []
    ci = 0
    while ci < small_clauses.size && clusters.size < 32
      c = small_clauses[ci]
      j = 0
      while j < c.size
        v = c[j].abs
        if v >= 1 && v <= nv
          dup = false
          k = 0
          while k < vars.size
            dup = true if vars[k] == v
            k += 1
          vars.push(v) unless dup
        j += 1
      if vars.size >= 4
        chunk = vars.slice(0, vars.size > 6 ? 6 : vars.size)
        clusters.push(chunk)
        vars = []
      ci += 1
    clusters.push(vars) if vars.size >= 2 && vars.size <= 6

  return { "unsat": false, "units": units, "binaries": binaries, "phase_hints": [] } if clusters.empty?

  var_tables = []
  v = 0
  while v <= nv
    var_tables.push([])
    v += 1
  ti = 0
  while ti < clusters.size
    vars = clusters[ti]
    j = 0
    while j < vars.size
      var_tables[vars[j]].push(ti)
      j += 1
    ti += 1

  table_masks = i64[clusters.size]
  ti = 0
  while ti < clusters.size
    k = clusters[ti].size
    table_masks[ti] = k == 6 ? -1 : ((1 << (1 << k)) - 1)
    ti += 1

  ci = 0
  while ci < small_clauses.size
    c = small_clauses[ci]
    v0 = c[0].abs
    cand_tables = var_tables[v0]
    ct = 0
    while ct < cand_tables.size
      ti = cand_tables[ct]
      tvars = clusters[ti]
      all_in = true
      pos_req = 0 ## i64
      neg_req = 0 ## i64
      taut = false
      j = 0
      while j < c.size && all_in
        l = c[j]
        lv = l.abs
        bit_idx = 0 - 1
        m = 0
        while m < tvars.size
          if tvars[m] == lv
            bit_idx = m
            m = tvars.size
          else
            m += 1
        if bit_idx < 0
          all_in = false
        else
          if l > 0
            taut = true if ((pos_req >> bit_idx) & 1) == 1
            neg_req = neg_req | (1 << bit_idx)
          else
            taut = true if ((neg_req >> bit_idx) & 1) == 1
            pos_req = pos_req | (1 << bit_idx)
        j += 1
      if all_in && !taut
        k = tvars.size
        nrows = 1 << k
        row = 0
        fmask = table_masks[ti]
        while row < nrows
          if (row & pos_req) == pos_req && (row & neg_req) == 0
            fmask = fmask & (0 - 1 - (1 << row))
          row += 1
        table_masks[ti] = fmask
      ct += 1
    ci += 1

  changed = true
  rounds = 0
  while changed && rounds < 8
    changed = false
    rounds += 1
    ti = 0
    while ti < clusters.size
      tvars = clusters[ti]
      k = tvars.size
      nrows = 1 << k
      mask = table_masks[ti]

      m = 0
      while m < k
        vv = val[tvars[m]]
        if vv != 0
          row = 0
          while row < nrows
            bit = (row >> m) & 1
            if (vv > 0 && bit == 0) || (vv < 0 && bit == 1)
              mask = mask & (0 - 1 - (1 << row))
            row += 1
        m += 1
      table_masks[ti] = mask
      return { "unsat": true, "units": units, "binaries": binaries, "phase_hints": [] } if mask == 0

      always_one = (1 << k) - 1
      always_zero = (1 << k) - 1
      row = 0
      while row < nrows
        if ((mask >> row) & 1) != 0
          always_one = always_one & row
          always_zero = always_zero & (((1 << k) - 1) ^ row)
        row += 1

      m = 0
      while m < k
        v = tvars[m]
        if ((always_one >> m) & 1) == 1 && val[v] == 0
          val[v] = 1
          units.push(v)
          changed = true
        elsif ((always_zero >> m) & 1) == 1 && val[v] == 0
          val[v] = -1
          units.push(0 - v)
          changed = true
        m += 1

      if rounds == 1 && binaries.size < 2048
        m1 = 0
        while m1 < k
          v1 = tvars[m1]
          if val[v1] == 0
            m2 = m1 + 1
            while m2 < k
              v2 = tvars[m2]
              if val[v2] == 0
                quad = 0
                row = 0
                while row < nrows && quad != 15
                  if ((mask >> row) & 1) != 0
                    b1 = (row >> m1) & 1
                    b2 = (row >> m2) & 1
                    quad = quad | (1 << ((b1 << 1) | b2))
                  row += 1
                cands = []
                cands.push([v1, v2]) if (quad & 1) == 0
                cands.push([v1, 0 - v2]) if (quad & 2) == 0
                cands.push([0 - v1, v2]) if (quad & 4) == 0
                cands.push([0 - v1, 0 - v2]) if (quad & 8) == 0
                ci2 = 0
                while ci2 < cands.size
                  pair = cands[ci2]
                  a = pair[0] < pair[1] ? pair[0] : pair[1]
                  b = pair[0] < pair[1] ? pair[1] : pair[0]
                  bkey = "[a]:[b]"
                  unless seen_bin.has_key?(bkey)
                    seen_bin[bkey] = true
                    binaries.push([a, b])
                  ci2 += 1
              m2 += 1
          m1 += 1
      ti += 1

  phase_hints = []
  seen_hint = i8[nv + 1]
  ti = 0
  while ti < clusters.size
    tvars = clusters[ti]
    k = tvars.size
    nrows = 1 << k
    mask = table_masks[ti]
    m = 0
    while m < k
      v = tvars[m]
      if seen_hint[v] == 0
        seen_hint[v] = 1
        ones = 0
        zeros = 0
        row = 0
        while row < nrows
          if ((mask >> row) & 1) != 0
            if ((row >> m) & 1) == 1
              ones += 1
            else
              zeros += 1
          row += 1
        if ones > 0 || zeros > 0
          phase_hints.push(ones >= zeros ? v : (0 - v))
      m += 1
    ti += 1

  { "unsat": false, "units": units, "binaries": binaries, "phase_hints": phase_hints }

# ---- 5. Combined Structural Pruning Coordinator ----------------------------

-> wassat_structural_prune(nv, formula)
  if nv <= 0 || formula["flat_ncl"] != nil && formula["flat_ncl"] > 1000000
    return {
      "unsat": false, "units": [], "binaries": [],
      "control_vars": [], "detour_phases": [], "tt_phases": []
    }
  ctrl = wassat_identify_control_vars(nv, formula, 64)
  card = wassat_extract_cardinality_and_propagate(nv, formula)
  if card["unsat"]
    return {
      "unsat": true, "units": card["units"], "binaries": card["binaries"],
      "control_vars": ctrl["control_vars"], "detour_phases": [], "tt_phases": []
    }
  det = wassat_detour_prune(nv, formula, card)
  if det["unsat"]
    return {
      "unsat": true, "units": det["units"], "binaries": det["binaries"],
      "control_vars": ctrl["control_vars"], "detour_phases": [], "tt_phases": []
    }
  tt = wassat_truth_table_prune(nv, formula, 128)
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

  seen_b = {}
  merged_bins = []
  db = det["binaries"]
  i = 0
  while i < db.size
    pair = db[i]
    a = pair[0] < pair[1] ? pair[0] : pair[1]
    b = pair[0] < pair[1] ? pair[1] : pair[0]
    if a != b && a != 0 - b && merged_bins.size < 16384
      key = "[a]:[b]"
      unless seen_b.has_key?(key)
        seen_b[key] = true
        merged_bins.push([a, b])
    i += 1
  tb = tt["binaries"]
  i = 0
  while i < tb.size
    pair = tb[i]
    a = pair[0] < pair[1] ? pair[0] : pair[1]
    b = pair[0] < pair[1] ? pair[1] : pair[0]
    if a != b && a != 0 - b && merged_bins.size < 16384
      key = "[a]:[b]"
      unless seen_b.has_key?(key)
        seen_b[key] = true
        merged_bins.push([a, b])
    i += 1

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
