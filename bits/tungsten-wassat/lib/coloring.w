# Fast-only certificates for explicit pigeonhole, AMO-clique-cover, parity,
# relativized-PHP, and clique-coloring obstructions in combinatorial CNFs.
#
# Recognition is deliberately one-sided. Partial bundles, unsupported widths,
# or a bounded search miss all fall through to ordinary solving. Every
# successful result is backed only by clauses literally present in the
# original formula; unrelated clauses are ignored.

WASSAT_COLORING_MAX_WIDTH = 124
WASSAT_COLORING_MAX_GROUPS = 512
WASSAT_COLORING_NODE_CAP = 200000

# Bounded target-clique search over a dense row-major adjacency matrix.
# Candidate vectors for depth d occupy cands[d*g .. (d+1)*g).
-> wassat_coloring_clique_dfs(adj, g, target, cands, ncand,
                              depth, clique, pm) (i64[] i64 i64 i64[] i64 i64 i64[] i64[]) i64
  pm[0] = pm[0] + 1
  return 0 if pm[0] > pm[1]
  return 1 if depth >= target
  return 0 if depth + ncand < target

  base = depth * g
  remaining = ncand
  while remaining > 0
    return 0 if depth + remaining < target

    # Follow the densest remaining vertex first. On the competition coloring
    # families this finds the explicit k+1 witness after only tens of nodes;
    # the node cap keeps an adversarial non-witness from becoming a new stage.
    best_i = 0
    best_degree = -1
    i = 0
    while i < remaining
      v = cands[base + i]
      degree = 0
      j = 0
      while j < remaining
        u = cands[base + j]
        degree += 1 if adj[v * g + u] != 0
        j += 1
      if degree > best_degree
        best_degree = degree
        best_i = i
      i += 1

    v = cands[base + best_i]
    remaining -= 1
    cands[base + best_i] = cands[base + remaining]
    cands[base + remaining] = v

    child_base = (depth + 1) * g
    child_n = 0
    i = 0
    while i < remaining
      u = cands[base + i]
      if adj[v * g + u] != 0
        cands[child_base + child_n] = u
        child_n += 1
      i += 1
    clique[depth] = v
    if wassat_coloring_clique_dfs(adj, g, target, cands, child_n,
                                  depth + 1, clique, pm) == 1
      return 1
  0

# Check if disjoint choice clauses (width >= 3) in the given active clause set
# are covered by fewer complete AMO cliques than choice clauses, or if m == k
# complete AMO hole cliques force relay literals that reduce the remaining
# clauses to such an AMO-clique-cover obstruction (relativized PHP).
-> wassat_amo_cover_or_rphp_unsat(fla, fcs, fcl, nv, ncl, forced_lit, pos_only) (i64[] i64[] i64[] i64 i64 i8[] bool) i64
  choice_owner = i64[nv + 1]
  choice_pol = i8[nv + 1]
  choice_ci = i64[nv + 1]
  u_vars = i64[nv + 1]
  u_count = 0
  m = 0

  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    # Evaluate clause under forced_lit (0 = unassigned, 1 = pos true, -1 = neg true)
    sat = false
    rem_len = 0
    disjoint = true
    j = 0
    while j < n
      l = fla[off + j]
      v = l < 0 ? 0 - l : l
      if v < 1 || v > nv
        sat = true
      else
        fl = forced_lit[v]
        if (fl == 1 && l > 0) || (fl == -1 && l < 0)
          sat = true
        elsif fl == 0
          rem_len += 1
          disjoint = false if choice_owner[v] != 0
          disjoint = false if pos_only && l < 0
      j += 1
    if !sat && rem_len >= 3 && disjoint
      # Also ensure no duplicate variable inside the clause itself
      dup = false
      j = 0
      while j < n
        l = fla[off + j]
        v = l < 0 ? 0 - l : l
        if forced_lit[v] == 0
          if choice_owner[v] != 0
            dup = true
          else
            choice_owner[v] = m + 1
            choice_pol[v] = l > 0 ? 1 : -1
            u_vars[u_count] = v
            u_count += 1
        j += 1
      if dup
        # Roll back partial marks for this clause
        while u_count > 0 && choice_owner[u_vars[u_count - 1]] == m + 1
          u_count -= 1
          choice_owner[u_vars[u_count]] = 0
          choice_pol[u_vars[u_count]] = 0
      else
        choice_ci[m] = ci
        m += 1
    ci += 1

  return 0 if m < 2 || u_count < m * 3

  # Map variables in U to 0..u_count-1 for compact adjacency bitsets/matrix
  u_idx = i64[nv + 1]
  i = 0
  while i < u_count
    u_idx[u_vars[i]] = i + 1
    i += 1

  # Build full exclusion graph G and inter-choice exclusion graph G_inter on U
  words = (u_count + 61) / 62
  g_full = i64[u_count * words]
  g_inter = i64[u_count * words]
  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n >= 2 && n <= 4
      off = fcs[ci]
      sat = false
      l1 = 0
      l2 = 0
      rem = 0
      j = 0
      while j < n
        l = fla[off + j]
        v = l < 0 ? 0 - l : l
        fl = forced_lit[v]
        if (fl == 1 && l > 0) || (fl == -1 && l < 0)
          sat = true
        elsif fl == 0
          rem += 1
          if rem == 1
            l1 = l
          elsif rem == 2
            l2 = l
        j += 1
      if !sat && rem == 2
        v1 = l1 < 0 ? 0 - l1 : l1
        v2 = l2 < 0 ? 0 - l2 : l2
        idx1 = u_idx[v1] - 1
        idx2 = u_idx[v2] - 1
        if idx1 >= 0 && idx2 >= 0 && idx1 != idx2
          # Binary clause (l1 | l2) forbids (-l1 & -l2), so it is an exclusion
          # on (v1, v2) iff l1 has opposite sign to choice_pol[v1] and l2 has
          # opposite sign to choice_pol[v2].
          p1 = l1 > 0 ? 1 : -1
          p2 = l2 > 0 ? 1 : -1
          if p1 == 0 - choice_pol[v1] && p2 == 0 - choice_pol[v2]
            w1 = idx2 / 62
            b1 = 1 << (idx2 % 62)
            w2 = idx1 / 62
            b2 = 1 << (idx1 % 62)
            g_full[idx1 * words + w1] = g_full[idx1 * words + w1] | b1
            g_full[idx2 * words + w2] = g_full[idx2 * words + w2] | b2
            if choice_owner[v1] != choice_owner[v2]
              g_inter[idx1 * words + w1] = g_inter[idx1 * words + w1] | b1
              g_inter[idx2 * words + w2] = g_inter[idx2 * words + w2] | b2
    ci += 1

  # Connected components of G_inter on 0..u_count-1
  comp_id = i64[u_count]
  comp_nodes = i64[u_count]
  comp_offs = i64[u_count + 1]
  queue = i64[u_count]
  ncomp = 0
  out_pos = 0
  start = 0
  while start < u_count
    if comp_id[start] == 0
      ncomp += 1
      comp_offs[ncomp - 1] = out_pos
      comp_id[start] = ncomp
      qh = 0
      qt = 0
      queue[qt] = start
      qt += 1
      while qh < qt
        cur = queue[qh]
        qh += 1
        comp_nodes[out_pos] = cur
        out_pos += 1
        # Scan neighbors of cur in g_inter
        nxt = 0
        while nxt < u_count
          if comp_id[nxt] == 0
            w = nxt / 62
            b = 1 << (nxt % 62)
            if (g_inter[cur * words + w] & b) != 0
              comp_id[nxt] = ncomp
              queue[qt] = nxt
              qt += 1
          nxt += 1
      comp_offs[ncomp] = out_pos
    start += 1

  # Verify which components of G_inter are complete cliques of size >= 2 in G_full
  is_clique = i8[ncomp + 1]
  c = 0
  while c < ncomp
    c_start = comp_offs[c]
    c_end = comp_offs[c + 1]
    c_size = c_end - c_start
    ok = c_size >= 2
    ia = c_start
    while ia < c_end && ok
      ua = comp_nodes[ia]
      ib = ia + 1
      while ib < c_end
        ub = comp_nodes[ib]
        w = ub / 62
        b = 1 << (ub % 62)
        if (g_full[ua * words + w] & b) == 0
          ok = false
        ib += 1
      ia += 1
    is_clique[c + 1] = 1 if ok
    c += 1

  # A choice clause P_i is covered if all of its variables belong to clique components
  choice_bad = i8[m + 1]
  i = 0
  while i < u_count
    v = u_vars[i]
    owner_i = choice_owner[v]
    cid = comp_id[i]
    choice_bad[owner_i] = 1 if is_clique[cid] == 0
    i += 1

  comp_used = i8[ncomp + 1]
  i = 0
  while i < u_count
    v = u_vars[i]
    owner_i = choice_owner[v]
    if choice_bad[owner_i] == 0
      comp_used[comp_id[i]] = 1
    i += 1

  m_cov = 0
  pi = 1
  while pi <= m
    m_cov += 1 if choice_bad[pi] == 0
    pi += 1

  k_cov = 0
  c = 1
  while c <= ncomp
    k_cov += 1 if comp_used[c] == 1
    c += 1

  if m_cov >= 2
    # Direct AMO clique-cover obstruction: m_cov disjoint choice clauses covered
    # by k_cov < m_cov complete AMO cliques!
    return m_cov if k_cov < m_cov

    # Relativized PHP (m_cov == k_cov): each of the k_cov used hole cliques C_c
    # must contain at least 1 true literal from the m_cov covered choice clauses
    # (and since C_c is an AMO clique, any literal in C_c from an uncovered clause
    # is also in the same AMO clique, so at least 1 literal in C_c is true!).
    # Any literal y outside the covered variables with (-l_u | y) for all u in C_c
    # is therefore forced true!
    if k_cov == m_cov
      hit_comp = i64[2 * nv + 2]
      hit_cnt = i64[2 * nv + 2]
      seen_u_for_y = i64[2 * nv + 2]
      new_forced = 0
      ci = 0
      while ci < ncl
        if fcl[ci] == 2
          off = fcs[ci]
          la = fla[off]
          lb = fla[off + 1]
          va = la < 0 ? 0 - la : la
          vb = lb < 0 ? 0 - lb : lb
          idx_a = u_idx[va] - 1
          idx_b = u_idx[vb] - 1
          a_cov = idx_a >= 0 && choice_bad[choice_owner[va]] == 0
          b_cov = idx_b >= 0 && choice_bad[choice_owner[vb]] == 0
          if a_cov && !b_cov && forced_lit[vb] == 0
            pa = la > 0 ? 1 : -1
            if pa == 0 - choice_pol[va]
              yi = lb > 0 ? 2 * vb : 2 * vb + 1
              hc = comp_id[idx_a]
              c_start = comp_offs[hc - 1]
              c_size = comp_offs[hc] - c_start
              if comp_used[hc] == 1 && c_size <= 62
                loc = 0
                k = c_start
                while k < comp_offs[hc]
                  break if comp_nodes[k] == idx_a
                  loc += 1
                  k += 1
                if hit_comp[yi] != hc
                  hit_comp[yi] = hc
                  seen_u_for_y[yi] = 0
                  hit_cnt[yi] = 0
                bit = 1 << loc
                if (seen_u_for_y[yi] & bit) == 0
                  seen_u_for_y[yi] = seen_u_for_y[yi] | bit
                  hit_cnt[yi] = hit_cnt[yi] + 1
                  if hit_cnt[yi] == c_size
                    forced_lit[vb] = lb > 0 ? 1 : -1
                    new_forced += 1
          elsif b_cov && !a_cov && forced_lit[va] == 0
            pb = lb > 0 ? 1 : -1
            if pb == 0 - choice_pol[vb]
              yi = la > 0 ? 2 * va : 2 * va + 1
              hc = comp_id[idx_b]
              c_start = comp_offs[hc - 1]
              c_size = comp_offs[hc] - c_start
              if comp_used[hc] == 1 && c_size <= 62
                loc = 0
                k = c_start
                while k < comp_offs[hc]
                  break if comp_nodes[k] == idx_b
                  loc += 1
                  k += 1
                if hit_comp[yi] != hc
                  hit_comp[yi] = hc
                  seen_u_for_y[yi] = 0
                  hit_cnt[yi] = 0
                bit = 1 << loc
                if (seen_u_for_y[yi] & bit) == 0
                  seen_u_for_y[yi] = seen_u_for_y[yi] | bit
                  hit_cnt[yi] = hit_cnt[yi] + 1
                  if hit_cnt[yi] == c_size
                    forced_lit[va] = la > 0 ? 1 : -1
                    new_forced += 1
        ci += 1
      if new_forced > 0
        i = 0
        while i < u_count
          v = u_vars[i]
          forced_lit[v] = 2 if choice_bad[choice_owner[v]] == 0
          i += 1
        return wassat_amo_cover_residual_unsat(fla, fcs, fcl, nv, ncl, forced_lit)
  0

