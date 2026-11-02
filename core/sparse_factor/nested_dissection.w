+ SparseAnalysis
  # Nested dissection (George–Liu level-set flavor): find a small
  # balanced vertex separator from the BFS level structure of a
  # pseudo-peripheral root, order the two sides recursively, and order
  # the separator last with AMD — the classic lead over pure minimum
  # degree on large grid-like patterns, where eliminating a separator
  # after its halves bounds fill by the separator clique instead of
  # letting cliques crawl across the whole domain. Level separators are
  # minimalized (a separator vertex touching only one side moves into
  # it). Components split without a separator; shallow level structures
  # (dense blobs) and small subsets fall back to AMD directly.
  -> nd_ordering_of(nn, ri, ci, m)
    none = 4294967295
    # global deduped diagonal-free CSC
    rows = u32[nn]
    k = 0
    while k < m
      a = ri[k]
      b = ci[k]
      if a != b
        rows[a] = rows[a] + 1
        rows[b] = rows[b] + 1
      k += 1
    ptr = u32[nn + 1]
    run = 0
    i = 0
    while i < nn
      ptr[i] = run
      run += rows[i]
      rows[i] = 0
      i += 1
    ptr[nn] = run
    cap = run
    cap = 1 if cap == 0
    idx = u32[cap]
    k = 0
    while k < m
      a = ri[k]
      b = ci[k]
      if a != b
        idx[ptr[a] + rows[a]] = b
        rows[a] = rows[a] + 1
        idx[ptr[b] + rows[b]] = a
        rows[b] = rows[b] + 1
      k += 1
    mark = u32[nn]
    i = 0
    while i < nn
      p = ptr[i]
      stop = p + rows[i]
      q = p
      while p < stop
        j = idx[p]
        if mark[j] != i + 1
          mark[j] = i + 1
          idx[q] = j
          q += 1
        p += 1
      rows[i] = q - ptr[i]
      i += 1
    # subset pool with growth; tasks reference [start, len) segments
    bcap = nn * 4 + 64
    buf = u32[bcap]
    i = 0
    while i < nn
      buf[i] = i
      i += 1
    bcur = nn
    level = u32[nn]
    inset = u32[nn]   # subset-membership generation
    side = u32[nn]    # 1 = below, 2 = separator, 3 = above (per op)
    bfsq = u32[nn]
    linx = u32[nn]
    lvis = u32[nn]
    lgen2 = 0
    gen = 0
    out = u32[nn]
    ocur = 0
    stack = []
    stack.push([0, 0, nn])
    while stack.size > 0
      task = stack.pop
      kind = task[0]
      start = task[1]
      slen = task[2]
      solve_leaf = kind == 1 || slen <= 300
      if !solve_leaf
        # mark membership (+ local index for coarse-map composition)
        gen += 1
        i = 0
        while i < slen
          inset[buf[start + i]] = gen
          linx[buf[start + i]] = i
          i += 1
        # BFS 1: component + farthest vertex from seg[0]
        root = buf[start]
        gen2 = gen
        qh = 0
        qt = 0
        bfsq[qt] = root
        qt += 1
        level[root] = 0
        seen = u32[0 + 1]
        # reuse side[] as visited stamp via gen: side stores gen when visited
        side[root] = gen
        far = root
        while qh < qt
          v = bfsq[qh]
          qh += 1
          far = v
          p = ptr[v]
          stop = p + rows[v]
          while p < stop
            u = idx[p]
            if inset[u] == gen && side[u] != gen
              side[u] = gen
              bfsq[qt] = u
              qt += 1
            p += 1
        if qt < slen
          # disconnected: component first, remainder second, no separator
          comp_start = bcur
          if bcur + slen > bcap
            nlen = bcap * 2
            nlen = bcur + slen + slen + 64 if nlen < bcur + slen + slen + 64
            nb = u32[nlen]
            q = 0
            while q < bcur
              nb[q] = buf[q]
              q += 1
            buf = nb
            bcap = nlen
          i = 0
          while i < qt
            buf[bcur] = bfsq[i]
            bcur += 1
            i += 1
          rest_start = bcur
          i = 0
          while i < slen
            v = buf[start + i]
            if side[v] != gen
              buf[bcur] = v
              bcur += 1
            i += 1
          stack.push([0, rest_start, bcur - rest_start])
          stack.push([0, comp_start, qt])
        else
          # Multilevel bisection: build the induced graph, coarsen by
          # heavy-edge matching, bisect the coarsest by BFS growth to
          # half weight, then uncoarsen with greedy boundary refinement
          # of the weighted edge cut. The finest partition yields a
          # vertex separator by greedy cover of the cut edges.
          gen += 1
          i = 0
          while i < slen
            v = buf[start + i]
            inset[v] = gen
            level[v] = i
            i += 1
          # induced graph in local ids (level[] holds local id)
          g_xadj = u32[slen + 1]
          i = 0
          while i < slen
            v = buf[start + i]
            d = 0
            p = ptr[v]
            stop = p + rows[v]
            while p < stop
              d += 1 if inset[idx[p]] == gen
              p += 1
            g_xadj[i + 1] = d
            i += 1
          i = 0
          while i < slen
            g_xadj[i + 1] = g_xadj[i + 1] + g_xadj[i]
            i += 1
          g_m = g_xadj[slen]
          g_m = 1 if g_m == 0
          g_adj = u32[g_m]
          g_wgt = u32[g_m]
          g_vw = u32[slen]
          fillp = u32[slen]
          i = 0
          while i < slen
            v = buf[start + i]
            g_vw[i] = 1
            p = ptr[v]
            stop = p + rows[v]
            while p < stop
              u = idx[p]
              if inset[u] == gen
                g_adj[g_xadj[i] + fillp[i]] = level[u]
                g_wgt[g_xadj[i] + fillp[i]] = 1
                fillp[i] = fillp[i] + 1
              p += 1
            i += 1
          # --- coarsen ---
          levels_x = [g_xadj]
          levels_a = [g_adj]
          levels_w = [g_wgt]
          levels_v = [g_vw]
          levels_map = []
          cn = slen
          while cn > 100
            cx = levels_x[levels_x.size - 1]
            ca = levels_a[levels_a.size - 1]
            cw = levels_w[levels_w.size - 1]
            cv = levels_v[levels_v.size - 1]
            match = u32[cn]
            i = 0
            while i < cn
              match[i] = 4294967295
              i += 1
            nc = 0
            i = 0
            while i < cn
              if match[i] == 4294967295
                bestu = 4294967295
                bestw = 0
                p = cx[i]
                stop = cx[i + 1]
                while p < stop
                  u = ca[p]
                  if match[u] == 4294967295 && u != i && cw[p] > bestw
                    bestw = cw[p]
                    bestu = u
                  p += 1
                if bestu == 4294967295
                  match[i] = i
                else
                  match[i] = bestu
                  match[bestu] = i
                nc += 1
              i += 1
            break if nc * 10 > cn * 9
            # coarse ids
            cmap = u32[cn]
            cid = 0
            i = 0
            while i < cn
              if match[i] >= i
                cmap[i] = cid
                cmap[match[i]] = cid
                cid += 1
              i += 1
            # coarse graph via mark-accumulate
            nx = u32[cid + 1]
            nv2 = u32[cid]
            cmark = u32[cid]
            cslot = u32[cid]
            i = 0
            while i < cid
              cmark[i] = 4294967295
              i += 1
            # count pass
            i = 0
            while i < cn
              if match[i] >= i
                c1 = cmap[i]
                cnt2 = 0
                pass2 = 0
                while pass2 < 2
                  src2 = i
                  src2 = match[i] if pass2 == 1
                  if pass2 == 0 || match[i] != i
                    p = cx[src2]
                    stop = cx[src2 + 1]
                    while p < stop
                      tgt = cmap[ca[p]]
                      if tgt != c1 && cmark[tgt] != i + 1
                        cmark[tgt] = i + 1
                        cnt2 += 1
                      p += 1
                  pass2 += 1
                nx[c1 + 1] = cnt2
                nv2[c1] = cv[i]
                nv2[c1] = cv[i] + cv[match[i]] if match[i] != i
              i += 1
            i = 0
            while i < cid
              nx[i + 1] = nx[i + 1] + nx[i]
              i += 1
            nm = nx[cid]
            nm = 1 if nm == 0
            na = u32[nm]
            nw = u32[nm]
            i = 0
            while i < cid
              cmark[i] = 4294967295
              i += 1
            i = 0
            while i < cn
              if match[i] >= i
                c1 = cmap[i]
                fp = 0
                pass2 = 0
                while pass2 < 2
                  src2 = i
                  src2 = match[i] if pass2 == 1
                  if pass2 == 0 || match[i] != i
                    p = cx[src2]
                    stop = cx[src2 + 1]
                    while p < stop
                      tgt = cmap[ca[p]]
                      if tgt != c1
                        if cmark[tgt] != i + 1
                          cmark[tgt] = i + 1
                          na[nx[c1] + fp] = tgt
                          nw[nx[c1] + fp] = cw[p]
                          cslot[tgt] = nx[c1] + fp
                          fp += 1
                        else
                          nw[cslot[tgt]] = nw[cslot[tgt]] + cw[p]
                      p += 1
                  pass2 += 1
              i += 1
            levels_x.push(nx)
            levels_a.push(na)
            levels_w.push(nw)
            levels_v.push(nv2)
            levels_map.push(cmap)
            cn = cid
          # --- initial bisection on the coarsest: several seeded BFS
          # growths, keep the minimum weighted edge cut ---
          cx = levels_x[levels_x.size - 1]
          ca = levels_a[levels_a.size - 1]
          cwz = levels_w[levels_w.size - 1]
          cv = levels_v[levels_v.size - 1]
          totw = 0
          i = 0
          while i < cn
            totw += cv[i]
            i += 1
          half = totw >> 1
          cpart = u32[cn]
          tpart = u32[cn]
          cq = u32[cn]
          seenb = u32[cn]
          bgen = 0
          rstate = 12345
          best_cut = none
          # pseudo-peripheral seeds: the far vertex of BFS-1 composed through
          # the coarsening maps, and its antipode on the coarsest graph. A
          # BFS half grown from a periphery is a half-plane, not a disc —
          # on grid-like graphs the cut is O(√n) instead of O(perimeter).
          farc = linx[far]
          lm = 0
          while lm < levels_map.size
            farc = levels_map[lm][farc]
            lm += 1
          farc = 0 if farc >= cn
          bgen += 1
          qh = 0
          qt = 1
          cq[0] = farc
          seenb[farc] = bgen
          farc2 = farc
          while qh < qt
            v2 = cq[qh]
            qh += 1
            farc2 = v2
            p = cx[v2]
            stop = cx[v2 + 1]
            while p < stop
              u = ca[p]
              if seenb[u] != bgen
                seenb[u] = bgen
                cq[qt] = u
                qt += 1
              p += 1
          tryi = 0
          while tryi < 6
            rstate = (rstate * 48271) % 2147483647
            root2 = rstate % cn
            root2 = farc if tryi == 4
            root2 = farc2 if tryi == 5
            bgen += 1
            qh = 0
            qt = 0
            cq[0] = root2
            qt = 1
            seenb[root2] = bgen
            grown = 0
            i = 0
            while i < cn
              tpart[i] = 0
              i += 1
            while qh < qt && grown < half
              v2 = cq[qh]
              qh += 1
              tpart[v2] = 1
              grown += cv[v2]
              p = cx[v2]
              stop = cx[v2 + 1]
              while p < stop
                u = ca[p]
                if seenb[u] != bgen
                  seenb[u] = bgen
                  cq[qt] = u
                  qt += 1
                p += 1
            cutw = 0
            i = 0
            while i < cn
              p = cx[i]
              stop = cx[i + 1]
              while p < stop
                cutw += cwz[p] if tpart[ca[p]] != tpart[i] && ca[p] > i
                p += 1
              i += 1
            if cutw < best_cut
              best_cut = cutw
              i = 0
              while i < cn
                cpart[i] = tpart[i]
                i += 1
            tryi += 1
          # --- uncoarsen with boundary FM refinement (best-state
          # rollback: all boundary moves are tried in gain order, the
          # prefix with the best cumulative cut improvement is kept) ---
          goff = 1048576
          li = levels_map.size
          while li >= 0
            cx = levels_x[li]
            ca = levels_a[li]
            cw2 = levels_w[li]
            cv = levels_v[li]
            ln = slen
            ln = levels_v[li].size if li > 0
            fmpass = 0
            hkey2 = u32[ln * 4 + 16]
            hv2 = u32[ln * 4 + 16]
            hver2 = u32[ln * 4 + 16]
            ver2 = u32[ln]
            lockg = u32[ln]
            lgen = 0
            mlist = u32[ln]
            while fmpass < 4
              lgen += 1
              w0 = 0
              i = 0
              while i < ln
                w0 += cv[i] if cpart[i] == 0
                i += 1
              hsz = 0
              i = 0
              while i < ln
                g2 = 0
                isb = 0 == 1
                p = cx[i]
                stop = cx[i + 1]
                while p < stop
                  if cpart[ca[p]] == cpart[i]
                    g2 -= cw2[p]
                  else
                    g2 += cw2[p]
                    isb = 0 == 0
                  p += 1
                if isb
                  ver2[i] = ver2[i] + 1
                  hkey2[hsz] = goff - g2
                  hv2[hsz] = i
                  hver2[hsz] = ver2[i]
                  hsz += 1
                  j = hsz - 1
                  while j > 0
                    pj = (j - 1) >> 1
                    break if hkey2[pj] <= hkey2[j]
                    tk = hkey2[pj]
                    hkey2[pj] = hkey2[j]
                    hkey2[j] = tk
                    tk = hv2[pj]
                    hv2[pj] = hv2[j]
                    hv2[j] = tk
                    tk = hver2[pj]
                    hver2[pj] = hver2[j]
                    hver2[j] = tk
                    j = pj
                i += 1
              cur_d = 0
              best_d = 0
              mcount = 0
              best_len = 0
              while hsz > 0
                topv = hv2[0]
                topk = hkey2[0]
                topver = hver2[0]
                hsz -= 1
                hkey2[0] = hkey2[hsz]
                hv2[0] = hv2[hsz]
                hver2[0] = hver2[hsz]
                j = 0
                while 0 == 0
                  l3 = j * 2 + 1
                  r4 = j * 2 + 2
                  sm3 = j
                  sm3 = l3 if l3 < hsz && hkey2[l3] < hkey2[sm3]
                  sm3 = r4 if r4 < hsz && hkey2[r4] < hkey2[sm3]
                  break if sm3 == j
                  tk = hkey2[sm3]
                  hkey2[sm3] = hkey2[j]
                  hkey2[j] = tk
                  tk = hv2[sm3]
                  hv2[sm3] = hv2[j]
                  hv2[j] = tk
                  tk = hver2[sm3]
                  hver2[sm3] = hver2[j]
                  hver2[j] = tk
                  j = sm3
                next if topver != ver2[topv]
                next if lockg[topv] == lgen
                # balance guard
                vw3 = cv[topv]
                # 45/55 tolerance: the old 30/70 let zero-gain moves slide a
                # grid's cut line to the edge (440/1120 halves on 40x40)
                if cpart[topv] == 0
                  next if (w0 - vw3) * 20 < totw * 9
                else
                  next if (w0 + vw3) * 20 > totw * 11
                # recompute the true gain (entries can be stale)
                g2 = 0
                p = cx[topv]
                stop = cx[topv + 1]
                while p < stop
                  if cpart[ca[p]] == cpart[topv]
                    g2 -= cw2[p]
                  else
                    g2 += cw2[p]
                  p += 1
                if goff - g2 != topk
                  ver2[topv] = ver2[topv] + 1
                  hkey2[hsz] = goff - g2
                  hv2[hsz] = topv
                  hver2[hsz] = ver2[topv]
                  hsz += 1
                  j = hsz - 1
                  while j > 0
                    pj = (j - 1) >> 1
                    break if hkey2[pj] <= hkey2[j]
                    tk = hkey2[pj]
                    hkey2[pj] = hkey2[j]
                    hkey2[j] = tk
                    tk = hv2[pj]
                    hv2[pj] = hv2[j]
                    hv2[j] = tk
                    tk = hver2[pj]
                    hver2[pj] = hver2[j]
                    hver2[j] = tk
                    j = pj
                  next
                # apply the move
                lockg[topv] = lgen
                if cpart[topv] == 0
                  cpart[topv] = 1
                  w0 -= vw3
                else
                  cpart[topv] = 0
                  w0 += vw3
                cur_d += g2
                mlist[mcount] = topv
                mcount += 1
                if cur_d > best_d
                  best_d = cur_d
                  best_len = mcount
                # refresh neighbors into the heap
                p = cx[topv]
                stop = cx[topv + 1]
                while p < stop
                  u = ca[p]
                  if lockg[u] != lgen
                    g3 = 0
                    isb = 0 == 1
                    p2 = cx[u]
                    stop2 = cx[u + 1]
                    while p2 < stop2
                      if cpart[ca[p2]] == cpart[u]
                        g3 -= cw2[p2]
                      else
                        g3 += cw2[p2]
                        isb = 0 == 0
                      p2 += 1
                    if isb
                      ver2[u] = ver2[u] + 1
                      hkey2[hsz] = goff - g3
                      hv2[hsz] = u
                      hver2[hsz] = ver2[u]
                      hsz += 1
                      if hsz >= ln * 4 + 16
                        hsz -= 1
                      j = hsz - 1
                      while j > 0
                        pj = (j - 1) >> 1
                        break if hkey2[pj] <= hkey2[j]
                        tk = hkey2[pj]
                        hkey2[pj] = hkey2[j]
                        hkey2[j] = tk
                        tk = hv2[pj]
                        hv2[pj] = hv2[j]
                        hv2[j] = tk
                        tk = hver2[pj]
                        hver2[pj] = hver2[j]
                        hver2[j] = tk
                        j = pj
                  p += 1
              # roll back past the best prefix
              i = mcount
              while i > best_len
                i -= 1
                v3 = mlist[i]
                if cpart[v3] == 0
                  cpart[v3] = 1
                else
                  cpart[v3] = 0
              break if best_d <= 0
              fmpass += 1
            break if li == 0
            fmap = levels_map[li - 1]
            fcount = slen
            fcount = levels_v[li - 1].size if li - 1 > 0
            fpart = u32[fcount]
            i = 0
            while i < fcount
              fpart[i] = cpart[fmap[i]]
              i += 1
            cpart = fpart
            li -= 1
          # --- level-set candidate: BFS from the pseudo-peripheral vertex
          # `far`, split at the half-count level. On strip/grid pieces the
          # multilevel bisection cuts along the long axis (coarsest BFS
          # halves are discs, FM cannot move a whole line); the level-set
          # cut across the short axis is the textbook ND separator. Keep
          # whichever finest-level edge cut is smaller. ---
          cx = levels_x[0]
          ca = levels_a[0]
          mlcut = 0
          i = 0
          while i < slen
            p = cx[i]
            stop = cx[i + 1]
            while p < stop
              mlcut += 1 if cpart[ca[p]] != cpart[i] && ca[p] > i
              p += 1
            i += 1
          ls_ok = 0 == 1
          bestw = none
          splitl = 0
          acc = 0
          lgen2 += 1
          fl = linx[far]
          qh = 0
          qt = 1
          bfsq[0] = fl
          lvis[fl] = lgen2
          level[fl] = 0
          while qh < qt
            v2 = bfsq[qh]
            qh += 1
            p = cx[v2]
            stop = cx[v2 + 1]
            while p < stop
              u = ca[p]
              if lvis[u] != lgen2
                lvis[u] = lgen2
                level[u] = level[v2] + 1
                bfsq[qt] = u
                qt += 1
              p += 1
          if qt == slen
            # cumulative level counts -> split level
            maxl = 0
            i = 0
            while i < slen
              maxl = level[i] if level[i] > maxl
              i += 1
            lcnt = u32[maxl + 2]
            i = 0
            while i < slen
              lcnt[level[i]] += 1
              i += 1
            # thinnest level whose prefix is within the 35-65% balance window
            acc = 0
            splitl = 0
            cum = 0
            bestw = none
            l9 = 0
            while l9 <= maxl
              if cum * 20 >= slen * 7 && (slen - cum - lcnt[l9]) * 20 >= slen * 7 && lcnt[l9] < bestw
                bestw = lcnt[l9]
                splitl = l9
                acc = cum
              cum += lcnt[l9]
              l9 += 1
            ls_ok = 0 == 0 if bestw != none && acc * 20 >= slen * 7 && (slen - acc - bestw) * 20 >= slen * 7
          # --- vertex separator: greedy cover of the cut edges ---
          i = 0
          while i < slen
            v = buf[start + i]
            side[v] = 1
            side[v] = 3 if cpart[i] == 1
            i += 1
          # cover counts per vertex over uncovered cut edges
          ccov = u32[slen]
          total_cut = 0
          i = 0
          while i < slen
            cnt3 = 0
            p = cx[i]
            stop = cx[i + 1]
            while p < stop
              if cpart[ca[p]] != cpart[i]
                cnt3 += 1
                total_cut += 1 if ca[p] > i
              p += 1
            ccov[i] = cnt3
            i += 1
          # #11 (METIS-quality separator): exact minimum vertex cover of the
          # cut's bipartite boundary graph — maximum matching by augmenting
          # paths, then König's theorem (cover = (L \ Z) ∪ (R ∩ Z), Z =
          # alternating-reachable from unmatched L). The greedy cover it
          # replaces over-covers by up to 2x on irregular boundaries.
          matchv = u32[slen]
          i = 0
          while i < slen
            matchv[i] = none
            i += 1
          vis3 = u32[slen]
          vgen3 = 0
          stk3 = u32[slen + 1]
          par3 = u32[slen]
          # augmenting-path search from each left (side-0 boundary) vertex,
          # iterative DFS over alternating paths
          i = 0
          while i < slen
            if cpart[i] == 0 && ccov[i] > 0 && matchv[i] == none
              vgen3 += 1
              sp3 = 0
              stk3[sp3] = i
              sp3 += 1
              vis3[i] = vgen3
              par3[i] = none
              found = none
              while sp3 > 0 && found == none
                sp3 -= 1
                x = stk3[sp3]
                p = cx[x]
                stop = cx[x + 1]
                while p < stop && found == none
                  y = ca[p]
                  if cpart[y] == 1 && vis3[y] != vgen3
                    vis3[y] = vgen3
                    par3[y] = x
                    if matchv[y] == none
                      found = y
                    else
                      z = matchv[y]
                      if vis3[z] != vgen3
                        vis3[z] = vgen3
                        par3[z] = y
                        stk3[sp3] = z
                        sp3 += 1
                  p += 1
              if found != none
                # flip along the path: y <- x, x's previous mate ...
                y = found
                while y != none
                  x = par3[y]
                  prevy = matchv[x]
                  matchv[x] = y
                  matchv[y] = x
                  y = prevy
            i += 1
          # König: Z = reachable from unmatched L via alternating paths
          vgen3 += 1
          sp3 = 0
          i = 0
          while i < slen
            if cpart[i] == 0 && ccov[i] > 0 && matchv[i] == none
              vis3[i] = vgen3
              stk3[sp3] = i
              sp3 += 1
            i += 1
          while sp3 > 0
            sp3 -= 1
            x = stk3[sp3]
            p = cx[x]
            stop = cx[x + 1]
            while p < stop
              y = ca[p]
              if cpart[y] == 1 && vis3[y] != vgen3
                vis3[y] = vgen3
                z = matchv[y]
                if z != none && vis3[z] != vgen3
                  vis3[z] = vgen3
                  stk3[sp3] = z
                  sp3 += 1
              p += 1
          i = 0
          while i < slen
            if ccov[i] > 0
              incover = 0 == 1
              incover = 0 == 0 if cpart[i] == 0 && vis3[i] != vgen3
              incover = 0 == 0 if cpart[i] == 1 && vis3[i] == vgen3
              side[buf[start + i]] = 2 if incover
            i += 1
          # level-set override: the level itself IS a vertex separator
          # (levels < L | L | levels > L); take it when thinner than the
          # greedy cover (strips: width-11 level vs a ~20-vertex cover)
          sepc = 0
          i = 0
          while i < slen
            sepc += 1 if side[buf[start + i]] == 2
            i += 1
          if ls_ok && bestw < sepc
            i = 0
            while i < slen
              v = buf[start + i]
              side[v] = 1
              side[v] = 2 if level[i] == splitl
              side[v] = 3 if level[i] > splitl
              i += 1
          if 0 == 0
            # (no minimalization: a cut-boundary separator vertex always
            # has an opposite-side edge, and bidirectional moves can
            # de-separate the sides)
            if 0 == 0
              # pack A, B, sep into the pool
              need = slen + slen
              if bcur + need > bcap
                nlen = bcap * 2
                nlen = bcur + need + 64 if nlen < bcur + need + 64
                nb = u32[nlen]
                q = 0
                while q < bcur
                  nb[q] = buf[q]
                  q += 1
                buf = nb
                bcap = nlen
              a_start = bcur
              i = 0
              while i < slen
                v = buf[start + i]
                if side[v] == 1
                  buf[bcur] = v
                  bcur += 1
                i += 1
              b_start = bcur
              i = 0
              while i < slen
                v = buf[start + i]
                if side[v] == 3
                  buf[bcur] = v
                  bcur += 1
                i += 1
              s_start = bcur
              i = 0
              while i < slen
                v = buf[start + i]
                if side[v] == 2
                  buf[bcur] = v
                  bcur += 1
                i += 1
              s_len = bcur - s_start
              if s_start - b_start == 0 || b_start - a_start == 0
                solve_leaf = 1 == 1
                bcur = a_start
              else
                stack.push([1, s_start, s_len]) if s_len > 0
                stack.push([0, b_start, s_start - b_start])
                stack.push([0, a_start, b_start - a_start])
      if solve_leaf
        # order the induced subgraph with AMD, append composed ids
        gen += 1
        i = 0
        while i < slen
          v = buf[start + i]
          inset[v] = gen
          level[v] = i
          i += 1
        lri = []
        lci = []
        i = 0
        while i < slen
          v = buf[start + i]
          p = ptr[v]
          stop = p + rows[v]
          while p < stop
            u = idx[p]
            if inset[u] == gen && u < v
              lri.push(level[v])
              lci.push(level[u])
            p += 1
          i += 1
        sub = amd_core(slen, lri, lci, lri.size)
        i = 0
        while i < slen
          out[ocur] = buf[start + sub[i]]
          ocur += 1
          i += 1
    order = []
    k = 0
    while k < nn
      order.push(out[k])
      k += 1
    order

  # PREDICTOR-CORRECTOR ordering: exact minimum deficiency chooses the
  # tie set (on KKT patterns a few percent of the graph ties at the
  # minimum every pivot), and the corrector resolves it by the objective
  # actually scored — the candidate minimizing the induced change in
  # Σ(deg+1)² over its neighborhood; remaining ties break by degree then
  # index. Deficiencies are maintained with a lazy heap: eliminating x
  # re-evaluates N(x) exactly, while second-ring vertices (whose
  # deficiency can only fall) re-enter with an optimistic key lowered by
  # this pivot's total added fill and are re-checked when popped. When
  # the work budget is spent or a pivot exceeds the dense threshold, the
  # remaining (filled) graph is ordered by AMD — the tail is where pivot
  # choice stops mattering, and AMD bounds it at the baseline.
  -> predcorr_ordering_of(nn, ri, ci, m, work_budget)
    n = nn
    words = (n + 31) >> 5
    full = 4294967295
    none = 4294967295
    return [] if m * words > work_budget
    adj = u32[n * words]
    k = 0
    while k < m
      r = ri[k]
      c = ci[k]
      if r != c
        adj[r * words + (c >> 5)] = adj[r * words + (c >> 5)] | (1 << (c & 31))
        adj[c * words + (r >> 5)] = adj[c * words + (r >> 5)] | (1 << (r & 31))
      k += 1
    alive = u32[words]
    i = 0
    while i < words
      alive[i] = full
      i += 1
    tail = n & 31
    alive[words - 1] = (1 << tail) - 1 if tail != 0
    deg = u32[n]
    i = 0
    while i < n
      d = 0
      base = i * words
      wi = 0
      while wi < words
        d += ccall_nobox("__w_bit_ctpop_u32", adj[base + wi])
        wi += 1
      deg[i] = d
      i += 1
    nb = u32[words]
    nbrs = u32[n]
    # deficiency of v: missing adjacencies among alive neighbors
    # (double-counted; comparisons only). ops-charged per word touched.
    defv = u32[n]
    ops = 0
    i = 0
    while i < n
      vbase = i * words
      wi = 0
      while wi < words
        nb[wi] = adj[vbase + wi] & alive[wi]
        wi += 1
      miss = 0
      wi = 0
      while wi < words
        nw = nb[wi]
        while nw != 0
          u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
          ubase = u * words
          miss += ccall_nobox("__w_u32_andnot_count_raw", nb, 0, adj, ubase, words)
          ops += words
          miss -= 1
          nw = nw & (nw - 1)
        wi += 1
      defv[i] = miss
      i += 1
    # lazy min-heap of (key, vertex) with per-vertex versions
    hcap = n * 4 + 16
    hkey = u32[hcap]
    hv = u32[hcap]
    hver = u32[hcap]
    version = u32[n]
    hsize = 0
    i = 0
    while i < n
      hkey[hsize] = defv[i]
      hv[hsize] = i
      hver[hsize] = 0
      hsize += 1
      j = hsize - 1
      while j > 0
        pj = (j - 1) >> 1
        break if hkey[pj] <= hkey[j]
        tk = hkey[pj]
        hkey[pj] = hkey[j]
        hkey[j] = tk
        tk = hv[pj]
        hv[pj] = hv[j]
        hv[j] = tk
        tk = hver[pj]
        hver[pj] = hver[j]
        hver[j] = tk
        j = pj
      i += 1
    order = []
    alive_cnt = n
    degraded = 0 == 1
    while alive_cnt > 0
      break if ops > work_budget
      # pop the exact minimum-deficiency vertex (validating lazily),
      # collecting the tie set
      me = none
      mekey = 0
      while hsize > 0
        topv = hv[0]
        topk = hkey[0]
        topver = hver[0]
        # remove root
        hsize -= 1
        hkey[0] = hkey[hsize]
        hv[0] = hv[hsize]
        hver[0] = hver[hsize]
        j = 0
        while 0 == 0
          l2 = j * 2 + 1
          r3 = j * 2 + 2
          sm2 = j
          sm2 = l2 if l2 < hsize && hkey[l2] < hkey[sm2]
          sm2 = r3 if r3 < hsize && hkey[r3] < hkey[sm2]
          break if sm2 == j
          tk = hkey[sm2]
          hkey[sm2] = hkey[j]
          hkey[j] = tk
          tk = hv[sm2]
          hv[sm2] = hv[j]
          hv[j] = tk
          tk = hver[sm2]
          hver[sm2] = hver[j]
          hver[j] = tk
          j = sm2
        next if topver != version[topv]
        next if (alive[topv >> 5] & (1 << (topv & 31))) == 0
        # validate: recompute if the stored key is optimistic
        if topk != defv[topv]
          truek = defv[topv]
          # re-push with the exact key
          hkey[hsize] = truek
          hv[hsize] = topv
          hver[hsize] = version[topv]
          hsize += 1
          j = hsize - 1
          while j > 0
            pj = (j - 1) >> 1
            break if hkey[pj] <= hkey[j]
            tk = hkey[pj]
            hkey[pj] = hkey[j]
            hkey[j] = tk
            tk = hv[pj]
            hv[pj] = hv[j]
            hv[j] = tk
            tk = hver[pj]
            hver[pj] = hver[j]
            hver[j] = tk
            j = pj
          next
        me = topv
        mekey = topk
        break
      break if me == none
      # corrector among the tie set: pop every entry tied at mekey, pick
      # the candidate minimizing the induced Δ Σ(deg+1)² (ties: degree,
      # then index); re-push the losers
      tied = [me]
      while hsize > 0 && hkey[0] == mekey && tied.size < 12
        tv = hv[0]
        tver = hver[0]
        hsize -= 1
        hkey[0] = hkey[hsize]
        hv[0] = hv[hsize]
        hver[0] = hver[hsize]
        j = 0
        while 0 == 0
          l2 = j * 2 + 1
          r3 = j * 2 + 2
          sm2 = j
          sm2 = l2 if l2 < hsize && hkey[l2] < hkey[sm2]
          sm2 = r3 if r3 < hsize && hkey[r3] < hkey[sm2]
          break if sm2 == j
          tk = hkey[sm2]
          hkey[sm2] = hkey[j]
          hkey[j] = tk
          tk = hv[sm2]
          hv[sm2] = hv[j]
          hv[j] = tk
          tk = hver[sm2]
          hver[sm2] = hver[j]
          hver[j] = tk
          j = sm2
        if tver == version[tv] && (alive[tv >> 5] & (1 << (tv & 31))) != 0 && defv[tv] == mekey
          tied.push(tv)
      if ops > work_budget
        degraded = 0 == 0
        # push the popped candidates back before degrading
        # (the AMD tail reads only alive/adj, so the heap state no
        # longer matters; just stop)
        break
      if tied.size > 1
        bestc = none
        bestcor = none
        bestdeg = none
        t3 = 0
        while t3 < tied.size
          v3 = tied[t3]
          vbase = v3 * words
          wi = 0
          while wi < words
            nb[wi] = adj[vbase + wi] & alive[wi]
            wi += 1
          cor = 0
          wi = 0
          while wi < words
            nw = nb[wi]
            while nw != 0
              u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
              ubase = u * words
              addu = ccall_nobox("__w_u32_andnot_count_raw", nb, 0, adj, ubase, words) - 1
              ops += words
              du = deg[u]
              cor += (du + addu) * (du + addu) - (du + 1) * (du + 1)
              nw = nw & (nw - 1)
            wi += 1
          better = 0 == 1
          better = 0 == 0 if bestcor == none
          better = 0 == 0 if bestcor != none && cor < bestcor
          if bestcor != none && cor == bestcor
            better = 0 == 0 if deg[v3] < bestdeg || (deg[v3] == bestdeg && v3 < bestc)
          if better
            bestc = v3
            bestcor = cor
            bestdeg = deg[v3]
          t3 += 1
        # re-push the losers
        t3 = 0
        while t3 < tied.size
          v3 = tied[t3]
          if v3 != bestc
            hkey[hsize] = defv[v3]
            hv[hsize] = v3
            hver[hsize] = version[v3]
            hsize += 1
            j = hsize - 1
            while j > 0
              pj = (j - 1) >> 1
              break if hkey[pj] <= hkey[j]
              tk = hkey[pj]
              hkey[pj] = hkey[j]
              hkey[j] = tk
              tk = hv[pj]
              hv[pj] = hv[j]
              hv[j] = tk
              tk = hver[pj]
              hver[pj] = hver[j]
              hver[j] = tk
              j = pj
          t3 += 1
        me = bestc
      # dense-pivot degradation gate
      if deg[me] > 96
        degraded = 0 == 0
        break
      # eliminate me on the bitsets
      order.push(me)
      alive[me >> 5] = alive[me >> 5] ^ (1 << (me & 31))
      alive_cnt -= 1
      vbase = me * words
      nbcnt = 0
      wi = 0
      while wi < words
        nw = adj[vbase + wi] & alive[wi]
        nb[wi] = nw
        while nw != 0
          nbrs[nbcnt] = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
          nbcnt += 1
          nw = nw & (nw - 1)
        wi += 1
      ops += words
      addtot = 0
      t = 0
      while t < nbcnt
        u = nbrs[t]
        ubase = u * words
        added = 0
        wi = 0
        while wi < words
          aw = nb[wi] & (adj[ubase + wi] ^ full)
          if aw != 0
            adj[ubase + wi] = adj[ubase + wi] | aw
            added += ccall_nobox("__w_bit_ctpop_u32", aw)
          wi += 1
        ops += words
        uw = ubase + (u >> 5)
        ubit = 1 << (u & 31)
        if (adj[uw] & ubit) != 0
          adj[uw] = adj[uw] ^ ubit
          added -= 1
        deg[u] = deg[u] - 1 + added
        addtot += added
        t += 1
      # exact deficiency refresh for N(me); optimistic decrement for the
      # second ring (their deficiency can only fall, by at most the
      # total fill added here)
      halfadd = addtot >> 1
      t = 0
      while t < nbcnt
        u = nbrs[t]
        ubase = u * words
        wi = 0
        while wi < words
          nb[wi] = adj[ubase + wi] & alive[wi]
          wi += 1
        miss = 0
        wi = 0
        while wi < words
          nw = nb[wi]
          while nw != 0
            u2 = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
            u2base = u2 * words
            miss += ccall_nobox("__w_u32_andnot_count_raw", nb, 0, adj, u2base, words)
            ops += words
            miss -= 1
            # second ring: optimistic lower key
            if version[u2] < 4294967290 && defv[u2] > 0
              nk = 0
              nk = defv[u2] - halfadd - halfadd if defv[u2] > halfadd + halfadd
              if nk < defv[u2]
                version[u2] = version[u2] + 1
                hkey[hsize] = nk
                hv[hsize] = u2
                hver[hsize] = version[u2]
                hsize += 1
                if hsize >= hcap
                  # grow the heap arrays
                  ncap = hcap * 2
                  nhk = u32[ncap]
                  nhv = u32[ncap]
                  nhr = u32[ncap]
                  q2 = 0
                  while q2 < hsize
                    nhk[q2] = hkey[q2]
                    nhv[q2] = hv[q2]
                    nhr[q2] = hver[q2]
                    q2 += 1
                  hkey = nhk
                  hv = nhv
                  hver = nhr
                  hcap = ncap
                j = hsize - 1
                while j > 0
                  pj = (j - 1) >> 1
                  break if hkey[pj] <= hkey[j]
                  tk = hkey[pj]
                  hkey[pj] = hkey[j]
                  hkey[j] = tk
                  tk = hv[pj]
                  hv[pj] = hv[j]
                  hv[j] = tk
                  tk = hver[pj]
                  hver[pj] = hver[j]
                  hver[j] = tk
                  j = pj
            nw = nw & (nw - 1)
          wi += 1
        defv[u] = miss
        version[u] = version[u] + 1
        hkey[hsize] = miss
        hv[hsize] = u
        hver[hsize] = version[u]
        hsize += 1
        if hsize >= hcap
          ncap = hcap * 2
          nhk = u32[ncap]
          nhv = u32[ncap]
          nhr = u32[ncap]
          q2 = 0
          while q2 < hsize
            nhk[q2] = hkey[q2]
            nhv[q2] = hv[q2]
            nhr[q2] = hver[q2]
            q2 += 1
          hkey = nhk
          hv = nhv
          hver = nhr
          hcap = ncap
        j = hsize - 1
        while j > 0
          pj = (j - 1) >> 1
          break if hkey[pj] <= hkey[j]
          tk = hkey[pj]
          hkey[pj] = hkey[j]
          hkey[j] = tk
          tk = hv[pj]
          hv[pj] = hv[j]
          hv[j] = tk
          tk = hver[pj]
          hver[pj] = hver[j]
          hver[j] = tk
          j = pj
        t += 1
    # AMD tail on the (filled) remainder
    if alive_cnt > 0
      rid = u32[n]
      rvs = u32[alive_cnt]
      rp = 0
      wi = 0
      while wi < words
        aw = alive[wi]
        while aw != 0
          u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", aw)
          rid[u] = rp
          rvs[rp] = u
          rp += 1
          aw = aw & (aw - 1)
        wi += 1
      tri = []
      tci = []
      i = 0
      while i < alive_cnt
        v = rvs[i]
        vbase = v * words
        wi = 0
        while wi < words
          aw = adj[vbase + wi] & alive[wi]
          while aw != 0
            u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", aw)
            if u < v
              tri.push(rid[v])
              tci.push(rid[u])
            aw = aw & (aw - 1)
          wi += 1
        i += 1
      sub = amd_core(alive_cnt, tri, tci, tri.size)
      i = 0
      while i < alive_cnt
        order.push(rvs[sub[i]])
        i += 1
    order

  -> min_degree_ordering_heap
    n = @pattern.rows
    adj = []
    ensure_symmetric_adjacency
    @symmetric_adj.each -> (row)
      set = {}
      row.each -> (u)
        set[u] = true
      adj.push(set)
    alive = []
    degree = []
    heap_d = []
    heap_v = []
    i = 0
    while i < n
      alive.push(true)
      d = adj[i].size
      degree.push(d)
      SparseAnalysis.md_heap_push(heap_d, heap_v, d, i)
      i += 1
    order = []
    step = 0
    while step < n
      best = -1
      while best == -1
        candidate_d = heap_d[0]
        candidate_v = heap_v[0]
        last_d = heap_d.pop
        last_v = heap_v.pop
        if heap_d.size > 0
          pos = 0
          heap_d[0] = last_d
          heap_v[0] = last_v
          moving = true
          while moving
            left = pos * 2 + 1
            if left >= heap_d.size
              moving = false
            else
              right = left + 1
              child = left
              if right < heap_d.size && SparseAnalysis.md_heap_less?(heap_d[right], heap_v[right], heap_d[left], heap_v[left])
                child = right
              if SparseAnalysis.md_heap_less?(heap_d[child], heap_v[child], heap_d[pos], heap_v[pos])
                td = heap_d[pos]
                tv = heap_v[pos]
                heap_d[pos] = heap_d[child]
                heap_v[pos] = heap_v[child]
                heap_d[child] = td
                heap_v[child] = tv
                pos = child
              else
                moving = false
        if alive[candidate_v] && degree[candidate_v] == candidate_d
          best = candidate_v
      order.push(best)
      alive[best] = false
      neighbors = []
      adj[best].each_pair -> (u, flag)
        neighbors.push(u) if alive[u]
      neighbors = neighbors.sort
      a = 0
      while a < neighbors.size
        u = neighbors[a]
        adj[u].delete(best)
        b = a + 1
        while b < neighbors.size
          w = neighbors[b]
          if adj[u][w] == nil
            adj[u][w] = true
            adj[w][u] = true
          b += 1
        a += 1
      a = 0
      while a < neighbors.size
        u = neighbors[a]
        degree[u] = adj[u].size
        SparseAnalysis.md_heap_push(heap_d, heap_v, degree[u], u)
        a += 1
      step += 1
    order
