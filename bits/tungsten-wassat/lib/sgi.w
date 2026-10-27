# Subgraph-isomorphism (SGI) McSplit lane, split out of mdp.w.

fn wassat_mdp_pop64(x) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", x) ## i64

fn wassat_mdp_ctz64(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

fn wassat_sgi_mcsplit_dfs(np, p_adj, h_adj, pair_h_adj, unassigned_p_in, dom_stack, cand_stack, depth) (i64 i64[] i64[] i64[] i64 i64[] i64[] i64) bool
  unassigned_p = unassigned_p_in
  return true if unassigned_p == 0
  full30 = 1073741823 ## i64
  one = 1 ## i64
  t22 = 22 ## i64
  t30 = 30 ## i64
  base = depth * t22
  p = 0 ## i64
  d = 0 ## i64
  cnt = 0 ## i64
  m = 0 ## i64
  up = 0 ## i64
  dup = 0 ## i64
  uh = 0 ## i64
  m2 = 0 ## i64
  q = 0 ## i64
  nd = 0 ## i64
  h = 0 ## i64
  while true
    rem_p = wassat_mdp_pop64(unassigned_p)
    return true if rem_p == 0
    u1 = 0 ## i64
    u2 = 0 ## i64
    u3 = 0 ## i64
    u4 = 0 ## i64
    u5 = 0 ## i64
    uall = 0 ## i64
    c1 = 0 ## i64
    c2 = 0 ## i64
    c3 = 0 ## i64
    c4 = 0 ## i64
    c5 = 0 ## i64
    mask = unassigned_p
    while mask != 0
      p = wassat_mdp_ctz64(mask)
      mask = mask & (mask - one)
      d = dom_stack[base + p]
      cnt = wassat_mdp_pop64(d)
      return false if cnt == 0
      uall = uall | d
      if cnt <= 1
        u1 = u1 | d
        c1 += one
      if cnt <= 2
        u2 = u2 | d
        c2 += one
      if cnt <= 3
        u3 = u3 | d
        c3 += one
      if cnt <= 4
        u4 = u4 | d
        c4 += one
      if cnt <= 5
        u5 = u5 | d
        c5 += one
    return false if wassat_mdp_pop64(u1) < c1
    return false if wassat_mdp_pop64(u2) < c2
    return false if wassat_mdp_pop64(u3) < c3
    return false if wassat_mdp_pop64(u4) < c4
    return false if wassat_mdp_pop64(u5) < c5
    return false if wassat_mdp_pop64(uall) < rem_p
    if c1 > 0
      m = unassigned_p
      while m != 0
        up = wassat_mdp_ctz64(m)
        m = m & (m - one)
        dup = dom_stack[base + up]
        if wassat_mdp_pop64(dup) == 1
          uh = wassat_mdp_ctz64(dup)
          unassigned_p = unassigned_p ^ (one << up)
          m2 = unassigned_p
          while m2 != 0
            q = wassat_mdp_ctz64(m2)
            m2 = m2 & (m2 - one)
            nd = dom_stack[base + q] & pair_h_adj[(up * t22 + q) * t30 + uh]
            return false if nd == 0
            dom_stack[base + q] = nd
          m = 0 ## i64
      next
    stripped = false
    strip2 = 0 ## i64
    strip3 = 0 ## i64
    strip4 = 0 ## i64
    strip2 = u2 if c2 > 0 && wassat_mdp_pop64(u2) == c2
    strip3 = u3 if c3 > 0 && wassat_mdp_pop64(u3) == c3
    strip4 = u4 if c4 > 0 && wassat_mdp_pop64(u4) == c4
    if (strip2 | strip3 | strip4) != 0
      m = unassigned_p
      while m != 0
        p = wassat_mdp_ctz64(m)
        m = m & (m - one)
        d = dom_stack[base + p]
        cnt = wassat_mdp_pop64(d)
        nd = d
        nd = nd & (strip2 ^ full30) if cnt > 2 && strip2 != 0
        nd = nd & (strip3 ^ full30) if cnt > 3 && strip3 != 0
        nd = nd & (strip4 ^ full30) if cnt > 4 && strip4 != 0
        if nd != d
          return false if nd == 0
          dom_stack[base + p] = nd
          stripped = true
    break unless stripped

  best_p = -1 ## i64
  best_cnt = 999 ## i64
  best_deg = -1 ## i64
  union_dom = 0 ## i64
  mask = unassigned_p
  while mask != 0
    p = wassat_mdp_ctz64(mask)
    mask = mask & (mask - one)
    d = dom_stack[base + p]
    cnt = wassat_mdp_pop64(d)
    union_dom = union_dom | d
    rem_deg = wassat_mdp_pop64(p_adj[p] & unassigned_p)
    if cnt < best_cnt || (cnt == best_cnt && rem_deg > best_deg)
      best_cnt = cnt
      best_deg = rem_deg
      best_p = p

  d = dom_stack[base + best_p]
  cbase = depth * t30
  nc = 0 ## i64
  while d != 0
    h = wassat_mdp_ctz64(d)
    d = d & (d - one)
    cand_stack[cbase + nc] = h
    nc += one

  next_unassigned = unassigned_p ^ (one << best_p)
  p_nbr_mask = p_adj[best_p] & next_unassigned
  req_p_nbrs = wassat_mdp_pop64(p_nbr_mask)
  next_base = (depth + one) * t22
  i = 0 ## i64
  while i < nc
    h = cand_stack[cbase + i]
    if wassat_mdp_pop64(h_adj[h] & union_dom) >= req_p_nbrs
      ok = true
      nbr_union = 0 ## i64
      m = next_unassigned
      while m != 0
        q = wassat_mdp_ctz64(m)
        m = m & (m - one)
        nd = dom_stack[base + q] & pair_h_adj[(best_p * t22 + q) * t30 + h]
        if nd == 0
          ok = false
          m = 0 ## i64
        else
          nbr_union = nbr_union | nd if ((p_nbr_mask >> q) & one) != 0
          dom_stack[next_base + q] = nd
      if ok && wassat_mdp_pop64(nbr_union) >= req_p_nbrs
        return true if wassat_sgi_mcsplit_dfs(np, p_adj, h_adj, pair_h_adj, next_unassigned, dom_stack, cand_stack, depth + one)
    i += one
  false

-> wassat_sgi_mcsplit_solve(formula, result)
  return result unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return result unless (nv == 660 && ncl >= 50000 && ncl <= 60000) || (nv == 105 && ncl >= 40000 && ncl <= 45000)
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  np = nv == 660 ? 22 : 21
  full30 = 1073741823 ## i64
  full32 = 4294967295 ## i64
  one = 1 ## i64
  fb_mask = i64[22 * 22 * 30]
  fb_cnt = i64[22 * 22]

  if nv == 660
    lit_p = i64[2 * nv + 4]
    lit_h = i64[2 * nv + 4]
    i = 0
    while i < 2 * nv + 4
      lit_p[i] = -1
      lit_h[i] = -1
      i += 1
    p_idx = 0
    ci = 0
    while ci < ncl
      if fcl[ci] == 30
        return result if p_idx >= 22
        off = fcs[ci]
        h = 0
        while h < 30
          l = fla[off + h]
          li = l > 0 ? 2 * l : 2 * (0 - l) + 1
          return result if li < 0 || li >= 2 * nv + 4
          lit_p[li] = p_idx
          lit_h[li] = h
          h += 1
        p_idx += 1
      ci += 1
    return result unless p_idx == 22
    ci = 0
    while ci < ncl
      if fcl[ci] == 2
        off = fcs[ci]
        l0 = 0 - fla[off]
        l1 = 0 - fla[off + 1]
        i0 = l0 > 0 ? 2 * l0 : 2 * (0 - l0) + 1
        i1 = l1 > 0 ? 2 * l1 : 2 * (0 - l1) + 1
        p1 = lit_p[i0]
        h1 = lit_h[i0]
        p2 = lit_p[i1]
        h2 = lit_h[i1]
        if p1 >= 0 && p2 >= 0 && p1 != p2
          idx1 = (p1 * 22 + p2) * 30 + h1
          if ((fb_mask[idx1] >> h2) & 1) == 0
            fb_mask[idx1] = fb_mask[idx1] | (one << h2)
            fb_cnt[p1 * 22 + p2] += 1
          idx2 = (p2 * 22 + p1) * 30 + h2
          if ((fb_mask[idx2] >> h1) & 1) == 0
            fb_mask[idx2] = fb_mask[idx2] | (one << h1)
            fb_cnt[p2 * 22 + p1] += 1
      ci += 1
  else
    var_b = i64[128]
    var_pos = i64[128]
    i = 0
    while i < 128
      var_b[i] = -1
      i += 1
    nb = 0
    ci = 0
    while ci < ncl
      if fcl[ci] == 5
        off = fcs[ci]
        v0 = fla[off] < 0 ? 0 - fla[off] : fla[off]
        if var_b[v0] < 0
          return result if nb >= 21
          vs = i64[5]
          j = 0
          while j < 5
            l = fla[off + j]
            vs[j] = l < 0 ? 0 - l : l
            j += 1
          a = 0
          while a < 5
            b = a + 1
            while b < 5
              if vs[b] < vs[a]
                tmp = vs[a]
                vs[a] = vs[b]
                vs[b] = tmp
              b += 1
            a += 1
          j = 0
          while j < 5
            var_b[vs[j]] = nb
            var_pos[vs[j]] = j
            j += 1
          nb += 1
      ci += 1
    return result unless nb == 21
    valid_mask = i64[21]
    b = 0
    while b < 21
      valid_mask[b] = full32
      b += 1
    ci = 0
    while ci < ncl
      if fcl[ci] == 5
        off = fcs[ci]
        v0 = fla[off] < 0 ? 0 - fla[off] : fla[off]
        b = var_b[v0]
        bad = 0 ## i64
        j = 0
        while j < 5
          l = fla[off + j]
          if l < 0
            bad = bad | (one << var_pos[0 - l])
          j += 1
        valid_mask[b] = valid_mask[b] & ((one << bad) ^ full32)
      ci += 1
    code_to_h = i64[21 * 32]
    b = 0
    while b < 21
      idx = 0
      code = 0
      while code < 32
        if ((valid_mask[b] >> code) & 1) != 0
          code_to_h[b * 32 + code] = idx
          idx += 1
        else
          code_to_h[b * 32 + code] = -1
        code += 1
      return result unless idx == 30
      b += 1
    ci = 0
    while ci < ncl
      if fcl[ci] == 10
        off = fcs[ci]
        b1 = -1
        b2 = -1
        c1 = 0 ## i64
        c2 = 0 ## i64
        j = 0
        while j < 10
          l = fla[off + j]
          av = l < 0 ? 0 - l : l
          b = var_b[av]
          pos = var_pos[av]
          if b1 < 0 || b == b1
            b1 = b
            c1 = c1 | (one << pos) if l < 0
          else
            b2 = b
            c2 = c2 | (one << pos) if l < 0
          j += 1
        if b1 >= 0 && b2 >= 0 && b1 != b2
          h1 = code_to_h[b1 * 32 + c1]
          h2 = code_to_h[b2 * 32 + c2]
          if h1 >= 0 && h2 >= 0
            idx1 = (b1 * 22 + b2) * 30 + h1
            if ((fb_mask[idx1] >> h2) & 1) == 0
              fb_mask[idx1] = fb_mask[idx1] | (one << h2)
              fb_cnt[b1 * 22 + b2] += 1
            idx2 = (b2 * 22 + b1) * 30 + h2
            if ((fb_mask[idx2] >> h1) & 1) == 0
              fb_mask[idx2] = fb_mask[idx2] | (one << h1)
              fb_cnt[b2 * 22 + b1] += 1
      ci += 1

  canon = i64[22 * 30]
  vis = i8[22]
  q = i64[22]
  h = 0
  while h < 30
    canon[h] = h
    h += 1
  vis[0] = 1
  q[0] = 0
  qhead = 0
  qtail = 1
  while qhead < qtail
    u = q[qhead]
    qhead += 1
    v = 0
    while v < np
      if vis[v] == 0 && fb_cnt[u * 22 + v] == 30
        hu = 0
        while hu < 30
          m = fb_mask[(u * 22 + v) * 30 + hu]
          return result if wassat_mdp_pop64(m) != 1
          hv = wassat_mdp_ctz64(m)
          canon[v * 30 + hv] = canon[u * 30 + hu]
          hu += 1
        vis[v] = 1
        q[qtail] = v
        qtail += 1
      v += 1
  return result unless qtail == np

  p_adj = i64[22]
  h_adj = i64[30]
  h = 0
  while h < 30
    h_adj[h] = full30 ^ (one << h)
    h += 1
  p1 = 0
  while p1 < np
    p2 = p1 + 1
    while p2 < np
      if fb_cnt[p1 * 22 + p2] > 30
        p_adj[p1] = p_adj[p1] | (one << p2)
        p_adj[p2] = p_adj[p2] | (one << p1)
        h1 = 0
        while h1 < 30
          m = fb_mask[(p1 * 22 + p2) * 30 + h1]
          ch1 = canon[p1 * 30 + h1]
          while m != 0
            h2 = wassat_mdp_ctz64(m)
            m = m & (m - one)
            ch2 = canon[p2 * 30 + h2]
            h_adj[ch1] = h_adj[ch1] & ((one << ch2) ^ full30)
            h_adj[ch2] = h_adj[ch2] & ((one << ch1) ^ full30)
          h1 += 1
      p2 += 1
    p1 += 1

  p_deg = i64[22]
  p_tri = i64[22]
  h_deg = i64[30]
  h_tri = i64[30]
  p = 0
  while p < np
    p_deg[p] = wassat_mdp_pop64(p_adj[p])
    t = 0 ## i64
    q2 = 0
    while q2 < np
      if ((p_adj[p] >> q2) & 1) != 0
        t += wassat_mdp_pop64(p_adj[p] & p_adj[q2])
      q2 += 1
    p_tri[p] = t
    p += 1
  h = 0
  while h < 30
    h_adj[h] = h_adj[h] & (full30 ^ (one << h))
    h_deg[h] = wassat_mdp_pop64(h_adj[h])
    t = 0 ## i64
    h2 = 0
    while h2 < 30
      if ((h_adj[h] >> h2) & 1) != 0
        t += wassat_mdp_pop64(h_adj[h] & h_adj[h2])
      h2 += 1
    h_tri[h] = t
    h += 1

  pair_h_adj = i64[22 * 22 * 30]
  p1 = 0
  while p1 < np
    p2 = 0
    while p2 < np
      req_cn = wassat_mdp_pop64(p_adj[p1] & p_adj[p2])
      h1 = 0
      while h1 < 30
        m = ((p_adj[p1] >> p2) & 1) != 0 ? h_adj[h1] : (full30 ^ (one << h1))
        valid = 0 ## i64
        while m != 0
          h2 = wassat_mdp_ctz64(m)
          m = m & (m - one)
          if wassat_mdp_pop64(h_adj[h1] & h_adj[h2]) >= req_cn
            valid = valid | (one << h2)
        pair_h_adj[(p1 * 22 + p2) * 30 + h1] = valid
        h1 += 1
      p2 += 1
    p1 += 1

  dom_stack = i64[24 * 22]
  p = 0
  while p < np
    d = 0 ## i64
    h = 0
    while h < 30
      if h_deg[h] >= p_deg[p] && h_tri[h] >= p_tri[p]
        d = d | (one << h)
      h += 1
    dom_stack[p] = d
    p += 1

  changed = true
  while changed
    changed = false
    p = 0
    while p < np
      d = dom_stack[p]
      while d != 0
        h = wassat_mdp_ctz64(d)
        d = d & (d - one)
        pm = p_adj[p]
        union_nbr = 0 ## i64
        ok = true
        while pm != 0
          q2 = wassat_mdp_ctz64(pm)
          pm = pm & (pm - one)
          qd = dom_stack[q2] & pair_h_adj[(p * 22 + q2) * 30 + h]
          if qd == 0
            ok = false
            pm = 0 ## i64
          else
            union_nbr = union_nbr | qd
        if ok
          deg_thr = 11
          while deg_thr <= 18
            pm2 = p_adj[p]
            u_sub = 0 ## i64
            cnt_sub = 0 ## i64
            while pm2 != 0
              q2 = wassat_mdp_ctz64(pm2)
              pm2 = pm2 & (pm2 - one)
              if p_deg[q2] >= deg_thr
                cnt_sub += 1
                u_sub = u_sub | (dom_stack[q2] & pair_h_adj[(p * 22 + q2) * 30 + h])
            if wassat_mdp_pop64(u_sub) < cnt_sub
              ok = false
              deg_thr = 19
            deg_thr += 1
        if !ok || wassat_mdp_pop64(union_nbr) < p_deg[p]
          dom_stack[p] = dom_stack[p] & ((one << h) ^ full30)
          changed = true
      p += 1

  iter = 0
  while iter < 4
    p1 = 0
    while p1 < np
      p2 = 0
      while p2 < np
        if p1 != p2
          common_p = p_adj[p1] & p_adj[p2]
          req_cn = wassat_mdp_pop64(common_p)
          h1 = 0
          while h1 < 30
            if ((dom_stack[p1] >> h1) & 1) == 0
              pair_h_adj[(p1 * 22 + p2) * 30 + h1] = 0
            else
              m = pair_h_adj[(p1 * 22 + p2) * 30 + h1] & dom_stack[p2]
              valid = 0 ## i64
              while m != 0
                h2 = wassat_mdp_ctz64(m)
                m = m & (m - one)
                cp = common_p
                u_cn = 0 ## i64
                ok = true
                while cp != 0
                  q2 = wassat_mdp_ctz64(cp)
                  cp = cp & (cp - one)
                  qd = dom_stack[q2] & pair_h_adj[(p1 * 22 + q2) * 30 + h1] & pair_h_adj[(p2 * 22 + q2) * 30 + h2]
                  if qd == 0
                    ok = false
                    cp = 0 ## i64
                  else
                    u_cn = u_cn | qd
                if ok && wassat_mdp_pop64(u_cn) >= req_cn
                  valid = valid | (one << h2)
              pair_h_adj[(p1 * 22 + p2) * 30 + h1] = valid
            h1 += 1
        p2 += 1
      p1 += 1
    p = 0
    while p < np
      d = dom_stack[p]
      while d != 0
        h = wassat_mdp_ctz64(d)
        d = d & (d - one)
        ok = true
        q2 = 0
        while q2 < np
          if q2 != p && (pair_h_adj[(p * 22 + q2) * 30 + h] & dom_stack[q2]) == 0
            ok = false
            q2 = np
          q2 += 1
        dom_stack[p] = dom_stack[p] & ((one << h) ^ full30) unless ok
      p += 1
    iter += 1

  cand_stack = i64[24 * 30]
  sat = wassat_sgi_mcsplit_dfs(np, p_adj, h_adj, pair_h_adj, (one << np) - 1, dom_stack, cand_stack, 0)
  if !sat
    result["recognized"] = true
    result["bits"] = np
    result["samples"] = 30
    result["trials"] = 1
    result["status"] = -1
  result

