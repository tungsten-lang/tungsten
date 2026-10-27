# Exact-one block CSP lane (iterative symmetry fixing + degree peeling),
# split out of mdp.w. Superseded in the long run by the generic block-CSP
# engine in block_csp.w; kept here with its measured SC2026 rows.

-> wassat_symmetry_fix_solve(formula, result)
  return result unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return result if nv < 100 || nv > 40000 || ncl < 500 || ncl > 1200000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  one = 1 ## i64
  block_len = i64[1800]
  block_vars = i64[1800 * 24]
  var_block = i64[nv + 1]
  var_bit = i64[nv + 1]
  dom = i64[1800]
  blk_alive = i8[1800]
  nblocks = 0
  tot_bvars = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n >= 3
      if n > 24 || nblocks >= 1800
        return result
      off = fcs[ci]
      all_pos = true
      j = 0
      while j < n
        if fla[off + j] < 1 || fla[off + j] > nv
          all_pos = false
          break
        j += 1
      if all_pos
        bi = nblocks
        nblocks += 1
        block_len[bi] = n
        dom[bi] = (one << n) - one
        blk_alive[bi] = 1
        j = 0
        while j < n
          v = fla[off + j]
          return result if var_block[v] != 0
          block_vars[bi * 24 + j] = v
          var_block[v] = bi + 1
          var_bit[v] = j
          tot_bvars += 1
          j += 1
    ci += 1
  return result if nblocks < 10 || tot_bvars != nv

  forbid = i64[(nv + 1) * nblocks]
  blk_has = i8[nblocks * nblocks]
  blk_adj = i64[nblocks * nblocks]
  blk_deg = i64[nblocks]
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    if n == 1
      l0 = fla[off]
      if l0 > 0 && l0 <= nv
        bi = var_block[l0] - 1
        dom[bi] = dom[bi] & (one << var_bit[l0])
      elsif l0 < 0 && (0 - l0) <= nv
        v = 0 - l0
        bi = var_block[v] - 1
        dom[bi] = dom[bi] & ((one << block_len[bi]) - one - (one << var_bit[v]))
    elsif n == 2
      l0 = fla[off]
      l1 = fla[off + 1]
      if l0 < 0 && l1 < 0
        u = 0 - l0
        v = 0 - l1
        if u >= 1 && u <= nv && v >= 1 && v <= nv
          bu = var_block[u] - 1
          bv = var_block[v] - 1
          if bu != bv
            forbid[u * nblocks + bv] = forbid[u * nblocks + bv] | (one << var_bit[v])
            forbid[v * nblocks + bu] = forbid[v * nblocks + bu] | (one << var_bit[u])
            if blk_has[bu * nblocks + bv] == 0
              blk_has[bu * nblocks + bv] = 1
              blk_adj[bu * nblocks + blk_deg[bu]] = bv
              blk_deg[bu] += 1
            if blk_has[bv * nblocks + bu] == 0
              blk_has[bv * nblocks + bu] = 1
              blk_adj[bv * nblocks + blk_deg[bv]] = bu
              blk_deg[bv] += 1
    ci += 1

  peel_stack = i64[1800]
  n_peeled = 0
  while true
    changed = false
    peel_loop = true
    while peel_loop
      peel_loop = false
      bi = 0
      while bi < nblocks
        if blk_alive[bi] == 1
          d = dom[bi]
          if d == 0
            result["recognized"] = true
            result["bits"] = nblocks
            result["samples"] = nv
            result["trials"] = 1
            result["status"] = -1
            return result
          if (d & (d - one)) == 0
            blk_alive[bi] = 0
            peel_stack[n_peeled] = bi
            n_peeled += 1
            b = wassat_mdp_ctz64(d)
            u = block_vars[bi * 24 + b]
            deg = blk_deg[bi]
            i = 0
            while i < deg
              bj = blk_adj[bi * nblocks + i]
              if blk_alive[bj] == 1
                dom[bj] = dom[bj] & (dom[bj] ^ (dom[bj] & forbid[u * nblocks + bj]))
              i += 1
            peel_loop = true
            changed = true
          else
            tot_hit = 0
            deg = blk_deg[bi]
            i = 0
            while i < deg
              bj = blk_adj[bi * nblocks + i]
              if blk_alive[bj] == 1
                mh = 0
                dj = dom[bj]
                while dj != 0
                  bj_b = wassat_mdp_ctz64(dj)
                  dj = dj & (dj - one)
                  cnt = wassat_mdp_pop64(forbid[block_vars[bj * 24 + bj_b] * nblocks + bi] & d)
                  mh = cnt if cnt > mh
                tot_hit += mh
              i += 1
            if tot_hit < wassat_mdp_pop64(d)
              blk_alive[bi] = 0
              peel_stack[n_peeled] = bi
              n_peeled += 1
              peel_loop = true
              changed = true
        bi += 1

    bi = 0
    while bi < nblocks
      if blk_alive[bi] == 1
        d = dom[bi]
        if (d & (d - one)) != 0
          blen = block_len[bi]
          deg = blk_deg[bi]
          bv = 0
          while bv < blen
            if ((dom[bi] >> bv) & 1) != 0
              v = block_vars[bi * 24 + bv]
              bu = 0
              while bu < blen
                if bu != bv && ((dom[bi] >> bu) & 1) != 0
                  u = block_vars[bi * 24 + bu]
                  sub = true
                  eq = true
                  i = 0
                  while i < deg
                    bj = blk_adj[bi * nblocks + i]
                    if blk_alive[bj] == 1
                      dj = dom[bj]
                      mu = forbid[u * nblocks + bj] & dj
                      mv = forbid[v * nblocks + bj] & dj
                      if (mu & (mu ^ (mu & mv))) != 0
                        sub = false
                        break
                      eq = false if mu != mv
                    i += 1
                  if sub && (!eq || bu < bv)
                    dom[bi] = dom[bi] ^ (one << bv)
                    changed = true
                    break
                bu += 1
            bv += 1
      bi += 1
    break unless changed

  if n_peeled == nblocks
    cur_val = i64[nblocks]
    p = n_peeled - 1
    while p >= 0
      bi = peel_stack[p]
      avail = dom[bi]
      deg = blk_deg[bi]
      i = 0
      while i < deg
        bj = blk_adj[bi * nblocks + i]
        if blk_alive[bj] == 1
          u_bj = block_vars[bj * 24 + cur_val[bj]]
          avail = avail & (avail ^ (avail & forbid[u_bj * nblocks + bi]))
        i += 1
      return result if avail == 0
      cur_val[bi] = wassat_mdp_ctz64(avail)
      blk_alive[bi] = 1
      p -= 1
    model = i64[nv]
    v = 1
    while v <= nv
      bi = var_block[v] - 1
      chosen = block_vars[bi * 24 + cur_val[bi]]
      model[v - 1] = v == chosen ? v : 0 - v
      v += 1
    if wassat_model_satisfies?(formula, model)
      result["recognized"] = true
      result["bits"] = nblocks
      result["samples"] = nv
      result["trials"] = 1
      result["status"] = 1
      result["model"] = model
  result

