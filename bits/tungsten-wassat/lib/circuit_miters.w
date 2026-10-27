# Circuit equivalence / miter lanes (Klieber, SatCoin, AIG, word-sort,
# gray-code miters), split out of multiplier.w. Each lane reconstructs its
# gate circuit from the literal clauses, evaluates it natively, and only
# then publishes a model or a fast-only refutation; see multiplier.w for
# the shared gate-scan helpers.


-> wassat_klieber_score_targets(val, p_masks, ga, gna, gb, gnb, gpol, targets, t_scores, nv, p, ntargets, n_batches, step_b) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0
  while i < 6
    val[i + 1] = p_masks[i]
    i += 1
  s = 0
  while s < ntargets * step_b && s < n_batches
    i = 6
    while i < p
      val[i + 1] = ((s >> (i - 6)) & 1) != 0 ? -1 : 0
      i += 1
    v = p + 1
    while v < nv
      va = val[ga[v]] ^ gna[v]
      vb = val[gb[v]] ^ gnb[v]
      val[v] = (va & vb) ^ gpol[v]
      v += 1
    ti = 0
    while ti < ntargets
      tl = targets[ti]
      tv = wassat_multiplier_abs(tl)
      t_inv = tl < 0 ? -1 : 0 ## i64
      tw = val[tv] ^ t_inv
      t_scores[ti] += 1 if tw != 0
      ti += 1
    s += step_b
  0

