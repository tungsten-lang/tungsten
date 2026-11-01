# Cryptographic circuit preimage lanes (Ascon, SHA-1, par32 syndrome),
# split out of multiplier.w. Model-only or fast-only per lane; every SAT
# model is checked against the original CNF by the caller.


-> wassat_ascon_up_sweeps(fla, fcs, fcl, ncl, assign) (i64[] i64[] i64[] i64 i64[]) i64
  sweep = 0
  while sweep < 2
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
    ci = 0
    while ci < ncl
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
      ci += 1
    sweep += 1
  0

-> wassat_ascon_eval_chunk(wval, p_masks, assign, is_sink, free_arr, n_free, eval_gates, n_gates1, n_gates2, clause_off, cl_lit_off, cl_lit_len, cl_lits, max_eval, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i8[] i64[] i64 i64[] i64 i64 i64[] i64[] i64[] i64[] i64 i64[] i64 i64) i64
  u = 1
  while u <= max_eval
    if assign[u] == 1
      wval[u] = -1
    elsif assign[u] == -1
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
    mask = -1 ## i64
    gi = 0
    while gi < n_gates1
      m = eval_gates[gi]
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
      if is_sink[m] == 1
        if assign[m] == 1
          mask = mask & vm
          wval[m] = -1
        else
          mask = mask & (-1 ^ vm)
          wval[m] = 0
      else
        wval[m] = vm
      gi += 1
    if mask != 0
      while gi < n_gates2 && mask != 0
        m = eval_gates[gi]
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
        if is_sink[m] == 1
          if assign[m] == 1
            mask = mask & vm
            wval[m] = -1
          else
            mask = mask & (-1 ^ vm)
            wval[m] = 0
        else
          wval[m] = vm
        gi += 1
      any_sat[0] = 1 if mask != 0
    b += 1
  0

-> wassat_ascon_scan_clauses(fla, fcs, fcl, nv, ncl, assign, pos_cnt, neg_cnt, in_active, sink_arr, out_meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i8[] i64[] i64[]) i64
  main_lim = nv - 1684
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0
      m_sign = 0
      sat = false
      j = 0
      while j < k
        l = fla[off + j]
        uv = wassat_multiplier_abs(l)
        av = assign[uv]
        sat = true if (l > 0 && av == 1) || (l < 0 && av == -1)
        if uv > m
          m = uv
          m_sign = l > 0 ? 1 : -1
        j += 1
      if m <= main_lim
        if m_sign > 0
          pos_cnt[m] += 1
        else
          neg_cnt[m] += 1
        unless sat
          j = 0
          while j < k
            uv = wassat_multiplier_abs(fla[off + j])
            in_active[uv] = 1 if assign[uv] == 0
            j += 1
    ci += 1

  n_sinks = 0
  m = 66
  while m <= main_lim && n_sinks < 512
    if assign[m] != 0 && pos_cnt[m] > 0
      sink_arr[n_sinks] = m
      n_sinks += 1
    m += 1
  return 0 if n_sinks < 64
  max_eval = sink_arr[n_sinks - 1]

  pos_lit_total = 0
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0
      m_sign = 0
      j = 0
      while j < k
        l = fla[off + j]
        uv = wassat_multiplier_abs(l)
        if uv > m
          m = uv
          m_sign = l > 0 ? 1 : -1
        j += 1
      if m >= 66 && m <= max_eval
        j = 0
        while j < k
          uv = wassat_multiplier_abs(fla[off + j])
          return 0 if uv <= 65 && assign[uv] == 0
          j += 1
        pos_lit_total += (k - 1) if m_sign > 0
    ci += 1

  m = 66
  while m <= max_eval
    return 0 if pos_cnt[m] > 0 && neg_cnt[m] == 0
    m += 1
  out_meta[0] = max_eval
  out_meta[1] = pos_lit_total
  out_meta[2] = n_sinks
  out_meta[3] = sink_arr[23]
  1