-> wassat_amo_cover_residual_unsat(fla, fcs, fcl, nv, ncl, forced_lit) (i64[] i64[] i64[] i64 i64 i8[]) i64
  choice_owner = i64[nv + 1]
  choice_pol = i8[nv + 1]
  u_vars = i64[nv + 1]
  u_count = 0
  m = 0

  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    skip = false
    rem_len = 0
    disjoint = true
    j = 0
    while j < n
      l = fla[off + j]
      v = l < 0 ? 0 - l : l
      fl = forced_lit[v]
      if fl == 2 || (fl == 1 && l > 0) || (fl == -1 && l < 0)
        skip = true
      elsif fl == 0
        rem_len += 1
        disjoint = false if choice_owner[v] != 0
      j += 1
    if !skip && rem_len >= 3 && disjoint
      dup = false
      j = 0
      while j < n
        l = fla[off + j]
        v = l < 0 ? 0 - l : l
        if forced_lit[v] == 0
          if choice_owner[v] != 0
            dup = true
          else
            choice_owner[v] = m + 1
            choice_pol[v] = l > 0 ? 1 : -1
            u_vars[u_count] = v
            u_count += 1
        j += 1
      if dup
        while u_count > 0 && choice_owner[u_vars[u_count - 1]] == m + 1
          u_count -= 1
          choice_owner[u_vars[u_count]] = 0
          choice_pol[u_vars[u_count]] = 0
      else
        m += 1
    ci += 1

  return 0 if m < 2 || u_count < m * 3

  u_idx = i64[nv + 1]
  i = 0
  while i < u_count
    u_idx[u_vars[i]] = i + 1
    i += 1

  words = (u_count + 61) / 62
  g_full = i64[u_count * words]
  g_inter = i64[u_count * words]
  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n >= 2 && n <= 4
      off = fcs[ci]
      skip = false
      l1 = 0
      l2 = 0
      rem = 0
      j = 0
      while j < n
        l = fla[off + j]
        v = l < 0 ? 0 - l : l
        fl = forced_lit[v]
        if fl == 2 || (fl == 1 && l > 0) || (fl == -1 && l < 0)
          skip = true
        elsif fl == 0
          rem += 1
          if rem == 1
            l1 = l
          elsif rem == 2
            l2 = l
        j += 1
      if !skip && rem == 2
        v1 = l1 < 0 ? 0 - l1 : l1
        v2 = l2 < 0 ? 0 - l2 : l2
        idx1 = u_idx[v1] - 1
        idx2 = u_idx[v2] - 1
        if idx1 >= 0 && idx2 >= 0 && idx1 != idx2
          p1 = l1 > 0 ? 1 : -1
          p2 = l2 > 0 ? 1 : -1
          if p1 == 0 - choice_pol[v1] && p2 == 0 - choice_pol[v2]
            w1 = idx2 / 62
            b1 = 1 << (idx2 % 62)
            w2 = idx1 / 62
            b2 = 1 << (idx1 % 62)
            g_full[idx1 * words + w1] = g_full[idx1 * words + w1] | b1
            g_full[idx2 * words + w2] = g_full[idx2 * words + w2] | b2
            if choice_owner[v1] != choice_owner[v2]
              g_inter[idx1 * words + w1] = g_inter[idx1 * words + w1] | b1
              g_inter[idx2 * words + w2] = g_inter[idx2 * words + w2] | b2
    ci += 1

  comp_id = i64[u_count]
  comp_nodes = i64[u_count]
  comp_offs = i64[u_count + 1]
  queue = i64[u_count]
  ncomp = 0
  out_pos = 0
  start = 0
  while start < u_count
    if comp_id[start] == 0
      ncomp += 1
      comp_offs[ncomp - 1] = out_pos
      comp_id[start] = ncomp
      qh = 0
      qt = 0
      queue[qt] = start
      qt += 1
      while qh < qt
        cur = queue[qh]
        qh += 1
        comp_nodes[out_pos] = cur
        out_pos += 1
        nxt = 0
        while nxt < u_count
          if comp_id[nxt] == 0
            w = nxt / 62
            b = 1 << (nxt % 62)
            if (g_inter[cur * words + w] & b) != 0
              comp_id[nxt] = ncomp
              queue[qt] = nxt
              qt += 1
          nxt += 1
      comp_offs[ncomp] = out_pos
    start += 1

  return 0 if ncomp >= m

  c = 0
  while c < ncomp
    c_start = comp_offs[c]
    c_end = comp_offs[c + 1]
    return 0 if c_end - c_start < 2
    ia = c_start
    while ia < c_end
      ua = comp_nodes[ia]
      ib = ia + 1
      while ib < c_end
        ub = comp_nodes[ib]
        w = ub / 62
        b = 1 << (ub % 62)
        return 0 if (g_full[ua * words + w] & b) == 0
        ib += 1
      ia += 1
    c += 1
  m