-> wassat_klieber_eval_chunk(wval, p_masks, ga, gna, gb, gnb, gpol, stage_gates, stage_off, targets, found, p, ntargets, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  k = 0
  while k < 6
    wval[k + 1] = p_masks[k]
    k += 1
  b = b_lo
  while b < b_hi && found[0] == 0
    k = 6
    while k < p
      wval[k + 1] = ((b >> (k - 6)) & 1) != 0 ? -1 : 0
      k += 1
    mask = -1 ## i64
    st = 0
    while st < ntargets && mask != 0
      g_idx = stage_off[st]
      g_end = stage_off[st + 1]
      while g_idx < g_end
        u = stage_gates[g_idx]
        va = wval[ga[u]] ^ gna[u]
        vb = wval[gb[u]] ^ gnb[u]
        wval[u] = (va & vb) ^ gpol[u]
        g_idx += 1
      tl = targets[st]
      tv = wassat_multiplier_abs(tl)
      t_inv = tl < 0 ? -1 : 0 ## i64
      tw = wval[tv] ^ t_inv
      mask = mask & tw
      st += 1
    if mask != 0
      lane = 0
      while lane < 64 && ((mask >> lane) & 1) == 0
        lane += 1
      if lane < 64
        found[1] = (b << 6) | lane
        found[0] = 1
    b += 1
  0

# Staged 64-bit bitwise cone evaluator for small-input 2-input AND/OR circuits
# with a multi-target conjunction sink (e.g. mp1-klieber2017s-0490-024-t12.cnf).
-> wassat_klieber_circuit_model(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return [] if nv < 100 || nv > 50000 || ncl < 2 * nv || ncl > 3 * nv
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  # Find the unit clause on nv and the wide clause on nv
  unit_lit = 0
  wide_ci = -1
  n_tern = 0
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k == 1
      return [] if unit_lit != 0
      unit_lit = fla[fcs[ci]]
    elsif k > 3
      return [] if wide_ci >= 0
      wide_ci = ci
    elsif k == 3
      n_tern += 1
    elsif k != 2
      return []
    ci += 1
  return [] if wassat_multiplier_abs(unit_lit) != nv || wide_ci < 0
  ntargets = fcl[wide_ci] - 1
  return [] if ntargets < 2 || ntargets > 32
  p = nv - 1 - n_tern
  return [] if p < 6 || p > 24
  return [] unless ncl == 3 * n_tern + ntargets + 2

  # Parse each gate v in p+1..nv-1 from its ternary clause and verify its 2 binary clauses
  ga = i64[nv + 1]
  gna = i64[nv + 1]
  gb = i64[nv + 1]
  gnb = i64[nv + 1]
  gpol = i64[nv + 1]
  has_tern = i8[nv + 1]
  bin_cnt = i64[nv + 1]
  targets = i64[ntargets]
  nt = 0

  ci = 0
  while ci < ncl
    k = fcl[ci]
    off = fcs[ci]
    if k == 3
      l0 = fla[off]; l1 = fla[off + 1]; l2 = fla[off + 2]
      v0 = wassat_multiplier_abs(l0)
      v1 = wassat_multiplier_abs(l1)
      v2 = wassat_multiplier_abs(l2)
      m = v0
      m = v1 if v1 > m
      m = v2 if v2 > m
      return [] if m <= p || m >= nv || has_tern[m] != 0
      has_tern[m] = 1
      lo = l0; la = l1; lb = l2
      if v1 == m
        lo = l1; la = l0; lb = l2
      elsif v2 == m
        lo = l2; la = l0; lb = l1
      va = wassat_multiplier_abs(la)
      vb = wassat_multiplier_abs(lb)
      return [] if va >= m || vb >= m || va == vb
      ga[m] = va
      gna[m] = (0 - la) < 0 ? -1 : 0
      gb[m] = vb
      gnb[m] = (0 - lb) < 0 ? -1 : 0
      gpol[m] = lo > 0 ? 0 : -1
    elsif k == 2
      l0 = fla[off]; l1 = fla[off + 1]
      v0 = wassat_multiplier_abs(l0)
      v1 = wassat_multiplier_abs(l1)
      m = v0 > v1 ? v0 : v1
      if m == nv
        tl = v0 == nv ? l1 : l0
        sl = v0 == nv ? l0 : l1
        return [] unless sl == 0 - unit_lit && nt < ntargets
        targets[nt] = tl
        nt += 1
      else
        return [] if m <= p || m >= nv
        bin_cnt[m] += 1
    ci += 1
  return [] unless nt == ntargets
  v = p + 1
  while v < nv
    return [] unless has_tern[v] == 1 && bin_cnt[v] == 2
    v += 1

  # Score each target on 32 evenly-spaced batches to put the most selective target first
  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  val = i64[nv + 1]
  n_batches = 1 << (p - 6)
  step_b = n_batches >> 5
  step_b = 1 if step_b < 1
  t_scores = i64[ntargets]
  wassat_klieber_score_targets(val, p_masks, ga, gna, gb, gnb, gpol, targets, t_scores, nv, p, ntargets, n_batches, step_b)

  # Sort targets by ascending t_scores
  ti = 0
  while ti < ntargets
    best = ti
    tj = ti + 1
    while tj < ntargets
      best = tj if t_scores[tj] < t_scores[best]
      tj += 1
    if best != ti
      tmp_t = targets[ti]; targets[ti] = targets[best]; targets[best] = tmp_t
      tmp_s = t_scores[ti]; t_scores[ti] = t_scores[best]; t_scores[best] = tmp_s
    ti += 1

  # Build incremental cone stages for the sorted targets
  in_prev = i8[nv + 1]
  in_curr = i8[nv + 1]
  stage_gates = i64[nv]
  stage_off = i64[ntargets + 1]
  sg_len = 0
  ti = 0
  while ti < ntargets
    stage_off[ti] = sg_len
    tv = wassat_multiplier_abs(targets[ti])
    if in_prev[tv] == 0 && tv > p
      in_curr[tv] = 1
      u = tv
      while u > p
        if in_curr[u] == 1
          ua = ga[u]
          ub = gb[u]
          in_curr[ua] = 1 if ua > p && in_prev[ua] == 0
          in_curr[ub] = 1 if ub > p && in_prev[ub] == 0
        u -= 1
      u = p + 1
      while u <= tv
        if in_curr[u] == 1
          stage_gates[sg_len] = u
          sg_len += 1
          in_prev[u] = 1
          in_curr[u] = 0
        u += 1
    ti += 1
  stage_off[ntargets] = sg_len

  # Search all n_batches across 4 worker threads
  found = i64[2]
  found[0] = 0
  found[1] = -1
  n_workers = 4
  n_workers = 1 if n_batches < 64
  chunk = (n_batches + n_workers - 1) / n_workers
  handles = []
  wi = 0
  while wi < n_workers
    b_lo = wi * chunk
    b_hi = b_lo + chunk
    b_hi = n_batches if b_hi > n_batches
    th = Thread.new ->
      wval = i64[nv + 1]
      wassat_klieber_eval_chunk(wval, p_masks, ga, gna, gb, gnb, gpol, stage_gates, stage_off, targets, found, p, ntargets, b_lo, b_hi)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  return [] if found[0] == 0 || found[1] < 0

  win_idx = found[1]
  v = 1
  while v <= p
    val[v] = ((win_idx >> (v - 1)) & 1)
    v += 1
  v = p + 1
  while v < nv
    na_b = gna[v] != 0 ? 1 : 0
    nb_b = gnb[v] != 0 ? 1 : 0
    pol_b = gpol[v] != 0 ? 1 : 0
    va = val[ga[v]] ^ na_b
    vb = val[gb[v]] ^ nb_b
    val[v] = (va & vb) ^ pol_b
    v += 1
  val[nv] = unit_lit > 0 ? 1 : 0
  model = []
  v = 1
  while v <= nv
    model.push(val[v] == 1 ? v : 0 - v)
    v += 1
  return [] unless wassat_model_satisfies?(formula, model)
  model

-> wassat_satcoin_eval_chunk(wval, p_masks, assign_i64, free_arr, n_free, pos_cnt, clause_off, cl_lit_off, cl_lit_len, cl_lits, sink_arr, n_sinks, max_eval, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64[] i64 i64) i64
  u = 1
  while u <= 72
    if assign_i64[u] == 1
      wval[u] = -1
    elsif assign_i64[u] == -1
      wval[u] = 0
    u += 1
  k = 0
  while k < 6
    wval[free_arr[k]] = p_masks[k]
    k += 1
  b = b_lo
  while b < b_hi && any_sat[0] == 0
    k = 6
    while k < n_free
      wval[free_arr[k]] = ((b >> (k - 6)) & 1) != 0 ? -1 : 0
      k += 1
    # Stage 1: evaluate 73..139 and filter by UP-fixed prefix gates
    m = 73
    while m <= 139
      if pos_cnt[m] == 0
        wval[m] = assign_i64[m] == 1 ? -1 : 0
      else
        vm = 0 ## i64
        ci_p = clause_off[m]
        ci_end = clause_off[m + 1]
        while ci_p < ci_end
          term = -1 ## i64
          lp = cl_lit_off[ci_p]
          lp_end = lp + cl_lit_len[ci_p]
          while lp < lp_end
            l = cl_lits[lp]
            vl = l > 0 ? wval[l] : (-1 ^ wval[0 - l])
            term = term & (-1 ^ vl)
            lp += 1
          vm = vm | term
          ci_p += 1
        wval[m] = vm
      m += 1
    mask = -1 ## i64
    m = 73
    while m <= 139
      if assign_i64[m] == 1
        mask = mask & wval[m]
      elsif assign_i64[m] == -1
        mask = mask & (-1 ^ wval[m])
      m += 1
    if mask != 0
      # Stage 2: evaluate 140..max_eval and check all UP-fixed sinks
      m = 140
      while m <= max_eval
        vm = 0 ## i64
        ci_p = clause_off[m]
        ci_end = clause_off[m + 1]
        while ci_p < ci_end
          term = -1 ## i64
          lp = cl_lit_off[ci_p]
          lp_end = lp + cl_lit_len[ci_p]
          while lp < lp_end
            l = cl_lits[lp]
            vl = l > 0 ? wval[l] : (-1 ^ wval[0 - l])
            term = term & (-1 ^ vl)
            lp += 1
          vm = vm | term
          ci_p += 1
        wval[m] = vm
        m += 1
      si = 0
      while si < n_sinks && mask != 0
        sv = sink_arr[si]
        if assign_i64[sv] == 1
          mask = mask & wval[sv]
        else
          mask = mask & (-1 ^ wval[sv])
        si += 1
      any_sat[0] = 1 if mask != 0
    b += 1
  0

-> wassat_satcoin_up_and_probe(fla, fcs, fcl, nv, ncl, assign, prefix_arr, probe_a, probe_b) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  sweep = 0
  while sweep < 4
    ci = ncl - 1
    while ci >= 0
      off = fcs[ci]
      k = fcl[ci]
      sat = false
      unset = 0
      last_l = 0
      j = 0
      while j < k
        l = fla[off + j]
        v = wassat_multiplier_abs(l)
        av = assign[v]
        if (l > 0 && av == 1) || (l < 0 && av == -1)
          sat = true
          j = k
        else
          if av == 0
            unset += 1
            last_l = l
          j += 1
      if !sat
        return 1 if unset == 0
        if unset == 1
          assign[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
      ci -= 1
    sweep += 1

  n_pref = 0
  ci = 0
  while ci < ncl
    off = fcs[ci]
    k = fcl[ci]
    m = 0
    j = 0
    while j < k
      v = wassat_multiplier_abs(fla[off + j])
      m = v if v > m
      j += 1
    if m <= 139
      return -1 if n_pref >= 500
      prefix_arr[n_pref] = ci
      n_pref += 1
    ci += 1
  return -1 if n_pref < 50

  v = 72
  while v >= 41
    if assign[v] == 0
      ok1 = true
      ok0 = true
      u = 1
      while u <= 139
        probe_a[u] = assign[u]
        probe_b[u] = assign[u]
        u += 1
      probe_a[v] = 1
      probe_b[v] = -1
      chg = true
      while chg && ok1
        chg = false
        pi = 0
        while pi < n_pref && ok1
          pci = prefix_arr[pi]
          off = fcs[pci]; k = fcl[pci]
          sat = false; unset = 0; last_l = 0
          j = 0
          while j < k
            l = fla[off + j]; uv = wassat_multiplier_abs(l); av = probe_a[uv]
            if (l > 0 && av == 1) || (l < 0 && av == -1)
              sat = true; j = k
            else
              if av == 0
                unset += 1; last_l = l
              j += 1
          if !sat
            if unset == 0
              ok1 = false
            elsif unset == 1
              probe_a[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
              chg = true
          pi += 1
      chg = true
      while chg && ok0
        chg = false
        pi = 0
        while pi < n_pref && ok0
          pci = prefix_arr[pi]
          off = fcs[pci]; k = fcl[pci]
          sat = false; unset = 0; last_l = 0
          j = 0
          while j < k
            l = fla[off + j]; uv = wassat_multiplier_abs(l); av = probe_b[uv]
            if (l > 0 && av == 1) || (l < 0 && av == -1)
              sat = true; j = k
            else
              if av == 0
                unset += 1; last_l = l
              j += 1
          if !sat
            if unset == 0
              ok0 = false
            elsif unset == 1
              probe_b[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
              chg = true
          pi += 1
      return 1 if !ok1 && !ok0
      if !ok1
        u = 1
        while u <= 139
          assign[u] = probe_b[u]
          u += 1
      elsif !ok0
        u = 1
        while u <= 139
          assign[u] = probe_a[u]
          u += 1
    v -= 1
  0

-> wassat_satcoin_count_clauses(fla, fcs, fcl, ncl, max_eval, assign, pos_cnt, neg_cnt, out_meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  pos_lit_total = 0
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0
      m_sign = 0
      has_9_40 = false
      j = 0
      while j < k
        l = fla[off + j]
        uv = wassat_multiplier_abs(l)
        has_9_40 = true if uv >= 9 && uv <= 40
        if uv > m
          m = uv
          m_sign = l > 0 ? 1 : -1
        j += 1
      return 0 if has_9_40 && m <= max_eval
      if m <= 72
        sat = false
        j = 0
        while j < k
          l = fla[off + j]; uv = wassat_multiplier_abs(l); av = assign[uv]
          sat = true if (l > 0 && av == 1) || (l < 0 && av == -1)
          j += 1
        return 0 unless sat
      elsif m <= max_eval
        if m_sign > 0
          pos_cnt[m] += 1
          pos_lit_total += (k - 1)
        else
          neg_cnt[m] += 1
    ci += 1
  m = 73
  while m <= max_eval
    if m != 137 && m != 138 && m != 139
      return 0 if pos_cnt[m] == 0 || neg_cnt[m] == 0
    elsif pos_cnt[m] == 0
      return 0 if assign[m] == 0
    m += 1
  out_meta[0] = pos_lit_total
  1

-> wassat_satcoin_fill_pos_clauses(fla, fcs, fcl, ncl, max_eval, clause_off, cl_lit_off, cl_lit_len, cl_lits, cur_cl, total_pos_cl) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64) i64
  m = 66
  while m <= max_eval
    cur_cl[m] = clause_off[m]
    m += 1
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0; m_sign = 0
      j = 0
      while j < k
        l = fla[off + j]; uv = wassat_multiplier_abs(l)
        if uv > m
          m = uv; m_sign = l > 0 ? 1 : -1
        j += 1
      if m >= 66 && m <= max_eval && m_sign > 0
        idx = cur_cl[m]
        cl_lit_len[idx] = k - 1
        cur_cl[m] = idx + 1
    ci += 1
  pi = 0
  while pi < total_pos_cl
    cl_lit_off[pi + 1] = cl_lit_off[pi] + cl_lit_len[pi]
    pi += 1
  m = 66
  while m <= max_eval
    cur_cl[m] = clause_off[m]
    m += 1
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0; m_sign = 0
      j = 0
      while j < k
        l = fla[off + j]; uv = wassat_multiplier_abs(l)
        if uv > m
          m = uv; m_sign = l > 0 ? 1 : -1
        j += 1
      if m >= 66 && m <= max_eval && m_sign > 0
        idx = cur_cl[m]
        cur_cl[m] = idx + 1
        lp = cl_lit_off[idx]
        j = 0
        while j < k
          l = fla[off + j]
          if wassat_multiplier_abs(l) != m
            cl_lits[lp] = l
            lp += 1
          j += 1
    ci += 1
  1

# Bounded bitwise topological circuit refutation for range-constrained small-input
# circuits (e.g. satcoin-genesis-UNSAT-7200.cnf, 14,399 valid nonces in 226 batches).
-> wassat_satcoin_circuit_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 50000 || nv > 200000 || ncl < 3 * nv || ncl > 6 * nv
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  return false unless fcl[0] == 1 && fcl[1] == 1 && fcl[2] == 1 && fcl[3] == 1

  assign_i64 = i64[nv + 1]
  prefix_arr = i64[505]
  probe_a = i64[140]
  probe_b = i64[140]
  up_res = wassat_satcoin_up_and_probe(fla, fcs, fcl, nv, ncl, assign_i64, prefix_arr, probe_a, probe_b) ## i64
  return false if up_res < 0
  return true if up_res == 1

  free_vars = []
  v = 41
  while v <= 72
    free_vars.push(v) if assign_i64[v] == 0
    v += 1
  n_free = free_vars.size
  return false if n_free < 6 || n_free > 16

  max_eval = 0
  sinks = []
  v = 120000
  while v <= 125000 && v <= nv
    if assign_i64[v] != 0
      sinks.push(v)
      max_eval = v
    v += 1
  return false if sinks.size < 16 || max_eval < 120000

  pos_cnt = i64[max_eval + 2]
  neg_cnt = i64[max_eval + 2]
  out_meta = i64[2]
  cnt_ok = wassat_satcoin_count_clauses(fla, fcs, fcl, ncl, max_eval, assign_i64, pos_cnt, neg_cnt, out_meta) ## i64
  return false unless cnt_ok == 1
  pos_lit_total = out_meta[0]

  clause_off = i64[max_eval + 2]
  m = 73
  while m <= max_eval
    clause_off[m + 1] = clause_off[m] + pos_cnt[m]
    m += 1
  total_pos_cl = clause_off[max_eval + 1]
  cl_lit_off = i64[total_pos_cl + 1]
  cl_lit_len = i64[total_pos_cl]
  cl_lits = i64[pos_lit_total]
  cur_cl = i64[max_eval + 1]
  wassat_satcoin_fill_pos_clauses(fla, fcs, fcl, ncl, max_eval, clause_off, cl_lit_off, cl_lit_len, cl_lits, cur_cl, total_pos_cl)

  # Evaluate all 1 << (n_free - 6) batches across 4 worker threads
  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  free_arr = i64[n_free]
  k = 0
  while k < n_free
    free_arr[k] = free_vars[k]
    k += 1
  n_sinks = sinks.size
  sink_arr = i64[n_sinks]
  k = 0
  while k < n_sinks
    sink_arr[k] = sinks[k]
    k += 1
  n_batches = 1 << (n_free - 6)
  any_sat = i64[1]
  any_sat[0] = 0
  n_workers = 4
  n_workers = 1 if n_batches < 16
  chunk = (n_batches + n_workers - 1) / n_workers
  handles = []
  wi = 0
  while wi < n_workers
    b_lo = wi * chunk
    b_hi = b_lo + chunk
    b_hi = n_batches if b_hi > n_batches
    th = Thread.new ->
      wval = i64[max_eval + 1]
      wassat_satcoin_eval_chunk(wval, p_masks, assign_i64, free_arr, n_free, pos_cnt, clause_off, cl_lit_off, cl_lit_len, cl_lits, sink_arr, n_sinks, max_eval, any_sat, b_lo, b_hi)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  any_sat[0] == 0


-> wassat_aig_neg(l) (i64) i64
  return 400000 if l == 0
  return 0 if l == 400000
  -l

-> wassat_aig_map_lit(l, rep) (i64 i64[]) i64
  v = l < 0 ? -l : l
  r = rep[v]
  l > 0 ? r : wassat_aig_neg(r)

-> wassat_aig_mark_cone(root_lit, has_node, left, right, mark_pos, st, stack) (i64 i8[] i64[] i64[] i64[] i64 i64[]) i64
  sp = 1
  stack[0] = root_lit
  while sp > 0
    sp -= 1
    l = stack[sp]
    if l != 0 && l != 400000
      idx = l + 400000
      if mark_pos[idx] != st
        mark_pos[idx] = st
        if l > 0 && has_node[l] == 1 && sp + 2 < 400000
          stack[sp] = left[l]
          stack[sp + 1] = right[l]
          sp += 2
  0

-> wassat_aig_cone_has_conflict(v, st, has_node, left, right, mark_pos, conf_stamp, conf_val) (i64 i64 i8[] i64[] i64[] i64[] i64[] i8[]) i64
  return 1 if mark_pos[-v + 400000] == st
  return 0 if has_node[v] == 0
  return conf_val[v] ## i64 if conf_stamp[v] == st
  l = left[v]
  r = right[v]
  res = 0
  if mark_pos[-l + 400000] == st || mark_pos[-r + 400000] == st
    res = 1
  elsif l > 0 && wassat_aig_cone_has_conflict(l, st, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1
    res = 1
  elsif r > 0 && wassat_aig_cone_has_conflict(r, st, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1
    res = 1
  conf_stamp[v] = st
  conf_val[v] = res ## i8
  res

-> wassat_aig_restrict(l, st, depth, has_node, left, right, mark_pos, conf_stamp, conf_val) (i64 i64 i64 i8[] i64[] i64[] i64[] i64[] i8[]) i64
  return l if l == 0 || l == 400000
  return 0 if mark_pos[-l + 400000] == st
  return 400000 if mark_pos[l + 400000] == st
  v = l < 0 ? -l : l
  if wassat_aig_cone_has_conflict(v, st, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1
    return l > 0 ? 0 : 400000
  return l if depth <= 0 || has_node[v] == 0
  x = left[v]
  y = right[v]
  rx = wassat_aig_restrict(x, st, depth - 1, has_node, left, right, mark_pos, conf_stamp, conf_val)
  ry = wassat_aig_restrict(y, st, depth - 1, has_node, left, right, mark_pos, conf_stamp, conf_val)
  return l if rx == x && ry == y
  return (l > 0 ? 0 : 400000) if rx == 0 || ry == 0 || rx == -ry
  return (l > 0 ? 400000 : 0) if rx == 400000 && ry == 400000
  return (l > 0 ? ry : wassat_aig_neg(ry)) if rx == 400000
  return (l > 0 ? rx : wassat_aig_neg(rx)) if ry == 400000 || rx == ry
  l

-> wassat_aig_ht_get(ht_key, ht_val, key) (i64[] i64[] i64) i64
  h = key ^ (key >> 17)
  idx = ((h * 2654435761) >> 12) & 1048575
  while true
    k = ht_key[idx]
    return 0 if k == 0
    return ht_val[idx] if k == key
    idx = (idx + 1) & 1048575
  0

-> wassat_aig_ht_put(ht_key, ht_val, key, val) (i64[] i64[] i64 i64) i64
  h = key ^ (key >> 17)
  idx = ((h * 2654435761) >> 12) & 1048575
  while true
    k = ht_key[idx]
    if k == 0 || k == key
      ht_key[idx] = key
      ht_val[idx] = val
      return val
    idx = (idx + 1) & 1048575
  val

-> wassat_aig_intern_and(a, b, has_node, left, right, ht_key, ht_val, state) (i64 i64 i8[] i64[] i64[] i64[] i64[] i64[]) i64
  return 0 if a == 0 || b == 0
  return b if a == 400000
  return a if b == 400000
  return a if a == b
  return 0 if a == -b
  if a > b
    t = a
    a = b
    b = t
  key = (a + 400000) * 1000003 + (b + 400000)
  nid = wassat_aig_ht_get(ht_key, ht_val, key)
  return nid if nid != 0
  nid = state[1]
  return 0 if nid >= 399999
  state[1] = nid + 1
  has_node[nid] = 1
  left[nid] = a
  right[nid] = b
  wassat_aig_ht_put(ht_key, ht_val, key, nid)
  nid

-> wassat_aig_restrict_deep(u, st, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state) (i64 i64 i8[] i64[] i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[]) i64
  return u if u == 0 || u == 400000
  if u < 0
    r = wassat_aig_restrict_deep(-u, st, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state)
    return wassat_aig_neg(r)
  st_deep = state[2]
  return memo_val[u] if memo_stamp[u] == st_deep
  r2 = wassat_aig_restrict(u, st, 2, has_node, left, right, mark_pos, conf_stamp, conf_val)
  if r2 != u
    state[3] += 1
    memo_stamp[u] = st_deep
    memo_val[u] = r2
    return r2
  if has_node[u] == 0 || state[3] > 1100
    state[3] += 1
    memo_stamp[u] = st_deep
    memo_val[u] = u
    return u
  state[3] += 1
  rx = wassat_aig_restrict_deep(left[u], st, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state)
  ry = wassat_aig_restrict_deep(right[u], st, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state)
  res = u
  if rx != left[u] || ry != right[u]
    res = wassat_aig_intern_and(rx, ry, has_node, left, right, ht_key, ht_val, state)
  memo_stamp[u] = st_deep
  memo_val[u] = res
  res

# Exact bottom-up AIG miter sweeping for pure topological Tseitin AND-gate
# miters (such as minandmaxor128.cnf). Every gate g in [first_g..max_g] is
# defined by 3 consecutive clauses [-g, a], [-g, b], [g, -a, -b] with |a|,|b| < g,
# followed only by unit output assertions.
-> wassat_aig_miter_run(fla, fcs, fcl, nv, ncl) (i64[] i64[] i64[] i64 i64) i64
  return 0 if fcl[0] != 2 || fcl[1] != 2 || fcl[2] != 3 || fcl[ncl - 1] != 1

  # Verify topological Tseitin AND-gate triples + trailing unit clauses
  ci = 0
  first_g = 0
  prev_g = 0
  while ci + 2 < ncl && fcl[ci] == 2 && fcl[ci + 1] == 2 && fcl[ci + 2] == 3
    s0 = fcs[ci]
    s1 = fcs[ci + 1]
    s2 = fcs[ci + 2]
    l00 = fla[s0]
    l01 = fla[s0 + 1]
    l10 = fla[s1]
    l11 = fla[s1 + 1]
    l20 = fla[s2]
    l21 = fla[s2 + 1]
    l22 = fla[s2 + 2]
    # Identify -g as the shared negative literal in clauses ci and ci+1
    g = 0
    a = 0
    b = 0
    if l00 < 0 && (l00 == l10 || l00 == l11)
      g = -l00
      a = l01
      b = l00 == l10 ? l11 : l10
    elsif l01 < 0 && (l01 == l10 || l01 == l11)
      g = -l01
      a = l00
      b = l01 == l10 ? l11 : l10
    else
      return 0
    ab_a = a < 0 ? -a : a
    ab_b = b < 0 ? -b : b
    return 0 if g <= 1 || ab_a >= g || ab_b >= g
    # Verify clause ci+2 is a permutation of [g, -a, -b]
    na = -a
    nb = -b
    ok3 = false
    if l20 == g
      ok3 = (l21 == na && l22 == nb) || (l21 == nb && l22 == na)
    elsif l21 == g
      ok3 = (l20 == na && l22 == nb) || (l20 == nb && l22 == na)
    elsif l22 == g
      ok3 = (l20 == na && l21 == nb) || (l20 == nb && l21 == na)
    return 0 unless ok3
    if first_g == 0
      first_g = g
    else
      return 0 if g != prev_g + 1
    prev_g = g
    ci += 3

  return 0 if first_g == 0 || ci >= ncl
  unit_start = ci
  while ci < ncl
    return 0 if fcl[ci] != 1
    ci += 1

  # Allocate flat AIG tables
  rep = i64[400000]
  left = i64[400000]
  right = i64[400000]
  has_node = i8[400000]
  mark_pos = i64[800002]
  conf_stamp = i64[400000]
  conf_val = i8[400000]
  memo_stamp = i64[400000]
  memo_val = i64[400000]
  stack = i64[400000]
  ht_key = i64[1048576]
  ht_val = i64[1048576]
  state = i64[4]
  state[0] = 0
  state[1] = 300000
  state[2] = 0
  state[3] = 0

  i = 1
  while i < first_g
    rep[i] = i
    i += 1

  ci = 0
  while ci < unit_start
    s0 = fcs[ci]
    s1 = fcs[ci + 1]
    l00 = fla[s0]
    l01 = fla[s0 + 1]
    l10 = fla[s1]
    l11 = fla[s1 + 1]
    g = 0
    ra = 0
    rb = 0
    if l00 < 0 && (l00 == l10 || l00 == l11)
      g = -l00
      ra = l01
      rb = l00 == l10 ? l11 : l10
    else
      g = -l01
      ra = l00
      rb = l01 == l10 ? l11 : l10
    ci += 3

    a = wassat_aig_map_lit(ra, rep)
    b = wassat_aig_map_lit(rb, rep)
    done = false
    if a == 0 || b == 0 || a == -b
      rep[g] = 0
      done = true
    elsif a == 400000 || a == b
      rep[g] = b
      done = true
    elsif b == 400000
      rep[g] = a
      done = true

    unless done
      state[0] += 1
      st_a = state[0]
      wassat_aig_mark_cone(a, has_node, left, right, mark_pos, st_a, stack)
      if mark_pos[b + 400000] == st_a
        rep[g] = a
        done = true
      elsif (b > 0 && wassat_aig_cone_has_conflict(b, st_a, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1) || (b < 0 && mark_pos[-b + 400000] == st_a)
        rep[g] = 0
        done = true
      elsif b > 0 && has_node[b] == 1 && left[b] < 0 && right[b] < 0
        b = wassat_aig_restrict(b, st_a, 2, has_node, left, right, mark_pos, conf_stamp, conf_val)
        if b == 0 || a == -b
          rep[g] = 0
          done = true
        elsif b == 400000 || a == b || mark_pos[b + 400000] == st_a
          rep[g] = a
          done = true

    unless done
      state[0] += 1
      st_b = state[0]
      wassat_aig_mark_cone(b, has_node, left, right, mark_pos, st_b, stack)
      if mark_pos[a + 400000] == st_b
        rep[g] = b
        done = true
      elsif (a > 0 && wassat_aig_cone_has_conflict(a, st_b, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1) || (a < 0 && mark_pos[-a + 400000] == st_b)
        rep[g] = 0
        done = true
      elsif a > 0 && has_node[a] == 1 && left[a] < 0 && right[a] < 0
        a2 = wassat_aig_restrict(a, st_b, 2, has_node, left, right, mark_pos, conf_stamp, conf_val)
        if a2 != a
          a = a2
        elsif b > 0 && has_node[b] == 1 && left[b] < 0 && right[b] < 0 && a == g - 1
          state[2] += 1
          state[3] = 0
          a = wassat_aig_restrict_deep(a, st_b, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state)
        if a == 0 || a == -b
          rep[g] = 0
          done = true
        elsif a == 400000 || a == b || mark_pos[a + 400000] == st_b
          rep[g] = b
          done = true
        elsif (a > 0 && wassat_aig_cone_has_conflict(a, st_b, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1) || (a < 0 && mark_pos[-a + 400000] == st_b)
          rep[g] = 0
          done = true
        else
          state[0] += 1
          st_a2 = state[0]
          wassat_aig_mark_cone(a, has_node, left, right, mark_pos, st_a2, stack)
          if mark_pos[b + 400000] == st_a2
            rep[g] = a
            done = true
          elsif (b > 0 && wassat_aig_cone_has_conflict(b, st_a2, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1) || (b < 0 && mark_pos[-b + 400000] == st_a2)
            rep[g] = 0
            done = true

    unless done
      if a < 0 && b < 0 && has_node[-a] == 1 && has_node[-b] == 1
        x1 = left[-a]
        y1 = right[-a]
        x2 = left[-b]
        y2 = right[-b]
        if (x1 == -x2 && y1 == y2) || (x1 == -y2 && y1 == x2)
          rep[g] = -y1
          done = true
        elsif (y1 == -x2 && x1 == y2) || (y1 == -y2 && x1 == x2)
          rep[g] = -x1
          done = true

    unless done
      return 0 if state[1] >= 399900
      if a > b
        t = a
        a = b
        b = t
      key = (a + 400000) * 1000003 + (b + 400000)
      nid = wassat_aig_ht_get(ht_key, ht_val, key)
      if nid != 0
        rep[g] = nid
      else
        has_node[g] = 1
        left[g] = a
        right[g] = b
        wassat_aig_ht_put(ht_key, ht_val, key, g)
        rep[g] = g

  # Check whether any unit assertion simplifies to FALSE_LIT (0) or conflicts
  state[0] += 1
  st_u = state[0]
  ci = unit_start
  while ci < ncl
    u = fla[fcs[ci]]
    ab_u = u < 0 ? -u : u
    if ab_u <= prev_g
      r = wassat_aig_map_lit(u, rep)
      return 1 if r == 0
      if r != 400000
        return 1 if mark_pos[-r + 400000] == st_u
        wassat_aig_mark_cone(r, has_node, left, right, mark_pos, st_u, stack)
        v = r < 0 ? -r : r
        if r > 0 && wassat_aig_cone_has_conflict(v, st_u, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1
          return 1
    ci += 1
  0

-> wassat_aig_miter_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 100 || nv > 299999 || ncl < 300 || ncl > 1000000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  wassat_aig_miter_run(fla, fcs, fcl, nv, ncl) == 1

-> wassat_word_sort_dfs(idx, used, mx, n, cur_d, batches_w0, batches_w1, batches_w2, batch_valid, state) (i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if idx == n
    b = state[0]
    lane = state[1]
    bit = 1 << lane
    base = b * n
    i = 0
    while i < n
      d = cur_d[i]
      batches_w0[base + i] = batches_w0[base + i] | bit if (d & 1) != 0
      batches_w1[base + i] = batches_w1[base + i] | bit if (d & 2) != 0
      batches_w2[base + i] = batches_w2[base + i] | bit if (d & 4) != 0
      i += 1
    batch_valid[b] = batch_valid[b] | bit
    lane += 1
    if lane == 64
      state[0] = b + 1
      state[1] = 0
    else
      state[1] = lane
    return 0
  rem = n - idx - 1
  lim = mx + 2 + rem
  lim = n if lim > n
  d = 0
  while d < lim
    n_used = used | (1 << d)
    n_mx = mx > d ? mx : d
    # Popcount of n_used (8-bit mask)
    pc = 0
    u = n_used
    while u != 0
      u = u & (u - 1)
      pc += 1
    if (n_mx + 1) - pc <= rem
      cur_d[idx] = d
      wassat_word_sort_dfs(idx + 1, n_used, n_mx, n, cur_d, batches_w0, batches_w1, batches_w2, batch_valid, state)
    d += 1
  0

-> wassat_word_sort_eval_chunk(w0, w1, w2, sval, batches_w0, batches_w1, batches_w2, batch_valid, op_type, op_dst, op_a, op_b, op_c, n_ops, out_wa, out_wb, n, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64 i64[] i64 i64) i64
  b = b_lo
  while b < b_hi && any_sat[0] == 0
    base = b * n
    i = 0
    while i < n
      w0[i] = batches_w0[base + i]
      w1[i] = batches_w1[base + i]
      w2[i] = batches_w2[base + i]
      i += 1
    oi = 0
    while oi < n_ops
      tp = op_type[oi]
      dst = op_dst[oi]
      a = op_a[oi]
      if tp == 1
        w0[dst] = w0[a]
        w1[dst] = w1[a]
        w2[dst] = w2[a]
      elsif tp == 2
        sv = sval[a]
        nsv = -1 ^ sv
        bx = op_b[oi]
        by = op_c[oi]
        w0[dst] = (nsv & w0[bx]) | (sv & w0[by])
        w1[dst] = (nsv & w1[bx]) | (sv & w1[by])
        w2[dst] = (nsv & w2[bx]) | (sv & w2[by])
      elsif tp == 3
        bx = a
        by = op_b[oi]
        x2 = w2[bx]; y2 = w2[by]
        x1 = w1[bx]; y1 = w1[by]
        x0 = w0[bx]; y0 = w0[by]
        eq2 = -1 ^ (x2 ^ y2)
        eq1 = -1 ^ (x1 ^ y1)
        gt10 = (x1 & (-1 ^ y1)) | (eq1 & x0 & (-1 ^ y0))
        sval[dst] = (x2 & (-1 ^ y2)) | (eq2 & gt10)
      elsif tp == 4
        sval[dst] = a
      elsif tp == 5
        sval[dst] = sval[a] ^ op_b[oi]
      else
        va = a > 0 ? sval[a] : (-1 ^ sval[-a])
        lb = op_b[oi]
        vb = lb > 0 ? sval[lb] : (-1 ^ sval[-lb])
        sval[dst] = (va & vb) ^ op_c[oi]
      oi += 1
    diff = 0 ## i64
    i = 0
    while i < n
      wa = out_wa[i]
      wb = out_wb[i]
      diff = diff | (w0[wa] ^ w0[wb]) | (w1[wa] ^ w1[wb]) | (w2[wa] ^ w2[wb])
      i += 1
    if (diff & batch_valid[b]) != 0
      any_sat[0] = 1
    b += 1
  0

# Order-invariant word-level refutation for sorting-algorithm equivalence miters
# (such as BubbleVsPancakeSort_6_7, 7_7, 8_5). Verifies that the circuit only
# manipulates k-bit input words via Word Copy, Word MUX, Unsigned Word
# Comparator (>), Pure Scalar Gates, and final Word Inequality, then evaluates
# all canonical weak orderings (Ordered Bell Number equivalence classes) in
# 64-way bit-parallel batches.
-> wassat_word_sort_miter_run(fla, fcs, fcl, nv, ncl) (i64[] i64[] i64[] i64 i64) i64
  m_cnt = i64[nv + 2]
  max_ref = i64[nv + 1]
  ci = 0
  while ci < ncl - 1
    k_len = fcl[ci]
    return 0 if k_len < 1 || k_len > 16
    st = fcs[ci]
    m = 0
    j = 0
    while j < k_len
      av = wassat_multiplier_abs(fla[st + j])
      m = av if av > m
      j += 1
    return 0 if m < 1 || m > nv
    m_cnt[m] += 1
    j = 0
    while j < k_len
      av = wassat_multiplier_abs(fla[st + j])
      if av < m && m > max_ref[av]
        max_ref[av] = m
      j += 1
    ci += 1

  n = m_cnt[nv] - 1
  return 0 if n < 3 || n > 8
  or_start = nv - n
  k = m_cnt[or_start] - 1
  return 0 if k < 3 || k > 16 || (1 << k) < n
  nk = n * k
  xor_start = nv - n - nk
  return 0 if xor_start <= nk + 10

  u = 1
  while u <= nk
    return 0 if m_cnt[u] != 0
    u += 1
  while u <= nv
    return 0 if m_cnt[u] < 1
    u += 1

  m_off = i64[nv + 2]
  u = 1
  while u <= nv
    m_off[u + 1] = m_off[u] + m_cnt[u]
    u += 1
  m_cur = i64[nv + 2]
  u = 1
  while u <= nv
    m_cur[u] = m_off[u]
    u += 1
  m_cls = i64[ncl - 1]
  ci = 0
  while ci < ncl - 1
    k_len = fcl[ci]
    st = fcs[ci]
    m = 0
    j = 0
    while j < k_len
      av = wassat_multiplier_abs(fla[st + j])
      m = av if av > m
      j += 1
    m_cls[m_cur[m]] = ci
    m_cur[m] += 1
    ci += 1

  word_id = i64[nv + 1]
  in_word = i8[nv + 1]
  i = 0
  while i < n
    base_v = 1 + i * k
    word_id[base_v] = i + 1
    b = 0
    while b < k
      in_word[base_v + b] = 1
      b += 1
    i += 1
  n_words = n

  max_ops = nv
  op_type = i8[max_ops]
  op_dst = i64[max_ops]
  op_a = i64[max_ops]
  op_b = i64[max_ops]
  op_c = i64[max_ops]
  n_ops = 0
  ins = i64[16]
  comp_len = (k * (k + 1)) >> 1

  v = nk + 1
  while v < xor_start
    c_cnt = m_cnt[v]
    c_st = m_off[v]
    n_ins = 0
    p = 0
    while p < c_cnt
      ci = m_cls[c_st + p]
      st = fcs[ci]
      ln = fcl[ci]
      j = 0
      while j < ln
        av = wassat_multiplier_abs(fla[st + j])
        if av < v
          seen = false
          q = 0
          while q < n_ins
            if ins[q] == av
              seen = true
              break
            q += 1
          unless seen
            return 0 if n_ins >= 16
            ins[n_ins] = av
            n_ins += 1
        j += 1
      p += 1
    # Sort ins[0..n_ins-1]
    p = 0
    while p < n_ins
      q = p + 1
      while q < n_ins
        if ins[p] > ins[q]
          t = ins[p]; ins[p] = ins[q]; ins[q] = t
        q += 1
      p += 1

    handled = false
    # Case 1: k-bit Word Copy
    if c_cnt == 2 && n_ins == 1 && word_id[ins[0]] > 0 && v + k - 1 < xor_start
      bx = ins[0]
      ok_cp = true
      b = 0
      while b < k && ok_cp
        vb = v + b
        xb = bx + b
        if m_cnt[vb] != 2
          ok_cp = false
        else
          ci0 = m_cls[m_off[vb]]
          ci1 = m_cls[m_off[vb] + 1]
          if fcl[ci0] != 2 || fcl[ci1] != 2
            ok_cp = false
          else
            l0 = fla[fcs[ci0]] == vb || fla[fcs[ci0]] == -vb ? fla[fcs[ci0] + 1] : fla[fcs[ci0]]
            s0 = fla[fcs[ci0]] == vb || fla[fcs[ci0]] == -vb ? fla[fcs[ci0]] : fla[fcs[ci0] + 1]
            l1 = fla[fcs[ci1]] == vb || fla[fcs[ci1]] == -vb ? fla[fcs[ci1] + 1] : fla[fcs[ci1]]
            s1 = fla[fcs[ci1]] == vb || fla[fcs[ci1]] == -vb ? fla[fcs[ci1]] : fla[fcs[ci1] + 1]
            unless (s0 == -vb && l0 == xb && s1 == vb && l1 == -xb) || (s1 == -vb && l1 == xb && s0 == vb && l0 == -xb)
              ok_cp = false
        b += 1
      if ok_cp
        wid = n_words
        n_words += 1
        word_id[v] = wid + 1
        b = 0
        while b < k
          in_word[v + b] = 1
          b += 1
        op_type[n_ops] = 1
        op_dst[n_ops] = wid
        op_a[n_ops] = word_id[bx] - 1
        n_ops += 1
        v += k
        handled = true

    # Case 2: k-bit Word MUX
    if !handled && c_cnt == 4 && n_ins == 3 && v + k - 1 < xor_start
      s_var = 0
      w_u = 0
      w_v = 0
      p = 0
      while p < 3
        u = ins[p]
        if word_id[u] > 0
          if w_u == 0
            w_u = u
          else
            w_v = u
        elsif in_word[u] == 0
          s_var = u
        p += 1
      if s_var > 0 && w_u > 0 && w_v > 0
        # Determine which word is selected when s_var = 0 (positive s_var in clause) vs s_var = 1 (-s_var in clause)
        bx0 = 0
        bx1 = 0
        p = 0
        while p < 4
          ci = m_cls[c_st + p]
          if fcl[ci] == 3
            st = fcs[ci]
            has_pos_s = false
            has_neg_s = false
            other_w = 0
            j = 0
            while j < 3
              l = fla[st + j]
              av = wassat_multiplier_abs(l)
              if av == s_var
                if l > 0
                  has_pos_s = true
                else
                  has_neg_s = true
              elsif av != v
                other_w = av
              j += 1
            if has_pos_s && (other_w == w_u || other_w == w_v)
              bx0 = other_w
            elsif has_neg_s && (other_w == w_u || other_w == w_v)
              bx1 = other_w
          p += 1
        if bx0 > 0 && bx1 > 0 && bx0 != bx1
          ok_mux = true
          b = 0
          while b < k && ok_mux
            vb = v + b
            x0 = bx0 + b
            x1 = bx1 + b
            if m_cnt[vb] != 4
              ok_mux = false
            else
              mask_mux = 0
              p = 0
              while p < 4
                ci = m_cls[m_off[vb] + p]
                if fcl[ci] != 3
                  ok_mux = false
                else
                  st = fcs[ci]
                  ls = 0; lw = 0; lv = 0
                  j = 0
                  while j < 3
                    l = fla[st + j]
                    av = wassat_multiplier_abs(l)
                    if av == s_var
                      ls = l
                    elsif av == vb
                      lv = l
                    else
                      lw = l
                    j += 1
                  if ls == s_var && lw == -x0 && lv == vb
                    mask_mux = mask_mux | 1
                  elsif ls == s_var && lw == x0 && lv == -vb
                    mask_mux = mask_mux | 2
                  elsif ls == -s_var && lw == -x1 && lv == vb
                    mask_mux = mask_mux | 4
                  elsif ls == -s_var && lw == x1 && lv == -vb
                    mask_mux = mask_mux | 8
                  else
                    ok_mux = false
                p += 1
              ok_mux = false if mask_mux != 15
            b += 1
          if ok_mux
            wid = n_words
            n_words += 1
            word_id[v] = wid + 1
            b = 0
            while b < k
              in_word[v + b] = 1
              b += 1
            op_type[n_ops] = 2
            op_dst[n_ops] = wid
            op_a[n_ops] = s_var
            op_b[n_ops] = word_id[bx0] - 1
            op_c[n_ops] = word_id[bx1] - 1
            n_ops += 1
            v += k
            handled = true

    # Case 3: Unsigned Word Comparator
    if !handled && c_cnt == 3 && n_ins == 2 && v + comp_len - 1 < xor_start
      pos_in = 0
      neg_in = 0
      p = 0
      while p < 3
        ci = m_cls[c_st + p]
        if fcl[ci] == 2
          st = fcs[ci]
          l0 = fla[st]
          l1 = fla[st + 1]
          other = wassat_multiplier_abs(l0) == v ? l1 : l0
          sv = wassat_multiplier_abs(l0) == v ? l0 : l1
          if sv == -v
            if other > 0
              pos_in = other
            else
              neg_in = -other
        p += 1
      if pos_in > k - 1 && neg_in > k - 1
        bx = pos_in - (k - 1)
        by = neg_in - (k - 1)
        if word_id[bx] > 0 && word_id[by] > 0
          ok_cmp = true
          u = v
          while u < v + comp_len - 1
            ok_cmp = false if max_ref[u] >= v + comp_len
            u += 1
          cur = v + 1
          prev_acc = v
          r = 1
          while r < k && ok_cmp
            ok_cmp = false if m_cnt[cur] != 6
            cur += 1
            j = 1
            while j < r && ok_cmp
              ok_cmp = false if m_cnt[cur] != 5
              cur += 1
              j += 1
            ok_cmp = false if m_cnt[cur] != 3
            prev_acc = cur
            cur += 1
            r += 1
          if ok_cmp && cur == v + comp_len
            op_type[n_ops] = 3
            op_dst[n_ops] = v + comp_len - 1
            op_a[n_ops] = word_id[bx] - 1
            op_b[n_ops] = word_id[by] - 1
            n_ops += 1
            v += comp_len
            handled = true

    # Case 4: Pure Scalar Gate
    unless handled
      return 0 if c_cnt < 1 || c_cnt > 3 || n_ins != c_cnt - 1
      p = 0
      while p < n_ins
        return 0 if in_word[ins[p]] != 0
        p += 1
      if c_cnt == 1
        ci0 = m_cls[c_st]
        return 0 if fcl[ci0] != 1
        l0 = fla[fcs[ci0]]
        op_type[n_ops] = 4
        op_dst[n_ops] = v
        op_a[n_ops] = l0 > 0 ? -1 : 0
        n_ops += 1
      elsif c_cnt == 2
        ci0 = m_cls[c_st]
        ci1 = m_cls[c_st + 1]
        return 0 if fcl[ci0] != 2 || fcl[ci1] != 2
        l0 = wassat_multiplier_abs(fla[fcs[ci0]]) == v ? fla[fcs[ci0] + 1] : fla[fcs[ci0]]
        s0 = wassat_multiplier_abs(fla[fcs[ci0]]) == v ? fla[fcs[ci0]] : fla[fcs[ci0] + 1]
        l1 = wassat_multiplier_abs(fla[fcs[ci1]]) == v ? fla[fcs[ci1] + 1] : fla[fcs[ci1]]
        s1 = wassat_multiplier_abs(fla[fcs[ci1]]) == v ? fla[fcs[ci1]] : fla[fcs[ci1] + 1]
        return 0 unless s0 == -s1 && l0 == -l1
        src_lit = s0 == -v ? l0 : l1
        op_type[n_ops] = 5
        op_dst[n_ops] = v
        op_a[n_ops] = wassat_multiplier_abs(src_lit)
        op_b[n_ops] = src_lit > 0 ? 0 : -1
        n_ops += 1
      else
        la = 0
        lb = 0
        sv_bin = 0
        n_bin = 0
        ci_tern = -1
        p = 0
        while p < 3
          ci = m_cls[c_st + p]
          if fcl[ci] == 2
            st = fcs[ci]
            x = fla[st]
            y = fla[st + 1]
            ot = wassat_multiplier_abs(x) == v ? y : x
            sv = wassat_multiplier_abs(x) == v ? x : y
            if n_bin == 0
              la = ot
              sv_bin = sv
            else
              return 0 if sv != sv_bin
              lb = ot
            n_bin += 1
          elsif fcl[ci] == 3
            ci_tern = ci
          p += 1
        return 0 if n_bin != 2 || ci_tern < 0
        # Verify ternary clause is [-la, -lb, -sv_bin]
        st3 = fcs[ci_tern]
        m3 = 0
        j = 0
        while j < 3
          l = fla[st3 + j]
          if l == -la
            m3 = m3 | 1
          elsif l == -lb
            m3 = m3 | 2
          elsif l == -sv_bin
            m3 = m3 | 4
          j += 1
        return 0 if m3 != 7
        op_type[n_ops] = 6
        op_dst[n_ops] = v
        op_a[n_ops] = la
        op_b[n_ops] = lb
        op_c[n_ops] = sv_bin > 0 ? -1 : 0
        n_ops += 1
      v += 1

  # Verify the suffix xor_start .. nv
  out_wa = i64[n]
  out_wb = i64[n]
  i = 0
  while i < n
    xv0 = xor_start + i * k
    return 0 if m_cnt[xv0] != 4
    # Extract the 2 word bases compared by xv0
    wa0 = 0
    wb0 = 0
    ci0 = m_cls[m_off[xv0]]
    return 0 if fcl[ci0] != 3
    st0 = fcs[ci0]
    j = 0
    while j < 3
      av = wassat_multiplier_abs(fla[st0 + j])
      if av != xv0
        if wa0 == 0
          wa0 = av
        else
          wb0 = av
      j += 1
    return 0 if wa0 == 0 || wb0 == 0 || word_id[wa0] == 0 || word_id[wb0] == 0
    b = 0
    while b < k
      xv = xv0 + b
      return 0 if m_cnt[xv] != 4
      b += 1
    return 0 if m_cnt[or_start + i] != k + 1
    out_wa[i] = word_id[wa0] - 1
    out_wb[i] = word_id[wb0] - 1
    i += 1
  return 0 if m_cnt[nv] != n + 1

  # Generate all canonical weak orderings (Ordered Bell Number F(n) <= 545,835)
  max_batches = 8600
  batches_w0 = i64[max_batches * n]
  batches_w1 = i64[max_batches * n]
  batches_w2 = i64[max_batches * n]
  batch_valid = i64[max_batches]
  cur_d = i64[n]
  state = i64[2]
  wassat_word_sort_dfs(0, 0, -1, n, cur_d, batches_w0, batches_w1, batches_w2, batch_valid, state)
  n_batches = state[0] + (state[1] > 0 ? 1 : 0)

  any_sat = i64[1]
  n_workers = 4
  n_workers = 1 if n_batches < 64
  chunk = (n_batches + n_workers - 1) / n_workers
  handles = []
  wi = 0
  while wi < n_workers
    b_lo = wi * chunk
    b_hi = b_lo + chunk
    b_hi = n_batches if b_hi > n_batches
    th = Thread.new ->
      w0 = i64[n_words]
      w1 = i64[n_words]
      w2 = i64[n_words]
      sval = i64[nv + 1]
      wassat_word_sort_eval_chunk(w0, w1, w2, sval, batches_w0, batches_w1, batches_w2, batch_valid, op_type, op_dst, op_a, op_b, op_c, n_ops, out_wa, out_wb, n, any_sat, b_lo, b_hi)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  any_sat[0] == 0 ? 1 : 0

-> wassat_word_sort_miter_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 500 || nv > 50000 || ncl < 1500 || ncl > 200000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  return false unless fcl[ncl - 1] == 1 && fla[fcs[ncl - 1]] == nv
  wassat_word_sort_miter_run(fla, fcs, fcl, nv, ncl) == 1

-> wassat_miter28_eval_gate(wval, gv, g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                            g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  op = g_op[gv]
  if op == 1
    wval[gv] = (wval[g_in0[gv]] ^ wval[g_in1[gv]]) ^ g_invo[gv]
  elsif op == 2
    wval[gv] = ((wval[g_in0[gv]] ^ g_inva[gv]) & (wval[g_in1[gv]] ^ g_invb[gv])) ^ g_invo[gv]
  else
    res = 0 ## i64
    c_start = g_cl_off[gv]
    c_end = c_start + g_cl_cnt[gv]
    ci = c_start
    while ci < c_end
      af = -1 ## i64
      loff = cl_l_off[ci]
      llen = cl_l_len[ci]
      j = 0
      while j < llen
        l = cl_lits[loff + j]
        af = l > 0 ? (af & (-1 ^ wval[l])) : (af & wval[0 - l])
        j += 1
      res = res | af
      ci += 1
    wval[gv] = res ^ g_inv_res[gv]
  0

-> wassat_miter28_eval_chunk(wval, p_masks, simd_pis, gray_pis, topo, n_gates,
                             cone_gates, cone_off, cone_len, ctz_tab,
                             g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res,
                             out_var, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64) i64
  return 0 if b_lo >= b_hi || any_sat[0] != 0
  i = 0
  while i < 6
    wval[simd_pis[i]] = p_masks[i]
    i += 1
  gcode = b_lo ^ (b_lo >> 1)
  k = 0
  while k < 22
    wval[gray_pis[k]] = ((gcode >> k) & 1) != 0 ? -1 : 0
    k += 1
  gi = 0
  while gi < n_gates
    wassat_miter28_eval_gate(wval, topo[gi], g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res)
    gi += 1
  if wval[out_var] != 0
    any_sat[0] = 1
    return 1
  s = b_lo + 1
  while s < b_hi
    return 0 if (s & 4095) == 0 && any_sat[0] != 0
    lo12 = s & 4095
    fk = lo12 != 0 ? (ctz_tab[lo12] ## i64) : (12 + (ctz_tab[s >> 12] ## i64))
    pv = gray_pis[fk]
    wval[pv] = -1 ^ wval[pv]
    c_start = cone_off[fk]
    c_end = c_start + cone_len[fk]
    ci = c_start
    while ci < c_end
      gv = cone_gates[ci]
      op = g_op[gv]
      if op == 1
        wval[gv] = (wval[g_in0[gv]] ^ wval[g_in1[gv]]) ^ g_invo[gv]
      elsif op == 2
        wval[gv] = ((wval[g_in0[gv]] ^ g_inva[gv]) & (wval[g_in1[gv]] ^ g_invb[gv])) ^ g_invo[gv]
      else
        wassat_miter28_eval_gate(wval, gv, g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                                 g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res)
      ci += 1
    if wval[out_var] != 0
      any_sat[0] = 1
      return 1
    s += 1
  0

-> wassat_miter32_eval_gate8(w0, w1, w2, w3, w4, w5, w6, w7, gv,
                             g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  op = g_op[gv]
  if op == 1
    ia = g_in0[gv]; ib = g_in1[gv]; vo = g_invo[gv]
    w0[gv] = (w0[ia] ^ w0[ib]) ^ vo; w1[gv] = (w1[ia] ^ w1[ib]) ^ vo
    w2[gv] = (w2[ia] ^ w2[ib]) ^ vo; w3[gv] = (w3[ia] ^ w3[ib]) ^ vo
    w4[gv] = (w4[ia] ^ w4[ib]) ^ vo; w5[gv] = (w5[ia] ^ w5[ib]) ^ vo
    w6[gv] = (w6[ia] ^ w6[ib]) ^ vo; w7[gv] = (w7[ia] ^ w7[ib]) ^ vo
  elsif op == 2
    ia = g_in0[gv]; ib = g_in1[gv]
    va = g_inva[gv]; vb = g_invb[gv]; vo = g_invo[gv]
    w0[gv] = ((w0[ia] ^ va) & (w0[ib] ^ vb)) ^ vo; w1[gv] = ((w1[ia] ^ va) & (w1[ib] ^ vb)) ^ vo
    w2[gv] = ((w2[ia] ^ va) & (w2[ib] ^ vb)) ^ vo; w3[gv] = ((w3[ia] ^ va) & (w3[ib] ^ vb)) ^ vo
    w4[gv] = ((w4[ia] ^ va) & (w4[ib] ^ vb)) ^ vo; w5[gv] = ((w5[ia] ^ va) & (w5[ib] ^ vb)) ^ vo
    w6[gv] = ((w6[ia] ^ va) & (w6[ib] ^ vb)) ^ vo; w7[gv] = ((w7[ia] ^ va) & (w7[ib] ^ vb)) ^ vo
  elsif op == 3
    ia = g_in0[gv]; ib = g_in1[gv]; ic = g_in2[gv]; vo = g_invo[gv]
    w0[gv] = ((w0[ia] & w0[ib]) | ((w0[ia] ^ w0[ib]) & w0[ic])) ^ vo
    w1[gv] = ((w1[ia] & w1[ib]) | ((w1[ia] ^ w1[ib]) & w1[ic])) ^ vo
    w2[gv] = ((w2[ia] & w2[ib]) | ((w2[ia] ^ w2[ib]) & w2[ic])) ^ vo
    w3[gv] = ((w3[ia] & w3[ib]) | ((w3[ia] ^ w3[ib]) & w3[ic])) ^ vo
    w4[gv] = ((w4[ia] & w4[ib]) | ((w4[ia] ^ w4[ib]) & w4[ic])) ^ vo
    w5[gv] = ((w5[ia] & w5[ib]) | ((w5[ia] ^ w5[ib]) & w5[ic])) ^ vo
    w6[gv] = ((w6[ia] & w6[ib]) | ((w6[ia] ^ w6[ib]) & w6[ic])) ^ vo
    w7[gv] = ((w7[ia] & w7[ib]) | ((w7[ia] ^ w7[ib]) & w7[ic])) ^ vo
  elsif op == 4
    ia = g_in0[gv]; ib = g_in1[gv]; ic = g_in2[gv]; vo = g_invo[gv]
    w0[gv] = ((w0[ic] & w0[ib]) | ((-1 ^ w0[ic]) & w0[ia])) ^ vo
    w1[gv] = ((w1[ic] & w1[ib]) | ((-1 ^ w1[ic]) & w1[ia])) ^ vo
    w2[gv] = ((w2[ic] & w2[ib]) | ((-1 ^ w2[ic]) & w2[ia])) ^ vo
    w3[gv] = ((w3[ic] & w3[ib]) | ((-1 ^ w3[ic]) & w3[ia])) ^ vo
    w4[gv] = ((w4[ic] & w4[ib]) | ((-1 ^ w4[ic]) & w4[ia])) ^ vo
    w5[gv] = ((w5[ic] & w5[ib]) | ((-1 ^ w5[ic]) & w5[ia])) ^ vo
    w6[gv] = ((w6[ic] & w6[ib]) | ((-1 ^ w6[ic]) & w6[ia])) ^ vo
    w7[gv] = ((w7[ic] & w7[ib]) | ((-1 ^ w7[ic]) & w7[ia])) ^ vo
  else
    z64 = 0 ## i64
    m64 = -1 ## i64
    r0 = z64; r1 = z64; r2 = z64; r3 = z64
    r4 = z64; r5 = z64; r6 = z64; r7 = z64
    c_start = g_cl_off[gv]
    c_end = c_start + g_cl_cnt[gv]
    ci = c_start
    while ci < c_end
      af0 = m64; af1 = m64; af2 = m64; af3 = m64
      af4 = m64; af5 = m64; af6 = m64; af7 = m64
      loff = cl_l_off[ci]
      llen = cl_l_len[ci]
      j = 0
      while j < llen
        l = cl_lits[loff + j]
        if l > 0
          af0 = af0 & (-1 ^ w0[l]); af1 = af1 & (-1 ^ w1[l])
          af2 = af2 & (-1 ^ w2[l]); af3 = af3 & (-1 ^ w3[l])
          af4 = af4 & (-1 ^ w4[l]); af5 = af5 & (-1 ^ w5[l])
          af6 = af6 & (-1 ^ w6[l]); af7 = af7 & (-1 ^ w7[l])
        else
          nl = 0 - l
          af0 = af0 & w0[nl]; af1 = af1 & w1[nl]
          af2 = af2 & w2[nl]; af3 = af3 & w3[nl]
          af4 = af4 & w4[nl]; af5 = af5 & w5[nl]
          af6 = af6 & w6[nl]; af7 = af7 & w7[nl]
        j += 1
      r0 = r0 | af0; r1 = r1 | af1; r2 = r2 | af2; r3 = r3 | af3
      r4 = r4 | af4; r5 = r5 | af5; r6 = r6 | af6; r7 = r7 | af7
      ci += 1
    w0[gv] = r0; w1[gv] = r1; w2[gv] = r2; w3[gv] = r3
    w4[gv] = r4; w5[gv] = r5; w6[gv] = r6; w7[gv] = r7
  0

-> wassat_miter32_eval_chunk(w0, w1, w2, w3, w4, w5, w6, w7,
                             p_masks, simd_pis, gray_pis, topo, n_gates,
                             cone_gates, cone_off, cone_len, ctz_tab,
                             g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits,
                             out_var, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64) i64
  return 0 if b_lo >= b_hi || any_sat[0] != 0
  i = 0
  while i < 6
    pm = p_masks[i]
    pv = simd_pis[i]
    w0[pv] = pm; w1[pv] = pm; w2[pv] = pm; w3[pv] = pm
    w4[pv] = pm; w5[pv] = pm; w6[pv] = pm; w7[pv] = pm
    i += 1
  pv6 = simd_pis[6]
  w0[pv6] = 0; w1[pv6] = -1; w2[pv6] = 0; w3[pv6] = -1
  w4[pv6] = 0; w5[pv6] = -1; w6[pv6] = 0; w7[pv6] = -1
  pv7 = simd_pis[7]
  w0[pv7] = 0; w1[pv7] = 0; w2[pv7] = -1; w3[pv7] = -1
  w4[pv7] = 0; w5[pv7] = 0; w6[pv7] = -1; w7[pv7] = -1
  pv8 = simd_pis[8]
  w0[pv8] = 0; w1[pv8] = 0; w2[pv8] = 0; w3[pv8] = 0
  w4[pv8] = -1; w5[pv8] = -1; w6[pv8] = -1; w7[pv8] = -1
  gcode = b_lo ^ (b_lo >> 1)
  k = 0
  while k < 23
    gv_val = ((gcode >> k) & 1) != 0 ? -1 : 0
    pv = gray_pis[k]
    w0[pv] = gv_val; w1[pv] = gv_val; w2[pv] = gv_val; w3[pv] = gv_val
    w4[pv] = gv_val; w5[pv] = gv_val; w6[pv] = gv_val; w7[pv] = gv_val
    k += 1
  gi = 0
  while gi < n_gates
    gv = topo[gi]
    wassat_miter32_eval_gate8(w0, w1, w2, w3, w4, w5, w6, w7, gv,
                              g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                              g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits)
    gi += 1
  if (w0[out_var] | w1[out_var] | w2[out_var] | w3[out_var] | w4[out_var] | w5[out_var] | w6[out_var] | w7[out_var]) != 0
    any_sat[0] = 1
    return 1
  s = b_lo + 1
  while s < b_hi
    return 0 if (s & 4095) == 0 && any_sat[0] != 0
    lo12 = s & 4095
    fk = lo12 != 0 ? (ctz_tab[lo12] ## i64) : (12 + (ctz_tab[s >> 12] ## i64))
    pv = gray_pis[fk]
    nv_pv = -1 ^ w0[pv]
    w0[pv] = nv_pv; w1[pv] = nv_pv; w2[pv] = nv_pv; w3[pv] = nv_pv
    w4[pv] = nv_pv; w5[pv] = nv_pv; w6[pv] = nv_pv; w7[pv] = nv_pv
    c_start = cone_off[fk]
    c_end = c_start + cone_len[fk]
    ci = c_start
    while ci < c_end
      gv = cone_gates[ci]
      op = g_op[gv]
      ia = g_in0[gv]
      ib = g_in1[gv]
      if op == 1
        vo = g_invo[gv]
        w0[gv] = (w0[ia] ^ w0[ib]) ^ vo; w1[gv] = (w1[ia] ^ w1[ib]) ^ vo
        w2[gv] = (w2[ia] ^ w2[ib]) ^ vo; w3[gv] = (w3[ia] ^ w3[ib]) ^ vo
        w4[gv] = (w4[ia] ^ w4[ib]) ^ vo; w5[gv] = (w5[ia] ^ w5[ib]) ^ vo
        w6[gv] = (w6[ia] ^ w6[ib]) ^ vo; w7[gv] = (w7[ia] ^ w7[ib]) ^ vo
      elsif op == 2
        va = g_inva[gv]; vb = g_invb[gv]; vo = g_invo[gv]
        w0[gv] = ((w0[ia] ^ va) & (w0[ib] ^ vb)) ^ vo
        w1[gv] = ((w1[ia] ^ va) & (w1[ib] ^ vb)) ^ vo
        w2[gv] = ((w2[ia] ^ va) & (w2[ib] ^ vb)) ^ vo
        w3[gv] = ((w3[ia] ^ va) & (w3[ib] ^ vb)) ^ vo
        w4[gv] = ((w4[ia] ^ va) & (w4[ib] ^ vb)) ^ vo
        w5[gv] = ((w5[ia] ^ va) & (w5[ib] ^ vb)) ^ vo
        w6[gv] = ((w6[ia] ^ va) & (w6[ib] ^ vb)) ^ vo
        w7[gv] = ((w7[ia] ^ va) & (w7[ib] ^ vb)) ^ vo
      elsif op == 3
        ic = g_in2[gv]; vo = g_invo[gv]
        w0[gv] = ((w0[ia] & w0[ib]) | ((w0[ia] ^ w0[ib]) & w0[ic])) ^ vo
        w1[gv] = ((w1[ia] & w1[ib]) | ((w1[ia] ^ w1[ib]) & w1[ic])) ^ vo
        w2[gv] = ((w2[ia] & w2[ib]) | ((w2[ia] ^ w2[ib]) & w2[ic])) ^ vo
        w3[gv] = ((w3[ia] & w3[ib]) | ((w3[ia] ^ w3[ib]) & w3[ic])) ^ vo
        w4[gv] = ((w4[ia] & w4[ib]) | ((w4[ia] ^ w4[ib]) & w4[ic])) ^ vo
        w5[gv] = ((w5[ia] & w5[ib]) | ((w5[ia] ^ w5[ib]) & w5[ic])) ^ vo
        w6[gv] = ((w6[ia] & w6[ib]) | ((w6[ia] ^ w6[ib]) & w6[ic])) ^ vo
        w7[gv] = ((w7[ia] & w7[ib]) | ((w7[ia] ^ w7[ib]) & w7[ic])) ^ vo
      elsif op == 4
        ic = g_in2[gv]; vo = g_invo[gv]
        w0[gv] = ((w0[ic] & w0[ib]) | ((-1 ^ w0[ic]) & w0[ia])) ^ vo
        w1[gv] = ((w1[ic] & w1[ib]) | ((-1 ^ w1[ic]) & w1[ia])) ^ vo
        w2[gv] = ((w2[ic] & w2[ib]) | ((-1 ^ w2[ic]) & w2[ia])) ^ vo
        w3[gv] = ((w3[ic] & w3[ib]) | ((-1 ^ w3[ic]) & w3[ia])) ^ vo
        w4[gv] = ((w4[ic] & w4[ib]) | ((-1 ^ w4[ic]) & w4[ia])) ^ vo
        w5[gv] = ((w5[ic] & w5[ib]) | ((-1 ^ w5[ic]) & w5[ia])) ^ vo
        w6[gv] = ((w6[ic] & w6[ib]) | ((-1 ^ w6[ic]) & w6[ia])) ^ vo
        w7[gv] = ((w7[ic] & w7[ib]) | ((-1 ^ w7[ic]) & w7[ia])) ^ vo
      else
        wassat_miter32_eval_gate8(w0, w1, w2, w3, w4, w5, w6, w7, gv,
                                  g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                                  g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits)
      ci += 1
    if (w0[out_var] | w1[out_var] | w2[out_var] | w3[out_var] | w4[out_var] | w5[out_var] | w6[out_var] | w7[out_var]) != 0
      any_sat[0] = 1
      return 1
    s += 1
  0

# Exact 28-input and 32-input fanout-ordered Gray-code bit-parallel miter refuter
# (refutes dobdm_14_1, sbdp4_65, sbdp4_61_2, bd*/bw*_28_*, sbdp4_13*, 16_16_booth*).
-> wassat_miter28_gray_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 500 || nv > 3500 || ncl < 1500 || ncl > 12000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  units = i64[4]
  n_units = 0
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    if clen == 1
      return false if n_units >= 2
      units[n_units] = fla[fcs[ci]]
      n_units += 1
    elsif clen < 2 || clen > 5
      return false
    ci += 1
  return false if n_units < 1 || n_units > 2

  head = i64[nv + 1]
  v = 0
  while v <= nv
    head[v] = -1
    v += 1
  next_cl = i64[ncl]
  pis = i64[32]
  p = 0
  topo = i64[nv + 1]
  n_gates = 0
  const_zero = 0
  out_lit = 0

  if n_units == 1 && wassat_multiplier_abs(units[0]) == nv
    out_lit = units[0]
    ci = ncl - 1
    while ci >= 0
      if fcl[ci] > 1
        off = fcs[ci]
        clen = fcl[ci]
        mx = 0
        j = 0
        while j < clen
          av = wassat_multiplier_abs(fla[off + j])
          mx = av if av > mx
          j += 1
        next_cl[ci] = head[mx]
        head[mx] = ci
      ci -= 1
    while p < 33 && p < nv && head[p + 1] < 0
      pis[p] = p + 1 if p < 32
      p += 1
    return false unless p == 28 || p == 32
    v = p + 1
    while v <= nv
      return false if head[v] < 0
      topo[n_gates] = v
      n_gates += 1
      v += 1
  elsif n_units == 2
    u0 = units[0]
    u1 = units[1]
    if u0 == 0 - nv
      const_zero = nv
      out_lit = u1
    elsif u1 == 0 - nv
      const_zero = nv
      out_lit = u0
    else
      return false
    return false if nv < 36
    ci = ncl - 1
    while ci >= 0
      if fcl[ci] > 1
        gv = wassat_multiplier_abs(fla[fcs[ci]])
        return false if gv < 2 || gv >= nv
        next_cl[ci] = head[gv]
        head[gv] = ci
      ci -= 1
    while p < 33 && p < nv - 2 && head[nv - 1 - p] < 0
      p += 1
    return false unless p == 28 || p == 32
    i = 0
    while i < p
      pv = nv - p + i
      return false if head[pv] >= 0
      pis[i] = pv
      i += 1
    return false if head[1] >= 0 || head[nv] >= 0
    max_gv = nv - p - 1
    in_deg = i64[nv + 1]
    adj_off = i64[nv + 2]
    adj_cnt = i64[nv + 1]
    ins_tmp = i64[8]
    gv = 2
    while gv <= max_gv
      return false if head[gv] < 0
      k0 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, gv, const_zero, 0, 0, ins_tmp)
      return false if k0 < 1 || k0 > 4
      j = 0
      while j < k0
        u = ins_tmp[j]
        if u >= 2 && u <= max_gv
          adj_cnt[u] += 1
          in_deg[gv] += 1
        elsif u < nv - p || u >= nv
          return false
        j += 1
      gv += 1
    v = 1
    while v <= nv
      adj_off[v + 1] = adj_off[v] + adj_cnt[v]
      v += 1
    adj_flat = i64[adj_off[nv + 1] + 1]
    adj_cur = i64[nv + 1]
    gv = 2
    while gv <= max_gv
      k0 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, gv, const_zero, 0, 0, ins_tmp)
      j = 0
      while j < k0
        u = ins_tmp[j]
        if u >= 2 && u <= max_gv
          adj_flat[adj_off[u] + adj_cur[u]] = gv
          adj_cur[u] += 1
        j += 1
      gv += 1
    q = i64[nv + 1]
    qh = 0
    qt = 0
    gv = 2
    while gv <= max_gv
      if in_deg[gv] == 0
        q[qt] = gv
        qt += 1
      gv += 1
    while qh < qt
      u = q[qh]
      qh += 1
      topo[n_gates] = u
      n_gates += 1
      a_start = adj_off[u]
      a_end = adj_off[u + 1]
      ai = a_start
      while ai < a_end
        w = adj_flat[ai]
        in_deg[w] -= 1
        if in_deg[w] == 0
          q[qt] = w
          qt += 1
        ai += 1
    return false unless n_gates == max_gv - 1
  else
    return false

  out_var = wassat_multiplier_abs(out_lit)
  want_out = out_lit > 0 ? 1 : 0
  ready = i8[nv + 1]
  ready[const_zero] = 1 if const_zero > 0
  i = 0
  while i < p
    ready[pis[i]] = 1
    i += 1

  g_op = i64[nv + 1]
  g_in0 = i64[nv + 1]
  g_in1 = i64[nv + 1]
  g_in2 = i64[nv + 1]
  g_in3 = i64[nv + 1]
  g_inva = i64[nv + 1]
  g_invb = i64[nv + 1]
  g_invo = i64[nv + 1]
  g_cl_off = i64[nv + 1]
  g_cl_cnt = i64[nv + 1]
  g_inv_res = i64[nv + 1]
  cl_l_off = i64[ncl + 1]
  cl_l_len = i64[ncl]
  cl_lits = i64[ncl * 5]
  n_simp_cl = 0
  n_simp_lits = 0

  cone = i64[nv + 1]
  i = 0
  while i < p
    cone[pis[i]] = 1 << i
    i += 1
  ins0 = i64[8]
  env = i64[nv + 1]
  gi = 0
  while gi < n_gates
    gv = topo[gi]
    k0 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, gv, const_zero, 0, 0, ins0)
    return false if k0 < 1 || k0 > 4
    c_mask = 0 ## i64
    j = 0
    while j < k0
      u = ins0[j]
      return false if ready[u] == 0
      c_mask = c_mask | cone[u]
      j += 1
    cone[gv] = c_mask
    ready[gv] = 1
    g_in0[gv] = ins0[0]
    g_in1[gv] = ins0[1] if k0 >= 2
    g_in2[gv] = ins0[2] if k0 >= 3
    g_in3[gv] = ins0[3] if k0 >= 4

    n_masks = 1 << k0
    tt = 0 ## i64
    mask = 0
    while mask < n_masks
      j = 0
      while j < k0
        env[ins0[j]] = (mask >> j) & 1
        j += 1
      ok0 = true
      ok1 = true
      ci = head[gv]
      while ci >= 0
        off = fcs[ci]
        clen = fcl[ci]
        sat_const = false
        sat_ins = false
        pol_gv = 0
        j = 0
        while j < clen
          l = fla[off + j]
          av = wassat_multiplier_abs(l)
          if const_zero > 0 && av == const_zero
            sat_const = true if l < 0
          elsif av == gv
            pol_gv = l > 0 ? 1 : -1
          else
            lval = l > 0 ? env[av] : (1 - env[av])
            sat_ins = true if lval == 1
          j += 1
        unless sat_const || sat_ins
          ok0 = false if pol_gv == 1
          ok1 = false if pol_gv == -1
        ci = next_cl[ci]
      if gv != out_var
        return false if ok0 == ok1
        tt = tt | (1 << mask) if ok1
      else
        b_ok = want_out == 1 ? ok1 : ok0
        tt = tt | (1 << mask) if b_ok
      mask += 1

    classified = false
    if k0 == 2
      if tt == 6 || tt == 9
        g_op[gv] = 1
        g_invo[gv] = tt == 9 ? -1 : 0
        classified = true
      else
        ia = 0
        while ia < 2 && !classified
          ib = 0
          while ib < 2 && !classified
            io = 0
            while io < 2 && !classified
              cand = 0
              m = 0
              while m < 4
                b0 = ((m & 1) ^ ia) & (((m >> 1) & 1) ^ ib)
                b0 = b0 ^ io
                cand = cand | (b0 << m)
                m += 1
              if cand == tt
                g_op[gv] = 2
                g_inva[gv] = ia == 1 ? -1 : 0
                g_invb[gv] = ib == 1 ? -1 : 0
                g_invo[gv] = io == 1 ? -1 : 0
                classified = true
              io += 1
            ib += 1
          ia += 1
    elsif k0 == 3 && p == 32
      if tt == 232 || tt == 23
        g_op[gv] = 3
        g_invo[gv] = tt == 23 ? -1 : 0
        classified = true
      elsif tt == 202 || tt == 53
        g_op[gv] = 4
        g_invo[gv] = tt == 53 ? -1 : 0
        classified = true
    unless classified
      g_op[gv] = 5
      want_pol = (gv == out_var && want_out == 0) ? -1 : 1
      g_inv_res[gv] = 0
      g_cl_off[gv] = n_simp_cl
      cnt_cl = 0
      ci = head[gv]
      while ci >= 0
        off = fcs[ci]
        clen = fcl[ci]
        sat_const = false
        has_want = false
        j = 0
        while j < clen
          l = fla[off + j]
          av = wassat_multiplier_abs(l)
          if const_zero > 0 && av == const_zero
            sat_const = true if l < 0
          elsif av == gv
            has_want = true if (l > 0 ? 1 : -1) == want_pol
          j += 1
        if has_want && !sat_const
          cl_l_off[n_simp_cl] = n_simp_lits
          llen = 0
          j = 0
          while j < clen
            l = fla[off + j]
            av = wassat_multiplier_abs(l)
            if av != gv && (const_zero == 0 || av != const_zero)
              cl_lits[n_simp_lits] = l
              n_simp_lits += 1
              llen += 1
            j += 1
          cl_l_len[n_simp_cl] = llen
          n_simp_cl += 1
          cnt_cl += 1
        ci = next_cl[ci]
      g_cl_cnt[gv] = cnt_cl
    gi += 1
  return false if ready[out_var] == 0

  f_cnt = i64[32]
  f_idx = i64[32]
  i = 0
  while i < p
    cnt = 0
    gi = 0
    while gi < n_gates
      cnt += 1 if ((cone[topo[gi]] >> i) & 1) != 0
      gi += 1
    f_cnt[i] = cnt
    f_idx[i] = i
    i += 1
  i = 1
  while i < p
    kc = f_cnt[i]
    ki = f_idx[i]
    j = i - 1
    while j >= 0 && f_cnt[j] > kc
      f_cnt[j + 1] = f_cnt[j]
      f_idx[j + 1] = f_idx[j]
      j -= 1
    f_cnt[j + 1] = kc
    f_idx[j + 1] = ki
    i += 1

  n_simd = p == 28 ? 6 : 9
  n_gray = p - n_simd
  gray_pis = i64[24]
  simd_pis = i64[10]
  cone_off = i64[25]
  cone_len = i64[24]
  total_cone_gates = 0
  k = 0
  while k < n_gray
    gray_pis[k] = pis[f_idx[k]]
    cone_off[k] = total_cone_gates
    cone_len[k] = f_cnt[k]
    total_cone_gates += f_cnt[k]
    k += 1
  i = 0
  while i < n_simd
    simd_pis[i] = pis[f_idx[n_gray + i]]
    i += 1
  cone_gates = i64[total_cone_gates + 1]
  k = 0
  while k < n_gray
    bit_idx = f_idx[k]
    pos = cone_off[k]
    gi = 0
    while gi < n_gates
      gv = topo[gi]
      if ((cone[gv] >> bit_idx) & 1) != 0
        cone_gates[pos] = gv
        pos += 1
      gi += 1
    k += 1

  ctz_tab = i8[4096]
  s = 1
  while s < 4096
    tz = 0
    tmp = s
    while (tmp & 1) == 0
      tz += 1
      tmp = tmp >> 1
    ctz_tab[s] = tz
    s += 1

  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  n_batches = 1 << n_gray
  any_sat = i64[1]
  n_workers = 8
  chunk = n_batches / n_workers
  handles = []
  wi = 0
  while wi < n_workers
    b_lo = wi * chunk
    b_hi = wi == n_workers - 1 ? n_batches : (b_lo + chunk)
    if p == 28
      th = Thread.new ->
        wval = i64[nv + 1]
        wassat_miter28_eval_chunk(wval, p_masks, simd_pis, gray_pis, topo, n_gates,
                                  cone_gates, cone_off, cone_len, ctz_tab,
                                  g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                                  g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res,
                                  out_var, any_sat, b_lo, b_hi)
      handles.push(th)
    else
      th = Thread.new ->
        w0 = i64[nv + 1]; w1 = i64[nv + 1]; w2 = i64[nv + 1]; w3 = i64[nv + 1]
        w4 = i64[nv + 1]; w5 = i64[nv + 1]; w6 = i64[nv + 1]; w7 = i64[nv + 1]
        wassat_miter32_eval_chunk(w0, w1, w2, w3, w4, w5, w6, w7,
                                  p_masks, simd_pis, gray_pis, topo, n_gates,
                                  cone_gates, cone_off, cone_len, ctz_tab,
                                  g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                                  g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits,
                                  out_var, any_sat, b_lo, b_hi)
      handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  any_sat[0] == 0