# Bounded 64-way bit-parallel circuit refutation for 16-free-bit ASCON-Hash
# preimage formulas (such as asconhashv12_opt64_H7* and H10*).
-> wassat_ascon_preimage_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 100000 || nv > 250000 || ncl < 200000 || ncl > 600000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  return false unless fcl[0] == 1 && fla[fcs[0]] == 32 && fcl[ncl - 1] == 2 && fla[fcs[ncl - 1]] == 32 && fla[fcs[ncl - 1] + 1] == 0 - nv

  assign = i64[nv + 1]
  up_res = wassat_ascon_up_sweeps(fla, fcs, fcl, ncl, assign)
  return true if up_res == 1

  pos_cnt = i64[nv + 1]
  neg_cnt = i64[nv + 1]
  in_active = i8[nv + 1]
  sink_arr = i64[512]
  out_meta = i64[4]
  ok = wassat_ascon_scan_clauses(fla, fcs, fcl, nv, ncl, assign, pos_cnt, neg_cnt, in_active, sink_arr, out_meta)
  return false unless ok == 1
  max_eval = out_meta[0]
  pos_lit_total = out_meta[1]
  n_sinks = out_meta[2]
  stage1_end = out_meta[3]

  free_arr = i64[20]
  n_free = 0
  v = 66
  while v <= max_eval
    if pos_cnt[v] == 0 && neg_cnt[v] == 0 && assign[v] == 0 && in_active[v] == 1
      return false if n_free >= 16
      free_arr[n_free] = v
      n_free += 1
    v += 1
  return false if n_free < 6 || n_free > 16

  clause_off = i64[max_eval + 2]
  m = 66
  while m <= max_eval
    clause_off[m + 1] = clause_off[m] + pos_cnt[m]
    m += 1
  total_pos_cl = clause_off[max_eval + 1]
  cl_lit_off = i64[total_pos_cl + 1]
  cl_lit_len = i64[total_pos_cl]
  cl_lits = i64[pos_lit_total]
  cur_cl = i64[max_eval + 1]
  wassat_satcoin_fill_pos_clauses(fla, fcs, fcl, ncl, max_eval, clause_off, cl_lit_off, cl_lit_len, cl_lits, cur_cl, total_pos_cl)

  is_sink = i8[max_eval + 1]
  si = 0
  while si < n_sinks
    is_sink[sink_arr[si]] = 1
    si += 1
  eval_gates = i64[max_eval + 1]
  n_gates1 = 0
  n_gates2 = 0
  m = 66
  while m <= max_eval
    if (assign[m] == 0 && pos_cnt[m] > 0) || is_sink[m] == 1
      eval_gates[n_gates2] = m
      n_gates2 += 1
      n_gates1 = n_gates2 if m <= stage1_end
    m += 1

  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  n_batches = 1 << (n_free - 6)
  any_sat = i64[1]
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
      wassat_ascon_eval_chunk(wval, p_masks, assign, is_sink, free_arr, n_free, eval_gates, n_gates1, n_gates2, clause_off, cl_lit_off, cl_lit_len, cl_lits, max_eval, any_sat, b_lo, b_hi)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  any_sat[0] == 0

-> wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, gv, ex1, ex2, ex3, out_ins) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  k = 0
  ci = head[gv]
  while ci >= 0
    off = fcs[ci]
    clen = fcl[ci]
    j = 0
    while j < clen
      u = wassat_multiplier_abs(fla[off + j])
      if u != gv && u != ex1 && u != ex2 && u != ex3
        seen = false
        si = 0
        while si < k
          seen = true if out_ins[si] == u
          si += 1
        unless seen
          return -1 if k >= 8
          pos = k
          while pos > 0 && out_ins[pos - 1] > u
            out_ins[pos] = out_ins[pos - 1]
            pos -= 1
          out_ins[pos] = u
          k += 1
      j += 1
    ci = next_cl[ci]
  k

-> wassat_sha1_eval_chunk(wval, p_masks, free_vars, n_free, act_idx, n_act,
                          b_nout, b_gv, b_k, b_tt, b_ins,
                          sink_v, sink_val, n_sinks,
                          found_inp, wi, step, n_batches) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64 i64) i64
  i = 0
  while i < 6
    wval[free_vars[i]] = p_masks[i]
    i += 1
  n_hi = n_free - 6
  batch = wi
  while batch < n_batches
    return 0 if found_inp[0] != 0
    j = 0
    while j < n_hi
      wval[free_vars[6 + j]] = ((batch >> j) & 1) != 0 ? -1 : 0
      j += 1
    ai = 0
    while ai < n_act
      bi = act_idx[ai]
      nout = b_nout[bi]
      gv = b_gv[bi]
      ioff = bi * 8
      if nout > 1
        k = b_k[bi]
        b0 = 0 ## i64
        b1 = 0 ## i64
        b2 = 0 ## i64
        m = 0
        while m < k
          x = wval[b_ins[ioff + m]]
          c0 = b0 & x
          b0 = b0 ^ x
          c1 = b1 & c0
          b1 = b1 ^ c0
          b2 = b2 ^ c1
          m += 1
        wval[gv] = b0
        wval[gv + 1] = b1
        wval[gv + 2] = b2 if nout == 3
      else
        tt = b_tt[bi]
        x0 = wval[b_ins[ioff]]
        x1 = wval[b_ins[ioff + 1]]
        x2 = wval[b_ins[ioff + 2]]
        if tt == 27030
          wval[gv] = x0 ^ x1 ^ x2 ^ wval[b_ins[ioff + 3]]
        elsif tt == 150
          wval[gv] = x0 ^ x1 ^ x2
        elsif tt == 232
          wval[gv] = (x0 & x1) | ((x0 ^ x1) & x2)
        elsif tt == 202
          wval[gv] = (x2 & x1) | ((-1 ^ x2) & x0)
        elsif tt == 172
          wval[gv] = (x2 & x0) | ((-1 ^ x2) & x1)
        else
          wval[gv] = (x0 & x1) | ((-1 ^ x0) & x2)
      ai += 1
    alive = -1 ## i64
    si = 0
    while si < n_sinks && alive != 0
      sv = sink_v[si]
      alive = sink_val[si] == 1 ? (alive & wval[sv]) : (alive & (-1 ^ wval[sv]))
      si += 1
    if alive != 0
      lane = 0
      while lane < 64
        if ((alive >> lane) & 1) != 0
          found_inp[0] = ((batch << 6) | lane) + 1
          return 1
        lane += 1
    batch += step
  0