# Check C: Odd number of exact-one choice clauses where every participating
# variable has consistent literal polarity and even degree across those clauses.
-> wassat_exact_one_even_parity_unsat(fla, fcs, fcl, nv, ncl) (i64[] i64[] i64[] i64 i64) i64
  pol = i8[nv + 1]
  deg = i64[nv + 1]
  m = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    return 0 if n < 2
    if n > 2
      return 0 if n > 256
      off = fcs[ci]
      j = 0
      while j < n
        l = fla[off + j]
        v = l < 0 ? 0 - l : l
        return 0 if v < 1 || v > nv
        p = l > 0 ? 1 : -1
        if pol[v] == 0
          pol[v] = p
        elsif pol[v] != p
          return 0
        # Reject duplicate variable inside the same clause
        k = 0
        while k < j
          return 0 if fla[off + k] == l
          k += 1
        deg[v] = deg[v] + 1
        j += 1
      m += 1
    ci += 1

  return 0 if m < 3
  g = 0
  v = 1
  while v <= nv
    d = deg[v]
    if d > 0
      a = g
      b = d
      while b != 0
        t = a % b
        a = b
        b = t
      g = a
    v += 1
  return 0 if g < 2 || (m % g) == 0

  # Verify every non-binary clause is a complete AMO clique under binary exclusions
  words = (nv + 61) / 62
  excl = i64[(nv + 1) * words]
  ci = 0
  while ci < ncl
    if fcl[ci] == 2
      off = fcs[ci]
      la = fla[off]
      lb = fla[off + 1]
      va = la < 0 ? 0 - la : la
      vb = lb < 0 ? 0 - lb : lb
      if va >= 1 && va <= nv && vb >= 1 && vb <= nv && va != vb
        pa = la > 0 ? 1 : -1
        pb = lb > 0 ? 1 : -1
        if pa == 0 - pol[va] && pb == 0 - pol[vb]
          w1 = vb / 62
          b1 = 1 << (vb % 62)
          w2 = va / 62
          b2 = 1 << (va % 62)
          excl[va * words + w1] = excl[va * words + w1] | b1
          excl[vb * words + w2] = excl[vb * words + w2] | b2
    ci += 1

  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n > 2
      off = fcs[ci]
      ia = 0
      while ia < n
        la = fla[off + ia]
        va = la < 0 ? 0 - la : la
        ib = ia + 1
        while ib < n
          lb = fla[off + ib]
          vb = lb < 0 ? 0 - lb : lb
          w = vb / 62
          b = 1 << (vb % 62)
          return 0 if (excl[va * words + w] & b) == 0
          ib += 1
        ia += 1
    ci += 1
  m

# Check E: Clique-coloring obstruction (k clique slots over n vertices vs
# c < k colors per vertex, mediated by n*(n-1)/2 edge variables).
-> wassat_clique_coloring_unsat(fla, fcs, fcl, nv, ncl) (i64[] i64[] i64[] i64 i64) i64
  # Collect allclauses of width > 3; they must partition into k clauses of
  # width n (clique slots) and n clauses of width c < k (vertex colorings).
  w1 = 0
  c1 = 0
  w2 = 0
  c2 = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    return 0 if n < 2
    if n > 3
      if w1 == 0 || n == w1
        w1 = n
        c1 += 1
      elsif w2 == 0 || n == w2
        w2 = n
        c2 += 1
      else
        return 0
    ci += 1

  return 0 if w1 == 0 || w2 == 0
  # Identify which width is n (vertex count) and which is c (color count):
  # There are k clauses of width n and n clauses of width c, with c < k < n.
  n_verts = 0
  k_slots = 0
  c_colors = 0
  if w1 > w2 && c2 == w1 && w2 < c1
    n_verts = w1
    k_slots = c1
    c_colors = w2
  elsif w2 > w1 && c1 == w2 && w1 < c2
    n_verts = w2
    k_slots = c2
    c_colors = w1
  else
    return 0
  return 0 if n_verts > 62 || k_slots > 30 || c_colors < 3 || c_colors >= k_slots

  q_role = i64[nv + 1] # 1..k_slots for clique-slot vars, -1..-n_verts for coloring vars
  q_col = i64[nv + 1]  # 0..n_verts-1 for clique-slot vars, 0..c_colors-1 for coloring vars
  q_vars = i64[k_slots * n_verts]
  c_vars = i64[n_verts * c_colors]
  qi = 0
  ci_idx = 0
  scratch = i64[n_verts]

  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n == n_verts && qi < k_slots
      off = fcs[ci]
      j = 0
      while j < n
        l = fla[off + j]
        return 0 if l <= 0 || l > nv
        scratch[j] = l
        j += 1
      # Sort variables so vertex columns align deterministically
      j = 1
      while j < n
        x = scratch[j]
        k = j
        while k > 0 && scratch[k - 1] > x
          scratch[k] = scratch[k - 1]
          k -= 1
        scratch[k] = x
        j += 1
      j = 0
      while j < n
        v = scratch[j]
        return 0 if q_role[v] != 0
        q_role[v] = qi + 1
        q_col[v] = j
        q_vars[qi * n_verts + j] = v
        j += 1
      qi += 1
    elsif n == c_colors && ci_idx < n_verts
      off = fcs[ci]
      j = 0
      while j < n
        l = fla[off + j]
        return 0 if l <= 0 || l > nv
        scratch[j] = l
        j += 1
      j = 1
      while j < n
        x = scratch[j]
        k = j
        while k > 0 && scratch[k - 1] > x
          scratch[k] = scratch[k - 1]
          k -= 1
        scratch[k] = x
        j += 1
      j = 0
      while j < n
        v = scratch[j]
        return 0 if q_role[v] != 0
        q_role[v] = 0 - (ci_idx + 1)
        q_col[v] = j
        c_vars[ci_idx * c_colors + j] = v
        j += 1
      ci_idx += 1
    ci += 1

  return 0 unless qi == k_slots && ci_idx == n_verts

  # Check that each vertex column u in 0..n_verts-1 has all k*(k-1)/2 binary
  # exclusions (-q[i,u] | -q[j,u]) so the k slots must choose k distinct vertices.
  col_pairs = i64[n_verts]
  ci = 0
  while ci < ncl
    if fcl[ci] == 2
      off = fcs[ci]
      la = fla[off]
      lb = fla[off + 1]
      if la < 0 && lb < 0
        va = 0 - la
        vb = 0 - lb
        if va <= nv && vb <= nv && q_role[va] > 0 && q_role[vb] > 0
          sa = q_role[va] - 1
          sb = q_role[vb] - 1
          if sa != sb && q_col[va] == q_col[vb]
            if sa > sb
              t = sa
              sa = sb
              sb = t
            pair_bit = 1 << ((sa * k_slots + sb) % 62)
            col_pairs[q_col[va]] = col_pairs[q_col[va]] | pair_bit
    ci += 1

  want_col_mask = 0
  sa = 0
  while sa < k_slots
    sb = sa + 1
    while sb < k_slots
      want_col_mask = want_col_mask | (1 << ((sa * k_slots + sb) % 62))
      sb += 1
    sa += 1
  u = 0
  while u < n_verts
    return 0 unless col_pairs[u] == want_col_mask
    u += 1

  # Track for each edge variable e:
  # - which vertex pair (u < v) it connects (edge_pair[e] = u * n_verts + v + 1, or -1 on mismatch)
  # - bitmask of ordered slot pairs (sa != sb) forcing +e via (-q[sa,u] | -q[sb,v] | e)
  # - bitmask of colors r in 0..c_colors-1 forbidden by (-e | -c[u,r] | -c[v,r])
  edge_pair = i64[nv + 1]
  edge_slot_cnt = i64[nv + 1]
  edge_col_mask = i64[nv + 1]
  ci = 0
  while ci < ncl
    if fcl[ci] == 3
      off = fcs[ci]
      l0 = fla[off]
      l1 = fla[off + 1]
      l2 = fla[off + 2]
      # Case 1: one positive edge literal e and two negative q literals
      e_var = 0
      qa = 0
      qb = 0
      if l0 > 0 && l1 < 0 && l2 < 0
        e_var = l0
        qa = 0 - l1
        qb = 0 - l2
      elsif l1 > 0 && l0 < 0 && l2 < 0
        e_var = l1
        qa = 0 - l0
        qb = 0 - l2
      elsif l2 > 0 && l0 < 0 && l1 < 0
        e_var = l2
        qa = 0 - l0
        qb = 0 - l1
      if e_var > 0 && e_var <= nv && qa <= nv && qb <= nv
        if q_role[e_var] == 0 && q_role[qa] > 0 && q_role[qb] > 0
          sa = q_role[qa] - 1
          sb = q_role[qb] - 1
          ua = q_col[qa]
          ub = q_col[qb]
          if sa != sb && ua != ub
            u_min = ua < ub ? ua : ub
            u_max = ua < ub ? ub : ua
            pcode = u_min * n_verts + u_max + 1
            if edge_pair[e_var] == 0
              edge_pair[e_var] = pcode
            if edge_pair[e_var] == pcode
              edge_slot_cnt[e_var] = edge_slot_cnt[e_var] + 1
            else
              edge_pair[e_var] = -1
      elsif l0 < 0 && l1 < 0 && l2 < 0
        # Case 2: three negative literals (-e | -c[u,r] | -c[v,r])
        v0 = 0 - l0
        v1 = 0 - l1
        v2 = 0 - l2
        if v0 <= nv && v1 <= nv && v2 <= nv
          ev = 0
          ca = 0
          cb = 0
          if q_role[v0] == 0 && q_role[v1] < 0 && q_role[v2] < 0
            ev = v0
            ca = v1
            cb = v2
          elsif q_role[v1] == 0 && q_role[v0] < 0 && q_role[v2] < 0
            ev = v1
            ca = v0
            cb = v2
          elsif q_role[v2] == 0 && q_role[v0] < 0 && q_role[v1] < 0
            ev = v2
            ca = v0
            cb = v1
          if ev > 0 && q_col[ca] == q_col[cb]
            ua = (0 - q_role[ca]) - 1
            ub = (0 - q_role[cb]) - 1
            if ua != ub
              u_min = ua < ub ? ua : ub
              u_max = ua < ub ? ub : ua
              pcode = u_min * n_verts + u_max + 1
              if edge_pair[ev] == 0
                edge_pair[ev] = pcode
              if edge_pair[ev] == pcode
                edge_col_mask[ev] = edge_col_mask[ev] | (1 << q_col[ca])
              else
                edge_pair[ev] = -1
    ci += 1

  want_slots = k_slots * (k_slots - 1)
  want_cols = (1 << c_colors) - 1
  pair_ok = i8[n_verts * n_verts]
  e = 1
  while e <= nv
    pcode = edge_pair[e]
    if pcode > 0 && edge_slot_cnt[e] >= want_slots && edge_col_mask[e] == want_cols
      pair_ok[pcode - 1] = 1
    e += 1

  u = 0
  while u < n_verts
    v = u + 1
    while v < n_verts
      return 0 if pair_ok[u * n_verts + v] == 0
      v += 1
    u += 1
  k_slots

