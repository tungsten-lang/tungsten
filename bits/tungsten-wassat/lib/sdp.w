# Syndrome-decoding (SDP_n_w) lane, split out of mdp.w. See wassat_sdp_solve.

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