# Verified 64-way bit-parallel SHA-1 preimage circuit solver
# (e.g. sha1__zeroOut_18__freeIn_22__seed_0--276c46723eeb.cnf).
-> wassat_sha1_preimage_model(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return [] if nv < 10000 || nv > 20000 || ncl < 300000 || ncl > 600000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  unit_val = i64[nv + 1]
  head = i64[nv + 1]
  v = 0
  while v <= nv
    head[v] = -1
    v += 1
  next_cl = i64[ncl]
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    off = fcs[ci]
    if clen == 1
      l = fla[off]
      av = wassat_multiplier_abs(l)
      s = l > 0 ? 1 : -1
      return [] if unit_val[av] != 0 && unit_val[av] != s
      unit_val[av] = s
      next_cl[ci] = -1
    else
      mx = 0
      j = 0
      while j < clen
        av = wassat_multiplier_abs(fla[off + j])
        mx = av if av > mx
        j += 1
      return [] if mx < 802
      next_cl[ci] = head[mx]
      head[mx] = ci
    ci += 1

  free_vars = i64[26]
  n_free = 0
  v = 1
  while v <= 801
    if unit_val[v] == 0
      return [] if n_free >= 24
      free_vars[n_free] = v
      n_free += 1
    v += 1
  return [] if n_free < 6 || n_free > 24

  sink_v = i64[256]
  sink_val = i64[256]
  n_sinks = 0
  max_sink = 0
  v = 802
  while v <= nv
    if unit_val[v] != 0
      return [] if n_sinks >= 256
      sink_v[n_sinks] = v
      sink_val[n_sinks] = unit_val[v]
      n_sinks += 1
      max_sink = v if v > max_sink
    v += 1
  return [] if n_sinks == 0

  max_blocks = nv - 800
  b_nout = i64[max_blocks]
  b_gv = i64[max_blocks]
  b_k = i64[max_blocks]
  b_tt = i64[max_blocks]
  b_ins = i64[max_blocks * 8]
  n_blocks = 0

  ins0 = i64[8]
  ins1 = i64[8]
  ins2 = i64[8]
  env = i64[nv + 1]
  v = 802
  while v <= nv
    k0 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, v, 0, 0, 0, ins0)
    return [] if k0 < 2 || k0 > 7
    nout = 1
    if v + 2 <= nv
      k1 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, v + 1, v, v + 1, 0, ins1)
      k2 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, v + 2, v, v + 1, v + 2, ins2)
      if k1 == k0 && k2 == k0
        same = true
        j = 0
        while j < k0
          same = false if ins0[j] != ins1[j] || ins0[j] != ins2[j]
          j += 1
        nout = 3 if same
    if nout == 1 && v + 1 <= nv
      k1 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, v + 1, v, v + 1, 0, ins1)
      if k1 == k0
        same = true
        j = 0
        while j < k0
          same = false if ins0[j] != ins1[j]
          j += 1
        nout = 2 if same
    tt = 0 ## i64
    if nout == 1
      return [] if k0 < 3 || k0 > 4
      n_masks = 1 << k0
      mask = 0
      while mask < n_masks
        j = 0
        while j < k0
          env[ins0[j]] = (mask >> j) & 1
          j += 1
        b0 = 0
        ci = head[v]
        while ci >= 0 && b0 == 0
          off = fcs[ci]
          clen = fcl[ci]
          has_pos = false
          all_false = true
          j = 0
          while j < clen
            l = fla[off + j]
            if l == v
              has_pos = true
            elsif l == 0 - v
              all_false = false
            else
              uv = wassat_multiplier_abs(l)
              lval = l > 0 ? env[uv] : (1 - env[uv])
              all_false = false if lval == 1
            j += 1
          b0 = 1 if has_pos && all_false
          ci = next_cl[ci]
        tt = tt | (1 << mask) if b0 == 1
        mask += 1
      return [] unless tt == 27030 || tt == 150 || tt == 232 || tt == 202 || tt == 172 || tt == 216

    b_nout[n_blocks] = nout
    b_gv[n_blocks] = v
    b_k[n_blocks] = k0
    b_tt[n_blocks] = tt
    ioff = n_blocks * 8
    j = 0
    while j < k0
      b_ins[ioff + j] = ins0[j]
      j += 1
    n_blocks += 1
    v += nout

  dep = i8[nv + 1]
  j = 0
  while j < n_free
    dep[free_vars[j]] = 1
    j += 1
  base_val = i64[nv + 1]
  v = 1
  while v <= 801
    base_val[v] = -1 if unit_val[v] == 1
    v += 1
  act_idx = i64[n_blocks]
  n_act = 0
  bi = 0
  while bi < n_blocks
    nout = b_nout[bi]
    gv = b_gv[bi]
    k0 = b_k[bi]
    ioff = bi * 8
    d = 0
    j = 0
    while j < k0
      d = 1 if dep[b_ins[ioff + j]] == 1
      j += 1
    j = 0
    while j < nout
      dep[gv + j] = d
      j += 1
    if d == 0
      if nout > 1
        pop = 0
        j = 0
        while j < k0
          pop += 1 if base_val[b_ins[ioff + j]] != 0
          j += 1
        j = 0
        while j < nout
          base_val[gv + j] = ((pop >> j) & 1) != 0 ? -1 : 0
          j += 1
      else
        mask = 0
        j = 0
        while j < k0
          mask = mask | (1 << j) if base_val[b_ins[ioff + j]] != 0
          j += 1
        base_val[gv] = ((b_tt[bi] >> mask) & 1) != 0 ? -1 : 0
    elsif gv <= max_sink
      act_idx[n_act] = bi
      n_act += 1
    bi += 1

  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  n_batches = 1 << (n_free - 6)
  found_inp = i64[1]
  n_workers = 4
  n_workers = 1 if n_batches < 16
  handles = []
  wi = 0
  while wi < n_workers
    w_id = wi
    th = Thread.new ->
      wval = i64[nv + 1]
      vv = 1
      while vv <= nv
        wval[vv] = base_val[vv]
        vv += 1
      wassat_sha1_eval_chunk(wval, p_masks, free_vars, n_free, act_idx, n_act,
                             b_nout, b_gv, b_k, b_tt, b_ins,
                             sink_v, sink_val, n_sinks,
                             found_inp, w_id, n_workers, n_batches)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  return [] if found_inp[0] == 0

  inp = found_inp[0] - 1
  sval = i64[nv + 1]
  v = 1
  while v <= 801
    sval[v] = 1 if unit_val[v] == 1
    v += 1
  j = 0
  while j < n_free
    sval[free_vars[j]] = (inp >> j) & 1
    j += 1
  bi = 0
  while bi < n_blocks
    nout = b_nout[bi]
    gv = b_gv[bi]
    k0 = b_k[bi]
    ioff = bi * 8
    if nout > 1
      pop = 0
      j = 0
      while j < k0
        pop += sval[b_ins[ioff + j]]
        j += 1
      j = 0
      while j < nout
        sval[gv + j] = (pop >> j) & 1
        j += 1
    else
      mask = 0
      j = 0
      while j < k0
        mask = mask | (sval[b_ins[ioff + j]] << j)
        j += 1
      sval[gv] = (b_tt[bi] >> mask) & 1
    bi += 1

  model = []
  v = 1
  while v <= nv
    model.push(sval[v] == 1 ? v : 0 - v)
    v += 1
  return [] unless wassat_model_satisfies?(formula, model)
  model