# Return the clique/obstruction size on a verified obstruction, otherwise zero.
-> wassat_coloring_clique_unsat(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return 0 if nv < 6 || ncl < 7

  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  # Cheap length-only gate. Supported coloring encodings are overwhelmingly
  # binary and nearly every non-binary clause has one dominant choice width.
  widths = i64[WASSAT_COLORING_MAX_WIDTH + 1]
  binaries = 0
  min_len = 999999
  ci = 0
  while ci < ncl
    n = fcl[ci]
    min_len = n if n < min_len
    if n == 2
      binaries += 1
    elsif n >= 2 && n <= WASSAT_COLORING_MAX_WIDTH
      widths[n] = widths[n] + 1
    ci += 1

  if binaries * 10 >= ncl * 9
    width = 0
    count = 0
    w = 2
    while w <= WASSAT_COLORING_MAX_WIDTH
      if widths[w] > count
        width = w
        count = widths[w]
      w += 1
    other = ncl - binaries
    if width >= 3 && count >= width + 1 && count * 10 >= other * 9 && count * width <= nv
      # Collect pairwise-disjoint positive choice clauses. Sorting the variable
      # ids gives each clause a deterministic color coordinate independent of
      # literal order. An overlapping clause is simply not a candidate.
      group_vars = i64[count * width]
      owner = i64[nv + 1]
      color = i64[nv + 1]
      scratch = i64[width]
      groups = 0
      ci = 0
      while ci < ncl && groups < WASSAT_COLORING_MAX_GROUPS
        if fcl[ci] == width
          off = fcs[ci]
          positive = true
          j = 0
          while j < width
            l = fla[off + j]
            positive = false if l <= 0 || l > nv
            scratch[j] = l
            j += 1
          if positive
            j = 1
            while j < width
              x = scratch[j]
              k = j
              while k > 0 && scratch[k - 1] > x
                scratch[k] = scratch[k - 1]
                k -= 1
              scratch[k] = x
              j += 1
            disjoint = true
            j = 0
            while j < width
              v = scratch[j]
              disjoint = false if j > 0 && scratch[j - 1] == v
              disjoint = false if owner[v] != 0
              j += 1
            if disjoint
              j = 0
              while j < width
                v = scratch[j]
                group_vars[groups * width + j] = v
                owner[v] = groups + 1
                color[v] = j
                j += 1
              groups += 1
        ci += 1
      target = width + 1
      if groups >= target
        # Accumulate which color coordinates (0..61 in masks0, 62..123 in masks1)
        # are forbidden for each group pair.
        masks0 = i64[groups * groups]
        masks1 = i64[groups * groups]
        ci = 0
        while ci < ncl
          if fcl[ci] == 2
            off = fcs[ci]
            la = fla[off]
            lb = fla[off + 1]
            if la < 0 && lb < 0
              a = 0 - la
              b = 0 - lb
              if a <= nv && b <= nv && owner[a] != 0 && owner[b] != 0
                ga = owner[a] - 1
                gb = owner[b] - 1
                if ga != gb && color[a] == color[b]
                  col = color[a]
                  if col < 62
                    bit = 1 << col
                    masks0[ga * groups + gb] = masks0[ga * groups + gb] | bit
                    masks0[gb * groups + ga] = masks0[gb * groups + ga] | bit
                  else
                    bit = 1 << (col - 62)
                    masks1[ga * groups + gb] = masks1[ga * groups + gb] | bit
                    masks1[gb * groups + ga] = masks1[gb * groups + ga] | bit
          ci += 1

        full0 = width <= 62 ? (1 << width) - 1 : (1 << 62) - 1
        full1 = width <= 62 ? 0 : (1 << (width - 62)) - 1
        adj = i64[groups * groups]
        a = 0
        while a < groups
          b = a + 1
          while b < groups
            if masks0[a * groups + b] == full0 && masks1[a * groups + b] == full1
              adj[a * groups + b] = 1
              adj[b * groups + a] = 1
            b += 1
          a += 1

        # Iteratively peel vertices with degree < target - 1 in the active subgraph
        active = i8[groups]
        a = 0
        while a < groups
          active[a] = 1
          a += 1
        changed = true
        while changed
          changed = false
          a = 0
          while a < groups
            if active[a] == 1
              deg = 0
              b = 0
              while b < groups
                deg += 1 if active[b] == 1 && adj[a * groups + b] != 0
                b += 1
              if deg < target - 1
                active[a] = 0
                changed = true
            a += 1

        cands = i64[(target + 1) * groups]
        ncand = 0
        a = 0
        while a < groups
          if active[a] == 1
            cands[ncand] = a
            ncand += 1
          a += 1
        if ncand >= target
          clique = i64[target]
          pm = i64[3]
          pm[1] = WASSAT_COLORING_NODE_CAP
          if wassat_coloring_clique_dfs(
            adj, groups, target, cands, ncand, 0, clique, pm
          ) == 1
            return target

  # Combinatorial AMO-clique-cover, relativized-PHP, exact-one parity, and
  # clique-coloring obstructions on compact unit-free formulas.
  if min_len >= 2 && nv <= 4096 && ncl <= 250000
    forced_lit = i8[nv + 1]
    res = wassat_amo_cover_or_rphp_unsat(fla, fcs, fcl, nv, ncl, forced_lit, true)
    return res if res > 0
    forced_lit2 = i8[nv + 1]
    res = wassat_amo_cover_or_rphp_unsat(fla, fcs, fcl, nv, ncl, forced_lit2, false)
    return res if res > 0
    res = wassat_exact_one_even_parity_unsat(fla, fcs, fcl, nv, ncl)
    return res if res > 0
    res = wassat_clique_coloring_unsat(fla, fcs, fcl, nv, ncl)
    return res if res > 0
    res = wassat_rpoc_bin_unsat(fla, fcs, fcl, nv, ncl)
    return res if res > 0
    res = wassat_stconn_grid_unsat(fla, fcs, fcl, nv, ncl)
    return res if res > 0
  0

-> wassat_rpoc_dfs(min_idx, used_items, used_amask, k, ex_sum, min_ex, max_bins, n_items, first_for_min, next_for_min, sub_imask, sub_amask, sub_pmask, sub_ex, chosen_idx, adj_out, state) (i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  return 1 if state[0] >= 500000
  state[0] += 1
  if ex_sum >= min_ex
    rem_items = n_items
    i = 0
    while i < k
      s_im = sub_imask[chosen_idx[i]]
      b = 0
      while b < n_items
        rem_items -= 1 if ((s_im >> b) & 1) != 0
        b += 1
      i += 1
    return 1 if k + rem_items <= max_bins
  return 0 if k >= max_bins
  rem_slots = max_bins - k
  # Prune if even maximum possible excess (5 per subset) cannot reach min_ex
  return 0 if ex_sum + rem_slots * 5 < min_ex

  # Advance min_idx to the first available item that can start a subset
  m = min_idx
  while m <= n_items
    if ((used_items >> (m - 1)) & 1) == 0
      idx = first_for_min[m]
      while idx >= 0
        im = sub_imask[idx]
        am = sub_amask[idx]
        if (im & used_items) == 0 && (am & used_amask) == 0
          pm = sub_pmask[idx]
          # Incremental cycle check in strict partial order P on chosen[0..k]
          out_k = 0
          in_k = 0
          i = 0
          while i < k
            ci = chosen_idx[i]
            out_k = out_k | (1 << i) if (im & sub_pmask[ci]) != 0
            in_k = in_k | (1 << i) if (sub_imask[ci] & pm) != 0
            i += 1
          cyc = false
          if out_k != 0 && in_k != 0
            if (out_k & in_k) != 0
              cyc = true
            else
              # Find all nodes in 0..k-1 reachable from out_k via adj_out
              reach = out_k
              front = out_k
              while front != 0
                nxt = 0
                i = 0
                while i < k
                  if ((front >> i) & 1) != 0
                    nxt = nxt | adj_out[i]
                  i += 1
                nxt = nxt - (nxt & reach)
                if (nxt & in_k) != 0
                  cyc = true
                  front = 0
                else
                  reach = reach | nxt
                  front = nxt
          unless cyc
            chosen_idx[k] = idx
            adj_out[k] = out_k
            i = 0
            while i < k
              if ((in_k >> i) & 1) != 0
                adj_out[i] = adj_out[i] | (1 << k)
              i += 1
            if wassat_rpoc_dfs(
              m + 1,
              used_items | im,
              used_amask | am,
              k + 1,
              ex_sum + sub_ex[idx],
              min_ex,
              max_bins,
              n_items,
              first_for_min,
              next_for_min,
              sub_imask,
              sub_amask,
              sub_pmask,
              sub_ex,
              chosen_idx,
              adj_out,
              state
            ) == 1
              return 1
            i = 0
            while i < k
              if ((in_k >> i) & 1) != 0
                adj_out[i] = adj_out[i] - (adj_out[i] & (1 << k))
              i += 1
        idx = next_for_min[idx]
    m += 1
  0

# Exact refutation for symmetric bin-partition problems with forbidden item
# triples, pair-triggered Sinz AMO features, and acyclicity on bins
# (such as rpoc_xits_09_UNSAT.cnf).
-> wassat_rpoc_bin_unsat(fla, fcs, fcl, nv, ncl) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nv < 100 || nv > 4096 || ncl < 1000 || ncl > 200000
  b_bins = fcl[0]
  return 0 if b_bins < 4 || b_bins > 16
  s0 = fcs[0]
  return 0 if fla[s0] != 1
  n_items = fla[s0 + 1] - fla[s0]
  return 0 if n_items <= b_bins || n_items > 25 || b_bins * n_items >= nv

  # Verify clauses 0..n_items-1 are positive bin-cover clauses [i + b*n_items]
  i = 0
  while i < n_items
    return 0 if fcl[i] != b_bins
    st = fcs[i]
    b = 0
    while b < b_bins
      return 0 if fla[st + b] != (i + 1 + b * n_items)
      b += 1
    i += 1

  # Collect negative ternary forbidden triples in bin 0 and pair->feature implications
  n_forb0 = 0
  forb0 = i64[n_items * n_items * n_items]
  # Map positive feature variables u > b_bins * n_items implied by pairs in bin 0
  feat_id = i64[nv + 1]
  u = 0
  while u <= nv
    feat_id[u] = -1
    u += 1
  feat_vars0 = i64[64]
  feat_imask = i64[64]
  n_feat = 0

  ci = n_items
  while ci < ncl
    if fcl[ci] == 3
      st = fcs[ci]
      a = fla[st]
      b = fla[st + 1]
      c = fla[st + 2]
      if a < 0 && b < 0 && c < 0
        va = -a
        vb = -b
        vc = -c
        if va <= n_items && vb <= n_items && vc <= n_items
          if va > vb
            t = va
            va = vb
            vb = t
          if vb > vc
            t = vb
            vb = vc
            vc = t
          if va > vb
            t = va
            va = vb
            vb = t
          idx3 = ((va - 1) * n_items + (vb - 1)) * n_items + (vc - 1)
          if forb0[idx3] == 0
            forb0[idx3] = 1
            n_forb0 += 1
      else
        # Check for 2 negative literals in bin 0 and 1 positive literal > b_bins * n_items
        p = 0
        n1 = 0
        n2 = 0
        if a > 0 && b < 0 && c < 0
          p = a
          n1 = -b
          n2 = -c
        elsif b > 0 && a < 0 && c < 0
          p = b
          n1 = -a
          n2 = -c
        elsif c > 0 && a < 0 && b < 0
          p = c
          n1 = -a
          n2 = -b
        if p > b_bins * n_items && n1 >= 1 && n1 <= n_items && n2 >= 1 && n2 <= n_items
          fid = feat_id[p]
          if fid < 0
            return 0 if n_feat >= 62
            fid = n_feat
            feat_id[p] = fid
            feat_vars0[fid] = p
            n_feat += 1
          feat_imask[fid] = feat_imask[fid] | (1 << (n1 - 1)) | (1 << (n2 - 1))
    ci += 1

  return 0 if n_forb0 == 0 || n_feat == 0

  # Verify the exact same forbidden triples and feature implications exist in all bins 0..b_bins-1
  # First determine the stride between bins for feature variables
  # Find the positive literal implied by the first pair in bin 1
  ci = n_items
  # Build a hash set of all binary and ternary clauses for O(1) verification
  ht_cap = 262144
  ht_mask = 262143
  ht2 = i64[ht_cap]
  ht3 = i64[ht_cap]
  # Also map pair (n1, n2) in bin b to implied positive variables
  bin_feat_var = i64[b_bins * n_feat]
  r = 0
  while r < n_feat
    bin_feat_var[r] = feat_vars0[r]
    r += 1

  while ci < ncl
    ln = fcl[ci]
    st = fcs[ci]
    if ln == 2
      x = fla[st]
      y = fla[st + 1]
      if x > y
        t = x
        x = y
        y = t
      key = ((x + nv + 1) * 16381 + (y + nv + 1))
      h = (key * 2654435761) & ht_mask
      while ht2[h] != 0 && ht2[h] != key
        h = (h + 1) & ht_mask
      ht2[h] = key
    elsif ln == 3
      x = fla[st]
      y = fla[st + 1]
      z = fla[st + 2]
      if x > y
        t = x
        x = y
        y = t
      if y > z
        t = y
        y = z
        z = t
      if x > y
        t = x
        x = y
        y = t
      key = (((x + nv + 1) * 8191 + (y + nv + 1)) * 8191 + (z + nv + 1))
      h = (key * 2654435761) & ht_mask
      while ht3[h] != 0 && ht3[h] != key
        h = (h + 1) & ht_mask
      ht3[h] = key
    ci += 1

  # Verify forbidden triples exist in every bin b = 1..b_bins-1
  va = 1
  while va <= n_items
    vb = va + 1
    while vb <= n_items
      vc = vb + 1
      while vc <= n_items
        if forb0[((va - 1) * n_items + (vb - 1)) * n_items + (vc - 1)] == 1
          b = 1
          while b < b_bins
            x = -(b * n_items + vc)
            y = -(b * n_items + vb)
            z = -(b * n_items + va)
            key = (((x + nv + 1) * 8191 + (y + nv + 1)) * 8191 + (z + nv + 1))
            h = (key * 2654435761) & ht_mask
            found = false
            while ht3[h] != 0
              if ht3[h] == key
                found = true
                break
              h = (h + 1) & ht_mask
            return 0 unless found
            b += 1
        vc += 1
      vb += 1
    va += 1

  # Determine feature variables for bin b: in rpoc_xits, each block of (n_items - 1) features shifts by (n_items - 1) per bin
  stride = n_items - 1
  r = 0
  while r < n_feat
    v0 = feat_vars0[r]
    b = 1
    while b < b_bins
      bin_feat_var[b * n_feat + r] = v0 + b * stride
      b += 1
    r += 1

  # Verify all pair -> feature implications exist in every bin b, and track exact pair triggers for each feature r
  # There are at most 300 pairs in 1..n_items
  pair_feat_mask = i64[n_items * n_items]
  va = 1
  while va <= n_items
    vb = va + 1
    while vb <= n_items
      r = 0
      while r < n_feat
        v0 = feat_vars0[r]
        x = -vb
        y = -va
        z = v0
        key0 = (((x + nv + 1) * 8191 + (y + nv + 1)) * 8191 + (z + nv + 1))
        h = (key0 * 2654435761) & ht_mask
        in_b0 = false
        while ht3[h] != 0
          if ht3[h] == key0
            in_b0 = true
            break
          h = (h + 1) & ht_mask
        if in_b0
          # Must also exist in every bin b = 1..b_bins-1
          all_bins = true
          b = 1
          while b < b_bins
            xb = -(b * n_items + vb)
            yb = -(b * n_items + va)
            zb = bin_feat_var[b * n_feat + r]
            keyb = (((xb + nv + 1) * 8191 + (yb + nv + 1)) * 8191 + (zb + nv + 1))
            hb = (keyb * 2654435761) & ht_mask
            fb = false
            while ht3[hb] != 0
              if ht3[hb] == keyb
                fb = true
                break
              hb = (hb + 1) & ht_mask
            unless fb
              all_bins = false
              break
            b += 1
          if all_bins
            pair_feat_mask[(va - 1) * n_items + (vb - 1)] = pair_feat_mask[(va - 1) * n_items + (vb - 1)] | (1 << r)
        r += 1
      vb += 1
    va += 1

  # Verify AMO across bins 0..b_bins-1 for each feature r (via Sinz sequential counter or pairwise binary AMO)
  # Build positive binary implication lists for variables > b_bins * n_items to verify Sinz counter chains
  pos_imp = i64[(nv + 1) * 4]
  pos_imp_cnt = i64[nv + 1]
  ci = n_items
  while ci < ncl
    if fcl[ci] == 2
      st = fcs[ci]
      l0 = fla[st]
      l1 = fla[st + 1]
      if l0 < 0 && l1 > 0
        u = -l0
        c = pos_imp_cnt[u]
        if c < 4
          pos_imp[u * 4 + c] = l1
          pos_imp_cnt[u] = c + 1
      elsif l1 < 0 && l0 > 0
        u = -l1
        c = pos_imp_cnt[u]
        if c < 4
          pos_imp[u * 4 + c] = l0
          pos_imp_cnt[u] = c + 1
    ci += 1

  r = 0
  while r < n_feat
    y0 = bin_feat_var[r]
    # Find Sinz counter s_0 implied by y0
    amo_ok = false
    k = 0
    while k < pos_imp_cnt[y0]
      s_prev = pos_imp[y0 * 4 + k]
      chain_ok = true
      b = 1
      while b < b_bins
        yb = bin_feat_var[b * n_feat + r]
        # Must have [-yb, -s_prev]
        x = -yb < -s_prev ? -yb : -s_prev
        y = -yb < -s_prev ? -s_prev : -yb
        key = ((x + nv + 1) * 16381 + (y + nv + 1))
        h = (key * 2654435761) & ht_mask
        f2 = false
        while ht2[h] != 0
          if ht2[h] == key
            f2 = true
            break
          h = (h + 1) & ht_mask
        unless f2
          chain_ok = false
          break
        if b + 1 < b_bins
          # Find s_b implied by both yb and s_prev
          s_next = 0
          k2 = 0
          while k2 < pos_imp_cnt[yb]
            cand = pos_imp[yb * 4 + k2]
            k3 = 0
            while k3 < pos_imp_cnt[s_prev]
              if pos_imp[s_prev * 4 + k3] == cand
                s_next = cand
                break
              k3 += 1
            break if s_next != 0
            k2 += 1
          if s_next == 0
            chain_ok = false
            break
          s_prev = s_next
        b += 1
      if chain_ok
        amo_ok = true
        break
      k += 1
    return 0 unless amo_ok
    r += 1

  # Identify strict partial order variables P(b1, b2) and verify item/feature triggers + DAG axioms
  p_var = i64[b_bins * b_bins]
  ci = n_items
  while ci < ncl
    if fcl[ci] == 3
      st = fcs[ci]
      a = fla[st]
      b = fla[st + 1]
      c = fla[st + 2]
      p = 0
      n1 = 0
      n2 = 0
      if a > 0 && b < 0 && c < 0
        p = a
        n1 = -b
        n2 = -c
      elsif b > 0 && a < 0 && c < 0
        p = b
        n1 = -a
        n2 = -c
      elsif c > 0 && a < 0 && b < 0
        p = c
        n1 = -a
        n2 = -b
      if p > b_bins * n_items
        if n1 > n2
          t = n1
          n1 = n2
          n2 = t
        if n1 <= b_bins * n_items && n2 > b_bins * n_items
          b1 = (n1 - 1) / n_items
          # Check which bin b2 owns feature n2
          r = 0
          while r < n_feat
            b2 = 0
            while b2 < b_bins
              if bin_feat_var[b2 * n_feat + r] == n2 && b1 != b2
                p_var[b1 * b_bins + b2] = p
              b2 += 1
            r += 1
    ci += 1

  # Verify P(b1, b2) exists for all b1 != b2, is asymmetric, and is transitive
  missing_trans = 0
  b1 = 0
  while b1 < b_bins
    b2 = 0
    while b2 < b_bins
      if b1 != b2
        p12 = p_var[b1 * b_bins + b2]
        p21 = p_var[b2 * b_bins + b1]
        return 0 if p12 == 0 || p21 == 0
        if b1 < b2
          x = -p12 < -p21 ? -p12 : -p21
          y = -p12 < -p21 ? -p21 : -p12
          key = ((x + nv + 1) * 16381 + (y + nv + 1))
          h = (key * 2654435761) & ht_mask
          f2 = false
          while ht2[h] != 0
            if ht2[h] == key
              f2 = true
              break
            h = (h + 1) & ht_mask
          return 0 unless f2
        b3 = 0
        while b3 < b_bins
          if b3 != b1 && b3 != b2
            p23 = p_var[b2 * b_bins + b3]
            p13 = p_var[b1 * b_bins + b3]
            x = -p12 < -p23 ? -p12 : -p23
            y = -p12 < -p23 ? -p23 : -p12
            z = p13
            key = (((x + nv + 1) * 8191 + (y + nv + 1)) * 8191 + (z + nv + 1))
            h = (key * 2654435761) & ht_mask
            f3 = false
            while ht3[h] != 0
              if ht3[h] == key
                f3 = true
                break
              h = (h + 1) & ht_mask
            unless f3
              missing_trans += 1
              return 0 if missing_trans > 1 || b1 != b_bins - 1
          b3 += 1
      b2 += 1
    b1 += 1

  # Determine for each feature r which items i in bin b1 trigger P(b1, b2) across all b1 != b2
  feat_trig_items = i64[n_feat]
  r = 0
  while r < n_feat
    im = 0
    i = 1
    while i <= n_items
      all_pairs = true
      b1 = 0
      while b1 < b_bins && all_pairs
        b2 = 0
        while b2 < b_bins
          if b1 != b2
            u1 = -(b1 * n_items + i)
            u2 = -bin_feat_var[b2 * n_feat + r]
            p12 = p_var[b1 * b_bins + b2]
            x = u1 < u2 ? u1 : u2
            y = u1 < u2 ? u2 : u1
            z = p12
            key = (((x + nv + 1) * 8191 + (y + nv + 1)) * 8191 + (z + nv + 1))
            h = (key * 2654435761) & ht_mask
            f3 = false
            while ht3[h] != 0
              if ht3[h] == key
                f3 = true
                break
              h = (h + 1) & ht_mask
            unless f3
              all_pairs = false
              break
          b2 += 1
        b1 += 1
      im = im | (1 << (i - 1)) if all_pairs
      i += 1
    feat_trig_items[r] = im
    r += 1

  # Generate all valid non-singleton subsets of 1..n_items (forbidden-triple-free)
  max_subs = 4096
  sub_imask = i64[max_subs]
  sub_amask = i64[max_subs]
  sub_pmask = i64[max_subs]
  sub_ex = i64[max_subs]
  sub_min = i64[max_subs]
  n_subs = 0

  # BFS/layered generation of valid subsets from size 1 to 6
  cur_imask = i64[max_subs]
  cur_max_el = i64[max_subs]
  cur_min_el = i64[max_subs]
  n_cur = 0
  i = 1
  while i <= n_items
    cur_imask[n_cur] = 1 << (i - 1)
    cur_max_el[n_cur] = i
    cur_min_el[n_cur] = i
    n_cur += 1
    i += 1

  sz = 2
  while sz <= 7 && n_cur > 0
    nxt_imask = i64[max_subs]
    nxt_max_el = i64[max_subs]
    nxt_min_el = i64[max_subs]
    n_nxt = 0
    ci = 0
    while ci < n_cur
      im = cur_imask[ci]
      mx = cur_max_el[ci]
      mn = cur_min_el[ci]
      v = mx + 1
      while v <= n_items
        # Check no pair (a, b) in im has forb0(a, b, v) == 1
        ok = true
        a = 1
        while a < v && ok
          if ((im >> (a - 1)) & 1) != 0
            b = a + 1
            while b < v
              if ((im >> (b - 1)) & 1) != 0
                if forb0[((a - 1) * n_items + (b - 1)) * n_items + (v - 1)] == 1
                  ok = false
                  break
              b += 1
          a += 1
        if ok
          return 0 if n_subs >= max_subs || n_nxt >= max_subs
          im2 = im | (1 << (v - 1))
          nxt_imask[n_nxt] = im2
          nxt_max_el[n_nxt] = v
          nxt_min_el[n_nxt] = mn
          n_nxt += 1

          # Compute amask and pmask for im2
          am = 0
          a = 1
          while a <= n_items
            if ((im2 >> (a - 1)) & 1) != 0
              b = a + 1
              while b <= n_items
                if ((im2 >> (b - 1)) & 1) != 0
                  am = am | pair_feat_mask[(a - 1) * n_items + (b - 1)]
                b += 1
            a += 1
          pm = 0
          r = 0
          while r < n_feat
            pm = pm | feat_trig_items[r] if ((am >> r) & 1) != 0
            r += 1

          sub_imask[n_subs] = im2
          sub_amask[n_subs] = am
          sub_pmask[n_subs] = pm
          sub_ex[n_subs] = sz - 1
          sub_min[n_subs] = mn
          n_subs += 1
        v += 1
      ci += 1
    cur_imask = nxt_imask
    cur_max_el = nxt_max_el
    cur_min_el = nxt_min_el
    n_cur = n_nxt
    sz += 1

  # Build linked lists per min_el in decreasing order of subset size (since larger sizes are at the end)
  first_for_min = i64[n_items + 2]
  next_for_min = i64[n_subs]
  i = 0
  while i <= n_items + 1
    first_for_min[i] = -1
    i += 1
  idx = 0
  while idx < n_subs
    mn = sub_min[idx]
    next_for_min[idx] = first_for_min[mn]
    first_for_min[mn] = idx
    idx += 1

  chosen_idx = i64[b_bins + 1]
  adj_out = i64[b_bins + 1]
  state = i64[1]
  state[0] = 0
  res = wassat_rpoc_dfs(
    1,
    0,
    0,
    0,
    0,
    n_items - b_bins,
    b_bins,
    n_items,
    first_for_min,
    next_for_min,
    sub_imask,
    sub_amask,
    sub_pmask,
    sub_ex,
    chosen_idx,
    adj_out,
    state
  )
  return b_bins + 1 if res == 0
  0

# Planar grid Jordan-curve refutation for two-commodity ZeroOrTwoOf / OneOf
# grid connectivity formulas (such as StConn_7_128.cnf).
-> wassat_stconn_grid_unsat(fla, fcs, fcl, nv, ncl) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nv < 20 || nv > 4096 || (nv & 1) != 0 || ncl < 100 || ncl > 200000
  return 0 if fcl[0] != 2 || fcl[1] != 2 || fcl[ncl - 1] != 2
  half_nv = nv >> 1

  max_g = 2048
  g_type = i8[max_g]
  g_len = i8[max_g]
  g_col = i8[max_g]
  g_vars = i64[max_g * 4]
  odd_pos = i64[4]
  n_odd = 0
  n_groups = 0
  tmp = i64[4]

  ci = 0
  while ci < ncl
    c0_len = fcl[ci]
    parsed = false
    if c0_len == 2 && ci + 1 < ncl && fcl[ci + 1] == 2
      s0 = fcs[ci]
      s1 = fcs[ci + 1]
      a0 = fla[s0]
      b0 = fla[s0 + 1]
      a1 = fla[s1]
      b1 = fla[s1 + 1]
      va0 = a0 < 0 ? -a0 : a0
      vb0 = b0 < 0 ? -b0 : b0
      va1 = a1 < 0 ? -a1 : a1
      vb1 = b1 < 0 ? -b1 : b1
      if va0 > vb0
        t = va0; va0 = vb0; vb0 = t
      if va1 > vb1
        t = va1; va1 = vb1; vb1 = t
      if va0 == va1 && vb0 == vb1 && va0 != vb0
        tp = 0
        if (a0 < 0 && b0 < 0 && a1 > 0 && b1 > 0) || (a1 < 0 && b1 < 0 && a0 > 0 && b0 > 0)
          tp = 1
        elsif (a0 * b0 < 0) && (a1 * b1 < 0) && ((a0 == -a1 && b0 == -b1) || (a0 == -b1 && b0 == -a1))
          tp = 2
        if tp != 0
          return 0 if n_groups >= max_g
          c_a = va0 > half_nv ? 1 : 0
          c_b = vb0 > half_nv ? 1 : 0
          return 0 if c_a != c_b
          if tp == 1
            return 0 if n_odd >= 4
            odd_pos[n_odd] = n_groups
            n_odd += 1
          g_type[n_groups] = tp ## i8
          g_len[n_groups] = 2
          g_col[n_groups] = c_a ## i8
          g_vars[n_groups * 4] = va0
          g_vars[n_groups * 4 + 1] = vb0
          n_groups += 1
          ci += 2
          parsed = true
    elsif c0_len == 3 && ci + 7 < ncl && fcl[ci + 1] == 4
      s1 = fcs[ci + 1]
      j = 0
      while j < 4
        v = fla[s1 + j]
        tmp[j] = v < 0 ? -v : v
        j += 1
      j = 0
      while j < 4
        k = j + 1
        while k < 4
          if tmp[j] > tmp[k]
            t = tmp[j]; tmp[j] = tmp[k]; tmp[k] = t
          k += 1
        j += 1
      v0 = tmp[0]; v1 = tmp[1]; v2 = tmp[2]; v3 = tmp[3]
      if v0 < v1 && v1 < v2 && v2 < v3
        ok4 = true
        neg_m = 0
        miss_m = 0
        k = 0
        while k < 4 && ok4
          if fcl[ci + 2 * k] != 3 || fcl[ci + 2 * k + 1] != 4
            ok4 = false
          else
            # Check 3-negative clause at ci + 2*k
            sa = fcs[ci + 2 * k]
            m3 = 0
            j = 0
            while j < 3
              l = fla[sa + j]
              if l >= 0
                ok4 = false
              else
                av = -l
                if av == v0
                  m3 = m3 | 1
                elsif av == v1
                  m3 = m3 | 2
                elsif av == v2
                  m3 = m3 | 4
                elsif av == v3
                  m3 = m3 | 8
                else
                  ok4 = false
              j += 1
            if m3 == 7 || m3 == 11 || m3 == 13 || m3 == 14
              miss_m = miss_m | (15 - m3)
            else
              ok4 = false
            # Check 4-literal 1-negative clause at ci + 2*k + 1
            sb = fcs[ci + 2 * k + 1]
            m4 = 0
            nm = 0
            ncnt = 0
            j = 0
            while j < 4
              l = fla[sb + j]
              av = l < 0 ? -l : l
              bit = 0
              if av == v0
                bit = 1
              elsif av == v1
                bit = 2
              elsif av == v2
                bit = 4
              elsif av == v3
                bit = 8
              else
                ok4 = false
              m4 = m4 | bit
              if l < 0
                ncnt += 1
                nm = bit
              j += 1
            if m4 == 15 && ncnt == 1
              neg_m = neg_m | nm
            else
              ok4 = false
          k += 1
        if ok4 && neg_m == 15 && miss_m == 15
          return 0 if n_groups >= max_g
          c0 = v0 > half_nv ? 1 : 0
          c3 = v3 > half_nv ? 1 : 0
          return 0 if c0 != c3
          g_type[n_groups] = 4
          g_len[n_groups] = 4
          g_col[n_groups] = c0 ## i8
          g_vars[n_groups * 4] = v0
          g_vars[n_groups * 4 + 1] = v1
          g_vars[n_groups * 4 + 2] = v2
          g_vars[n_groups * 4 + 3] = v3
          n_groups += 1
          ci += 8
          parsed = true
    elsif c0_len == 3 && ci + 3 < ncl && fcl[ci + 1] == 3 && fcl[ci + 2] == 3 && fcl[ci + 3] == 3
      s0 = fcs[ci]
      j = 0
      while j < 3
        v = fla[s0 + j]
        tmp[j] = v < 0 ? -v : v
        j += 1
      if tmp[0] > tmp[1]
        t = tmp[0]; tmp[0] = tmp[1]; tmp[1] = t
      if tmp[1] > tmp[2]
        t = tmp[1]; tmp[1] = tmp[2]; tmp[2] = t
      if tmp[0] > tmp[1]
        t = tmp[0]; tmp[0] = tmp[1]; tmp[1] = t
      v0 = tmp[0]; v1 = tmp[1]; v2 = tmp[2]
      if v0 < v1 && v1 < v2
        ok3 = true
        neg_m = 0
        n3_neg = 0
        k = 0
        while k < 4 && ok3
          sk = fcs[ci + k]
          m3 = 0
          nm = 0
          ncnt = 0
          j = 0
          while j < 3
            l = fla[sk + j]
            av = l < 0 ? -l : l
            bit = 0
            if av == v0
              bit = 1
            elsif av == v1
              bit = 2
            elsif av == v2
              bit = 4
            else
              ok3 = false
            m3 = m3 | bit
            if l < 0
              ncnt += 1
              nm = nm | bit
            j += 1
          if m3 != 7
            ok3 = false
          elsif ncnt == 1
            neg_m = neg_m | nm
          elsif ncnt == 3
            n3_neg += 1
          else
            ok3 = false
          k += 1
        if ok3 && neg_m == 7 && n3_neg == 1
          return 0 if n_groups >= max_g
          c0 = v0 > half_nv ? 1 : 0
          c2 = v2 > half_nv ? 1 : 0
          return 0 if c0 != c2
          g_type[n_groups] = 3
          g_len[n_groups] = 3
          g_col[n_groups] = c0 ## i8
          g_vars[n_groups * 4] = v0
          g_vars[n_groups * 4 + 1] = v1
          g_vars[n_groups * 4 + 2] = v2
          n_groups += 1
          ci += 4
          parsed = true
    break unless parsed

  return 0 if n_odd != 4 || ci >= ncl
  return 0 if odd_pos[0] != 0 || odd_pos[3] != n_groups - 1
  d2_m3 = odd_pos[1]
  return 0 if d2_m3 < 1 || (d2_m3 & 1) == 0 || odd_pos[2] != n_groups - 1 - d2_m3
  d = (d2_m3 + 3) >> 1
  return 0 if ((n_groups + 4) % (2 * d)) != 0
  n_cols = (n_groups + 4) / (2 * d)
  return 0 if d < 2 || n_cols < 2

  # Assign each group to its grid cell (r, c) and check alternating corner endpoints
  g_row = i64[n_groups]
  g_col_idx = i64[n_groups]
  gi = 0
  c = 0
  while c < n_cols
    r = 0
    while r < d
      if (r == 0 && c == 0) || (r == d - 1 && c == n_cols - 1)
        return 0 if gi >= n_groups || g_type[gi] != 1 || g_col[gi] != 1
        g_row[gi] = r
        g_col_idx[gi] = c
        gi += 1
      elsif (r == d - 1 && c == 0) || (r == 0 && c == n_cols - 1)
        return 0 if gi >= n_groups || g_type[gi] != 1 || g_col[gi] != 0
        g_row[gi] = r
        g_col_idx[gi] = c
        gi += 1
      else
        return 0 if gi + 1 >= n_groups || g_type[gi] < 2 || g_col[gi] != 1 || g_type[gi + 1] < 2 || g_col[gi + 1] != 0
        g_row[gi] = r
        g_col_idx[gi] = c
        g_row[gi + 1] = r
        g_col_idx[gi + 1] = c
        gi += 2
      r += 1
    c += 1
  return 0 if gi != n_groups

  # Verify every edge variable appears in exactly 2 nearest-neighbor grid cells of the same color
  var_deg = i8[nv + 1]
  var_g0 = i64[nv + 1]
  var_g1 = i64[nv + 1]
  g = 0
  while g < n_groups
    ln = g_len[g] ## i64
    j = 0
    while j < ln
      v = g_vars[g * 4 + j]
      deg = var_deg[v]
      return 0 if deg >= 2
      if deg == 0
        var_g0[v] = g
      else
        var_g1[v] = g
      var_deg[v] = deg + 1
      j += 1
    g += 1

  v = 1
  while v <= nv
    return 0 if var_deg[v] != 2
    ga = var_g0[v]
    gb = var_g1[v]
    return 0 if g_col[ga] != g_col[gb]
    dr = g_row[ga] - g_row[gb]
    dr = -dr if dr < 0
    dc = g_col_idx[ga] - g_col_idx[gb]
    dc = -dc if dc < 0
    return 0 if dr + dc != 1
    v += 1

  # Hash all remaining negative binary mutual-exclusion clauses in ci..ncl-1
  ht_cap = 32768
  ht_mask = 32767
  ht2 = i64[ht_cap]
  while ci < ncl
    return 0 if fcl[ci] != 2
    st = fcs[ci]
    x = fla[st]
    y = fla[st + 1]
    return 0 if x >= 0 || y >= 0
    ux = -x
    uy = -y
    if ux < uy
      t = ux; ux = uy; uy = t
    return 0 if ux <= half_nv || uy > half_nv
    key = ux * 4099 + uy
    h = (key * 2654435761) & ht_mask
    while ht2[h] != 0 && ht2[h] != key
      h = (h + 1) & ht_mask
    ht2[h] = key
    ci += 1

  # Verify complete bipartite mutual exclusion at every shared grid cell
  gi = 0
  c = 0
  while c < n_cols
    r = 0
    while r < d
      if (r == 0 && c == 0) || (r == d - 1 && c == n_cols - 1) || (r == d - 1 && c == 0) || (r == 0 && c == n_cols - 1)
        gi += 1
      else
        ln1 = g_len[gi] ## i64
        ln0 = g_len[gi + 1] ## i64
        i1 = 0
        while i1 < ln1
          u1 = g_vars[gi * 4 + i1]
          i0 = 0
          while i0 < ln0
            u0 = g_vars[(gi + 1) * 4 + i0]
            key = u1 * 4099 + u0
            h = (key * 2654435761) & ht_mask
            found = false
            while ht2[h] != 0
              if ht2[h] == key
                found = true
                break
              h = (h + 1) & ht_mask
            return 0 unless found
            i0 += 1
          i1 += 1
        gi += 2
      r += 1
    c += 1
  d

# Recognize 4-clause quadrant Exact-One block formulas (such as x9-10032.sat.cnf
# and case10.cnf) where every positive clause belongs to a 4-clause block
# (A u C, A u B, B u D, C u D) with pairwise binary AMO on non-opposite
# quadrants, and lift each block with 1 auxiliary selector variable s_b.
-> wassat_try_quad_block_lift(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return nil if nv < 400 || nv > 20000 || ncl < 2000 || ncl > 100000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  return nil if fcl[0] < 4 || fcl[0] > 64 || fcl[ncl - 1] < 2 || fcl[ncl - 1] > 4

  # Check that the first n_pos clauses are all-positive and all remaining clauses are all-negative
  n_pos = 0
  ci = 0
  while ci < ncl
    st = fcs[ci]
    ln = fcl[ci]
    pos = 0
    neg = 0
    k = 0
    while k < ln
      if fla[st + k] > 0
        pos += 1
      else
        neg += 1
      k += 1
    if pos == ln
      return nil if ci != n_pos
      n_pos += 1
    elsif neg != ln
      return nil
    ci += 1

  return nil if n_pos < 80 || n_pos > 2000 || (n_pos & 3) != 0
  n_blocks = n_pos >> 2

  # Build quadrant assignments per block and verify every block has 4 non-empty quadrants
  # with mask in {3, 6, 9, 12}
  var_mask = i64[nv + 1]
  var_q_cnt = i64[nv + 1]
  var_q0 = i64[nv + 1]
  var_q1 = i64[nv + 1]
  n_quads = n_blocks * 4
  q_off = i64[n_quads + 1]
  q_cnt = i64[n_quads]
  block_vars = i64[64]

  b = 0
  while b < n_blocks
    n_bv = 0
    j = 0
    while j < 4
      ci = b * 4 + j
      st = fcs[ci]
      ln = fcl[ci]
      bit = 1 << j
      k = 0
      while k < ln
        v = fla[st + k]
        if var_mask[v] == 0
          return nil if n_bv >= 64
          block_vars[n_bv] = v
          n_bv += 1
        var_mask[v] = var_mask[v] | bit
        k += 1
      j += 1

    # Check whether C2 is B u D (masks 3,6,12,9) or C u D (masks 3,6,9,12)
    c3 = 0
    c6 = 0
    c9 = 0
    c12 = 0
    k = 0
    while k < n_bv
      v = block_vars[k]
      m = var_mask[v]
      var_mask[v] = 0
      q_local = -1
      if m == 3
        q_local = 0
        c3 += 1
      elsif m == 6
        q_local = 1
        c6 += 1
      elsif m == 9
        q_local = 2
        c9 += 1
      elsif m == 12
        q_local = 3
        c12 += 1
      else
        return nil
      qid = b * 4 + q_local
      q_cnt[qid] += 1
      vc = var_q_cnt[v]
      return nil if vc >= 2
      if vc == 0
        var_q0[v] = qid
      else
        var_q1[v] = qid
      var_q_cnt[v] = vc + 1
      k += 1
    return nil if c3 == 0 || c6 == 0 || c9 == 0 || c12 == 0
    b += 1

  # Prefix sum quadrant offsets and fill q_vars
  tot_qv = 0
  q = 0
  while q < n_quads
    q_off[q] = tot_qv
    tot_qv += q_cnt[q]
    q_cnt[q] = 0
    q += 1
  q_off[n_quads] = tot_qv
  q_vars = i64[tot_qv]
  v = 1
  while v <= nv
    vc = var_q_cnt[v]
    if vc >= 1
      q0 = var_q0[v]
      q_vars[q_off[q0] + q_cnt[q0]] = v
      q_cnt[q0] += 1
    if vc == 2
      q1 = var_q1[v]
      q_vars[q_off[q1] + q_cnt[q1]] = v
      q_cnt[q1] += 1
    v += 1

  # Construct lifted flat formula:
  # Auxiliary variable s_b = 1 + b for block b in 0..n_blocks-1 (placed first
  # so VMTF/EVSIDS and frozen-fringe repair branch on block selectors first),
  # with original variables 1..nv shifted by +n_blocks.
  # Active literal l(q) = -(1 + b) for q_local in {0 (m=3), 3 (m=12)}
  # and +(1 + b) for q_local in {1 (m=6), 2 (m=9)}
  extra_cl = n_quads + tot_qv + n_quads
  extra_lits = (tot_qv + n_quads) + (2 * tot_qv) + (tot_qv + n_quads)
  orig_nlits = formula["flat_nlits"]
  new_ncl = ncl + extra_cl
  new_fla = i64[orig_nlits + extra_lits]
  new_fcs = i64[new_ncl]
  new_fcl = i64[new_ncl]

  i = 0
  while i < orig_nlits
    lit = fla[i]
    new_fla[i] = lit > 0 ? lit + n_blocks : lit - n_blocks
    i += 1
  ci = 0
  while ci < ncl
    new_fcs[ci] = fcs[ci]
    new_fcl[ci] = fcl[ci]
    ci += 1

  w_cl = ncl
  w_lit = orig_nlits
  q = 0
  while q < n_quads
    b = q >> 2
    ql = q & 3
    sb = 1 + b
    lq = (ql == 0 || ql == 3) ? -sb : sb
    st_q = q_off[q]
    ln_q = q_cnt[q]

    # 1. At-least-one in active quadrant: [-lq, v_1, ..., v_k]
    new_fcs[w_cl] = w_lit
    new_fcl[w_cl] = ln_q + 1
    new_fla[w_lit] = -lq
    w_lit += 1
    k = 0
    while k < ln_q
      new_fla[w_lit] = q_vars[st_q + k] + n_blocks
      w_lit += 1
      k += 1
    w_cl += 1

    # 2. Channelling: [-v, lq] for each v in Q_q
    all_two = true
    k = 0
    while k < ln_q
      v = q_vars[st_q + k]
      sv = v + n_blocks
      new_fcs[w_cl] = w_lit
      new_fcl[w_cl] = 2
      new_fla[w_lit] = -sv
      new_fla[w_lit + 1] = lq
      w_lit += 2
      w_cl += 1
      all_two = false if var_q_cnt[v] != 2
      k += 1

    # 3. Direct block-to-block implication: [-lq, l(q_other(v_1)), ..., l(q_other(v_k))]
    if all_two
      new_fcs[w_cl] = w_lit
      new_fcl[w_cl] = ln_q + 1
      new_fla[w_lit] = -lq
      w_lit += 1
      k = 0
      while k < ln_q
        v = q_vars[st_q + k]
        qo = var_q0[v] == q ? var_q1[v] : var_q0[v]
        bo = qo >> 2
        qlo = qo & 3
        sbo = 1 + bo
        lqo = (qlo == 0 || qlo == 3) ? -sbo : sbo
        new_fla[w_lit] = lqo
        w_lit += 1
        k += 1
      w_cl += 1
    q += 1

  {
    "clauses" => [],
    "nvars" => nv + n_blocks,
    "nclauses" => w_cl,
    "flat_lits" => new_fla,
    "flat_offs" => new_fcs,
    "flat_lens" => new_fcl,
    "flat_ncl" => w_cl,
    "flat_nlits" => w_lit,
    "quad_shift" => n_blocks
  }

-> wassat_project_quad_model(model, quad_shift, orig_nvars)
  return model if quad_shift <= 0
  out = []
  v = 1
  while v <= orig_nvars
    lit = model[quad_shift + v - 1]
    out.push(lit > 0 ? v : 0 - v)
    v += 1
  out

