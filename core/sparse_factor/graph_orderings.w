+ SparseAnalysis
  # Randomized-greedy elimination-game ILS (rgreedy): play the EXACT
  # game with the pivot drawn uniformly from {v : deg(v) <= dmin+slack}
  # over a ladder of slacks, replaying a frozen prefix of the incumbent
  # and re-randomizing the suffix. The objective is free — the column
  # count charged when v is eliminated is exactly deg(v)+1, so Σc²
  # accumulates during play and a run aborts the moment it can no
  # longer beat the incumbent. Sideways moves (equal cost) are accepted
  # to walk plateaus; the strict best is tracked separately. `budget`
  # caps total bitset word-operations. `nelim` optionally freezes vertices
  # nelim...nn-1 as read-only boundary terminals: they participate in degree
  # and fill updates but can never be chosen as pivots. This lets subtree
  # search model its active separator without moving outside vertices.
  # Returns [best_order, best_flops].
  -> rgreedy_refine(nn, ri, ci, m, seed_order, seed_flops, budget, stream = 0)
    # stream packs the schedule id in its high bits: sched = stream >> 10
    sched = stream >> 10
    stream = stream & 1023
    n = nn
    target = @rgreedy_nelim
    target = 0 if target == nil
    target = n if target <= 0 || target > n
    partial = target < n
    words = (n + 31) >> 5
    bitmap_words = n * words
    full = 4294967295
    none = 4294967295
    adj0 = u32[bitmap_words]
    k = 0
    while k < m
      r = ri[k]
      c = ci[k]
      if r != c
        adj0[r * words + (c >> 5)] = adj0[r * words + (c >> 5)] | (1 << (c & 31))
        adj0[c * words + (r >> 5)] = adj0[c * words + (r >> 5)] | (1 << (r & 31))
      k += 1
    deg0 = u32[n]
    e0 = 0
    i = 0
    while i < n
      d = 0
      base = i * words
      wi = 0
      while wi < words
        d += ccall_nobox("__w_bit_ctpop_u32", adj0[base + wi])
        wi += 1
      deg0[i] = d
      e0 += d
      i += 1
    e0 = e0 >> 1
    adj = u32[bitmap_words]
    deg = u32[n]
    cnt = u32[n + 1]
    head = u32[n + 1]
    dnext = u32[n]
    dlast = u32[n]
    alive = u32[words]
    nb = u32[words]
    nbrs = u32[n]
    cur = u32[n]
    cand = u32[n]
    bestb = u32[n]
    # checkpoint of the whole game state at the frozen-prefix position,
    # so several randomized suffixes share one prefix replay
    kadj = u32[bitmap_words]
    kdeg = u32[n]
    kcnt = u32[n + 1]
    khead = u32[n + 1]
    kdnext = u32[n]
    kdlast = u32[n]
    kalive = u32[words]
    i = 0
    while i < n
      cur[i] = seed_order[i]
      bestb[i] = seed_order[i]
      i += 1
    cur_f = seed_flops
    best_f = seed_flops
    ops = 0
    state = (88172645 + stream * 97531) % 2147483646 + 1
    iter = 0
    ckpt_pos = none
    ckpt_f = 0
    while ops < budget
      # per-iteration bookkeeping charge: list resets, pivot-loop
      # overheads and RNG are real cost the word counters miss — on a
      # tiny post-core-lift graph they dominate, and without this charge
      # a word budget balloons into wall time
      ops += n * 12 + 2048
      slack = 0
      sm = iter % 8
      if sched == 1
        # dense-block schedule: minimum-deficiency search dominates,
        # with wide windows — the basin on pooling-class rows is
        # fill-metric-shaped, not degree-shaped
        mdf = sm != 3 && sm != 7
        slack = 4
        slack = 8 if sm == 1 || sm == 5
        slack = 16 if sm == 2 || sm == 6
        slack = 2 if sm == 3
        slack = 8 if sm == 7
      else
        slack = 1 if sm == 1
        slack = 2 if sm == 2
        slack = 3 if sm == 3
        slack = 5 if sm == 4
        slack = 8 if sm == 5
        slack = 16 if sm == 6
        slack = 8 if sm == 7
        mdf = sm == 7
      if iter % 6 == 0 || ckpt_pos == none
        # build a fresh checkpoint: reset, replay a prefix of the
        # incumbent verbatim, snapshot
        state = (state * 48271) % 2147483647
        prefix = 0
        prefix = (state % target) if iter % 18 >= 6
        ccall_nobox(
          "__w_u32_copy_raw", adj, 0, adj0, 0, bitmap_words ## i64)
        ops += bitmap_words
        i = 0
        while i < n + 1
          cnt[i] = 0
          head[i] = none
          i += 1
        i = 0
        while i < n
          d = deg0[i]
          deg[i] = d
          if i < target
            cnt[d] = cnt[d] + 1
            dnext[i] = head[d]
            dlast[i] = none
            dlast[head[d]] = i if head[d] != none
            head[d] = i
          i += 1
        i = 0
        while i < words
          alive[i] = full
          i += 1
        tail = n & 31
        alive[words - 1] = (1 << tail) - 1 if tail != 0
        f = 0
        ecur = e0
        kstep = 0
        while kstep < prefix
          v = cur[kstep]
          c = deg[v] + 1
          f += c * c
          cand[kstep] = v
          ecur -= deg[v]
          addsum = 0
          dn = dnext[v]
          dl = dlast[v]
          if dl == none
            head[deg[v]] = dn
          else
            dnext[dl] = dn
          dlast[dn] = dl if dn != none
          cnt[deg[v]] = cnt[deg[v]] - 1
          alive[v >> 5] = alive[v >> 5] ^ (1 << (v & 31))
          vbase = v * words
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
          alive_cnt = n - kstep - 1
          t = 0
          while t < nbcnt
            u = nbrs[t]
            old_d = deg[u]
            if old_d == alive_cnt
              newdeg = old_d - 1
            else
              ubase = u * words
              added = ccall_nobox("__w_u32_merge_count_raw", adj, ubase, nb, 0, words)
              ops += words
              uw = ubase + (u >> 5)
              ubit = 1 << (u & 31)
              if (adj[uw] & ubit) != 0
                adj[uw] = adj[uw] ^ ubit
                added -= 1
              newdeg = old_d - 1 + added
              addsum += added
            deg[u] = newdeg
            if u < target
              dn = dnext[u]
              dl = dlast[u]
              if dl == none
                head[old_d] = dn
              else
                dnext[dl] = dn
              dlast[dn] = dl if dn != none
              cnt[old_d] = cnt[old_d] - 1
              cnt[newdeg] = cnt[newdeg] + 1
              dnext[u] = head[newdeg]
              dlast[u] = none
              dlast[head[newdeg]] = u if head[newdeg] != none
              head[newdeg] = u
            t += 1
          ecur += addsum >> 1
          kstep += 1
        # snapshot
        ccall_nobox(
          "__w_u32_copy_raw", kadj, 0, adj, 0, bitmap_words ## i64)
        ops += bitmap_words
        i = 0
        while i < n
          kdeg[i] = deg[i]
          kdnext[i] = dnext[i]
          kdlast[i] = dlast[i]
          i += 1
        i = 0
        while i < n + 1
          kcnt[i] = cnt[i]
          khead[i] = head[i]
          i += 1
        i = 0
        while i < words
          kalive[i] = alive[i]
          i += 1
        ckpt_pos = prefix
        ckpt_f = f
        ckpt_e = ecur
      else
        # restore the shared checkpoint — no replay work
        ccall_nobox(
          "__w_u32_copy_raw", adj, 0, kadj, 0, bitmap_words ## i64)
        ops += bitmap_words
        i = 0
        while i < n
          deg[i] = kdeg[i]
          dnext[i] = kdnext[i]
          dlast[i] = kdlast[i]
          i += 1
        i = 0
        while i < n + 1
          cnt[i] = kcnt[i]
          head[i] = khead[i]
          i += 1
        i = 0
        while i < words
          alive[i] = kalive[i]
          i += 1
        f = ckpt_f
        ecur = ckpt_e
        kstep = ckpt_pos
      # randomized suffix
      mindeg = 0
      dead = 0 == 1
      while kstep < target
        while cnt[mindeg] == 0
          mindeg += 1
        rem = n - kstep
        if !partial && mindeg == rem - 1
          # the alive graph is a clique: any completion costs exactly
          # Σ k² for k = 1..rem — finish in closed form
          f += rem * (rem + 1) * (2 * rem + 1) / 6
          if f > cur_f
            dead = 0 == 0
          else
            wi = 0
            while wi < words
              aw = alive[wi]
              while aw != 0
                cand[kstep] = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", aw)
                kstep += 1
                aw = aw & (aw - 1)
              wi += 1
          break
        kk = cnt[mindeg]
        d = mindeg + 1
        while d <= mindeg + slack && d <= n
          kk += cnt[d]
          d += 1
        state = (state * 48271) % 2147483647
        pick = state % kk
        d = mindeg
        while pick >= cnt[d]
          pick -= cnt[d]
          d += 1
        v = head[d]
        while pick > 0
          v = dnext[v]
          pick -= 1
          ops += 1
        if mdf
          # min-deficiency among sampled window candidates: exact new-fill
          # of eliminating the candidate, counted on the bitset rows
          tries = 8
          tries = kk if kk < 8
          bestv = v
          bestdef = none
          t2 = 0
          while t2 < tries
            if t2 > 0
              state = (state * 48271) % 2147483647
              pick = state % kk
              d = mindeg
              while pick >= cnt[d]
                pick -= cnt[d]
                d += 1
              v = head[d]
              while pick > 0
                v = dnext[v]
                pick -= 1
                ops += 1
            vbase = v * words
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
            if miss < bestdef
              bestdef = miss
              bestv = v
            t2 += 1
          v = bestv
        c = deg[v] + 1
        f += c * c
        r2 = target - kstep - 1
        if f + r2 > cur_f
          dead = 0 == 0
          break
        if r2 > 0 && !partial
          # every surviving edge lands in L: Σc ≥ r + E, so Σc² ≥ (r+E)²/r;
          # floor((q/r)·q) is a weaker but integer-only lower bound
          q = r2 + ecur - deg[v]
          if q < 8000000 && f + (q * q) / r2 > cur_f
            dead = 0 == 0
            break
          if q >= 8000000 && f + (q / r2) * q > cur_f
            dead = 0 == 0
            break
        cand[kstep] = v
        ecur -= deg[v]
        addsum = 0
        dn = dnext[v]
        dl = dlast[v]
        if dl == none
          head[deg[v]] = dn
        else
          dnext[dl] = dn
        dlast[dn] = dl if dn != none
        cnt[deg[v]] = cnt[deg[v]] - 1
        alive[v >> 5] = alive[v >> 5] ^ (1 << (v & 31))
        vbase = v * words
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
        alive_cnt = n - kstep - 1
        t = 0
        while t < nbcnt
          u = nbrs[t]
          old_d = deg[u]
          if old_d == alive_cnt
            newdeg = old_d - 1
          else
            ubase = u * words
            added = ccall_nobox("__w_u32_merge_count_raw", adj, ubase, nb, 0, words)
            ops += words
            uw = ubase + (u >> 5)
            sbit = (adj[uw] >> (u & 31)) & 1
            adj[uw] = adj[uw] ^ (sbit << (u & 31))
            added -= sbit
            newdeg = old_d - 1 + added
            addsum += added
          deg[u] = newdeg
          if u < target
            dn = dnext[u]
            dl = dlast[u]
            if dl == none
              head[old_d] = dn
            else
              dnext[dl] = dn
            dlast[dn] = dl if dn != none
            cnt[old_d] = cnt[old_d] - 1
            cnt[newdeg] = cnt[newdeg] + 1
            dnext[u] = head[newdeg]
            dlast[u] = none
            dlast[head[newdeg]] = u if head[newdeg] != none
            head[newdeg] = u
            mindeg = newdeg if newdeg < mindeg
          t += 1
        ecur += addsum >> 1
        kstep += 1
        # sudoku-style propagation: any neighbor left simplicial
        # (deficiency 0 — its live neighborhood is a clique) is a forced
        # move; eliminate it now, and let the deduction cascade
        qi2 = 0
        while qi2 < nbcnt && kstep < target
          u = nbrs[qi2]
          qi2 += 1
          next if (alive[u >> 5] & (1 << (u & 31))) == 0
          next if u >= target
          du = deg[u]
          next if du + 1 >= n - kstep && n - kstep > 1
          # deficiency test: every pair of u's live neighbors adjacent?
          ubase2 = u * words
          wi = 0
          while wi < words
            nb[wi] = adj[ubase2 + wi] & alive[wi]
            wi += 1
          simp = 0 == 0
          wi = 0
          while wi < words && simp
            nw = nb[wi]
            while nw != 0
              u2 = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
              u2b = u2 * words
              # nb is one complete u32 row, u2b addresses a complete adj row,
              # and live u2 < n <= words*32, proving the trusted ABI contract.
              simp = ccall_nobox(
                "__w_u32_subset_except_trusted_raw", nb, 0, adj,
                u2b ## i64, words ## i64, u2 ## i64) != 0
              ops += words
              break if !simp
              nw = nw & (nw - 1)
            wi += 1
          if simp
            c = du + 1
            f += c * c
            if f + (target - kstep - 1) > cur_f
              dead = 0 == 0
              kstep = target
            else
              cand[kstep] = u
              ecur -= du
              dn = dnext[u]
              dl = dlast[u]
              if dl == none
                head[du] = dn
              else
                dnext[dl] = dn
              dlast[dn] = dl if dn != none
              cnt[du] = cnt[du] - 1
              alive[u >> 5] = alive[u >> 5] ^ (1 << (u & 31))
              kstep += 1
              # neighbors of u lose one degree (no fill: u was simplicial)
              wi = 0
              while wi < words
                nw = nb[wi]
                while nw != 0
                  u3 = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
                  od3 = deg[u3]
                  deg[u3] = od3 - 1
                  if u3 < target
                    dn = dnext[u3]
                    dl = dlast[u3]
                    if dl == none
                      head[od3] = dn
                    else
                      dnext[dl] = dn
                    dlast[dn] = dl if dn != none
                    cnt[od3] = cnt[od3] - 1
                    cnt[od3 - 1] = cnt[od3 - 1] + 1
                    dnext[u3] = head[od3 - 1]
                    dlast[u3] = none
                    dlast[head[od3 - 1]] = u3 if head[od3 - 1] != none
                    head[od3 - 1] = u3
                    mindeg = od3 - 1 if od3 - 1 < mindeg
                  nw = nw & (nw - 1)
                wi += 1
      if !dead && f <= cur_f
        i = 0
        while i < target
          cur[i] = cand[i]
          i += 1
        if f < best_f
          best_f = f
          i = 0
          while i < target
            bestb[i] = cand[i]
            i += 1
        cur_f = f
        ckpt_pos = none
      iter += 1
    out = []
    i = 0
    while i < n
      out.push(bestb[i])
      i += 1
    [out, best_f]

  # Eight-argument dynamic-dispatch wrapper (the runtime method ABI caps
  # calls at eight arguments). The private worker analysis is thread-local,
  # so the temporary terminal count cannot race another search.
  -> rgreedy_prefix_refine(nn, ri, ci, m, seed_order, seed_flops, budget, control)
    old_target = @rgreedy_nelim
    @rgreedy_nelim = control[1]
    result = rgreedy_refine(
      nn, ri, ci, m, seed_order, seed_flops, budget, control[0])
    @rgreedy_nelim = old_target
    prefix = []
    i = 0
    while i < control[1]
      prefix.push(result[0][i])
      i += 1
    [prefix, result[1]]

  # Level-set nested dissection: the George–Liu variant — separator =
  # the thinnest balanced BFS level of a pseudo-peripheral root. Its
  # cuts are fatter than refined multilevel cuts but geometrically clean
  # (level bands), which keeps the recursive subproblems well-shaped;
  # on grid-like patterns this beats both AMD and the multilevel arm.
  # Kept alongside nd_ordering_of as a second exact-gated candidate.
  -> nd_levelset_of(nn, ri, ci, m)
    none = 4294967295
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
    bcap = nn * 4 + 64
    buf = u32[bcap]
    i = 0
    while i < nn
      buf[i] = i
      i += 1
    bcur = nn
    level = u32[nn]
    inset = u32[nn]
    side = u32[nn]
    bfsq = u32[nn]
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
        gen += 1
        i = 0
        while i < slen
          inset[buf[start + i]] = gen
          i += 1
        root = buf[start]
        qh = 0
        qt = 0
        bfsq[qt] = root
        qt += 1
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
          comp_start = bcur
          if bcur + slen + slen > bcap
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
          gen += 1
          i = 0
          while i < slen
            inset[buf[start + i]] = gen
            i += 1
          qh = 0
          qt = 0
          bfsq[qt] = far
          qt += 1
          side[far] = gen
          level[far] = 0
          h = 0
          while qh < qt
            v = bfsq[qh]
            qh += 1
            h = level[v] if level[v] > h
            p = ptr[v]
            stop = p + rows[v]
            while p < stop
              u = idx[p]
              if inset[u] == gen && side[u] != gen
                side[u] = gen
                level[u] = level[v] + 1
                bfsq[qt] = u
                qt += 1
              p += 1
          if h < 3
            solve_leaf = 0 == 0
          else
            lcount = u32[h + 1]
            i = 0
            while i < slen
              lcount[level[buf[start + i]]] = lcount[level[buf[start + i]]] + 1
              i += 1
            quarter = slen >> 2
            best_t = none
            best_sz = none
            below = lcount[0]
            t = 1
            while t < h
              above = slen - below - lcount[t]
              if below >= quarter && above >= quarter && lcount[t] < best_sz
                best_sz = lcount[t]
                best_t = t
              below += lcount[t]
              t += 1
            if best_t == none
              solve_leaf = 0 == 0
            else
              i = 0
              while i < slen
                v = buf[start + i]
                lv = level[v]
                side[v] = 1
                side[v] = 2 if lv == best_t
                side[v] = 3 if lv > best_t
                i += 1
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
                solve_leaf = 0 == 0
                bcur = a_start
              else
                stack.push([1, s_start, s_len]) if s_len > 0
                stack.push([0, b_start, s_start - b_start])
                stack.push([0, a_start, b_start - a_start])
      if solve_leaf
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

  # BFS scratch shared by RCM and Sloan.  Distances are one-based so zero is
  # the unvisited sentinel.  The queue is also the touched list: resetting its
  # entries before return leaves `dist` ready for the next component without
  # an O(n) clear.  Among the deepest-level vertices choose the first
  # minimum-degree vertex in deterministic BFS order, matching the reference
  # implementation's stable traversal semantics.
  -> .bfs_deepest(adj, degree, dist, queue, start)
    qh = 0
    qt = 1
    queue[0] = start
    dist[start] = 1
    max_d = 1
    while qh < qt
      u = queue[qh]
      qh += 1
      du = dist[u]
      max_d = du if du > max_d
      row = adj[u]
      p = 0
      while p < row.size
        v = row[p]
        if dist[v] == 0
          dist[v] = du + 1
          queue[qt] = v
          qt += 1
        p += 1
    best = start
    best_deg = 4294967295
    i = 0
    while i < qt
      u = queue[i]
      if dist[u] == max_d && degree[u] < best_deg
        best = u
        best_deg = degree[u]
      dist[u] = 0
      i += 1
    [best, max_d - 1]

  # George-Liu pseudo-peripheral refinement: jump to a minimum-degree vertex
  # on the deepest BFS level while eccentricity grows, with the same fixed
  # five-pass ceiling used by the challenge implementation.
  -> .pseudo_peripheral(adj, degree, dist, queue, seed)
    start = seed
    prev_ecc = 0
    pass = 0
    while pass < 5
      deep = SparseAnalysis.bfs_deepest(adj, degree, dist, queue, start)
      break if deep[1] <= prev_ecc
      prev_ecc = deep[1]
      start = deep[0]
      pass += 1
    start

  # Reverse Cuthill-McKee bandwidth/profile candidate.  Each connected
  # component starts from a pseudo-peripheral vertex, visits each BFS frontier
  # by ascending (degree, index), and the complete CM order is reversed.  The
  # graph cache is read-only; all traversal state is compact per-call scratch.
  -> rcm_ordering
    n = @pattern.rows
    return [] if n == 0
    ensure_symmetric_adjacency
    adj = @symmetric_adj
    degree = u32[n]
    visited = u32[n]
    dist = u32[n]
    queue = u32[n]
    i = 0
    while i < n
      degree[i] = adj[i].size
      i += 1
    order = []
    seed = 0
    while seed < n
      if visited[seed] == 0
        start = seed
        if degree[seed] != 0
          start = SparseAnalysis.pseudo_peripheral(
            adj, degree, dist, queue, seed)
        qh = 0
        qt = 1
        queue[0] = start
        visited[start] = 1
        order.push(start)
        while qh < qt
          u = queue[qh]
          qh += 1
          nbrs = []
          row = adj[u]
          p = 0
          while p < row.size
            v = row[p]
            nbrs.push(v) if visited[v] == 0
            p += 1
          # The combined key gives the stable Rust sort_by_key semantics even
          # if Array#sort_by itself changes stability: index is the fixed tie.
          nbrs = nbrs.sort_by -> (v) degree[v] * (n + 1) + v
          p = 0
          while p < nbrs.size
            v = nbrs[p]
            if visited[v] == 0
              visited[v] = 1
              order.push(v)
              queue[qt] = v
              qt += 1
            p += 1
      seed += 1
    order.reverse

  -> .sloan_heap_better?(ap, av, bp, bv)
    ap > bp || (ap == bp && av > bv)

  # Max-heap keyed by (priority, vertex), matching Rust BinaryHeap's tuple
  # order.  Sloan priorities only increase, so lazy stale-entry rejection is
  # sufficient and avoids decrease/increase-key bookkeeping.
  -> .sloan_heap_push(heap_p, heap_v, priority, vertex)
    i = heap_p.size
    heap_p.push(priority)
    heap_v.push(vertex)
    while i > 0
      parent = (i - 1) / 2
      break if !SparseAnalysis.sloan_heap_better?(
        priority, vertex, heap_p[parent], heap_v[parent])
      heap_p[i] = heap_p[parent]
      heap_v[i] = heap_v[parent]
      i = parent
    heap_p[i] = priority
    heap_v[i] = vertex
    nil

  # Sloan wavefront/profile candidate.  For each connected component, form a
  # pseudo-peripheral endpoint pair, initialize
  #   w1 * distance-to-end - w2 * (degree + 1),
  # then promote vertices through inactive/preactive/active/postactive while
  # incrementally raising affected priorities.  The two classic weightings
  # are exposed through the arguments (2,1 and 1,2).
  -> sloan_ordering(w1 = 2, w2 = 1)
    n = @pattern.rows
    return [] if n == 0
    ensure_symmetric_adjacency
    adj = @symmetric_adj
    degree = u32[n]
    status = u32[n]
    priority = i64[n]
    dist = u32[n]
    queue = u32[n]
    i = 0
    while i < n
      degree[i] = adj[i].size
      i += 1
    order = []
    heap_p = []
    heap_v = []
    seed = 0
    while seed < n
      if status[seed] != 3
        start = seed
        if degree[seed] != 0
          start = SparseAnalysis.pseudo_peripheral(
            adj, degree, dist, queue, seed)
        deepest = SparseAnalysis.bfs_deepest(
          adj, degree, dist, queue, start)
        endpoint = deepest[0]

        # BFS from the far endpoint both collects this component and records
        # its distance-to-end.  Queue contents remain valid while dist is read.
        qh = 0
        qt = 1
        queue[0] = endpoint
        dist[endpoint] = 1
        while qh < qt
          u = queue[qh]
          qh += 1
          row = adj[u]
          p = 0
          while p < row.size
            v = row[p]
            if dist[v] == 0
              dist[v] = dist[u] + 1
              queue[qt] = v
              qt += 1
            p += 1
        i = 0
        while i < qt
          u = queue[i]
          priority[u] = w1 * (dist[u] - 1) - w2 * (degree[u] + 1)
          status[u] = 0
          dist[u] = 0
          i += 1

        status[start] = 1
        SparseAnalysis.sloan_heap_push(
          heap_p, heap_v, priority[start], start)
        while heap_p.size > 0
          cand_p = heap_p[0]
          cand_v = heap_v[0]
          last_p = heap_p.pop
          last_v = heap_v.pop
          if heap_p.size > 0
            heap_p[0] = last_p
            heap_v[0] = last_v
            pos = 0
            moving = 0 == 0
            while moving
              left = pos * 2 + 1
              if left >= heap_p.size
                moving = 0 == 1
              else
                right = left + 1
                child = left
                if right < heap_p.size && SparseAnalysis.sloan_heap_better?(
                     heap_p[right], heap_v[right], heap_p[left], heap_v[left])
                  child = right
                if SparseAnalysis.sloan_heap_better?(
                     heap_p[child], heap_v[child], heap_p[pos], heap_v[pos])
                  tp = heap_p[pos]
                  tv = heap_v[pos]
                  heap_p[pos] = heap_p[child]
                  heap_v[pos] = heap_v[child]
                  heap_p[child] = tp
                  heap_v[child] = tv
                  pos = child
                else
                  moving = 0 == 1

          next if status[cand_v] == 3 || cand_p != priority[cand_v]
          if status[cand_v] == 1
            row = adj[cand_v]
            p = 0
            while p < row.size
              v = row[p]
              priority[v] = priority[v] + w2
              if status[v] == 0
                status[v] = 1
                SparseAnalysis.sloan_heap_push(
                  heap_p, heap_v, priority[v], v)
              elsif status[v] != 3
                SparseAnalysis.sloan_heap_push(
                  heap_p, heap_v, priority[v], v)
              p += 1

          order.push(cand_v)
          status[cand_v] = 3
          row = adj[cand_v]
          p = 0
          while p < row.size
            v = row[p]
            if status[v] == 1
              status[v] = 2
              priority[v] = priority[v] + w2
              SparseAnalysis.sloan_heap_push(
                heap_p, heap_v, priority[v], v)
              row2 = adj[v]
              q = 0
              while q < row2.size
                u = row2[q]
                if status[u] != 3
                  priority[u] = priority[u] + w2
                  status[u] = 1 if status[u] == 0
                  SparseAnalysis.sloan_heap_push(
                    heap_p, heap_v, priority[u], u)
                q += 1
            p += 1
      seed += 1
    order

  # Tarjan biconnected components as parallel edge lists.  The traversal is
  # iterative: sparse patterns can contain path-like components hundreds of
  # thousands of vertices deep, so using the language call stack here would
  # turn an otherwise linear preprocessing pass into a stack-overflow risk.
  # Sorted canonical adjacency and ascending DFS roots make component ids
  # deterministic.
  -> .biconnected_edge_components(adj)
    n = adj.size
    none = 4294967295
    disc = u32[n]
    low = u32[n]
    parent = u32[n]
    i = 0
    while i < n
      parent[i] = none
      i += 1
    edge_u = []
    edge_v = []
    comp_u = []
    comp_v = []
    stack_v = []
    stack_next = []
    time = 0
    start = 0
    while start < n
      if disc[start] == 0
        time += 1
        disc[start] = time
        low[start] = time
        stack_v.push(start)
        stack_next.push(0)
        while stack_v.size > 0
          top = stack_v.size - 1
          u = stack_v[top]
          slot = stack_next[top]
          row = adj[u]
          if slot < row.size
            v = row[slot]
            stack_next[top] = slot + 1
            if disc[v] == 0
              edge_u.push(u)
              edge_v.push(v)
              parent[v] = u
              time += 1
              disc[v] = time
              low[v] = time
              stack_v.push(v)
              stack_next.push(0)
            elsif v != parent[u] && disc[v] < disc[u]
              # Back edges are pushed only from descendant to ancestor, so
              # every undirected edge appears once on the edge stack.
              edge_u.push(u)
              edge_v.push(v)
              low[u] = disc[v] if disc[v] < low[u]
          else
            stack_v.pop
            stack_next.pop
            p = parent[u]
            if p != none
              low[p] = low[u] if low[u] < low[p]
              if low[u] >= disc[p]
                cu = []
                cv = []
                done = 0 == 1
                while edge_u.size > 0 && !done
                  eu = edge_u.pop
                  ev = edge_v.pop
                  cu.push(eu)
                  cv.push(ev)
                  done = eu == p && ev == u
                comp_u.push(cu)
                comp_v.push(cv)
        # Normally every root child closes its own component.  Keep the
        # residual drain as a defensive guard for unusual disconnected input.
        if edge_u.size > 0
          cu = []
          cv = []
          while edge_u.size > 0
            cu.push(edge_u.pop)
            cv.push(edge_v.pop)
          comp_u.push(cu)
          comp_v.push(cv)
      start += 1
    [comp_u, comp_v]

  # Canonical simple undirected CSR for structural graph traversals. Packing
  # each edge into one u64 makes the global sort deduplicate both repeated COO
  # entries and opposite-triangle copies without allocating n nested Arrays.
  # Inserting the sorted unique edges into both endpoints also leaves every
  # CSR row in ascending vertex order, preserving deterministic DFS ties.
  -> .symmetric_csr_of(n, m, ri, ci)
    slots = 0
    k = 0
    while k < m
      slots += 1 if ri[k] != ci[k]
      k += 1
    ptr = u32[n + 1]
    return [ptr, u32[0]] if slots == 0
    keys = u64[slots]
    n64 = n ## u64
    kp = 0
    k = 0
    while k < m
      a = ri[k]
      b = ci[k]
      if a != b
        if b < a
          t = a
          a = b
          b = t
        keys[kp] = (a ## u64) * n64 + (b ## u64)
        kp += 1
      k += 1
    keys = keys.sort

    unique = 0
    k = 0
    while k < slots
      key = keys[k] ## u64
      if k == 0 || key != (keys[k - 1] ## u64)
        a = (key / n64) ## u32
        b = (key % n64) ## u32
        ptr[a + 1] += 1
        ptr[b + 1] += 1
        unique += 1
      k += 1
    i = 0
    while i < n
      ptr[i + 1] += ptr[i]
      i += 1
    idx = u32[unique * 2]
    cursor = u32[n]
    i = 0
    while i < n
      cursor[i] = ptr[i]
      i += 1
    k = 0
    while k < slots
      key = keys[k] ## u64
      if k == 0 || key != (keys[k - 1] ## u64)
        a = (key / n64) ## u32
        b = (key % n64) ## u32
        idx[cursor[a]] = b
        cursor[a] += 1
        idx[cursor[b]] = a
        cursor[b] += 1
      k += 1
    [ptr, idx]

  # Iterative Tarjan over flat CSR. This is a trusted internal helper: callers
  # must provide ptr.size>=n+1, monotone row bounds ending at idx.size, and
  # in-range symmetric vertex ids. `symmetric_csr_of` establishes that
  # invariant; deliberately avoid another O(m) validation pass here. Edges
  # are retained in their DFS orientation and pop order, matching
  # biconnected_edge_components, but in two contiguous typed buffers:
  # comp_ptr delimits packed u64 edge slices.
  -> .biconnected_edge_components_csr(n, ptr, idx)
    none = 4294967295
    ne = idx.size / 2
    disc = u32[n]
    low = u32[n]
    parent = u32[n]
    dfs_v = u32[n]
    dfs_next = u32[n]
    edge_stack = u64[ne]
    comp_edges = u64[ne]
    comp_ptr = u32[ne + 1]
    n64 = n ## u64
    i = 0
    while i < n
      parent[i] = none
      i += 1
    time = 0
    dfs_top = 0
    edge_top = 0
    edge_out = 0
    nc = 0
    start = 0
    while start < n
      if disc[start] == 0
        time += 1
        disc[start] = time
        low[start] = time
        dfs_v[0] = start
        dfs_next[0] = ptr[start]
        dfs_top = 1
        while dfs_top > 0
          top = dfs_top - 1
          u = dfs_v[top]
          slot = dfs_next[top]
          if slot < ptr[u + 1]
            v = idx[slot]
            dfs_next[top] = slot + 1
            if disc[v] == 0
              edge_stack[edge_top] = (u ## u64) * n64 + (v ## u64)
              edge_top += 1
              parent[v] = u
              time += 1
              disc[v] = time
              low[v] = time
              dfs_v[dfs_top] = v
              dfs_next[dfs_top] = ptr[v]
              dfs_top += 1
            elsif v != parent[u] && disc[v] < disc[u]
              edge_stack[edge_top] = (u ## u64) * n64 + (v ## u64)
              edge_top += 1
              low[u] = disc[v] if disc[v] < low[u]
          else
            dfs_top -= 1
            p = parent[u]
            if p != none
              low[p] = low[u] if low[u] < low[p]
              if low[u] >= disc[p]
                done = 0 == 1
                while edge_top > 0 && !done
                  edge_top -= 1
                  edge = edge_stack[edge_top] ## u64
                  comp_edges[edge_out] = edge
                  edge_out += 1
                  eu = (edge / n64) ## u32
                  ev = (edge % n64) ## u32
                  done = eu == p && ev == u
                nc += 1
                comp_ptr[nc] = edge_out
        # A well-formed undirected DFS closes every root-child block above.
        # Retain the historical defensive drain for unusual input.
        if edge_top > 0
          while edge_top > 0
            edge_top -= 1
            comp_edges[edge_out] = edge_stack[edge_top]
            edge_out += 1
          nc += 1
          comp_ptr[nc] = edge_out
      start += 1
    [comp_ptr, comp_edges, nc]

  # One-dissection ordering over the block-cut forest, using only flat typed
  # storage. Returns [] for a single genuinely biconnected block so portfolio
  # callers can skip the duplicate whole-graph AMD and exact-score pass.
  -> biconn_split_ordering(amd_iw_cap = 0)
    n = @pattern.rows
    return [] if n == 0
    csr = SparseAnalysis.symmetric_csr_of(n, @pattern.nnz, @fri, @fci)
    ptr = csr[0]
    idx = csr[1]
    packed = SparseAnalysis.biconnected_edge_components_csr(n, ptr, idx)
    comp_ptr = packed[0]
    comp_edges = packed[1]
    nc = packed[2]
    return [] if nc == 0
    none = 4294967295
    n64 = n ## u64

    # Flat block -> vertex and vertex -> block incidence. The first pass
    # computes exact capacities; the second preserves the old edge-pop first
    # appearance order without one growable Array per block or per vertex.
    member_count = u32[n]
    mark = u32[n]
    block_ptr = u32[nc + 1]
    c = 0
    while c < nc
      token = c + 1
      count = 0
      k = comp_ptr[c]
      while k < comp_ptr[c + 1]
        edge = comp_edges[k] ## u64
        u = (edge / n64) ## u32
        v = (edge % n64) ## u32
        if mark[u] != token
          mark[u] = token
          member_count[u] += 1
          count += 1
        if mark[v] != token
          mark[v] = token
          member_count[v] += 1
          count += 1
        k += 1
      block_ptr[c + 1] = block_ptr[c] + count
      c += 1
    return [] if nc == 1 && block_ptr[1] == n

    total_members = block_ptr[nc]
    block_vertices = u32[total_members]
    i = 0
    while i < n
      mark[i] = 0
      i += 1
    c = 0
    while c < nc
      token = c + 1
      out = block_ptr[c]
      k = comp_ptr[c]
      while k < comp_ptr[c + 1]
        edge = comp_edges[k] ## u64
        u = (edge / n64) ## u32
        v = (edge % n64) ## u32
        if mark[u] != token
          mark[u] = token
          block_vertices[out] = u
          out += 1
        if mark[v] != token
          mark[v] = token
          block_vertices[out] = v
          out += 1
        k += 1
      c += 1

    vertex_ptr = u32[n + 1]
    i = 0
    while i < n
      vertex_ptr[i + 1] = vertex_ptr[i] + member_count[i]
      member_count[i] = vertex_ptr[i]
      i += 1
    vertex_blocks = u32[total_members]
    c = 0
    while c < nc
      p = block_ptr[c]
      while p < block_ptr[c + 1]
        v = block_vertices[p]
        vertex_blocks[member_count[v]] = c
        member_count[v] += 1
        p += 1
      c += 1

    # Root every block-cut tree at its largest block. Dense cores stay late,
    # while pendant blocks are emitted from leaves inward. Typed queues and a
    # packed u64 sort key avoid O(number-of-blocks) boxed objects here too.
    parent_ap = u32[nc]
    depth = u32[nc]
    seen = u32[nc]
    queue = u32[nc]
    c = 0
    while c < nc
      parent_ap[c] = none
      depth[c] = none
      c += 1
    start = 0
    while start < nc
      if seen[start] == 0
        qh = 0
        qt = 1
        queue[0] = start
        seen[start] = 1
        root = start
        while qh < qt
          b = queue[qh]
          qh += 1
          bsize = block_ptr[b + 1] - block_ptr[b]
          rsize = block_ptr[root + 1] - block_ptr[root]
          root = b if bsize > rsize || (bsize == rsize && b < root)
          vi = block_ptr[b]
          while vi < block_ptr[b + 1]
            v = block_vertices[vi]
            if vertex_ptr[v + 1] - vertex_ptr[v] > 1
              bi = vertex_ptr[v]
              while bi < vertex_ptr[v + 1]
                cb = vertex_blocks[bi]
                if seen[cb] == 0
                  seen[cb] = 1
                  queue[qt] = cb
                  qt += 1
                bi += 1
            vi += 1

        qh = 0
        qt = 1
        queue[0] = root
        depth[root] = 0
        parent_ap[root] = none
        while qh < qt
          b = queue[qh]
          qh += 1
          vi = block_ptr[b]
          while vi < block_ptr[b + 1]
            v = block_vertices[vi]
            if vertex_ptr[v + 1] - vertex_ptr[v] > 1
              bi = vertex_ptr[v]
              while bi < vertex_ptr[v + 1]
                cb = vertex_blocks[bi]
                if depth[cb] == none
                  depth[cb] = depth[b] + 1
                  parent_ap[cb] = v
                  queue[qt] = cb
                  qt += 1
                bi += 1
            vi += 1
      start += 1

    stride = (nc + 1) ## u64
    block_order = u64[nc]
    c = 0
    while c < nc
      block_order[c] = ((nc - depth[c]) ## u64) * stride + (c ## u64)
      c += 1
    block_order = block_order.sort

    order = u32[n]
    op = 0
    # Isolates belong to no edge block and are fill-free.
    i = 0
    while i < n
      if vertex_ptr[i] == vertex_ptr[i + 1]
        order[op] = i
        op += 1
      i += 1

    local_token = u32[n]
    local = u32[n]
    generation = 0
    oi = 0
    while oi < nc
      b = ((block_order[oi] ## u64) % stride) ## u32
      pa = parent_ap[b]
      owned_n = block_ptr[b + 1] - block_ptr[b]
      owned_n -= 1 if pa != none
      if owned_n == 1
        vi = block_ptr[b]
        vi += 1 while block_vertices[vi] == pa
        order[op] = block_vertices[vi]
        op += 1
      elsif owned_n > 1
        owned = u32[owned_n]
        vi = block_ptr[b]
        out = 0
        while vi < block_ptr[b + 1]
          v = block_vertices[vi]
          if v != pa
            owned[out] = v
            out += 1
          vi += 1
        owned = owned.sort
        generation += 1
        vi = 0
        while vi < owned_n
          v = owned[vi]
          local_token[v] = generation
          local[v] = vi
          vi += 1
        lm = 0
        k = comp_ptr[b]
        while k < comp_ptr[b + 1]
          edge = comp_edges[k] ## u64
          u = (edge / n64) ## u32
          v = (edge % n64) ## u32
          lm += 1 if local_token[u] == generation && local_token[v] == generation
          k += 1
        lri = u32[lm]
        lci = u32[lm]
        lp = 0
        k = comp_ptr[b]
        while k < comp_ptr[b + 1]
          edge = comp_edges[k] ## u64
          u = (edge / n64) ## u32
          v = (edge % n64) ## u32
          if local_token[u] == generation && local_token[v] == generation
            lri[lp] = local[u]
            lci[lp] = local[v]
            lp += 1
          k += 1
        local_iw_cap = 0
        if amd_iw_cap > 0
          local_initial = 4 * lm + owned_n + 64
          local_iw_cap = 2 * local_initial
          local_iw_cap = amd_iw_cap if local_iw_cap > amd_iw_cap
          return [] if local_iw_cap < local_initial
        sub = amd_core(owned_n, lri, lci, lm, 10, 1, 0, local_iw_cap)
        return [] if sub.size != owned_n
        k = 0
        while k < owned_n
          order[op] = owned[sub[k]]
          op += 1
          k += 1
      oi += 1
    return [] if op != n
    order

  # Public candidate preserves the old full-order contract: a graph with one
  # biconnected block falls back to the exact whole-graph AMD anchor.
  -> biconn_ordering
    split = biconn_split_ordering
    return split if split.size == @pattern.rows
    min_degree_ordering