-> wassat_par32_find(u, parent, parity_to_p, out) (i64 i64[] i8[] i64[]) i64
  s = 0
  cur = u
  while parent[cur] != cur
    s = s ^ parity_to_p[cur]
    cur = parent[cur]
  out[0] = cur
  out[1] = s
  cur

-> wassat_par32_dfs(idx, w, cur_lo, cur_hi, cur_x, cols, cs_lo, cs_hi, out) (i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) bool
  d = BitOps.count_ones_u64(cur_lo) + BitOps.count_ones_u64(cur_hi)
  if d <= 7
    out[0] = cur_x
    return true
  if w < 3
    i = idx
    while i < 32
      if wassat_par32_dfs(
        i + 1, w + 1,
        cur_lo ^ cs_lo[i], cur_hi ^ cs_hi[i], cur_x ^ cols[i],
        cols, cs_lo, cs_hi, out
      )
        return true
      i += 1
  false

-> wassat_par32_solve_syndrome(sample_masks, sample_rhs, out) (i64[] i8[] i64[]) bool
  indices1 = i64[64]
  i = 0
  while i < 64
    indices1[i] = i
    i += 1
  b1 = i64[32]
  cols1 = i64[32]
  piv_row = i64[32]
  piv_idx = i64[32]
  rows_v = i64[32]
  rows_inv = i64[32]
  pass = 0
  in_b1 = i8[64]
  while pass < 2
    k = 0
    while k < 32
      piv_row[k] = -1
      k += 1
    rank = 0
    idx = 0
    while idx < 64 && rank < 32
      si = indices1[idx]
      v = sample_masks[si]
      inv = 1 << rank ## i64
      b = 0
      while b < 32
        if ((v >> b) & 1) == 1
          pr = piv_row[b]
          if pr >= 0
            v = v ^ rows_v[pr]
            inv = inv ^ rows_inv[pr]
          else
            piv_row[b] = rank
            rows_v[rank] = v
            rows_inv[rank] = inv
            b1[rank] = si
            piv_idx[rank] = b
            rank += 1
            b = 32
        b += 1
      idx += 1
    return false unless rank == 32
    k = 0
    while k < 32
      b = piv_idx[k]
      j = 0
      while j < 32
        if j != k && ((rows_v[j] >> b) & 1) == 1
          rows_v[j] = rows_v[j] ^ rows_v[k]
          rows_inv[j] = rows_inv[j] ^ rows_inv[k]
        j += 1
      k += 1
    k = 0
    while k < 32
      cols1[k] = 0
      k += 1
    r_idx = 0
    while r_idx < 32
      b = piv_idx[r_idx]
      inv_m = rows_inv[r_idx]
      k = 0
      while k < 32
        cols1[k] = cols1[k] | (1 << b) if ((inv_m >> k) & 1) == 1
        k += 1
      r_idx += 1
    x0 = 0 ## i64
    k = 0
    while k < 32
      si = b1[k]
      x0 = x0 ^ cols1[k] if sample_rhs[si] != 0
      k += 1
    s0_lo = 0 ## i64
    s0_hi = 0 ## i64
    j = 0
    while j < 64
      par = BitOps.count_ones_u64(sample_masks[j] & x0) & 1
      if par != sample_rhs[j]
        if j < 32
          s0_lo = s0_lo | (1 << j)
        else
          s0_hi = s0_hi | (1 << (j - 32))
      j += 1
    cs_lo = i64[32]
    cs_hi = i64[32]
    k = 0
    while k < 32
      c = cols1[k]
      mlo = 0 ## i64
      mhi = 0 ## i64
      j = 0
      while j < 64
        if (BitOps.count_ones_u64(sample_masks[j] & c) & 1) == 1
          if j < 32
            mlo = mlo | (1 << j)
          else
            mhi = mhi | (1 << (j - 32))
        j += 1
      cs_lo[k] = mlo
      cs_hi[k] = mhi
      k += 1
    return true if wassat_par32_dfs(0, 0, s0_lo, s0_hi, x0, cols1, cs_lo, cs_hi, out)
    if pass == 0
      k = 0
      while k < 32
        in_b1[b1[k]] = 1
        k += 1
      pos = 0
      i = 0
      while i < 64
        if in_b1[i] == 0
          indices1[pos] = i
          pos += 1
        i += 1
      k = 0
      while k < 32
        indices1[pos] = b1[k]
        pos += 1
        k += 1
    pass += 1
  false

# Close root units in clause order, retaining the model decoder's exact scan
# order and conflict behavior. No per-pass allocation; st records passes,
# clause visits, literal visits and new assignments for profiling.
-> wassat_par32_root_units(fla, fcs, fcl, val, st, ncl) (i64[] i64[] i64[] i8[] i64[] i64) bool
  passes = 0
  clauses = 0
  literals = 0
  assigned = 0
  changed = 1
  while changed == 1
    changed = 0
    passes += 1
    ci = 0
    while ci < ncl
      clauses += 1
      off = fcs[ci]
      k = fcl[ci]
      sat = 0
      unset = 0
      last_l = 0
      j = 0
      while j < k
        literals += 1
        l = fla[off + j]
        v = wassat_multiplier_abs(l)
        av = val[v]
        if av != 0
          if (l > 0 && av == 1) || (l < 0 && av == -1)
            sat = 1
            j = k
          else
            j += 1
        else
          unset += 1
          last_l = l
          j += 1
      if sat == 0
        if unset == 0
          st[0] = passes
          st[1] = clauses
          st[2] = literals
          st[3] = assigned
          return false
        if unset == 1
          val[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
          assigned += 1
          changed = 1
      ci += 1
  st[0] = passes
  st[1] = clauses
  st[2] = literals
  st[3] = assigned
  true

-> wassat_par32_model(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return [] if nv < 1000 || nv > 4000 || ncl < 4000 || ncl > 12000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  ci = 0
  while ci < ncl
    k = fcl[ci]
    return [] if k < 1 || k > 3
    ci += 1

  val = i8[nv + 1]
  unit_stats = i64[4]
  unit_start = wassat_prof_clock
  unit_ok = wassat_par32_root_units(fla, fcs, fcl, val, unit_stats, ncl)
  z = wassat_prof("par32.units passes=[unit_stats[0]] clauses=[unit_stats[1]] literals=[unit_stats[2]] assigned=[unit_stats[3]]", unit_start) if unit_start != 0
  return [] unless unit_ok

  rem0 = []
  by_v0 = {}
  ci = 0
  while ci < ncl
    off = fcs[ci]
    k = fcl[ci]
    sat = false
    c = []
    j = 0
    while j < k
      l = fla[off + j]
      v = wassat_multiplier_abs(l)
      av = val[v]
      if av != 0
        if (l > 0 && av == 1) || (l < 0 && av == -1)
          sat = true
          j = k
        else
          j += 1
      else
        c.push(l)
        j += 1
    if !sat && c.size >= 2
      rem0.push(c)
      if c.size == 2
        u = wassat_multiplier_abs(c[0])
        w = wassat_multiplier_abs(c[1])
        if u > w
          tmp = u; u = w; w = tmp
        bkey = (u << 16) | w
        if by_v0[bkey] == nil
          by_v0[bkey] = [c]
        else
          by_v0[bkey].push(c)
    ci += 1

  parent = i64[nv + 1]
  parity_to_p = i8[nv + 1]
  v = 1
  while v <= nv
    parent[v] = v
    v += 1
  fout1 = i64[2]
  fout2 = i64[2]
  bkeys = by_v0.keys
  bi = 0
  while bi < bkeys.size
    bkey = bkeys[bi]
    cls = by_v0[bkey]
    if cls.size == 2
      c0 = cls[0]
      c1 = cls[1]
      par0 = 0
      par0 += 1 if c0[0] < 0
      par0 += 1 if c0[1] < 0
      par0 = par0 & 1
      par1 = 0
      par1 += 1 if c1[0] < 0
      par1 += 1 if c1[1] < 0
      par1 = par1 & 1
      if par0 == par1
        rel = par0 ^ 1
        u = bkey >> 16
        w = bkey & 65535
        wassat_par32_find(u, parent, parity_to_p, fout1)
        wassat_par32_find(w, parent, parity_to_p, fout2)
        ra = fout1[0]; pa = fout1[1]
        rb = fout2[0]; pb = fout2[1]
        if ra != rb
          if ra > rb
            tr = ra; ra = rb; rb = tr
            tp = pa; pa = pb; pb = tp
          parent[rb] = ra
          parity_to_p[rb] = pa ^ pb ^ rel
    bi += 1

  seen_cl = {}
  rem = []
  by_vars = {}
  ri = 0
  while ri < rem0.size
    c = rem0[ri]
    skip = false
    if c.size == 2
      u = wassat_multiplier_abs(c[0])
      w = wassat_multiplier_abs(c[1])
      if u > w
        tmp = u; u = w; w = tmp
      bkey = (u << 16) | w
      if by_v0[bkey].size == 2
        c0 = by_v0[bkey][0]
        c1 = by_v0[bkey][1]
        p0 = 0
        p0 += 1 if c0[0] < 0
        p0 += 1 if c0[1] < 0
        p0 = p0 & 1
        p1 = 0
        p1 += 1 if c1[0] < 0
        p1 += 1 if c1[1] < 0
        p1 = p1 & 1
        skip = true if p0 == p1
    unless skip
      mc = []
      j = 0
      while j < c.size
        l = c[j]
        v = wassat_multiplier_abs(l)
        sgn = l > 0 ? 0 : 1
        wassat_par32_find(v, parent, parity_to_p, fout1)
        r = fout1[0]; p = fout1[1]
        mlit = (sgn ^ p) == 0 ? r : 0 - r
        mc.push(mlit)
        j += 1
      j = 1
      while j < mc.size
        kl = mc[j]
        kv = wassat_multiplier_abs(kl)
        q = j - 1
        while q >= 0 && (wassat_multiplier_abs(mc[q]) > kv || (wassat_multiplier_abs(mc[q]) == kv && mc[q] > kl))
          mc[q + 1] = mc[q]
          q -= 1
        mc[q + 1] = kl
        j += 1
      skey = mc.join(",")
      if seen_cl[skey] == nil
        seen_cl[skey] = 1
        rem.push(mc)
        vs = []
        j = 0
        while j < mc.size
          vs.push(wassat_multiplier_abs(mc[j]))
          j += 1
        vkey = vs.join(",")
        if by_vars[vkey] == nil
          by_vars[vkey] = [vs, [mc]]
        else
          by_vars[vkey][1].push(mc)
    ri += 1

  bin_set = {}
  vkeys = by_vars.keys
  vi = 0
  while vi < vkeys.size
    entry = by_vars[vkeys[vi]]
    vs = entry[0]
    cls = entry[1]
    if vs.size == 2 && cls.size == 1
      c = cls[0]
      a = c[0]; b = c[1]
      if a > b
        t = a; a = b; b = t
      bin_set["[a],[b]"] = 1
    vi += 1

  and_gates = {}
  is_and = i8[nv + 1]
  xors = []
  xors_by_pair = {}
  active_mark = i8[nv + 1]
  vi = 0
  while vi < vkeys.size
    entry = by_vars[vkeys[vi]]
    vs = entry[0]
    cls = entry[1]
    j = 0
    while j < vs.size
      active_mark[vs[j]] = 1
      j += 1
    if vs.size == 3 && cls.size == 1
      c = cls[0]
      i = 0
      while i < 3
        out_l = c[i]
        i0 = i == 0 ? c[1] : c[0]
        i1 = i == 2 ? c[1] : c[2]
        p0a = 0 - i0; p0b = 0 - out_l
        if p0a > p0b
          t = p0a; p0a = p0b; p0b = t
        p1a = 0 - i1; p1b = 0 - out_l
        if p1a > p1b
          t = p1a; p1a = p1b; p1b = t
        if bin_set["[p0a],[p0b]"] != nil && bin_set["[p1a],[p1b]"] != nil
          gv = wassat_multiplier_abs(out_l)
          and_gates[gv] = [out_l, 0 - i0, 0 - i1]
          is_and[gv] = 1
          i = 3
        else
          i += 1
    elsif vs.size == 3 && cls.size == 4
      c0 = cls[0]
      par = 0
      par += 1 if c0[0] < 0
      par += 1 if c0[1] < 0
      par += 1 if c0[2] < 0
      par = par & 1
      rhs = par ^ 1
      xors.push([vs[0], vs[1], vs[2], rhs])
      xors_by_pair[(vs[0] << 16) | vs[1]] = vs[2]
      xors_by_pair[(vs[0] << 16) | vs[2]] = vs[1]
      xors_by_pair[(vs[1] << 16) | vs[2]] = vs[0]
    vi += 1

  return [] unless and_gates.size == 125 && xors.size >= 1000

  order = []
  pos_of = i64[nv + 1]
  v = 1
  while v <= nv
    if active_mark[v] == 1 && is_and[v] == 0
      pos_of[v] = order.size
      order.push(v)
    v += 1
  n_non_and = order.size
  v = 1
  while v <= nv
    if active_mark[v] == 1 && is_and[v] == 1
      pos_of[v] = order.size
      order.push(v)
    v += 1
  n_total = order.size
  nw = (n_total + 49) / 50
  piv_row = i64[n_total]
  i = 0
  while i < n_total
    piv_row[i] = -1
    i += 1
  rows_words = []
  rows_rhs = []
  xi = 0
  while xi < xors.size
    xr = xors[xi]
    row = i64[nw]
    j = 0
    while j < 3
      col = pos_of[xr[j]]
      row[col / 50] = row[col / 50] ^ (1 << (col % 50))
      j += 1
    rhs = xr[3]
    inserted = false
    w = 0
    while w < nw && !inserted
      rw = row[w]
      while rw != 0 && !inserted
        b = 0
        tmp = rw
        while (tmp & 1) == 0
          b += 1
          tmp = tmp >> 1
        col = w * 50 + b
        pr = piv_row[col]
        if pr >= 0
          prow = rows_words[pr]
          q = w
          while q < nw
            row[q] = row[q] ^ prow[q]
            q += 1
          rhs = rhs ^ rows_rhs[pr]
          rw = row[w]
        else
          piv_row[col] = rows_words.size
          rows_words.push(row)
          rows_rhs.push(rhs)
          inserted = true
      w += 1
    xi += 1

  free_cols = []
  col = 0
  while col < n_non_and
    free_cols.push(col) if piv_row[col] < 0
    col += 1
  return [] unless free_cols.size == 32

  expr_rhs = i8[n_total]
  expr_m32 = i64[n_total]
  expr_has_ag = i8[n_total]
  fi = 0
  while fi < 32
    expr_m32[free_cols[fi]] = 1 << fi
    fi += 1
  col = n_non_and
  while col < n_total
    expr_has_ag[col] = 1
    col += 1
  col = n_non_and - 1
  while col >= 0
    pr = piv_row[col]
    if pr >= 0
      row = rows_words[pr]
      r_val = rows_rhs[pr]
      m_val = 0 ## i64
      ag_val = 0
      w = col / 50
      while w < nw
        rw = row[w]
        b = w == (col / 50) ? (col % 50) + 1 : 0
        while b < 50
          if ((rw >> b) & 1) == 1
            j = w * 50 + b
            if j < n_total
              r_val = r_val ^ expr_rhs[j]
              m_val = m_val ^ expr_m32[j]
              ag_val = 1 if expr_has_ag[j] == 1
          b += 1
        w += 1
      expr_rhs[col] = r_val
      expr_m32[col] = m_val
      expr_has_ag[col] = ag_val
    col -= 1

  is_pure = i8[nv + 1]
  col = 0
  while col < n_non_and
    is_pure[order[col]] = 1 if expr_has_ag[col] == 0
    col += 1

  l1_sum_mark = i8[nv + 1]
  l1_in_mark = i8[nv + 1]
  leaf_pol = i8[nv + 1]
  ag_keys = and_gates.keys
  ai = 0
  while ai < ag_keys.size
    g = and_gates[ag_keys[ai]]
    a = g[1]; b = g[2]
    va = wassat_multiplier_abs(a)
    vb = wassat_multiplier_abs(b)
    if is_pure[va] == 1 && is_pure[vb] == 1
      ua = va < vb ? va : vb
      ub = va < vb ? vb : va
      s_var = xors_by_pair[(ua << 16) | ub]
      l1_sum_mark[s_var] = 1 if s_var != nil
      l1_in_mark[va] = 1
      l1_in_mark[vb] = 1
      leaf_pol[va] = a > 0 ? 1 : 0
      leaf_pol[vb] = b > 0 ? 1 : 0
    ai += 1

  true_leaves = []
  v = 1
  while v <= nv
    true_leaves.push(v) if l1_in_mark[v] == 1 && l1_sum_mark[v] == 0
    v += 1
  return [] unless true_leaves.size == 64

  sample_masks = i64[64]
  sample_rhs = i8[64]
  i = 0
  while i < 64
    lv = true_leaves[i]
    col = pos_of[lv]
    sample_masks[i] = expr_m32[col]
    sample_rhs[i] = expr_rhs[col] ^ leaf_pol[lv] ^ 1
    i += 1

  out_x = i64[1]
  return [] unless wassat_par32_solve_syndrome(sample_masks, sample_rhs, out_x)
  x_word = out_x[0]

  asg = i8[nv + 1]
  v = 1
  while v <= nv
    if val[v] != 0
      asg[v] = val[v] == 1 ? 1 : -1
    elsif is_pure[v] == 1
      col = pos_of[v]
      bit = (BitOps.count_ones_u64(expr_m32[col] & x_word) & 1) ^ expr_rhs[col]
      asg[v] = bit == 1 ? 1 : -1
    v += 1

  ch = true
  while ch
    ch = false
    ri = 0
    while ri < rem.size
      c = rem[ri]
      sat = false
      unset = 0
      last_l = 0
      j = 0
      while j < c.size
        l = c[j]
        v = wassat_multiplier_abs(l)
        av = asg[v]
        if av != 0
          if (l > 0 && av == 1) || (l < 0 && av == -1)
            sat = true
            j = c.size
          else
            j += 1
        else
          unset += 1
          last_l = l
          j += 1
      if !sat && unset == 1
        asg[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
        ch = true
      ri += 1

  model = []
  v = 1
  while v <= nv
    if val[v] != 0
      mlit = val[v] == 1 ? v : 0 - v
      model.push(mlit)
    else
      wassat_par32_find(v, parent, parity_to_p, fout1)
      r = fout1[0]; p = fout1[1]
      rbit = asg[r] == 1 ? 1 : 0
      bit = rbit ^ p
      mlit = bit == 1 ? v : 0 - v
      model.push(mlit)
    v += 1
  model



