+ SparseAnalysis
  # MINL: completion-lattice minimalization. Build the incumbent's
  # filled graph G+, then greedily delete a FILL edge uv whenever
  # N(u) ∩ N(v) is a clique in the current completion (the exact local
  # test that deletion preserves chordality), and realize the shrunken
  # completion with a maximum-cardinality-search perfect elimination
  # order. The completion's count multiset is order-invariant across its
  # PEOs, so any strict shrink is a real candidate; the exact oracle
  # still gates acceptance. `watcher=1` uses an event-driven sibling in the
  # historical lexicographic order; `watcher=2` seeds the same queue in stable
  # ascending endpoint-degree-sum order. In either mode, a
  # blocked fill edge watches the removable supports of one explicit
  # unique-chord four-cycle witness and is retried only when a support is
  # deleted. The default remains the historical four-round scan because
  # deletion schedule selects a different minimal-completion basin.
  # Optional watch_stats receives [removed, tests, complete, final_fill].
  # Returns [order, flops].
  -> minl_descent(order_in, flops_in, budget, alt = 0, watcher = 0, watch_stats = nil)
    n = @pattern.rows
    words = (n + 31) >> 5
    workspace = u32[2 * n * words]
    minl_descent_workspace(
      order_in, flops_in, budget, alt, watcher, watch_stats, workspace, 0)

  # Workspace form used by best_ordering's sequential MINL passes. The
  # pattern bitmap is immutable after the first pass; reset the mutable
  # completion from it so all passes share one caller-owned allocation. The
  # first bitmap_words elements are mutable G+; the second bitmap_words are
  # its immutable reset source. Keeping both halves in one checked buffer
  # makes overlap impossible by construction and avoids view allocations.
  -> minl_descent_workspace(order_in, flops_in, budget, alt, watcher, watch_stats, workspace, workspace_ready) (w64[] w64 w64 w64 w64 w64 u32[] w64) w64[]
    n = @pattern.rows
    m = @pattern.nnz
    ri = @fri
    ci = @fci
    words = (n + 31) >> 5
    full = 4294967295
    # G+ = pattern + fill from replaying the incumbent on bitsets
    bitmap_words = n * words
    if workspace.size < bitmap_words * 2
      raise "minl workspace: buffer is undersized"
    if workspace_ready == 0
      k = 0
      while k < m
        r = ri[k]
        c = ci[k]
        if r != c
          workspace[r * words + (c >> 5)] = workspace[r * words + (c >> 5)] | (1 << (c & 31))
          workspace[c * words + (r >> 5)] = workspace[c * words + (r >> 5)] | (1 << (r & 31))
          workspace[bitmap_words + r * words + (c >> 5)] = workspace[bitmap_words + r * words + (c >> 5)] | (1 << (c & 31))
          workspace[bitmap_words + c * words + (r >> 5)] = workspace[bitmap_words + c * words + (r >> 5)] | (1 << (r & 31))
        k += 1
    else
      ccall_nobox(
        "__w_u32_copy_raw", workspace, 0, workspace,
        bitmap_words ## i64, bitmap_words ## i64)
    alive = u32[words]
    i = 0
    while i < words
      alive[i] = full
      i += 1
    tail2 = n & 31
    alive[words - 1] = (1 << tail2) - 1 if tail2 != 0
    nb = u32[words]
    ops = 0
    kstep = 0
    while kstep < n
      v = order_in[kstep]
      alive[v >> 5] = alive[v >> 5] ^ (1 << (v & 31))
      vbase = v * words
      wi = 0
      while wi < words
        nb[wi] = workspace[vbase + wi] & alive[wi]
        wi += 1
      wi = 0
      while wi < words
        nw = nb[wi]
        while nw != 0
          u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
          ubase = u * words
          wj = 0
          while wj < words
            workspace[ubase + wj] = workspace[ubase + wj] | nb[wj]
            wj += 1
          workspace[ubase + (u >> 5)] = workspace[ubase + (u >> 5)] & (full ^ (1 << (u & 31)))
          ops += words
          nw = nw & (nw - 1)
        wi += 1
      kstep += 1
      return [order_in, flops_in] if ops > budget
    # symmetrize the completion (fill was added asymmetrically above:
    # ensure the mutable half is the union of both directions)
    i = 0
    while i < n
      vbase = i * words
      wi = 0
      while wi < words
        nw = workspace[vbase + wi]
        while nw != 0
          u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
          workspace[u * words + (i >> 5)] = workspace[u * words + (i >> 5)] | (1 << (i & 31))
          nw = nw & (nw - 1)
        wi += 1
      i += 1
    # Greedy deletion of fill edges whose common neighborhood is a clique.
    # The scan remains the default. The watcher sibling uses the same bitset
    # predicate and initial lexicographic edge order, but records a concrete
    # nonedge x-y in the common neighborhood when an edge is blocked.
    deleted = 0
    inter = u32[words]
    if watcher == 0
      rounds = 0
      changed = 0 == 0
      while changed && rounds < 4 && ops < budget
        changed = 0 == 1
        v = 0
        while v < n && ops < budget
          vbase = v * words
          wi = 0
          while wi < words
            nw = workspace[vbase + wi] & (workspace[bitmap_words + vbase + wi] ^ full)
            while nw != 0
              u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
              if u > v
                # fill edge (v,u): test N(v) ∩ N(u) clique
                ubase = u * words
                wj = 0
                while wj < words
                  inter[wj] = workspace[vbase + wj] & workspace[ubase + wj]
                  wj += 1
                ops += words
                isclq = 0 == 0
                wj = 0
                while wj < words && isclq
                  iw2 = inter[wj]
                  while iw2 != 0
                    x = (wj << 5) + ccall_nobox("__w_bit_cttz_u32", iw2)
                    xb = x * words
                    wk = 0
                    while wk < words
                      aw = inter[wk] & (workspace[xb + wk] ^ full)
                      aw = aw & (full ^ (1 << (x & 31))) if wk == (x >> 5)
                      if aw != 0
                        isclq = 0 == 1
                      wk += 1
                    ops += words
                    break if !isclq
                    iw2 = iw2 & (iw2 - 1)
                  wj += 1
                if isclq
                  workspace[vbase + (u >> 5)] = workspace[vbase + (u >> 5)] & (full ^ (1 << (u & 31)))
                  workspace[ubase + (v >> 5)] = workspace[ubase + (v >> 5)] & (full ^ (1 << (v & 31)))
                  deleted += 1
                  changed = 0 == 0
              nw = nw & (nw - 1)
            wi += 1
          v += 1
        rounds += 1
    else
      # Materialize stable lexicographic ids for the starting fill edges.
      # Count the symmetric bitset first so the hot path uses flat u32 arrays
      # instead of boxed pairs or a second dense n-by-n id matrix.
      fill_count2 = 0
      v = 0
      while v < n
        vbase = v * words
        wi = 0
        while wi < words
          fill_count2 += ccall_nobox(
            "__w_bit_ctpop_u32", workspace[vbase + wi] &
            (workspace[bitmap_words + vbase + wi] ^ full))
          wi += 1
        v += 1
      fill_count2 = fill_count2 >> 1
      watch_complete = 0 == 0
      # Four intrusive nodes plus state and endpoints cost about 72 bytes per
      # fill edge. These gates bound both that memory and bitset-test work.
      if n > 30000 || fill_count2 > 145000
        watch_complete = 0 == 1
        if watch_stats != nil
          watch_stats.push(0)
          watch_stats.push(0)
          watch_stats.push(0)
          watch_stats.push(fill_count2)
        return [order_in, flops_in]
      if fill_count2 == 0
        if watch_stats != nil
          watch_stats.push(0)
          watch_stats.push(0)
          watch_stats.push(1)
          watch_stats.push(0)
        return [order_in, flops_in]
      fill_u = u32[fill_count2]
      fill_v = u32[fill_count2]
      fi2 = 0
      v = 0
      while v < n
        vbase = v * words
        wi = 0
        while wi < words
          nw = workspace[vbase + wi] & (workspace[bitmap_words + vbase + wi] ^ full)
          while nw != 0
            u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
            if u > v
              fill_u[fi2] = v
              fill_v[fi2] = u
              fi2 += 1
            nw = nw & (nw - 1)
          wi += 1
        v += 1
      # Candidate e owns watcher nodes 4e..4e+3. Each support edge owns a
      # reverse intrusive list of the candidates whose current witness uses it.
      nonew = 4294967295
      alivew = u32[fill_count2]
      queuedw = u32[fill_count2]
      queuew = u32[fill_count2]
      watch_head = u32[fill_count2]
      node_count = fill_count2 << 2
      watch_prev = u32[node_count]
      watch_next = u32[node_count]
      watch_support = u32[node_count]
      fi2 = 0
      while fi2 < fill_count2
        alivew[fi2] = 1
        queuedw[fi2] = 1
        queuew[fi2] = fi2
        watch_head[fi2] = nonew
        fi2 += 1
      if watcher == 2
        # Stable counting sort by initial deg(u)+deg(v): spend a finite budget
        # on the cheapest predicates first while retaining edge-id tie order.
        degreew = u32[n]
        v = 0
        while v < n
          vbase = v * words
          wi = 0
          while wi < words
            degreew[v] += ccall_nobox("__w_bit_ctpop_u32", workspace[vbase + wi])
            wi += 1
          v += 1
        bucket_len = n * 2 + 2
        bucketw = u32[bucket_len]
        fi2 = 0
        while fi2 < fill_count2
          key2 = degreew[fill_u[fi2]] + degreew[fill_v[fi2]]
          bucketw[key2 + 1] += 1
          fi2 += 1
        i = 1
        while i < bucket_len
          bucketw[i] += bucketw[i - 1]
          i += 1
        fi2 = 0
        while fi2 < fill_count2
          key2 = degreew[fill_u[fi2]] + degreew[fill_v[fi2]]
          queuew[bucketw[key2]] = fi2
          bucketw[key2] += 1
          fi2 += 1
      ni2 = 0
      while ni2 < node_count
        watch_prev[ni2] = nonew
        watch_next[ni2] = nonew
        watch_support[ni2] = nonew
        ni2 += 1
      # Ring capacity F is sufficient: queuedw suppresses duplicates, so no
      # more than F candidate ids can be resident at once.
      qhead = 0
      qtail = 0
      qcount = fill_count2
      watch_tests = 0
      watch_exhausted = 0 == 1
      su = u32[4]
      sv = u32[4]
      while qcount > 0 && ops < budget && !watch_exhausted
        edge2 = queuew[qhead]
        qhead += 1
        qhead = 0 if qhead == fill_count2
        qcount -= 1
        queuedw[edge2] = 0
        next if alivew[edge2] == 0
        # Remove all old dependencies before recomputing the witness.
        slot2 = 0
        while slot2 < 4
          node2 = (edge2 << 2) + slot2
          support2 = watch_support[node2]
          if support2 != nonew
            prev2 = watch_prev[node2]
            next2 = watch_next[node2]
            if prev2 == nonew
              watch_head[support2] = next2
            else
              watch_next[prev2] = next2
            watch_prev[next2] = prev2 if next2 != nonew
            watch_prev[node2] = nonew
            watch_next[node2] = nonew
            watch_support[node2] = nonew
          slot2 += 1
        watch_tests += 1
        v = fill_u[edge2]
        u = fill_v[edge2]
        vbase = v * words
        ubase = u * words
        wj = 0
        while wj < words
          inter[wj] = workspace[vbase + wj] & workspace[ubase + wj]
          wj += 1
        ops += words
        watch_exhausted = 0 == 0 if ops > budget
        isclq = 0 == 0
        witness_x = nonew
        witness_y = nonew
        wj = 0
        while wj < words && isclq && !watch_exhausted
          iw2 = inter[wj]
          while iw2 != 0 && !watch_exhausted
            x = (wj << 5) + ccall_nobox("__w_bit_cttz_u32", iw2)
            xb = x * words
            wk = 0
            while wk < words
              aw = inter[wk] & (workspace[xb + wk] ^ full)
              aw = aw & (full ^ (1 << (x & 31))) if wk == (x >> 5)
              if aw != 0 && isclq
                isclq = 0 == 1
                witness_x = x
                witness_y = (wk << 5) + ccall_nobox("__w_bit_cttz_u32", aw)
              wk += 1
            ops += words
            watch_exhausted = 0 == 0 if ops > budget
            break if !isclq
            iw2 = iw2 & (iw2 - 1)
          wj += 1
        # A partially evaluated predicate is never allowed to mutate G+.
        break if watch_exhausted
        if isclq
          # Mutate only after the complete predicate, and clear both directions.
          workspace[vbase + (u >> 5)] = workspace[vbase + (u >> 5)] & (full ^ (1 << (u & 31)))
          workspace[ubase + (v >> 5)] = workspace[ubase + (v >> 5)] & (full ^ (1 << (v & 31)))
          alivew[edge2] = 0
          deleted += 1
          # Deleting edge2 invalidates every witness that watches it.
          while watch_head[edge2] != nonew
            node2 = watch_head[edge2]
            candidate2 = node2 >> 2
            prev2 = watch_prev[node2]
            next2 = watch_next[node2]
            if prev2 == nonew
              watch_head[edge2] = next2
            else
              watch_next[prev2] = next2
            watch_prev[next2] = prev2 if next2 != nonew
            watch_prev[node2] = nonew
            watch_next[node2] = nonew
            watch_support[node2] = nonew
            if alivew[candidate2] != 0 && queuedw[candidate2] == 0
              queuew[qtail] = candidate2
              qtail += 1
              qtail = 0 if qtail == fill_count2
              qcount += 1
              queuedw[candidate2] = 1
        else
          # Watch only removable supports. A present support absent from the
          # starting fill list is original and therefore permanent.
          su[0] = v
          sv[0] = witness_x
          su[1] = u
          sv[1] = witness_x
          su[2] = v
          sv[2] = witness_y
          su[3] = u
          sv[3] = witness_y
          si2 = 0
          slot2 = 0
          while si2 < 4
            lo2 = su[si2]
            hi2 = sv[si2]
            if lo2 > hi2
              tmp2 = lo2
              lo2 = hi2
              hi2 = tmp2
            left2 = 0
            right2 = fill_count2
            while left2 < right2
              mid2 = (left2 + right2) >> 1
              mu2 = fill_u[mid2]
              mv2 = fill_v[mid2]
              if mu2 < lo2 || (mu2 == lo2 && mv2 < hi2)
                left2 = mid2 + 1
              else
                right2 = mid2
            if left2 < fill_count2 && fill_u[left2] == lo2 && fill_v[left2] == hi2 && alivew[left2] != 0
              node2 = (edge2 << 2) + slot2
              old2 = watch_head[left2]
              watch_support[node2] = left2
              watch_prev[node2] = nonew
              watch_next[node2] = old2
              watch_prev[old2] = node2 if old2 != nonew
              watch_head[left2] = node2
              slot2 += 1
            si2 += 1
      watch_complete = qcount == 0 && !watch_exhausted
      if watch_stats != nil
        watch_stats.push(deleted)
        watch_stats.push(watch_tests)
        watch_stats.push(watch_complete ? 1 : 0)
        watch_stats.push(fill_count2 - deleted)
      # As a sibling, an unchanged completion would only repeat the scan arm's
      # three realizer passes. Keep this lane focused on watcher-derived graphs.
      return [order_in, flops_in] if deleted == 0
    # realize by maximum cardinality search (max label, tie lowest id),
    # output REVERSED (MCS gives a reverse PEO)
    lab = u32[n]
    done3 = u32[n]
    mcso = u32[n]
    none3 = 4294967295
    lh = u32[n + 1]
    ln2 = u32[n]
    lp = u32[n]
    i = 0
    while i < n + 1
      lh[i] = none3
      i += 1
    i = n
    while i > 0
      i -= 1
      ln2[i] = lh[0]
      lp[i] = none3
      lp[lh[0]] = i if lh[0] != none3
      lh[0] = i
    maxlab = 0
    t = 0
    while t < n
      while lh[maxlab] == none3
        maxlab -= 1
      bestv = lh[maxlab]
      lh[maxlab] = ln2[bestv]
      lp[ln2[bestv]] = none3 if ln2[bestv] != none3
      done3[bestv] = 1
      mcso[t] = bestv
      vbase = bestv * words
      wi = 0
      while wi < words
        nw = workspace[vbase + wi]
        while nw != 0
          u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
          if done3[u] == 0
            ol = lab[u]
            un = ln2[u]
            up = lp[u]
            if up == none3
              lh[ol] = un
            else
              ln2[up] = un
            lp[un] = up if un != none3
            lab[u] = ol + 1
            ln2[u] = lh[ol + 1]
            lp[u] = none3
            lp[lh[ol + 1]] = u if lh[ol + 1] != none3
            lh[ol + 1] = u
            maxlab = ol + 1 if ol + 1 > maxlab
          nw = nw & (nw - 1)
        wi += 1
      t += 1
    cand = []
    t = n
    while t > 0
      t -= 1
      cand.push(mcso[t])
    cand_flops = flops_for_order(cand)
    best_o = order_in
    best_f2 = flops_in
    if cand_flops < best_f2
      best_f2 = cand_flops
      best_o = cand
    # realization diversity: the completion choice and its PEO
    # realization are separable optimizations — different realizers
    # reach different tie basins of the same chordal completion
    # (1) degree-seeded MCS: rerun with buckets seeded lowest-degree-first
    gdeg = u32[n]
    i = 0
    while i < n
      d4 = 0
      vb4 = i * words
      wi = 0
      while wi < words
        d4 += ccall_nobox("__w_bit_ctpop_u32", workspace[vb4 + wi])
        wi += 1
      gdeg[i] = d4
      i += 1
    ordd = []
    i = 0
    while i < n
      ordd.push([0 - gdeg[i], i])
      i += 1
    ordd = ordd.sort_by -> (pr) pr[0]
    i = 0
    while i < n + 1
      lh[i] = none3
      i += 1
    i = 0
    while i < n
      lab[i] = 0
      done3[i] = 0
      i += 1
    t9 = 0
    while t9 < n
      i = ordd[t9][1]
      ln2[i] = lh[0]
      lp[i] = none3
      lp[lh[0]] = i if lh[0] != none3
      lh[0] = i
      t9 += 1
    maxlab = 0
    t = 0
    while t < n
      while lh[maxlab] == none3
        maxlab -= 1
      bestv = lh[maxlab]
      lh[maxlab] = ln2[bestv]
      lp[ln2[bestv]] = none3 if ln2[bestv] != none3
      done3[bestv] = 1
      mcso[t] = bestv
      vbase = bestv * words
      wi = 0
      while wi < words
        nw = workspace[vbase + wi]
        while nw != 0
          u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
          if done3[u] == 0
            ol = lab[u]
            un = ln2[u]
            up = lp[u]
            if up == none3
              lh[ol] = un
            else
              ln2[up] = un
            lp[un] = up if un != none3
            lab[u] = ol + 1
            ln2[u] = lh[ol + 1]
            lp[u] = none3
            lp[lh[ol + 1]] = u if lh[ol + 1] != none3
            lh[ol + 1] = u
            maxlab = ol + 1 if ol + 1 > maxlab
          nw = nw & (nw - 1)
        wi += 1
      t += 1
    cand = []
    t = n
    while t > 0
      t -= 1
      cand.push(mcso[t])
    cand_flops = flops_for_order(cand)
    if cand_flops < best_f2
      best_f2 = cand_flops
      best_o = cand
    # (2) AMF on the completion itself (dense deferral off)
    if n <= 25000
      cri2 = []
      cci2 = []
      i = 0
      while i < n
        vb4 = i * words
        wi = 0
        while wi < words
          nw4 = workspace[vb4 + wi]
          while nw4 != 0
            u4 = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw4)
            if u4 < i
              cri2.push(i)
              cci2.push(u4)
            nw4 = nw4 & (nw4 - 1)
          wi += 1
        i += 1
      # realizer rotation: the repass (alt=1) re-realizes the completion
      # with a different AMF alpha family than the first pass
      ralpha = 0 - 1
      ralpha = 25 if alt == 1
      cand = amf_core(n, cri2, cci2, cri2.size, ralpha)
      cand_flops = flops_for_order(cand)
      if cand_flops < best_f2
        best_f2 = cand_flops
        best_o = cand
    [best_o, best_f2]

  # Exact residual degree of window vertex `pick` after eliminating `subset`.
  # For a fixed eliminated set S the remaining graph is order-independent:
  # x and y are adjacent iff the pre-window graph contains an x..y path whose
  # internal vertices are in S.  Starting from N(pick), close through the
  # eliminated window vertices, union their rows, then remove S and pick.
  # `scratch` is caller-owned and overwritten completely.
  # WINDOW-DP: exact minimum-Σc² over sliding windows of K consecutive
  # positions of the incumbent. The elimination state before the window
  # is replayed once on bitset rows; a subset DP over the K window
  # vertices then finds the provably cheapest internal order (the state
  # is the eliminated subset — fill inside the window is recomputed per
  # transition on the bitsets). The tail beyond the window is unchanged,
  # so the exact global gain equals the window's own gain. Sudoku-style:
  # deduce the truly forced structure exactly where the space is small.
  -> window_dp(order_in, flops_in, kwin, budget)
    n = @pattern.rows
    m = @pattern.nnz
    ri = @fri
    ci = @fci
    words = (n + 31) >> 5
    full = 4294967295
    adj0 = u32[n * words]
    k = 0
    while k < m
      r = ri[k]
      c = ci[k]
      if r != c
        adj0[r * words + (c >> 5)] = adj0[r * words + (c >> 5)] | (1 << (c & 31))
        adj0[c * words + (r >> 5)] = adj0[c * words + (r >> 5)] | (1 << (r & 31))
      k += 1
    adj = u32[n * words]
    alive = u32[words]
    nb = u32[words]
    cur = []
    i = 0
    while i < n
      cur.push(order_in[i])
      i += 1
    cur_f = flops_in
    nstates = 1 << kwin
    dpc = w64[nstates]
    dppar = u32[nstates]
    dppick = u32[nstates]
    ops = 0
    changed = 0 == 0
    sweep = 0
    while changed && sweep < 3 && ops < budget
      changed = 0 == 1
      # replay from scratch, pausing at each window start
      i2 = 0
      while i2 < n * words
        adj[i2] = adj0[i2]
        i2 += 1
      i2 = 0
      while i2 < words
        alive[i2] = full
        i2 += 1
      tail2 = n & 31
      alive[words - 1] = (1 << tail2) - 1 if tail2 != 0
      ops += n * words
      pos = 0
      while pos + kwin <= n && ops < budget
        # DP over the kwin vertices at positions pos..pos+kwin-1
        # snapshot rows of the window vertices
        wl = u32[kwin]
        t = 0
        while t < kwin
          wl[t] = cur[pos + t]
          t += 1
        s2 = 1
        dpc[0] = 0
        while s2 < nstates
          dpc[s2] = 70368744177664
          s2 += 1
        s2 = 0
        while s2 < nstates
          if dpc[s2] < 70368744177664
            t = 0
            while t < kwin
              bit = 1 << t
              if (s2 & bit) == 0
                v = wl[t]
                d = ssi_window_state_degree(
                  adj, alive, nb, words, wl, kwin, s2, t)
                ops += words * (kwin + 1) + kwin * kwin
                cc = d + 1
                ns = s2 | bit
                if dpc[s2] + cc * cc < dpc[ns]
                  dpc[ns] = dpc[s2] + cc * cc
                  dppar[ns] = s2
                  dppick[ns] = t
              t += 1
          s2 += 1
        # compare with the incumbent's exact transition costs
        inc_cost = 0
        s2 = 0
        t = 0
        while t < kwin
          d = ssi_window_state_degree(
            adj, alive, nb, words, wl, kwin, s2, t)
          cc = d + 1
          inc_cost += cc * cc
          s2 = s2 | (1 << t)
          t += 1
        ops += kwin * (words * (kwin + 1) + kwin * kwin)
        if dpc[nstates - 1] < inc_cost
          # rebuild the window order from the DP and trial-splice
          picks = []
          s2 = nstates - 1
          while s2 != 0
            picks.push(dppick[s2])
            s2 = dppar[s2]
          cand = []
          i2 = 0
          while i2 < n
            cand.push(cur[i2])
            i2 += 1
          t = 0
          while t < kwin
            cand[pos + t] = wl[picks[picks.size - 1 - t]]
            t += 1
          cand_flops = flops_for_order(cand)
          if cand_flops < cur_f
            cur = cand
            cur_f = cand_flops
            changed = 0 == 0
        # advance the replay by ONE position (eliminate cur[pos])
        v = cur[pos]
        alive[v >> 5] = alive[v >> 5] ^ (1 << (v & 31))
        vbase = v * words
        nbcnt2 = 0
        wi = 0
        while wi < words
          nw = adj[vbase + wi] & alive[wi]
          nb[wi] = nw
          wi += 1
        wi = 0
        while wi < words
          nw = nb[wi]
          while nw != 0
            u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
            ubase = u * words
            wj = 0
            while wj < words
              adj[ubase + wj] = adj[ubase + wj] | nb[wj]
              wj += 1
            adj[ubase + (u >> 5)] = adj[ubase + (u >> 5)] & (full ^ (1 << (u & 31)))
            ops += words
            nw = nw & (nw - 1)
          wi += 1
        pos += 1
      sweep += 1
    [cur, cur_f]

  # Deterministic structural fingerprint for candidate deduplication.  A hash
  # match is always followed by exact order equality, so collisions cannot
  # discard a distinct downstream basin.
  -> order_hash(order)
    h = 104729
    i = 0
    while i < order.size
      h = (h * 48271 + order[i] + 1) % 2147483647
      i += 1
    h

  # Bounded near-elite candidate pool (MetaFlip shoulder): keep up to four
  # structurally distinct candidates, including equal-cost orders.  A worse
  # or equal-cost seed can reach a better terminal basin, so late descents
  # launch from each pool member.
  -> pool_consider(flops, cand)
    return nil if @cand_pool == nil
    if @pool_structural == 0
      i = 0
      while i < @cand_pool.size
        return nil if @cand_pool[i][0] == flops
        i += 1
      @cand_pool.push([flops, cand, 0])
      @cand_pool = @cand_pool.sort_by -> (pr) pr[0]
      @cand_pool.pop while @cand_pool.size > 4
      return nil
    hash = order_hash(cand)
    i = 0
    while i < @cand_pool.size
      if @cand_pool[i][2] == hash && @cand_pool[i][1] == cand
        return nil
      i += 1
    @cand_pool.push([flops, cand, hash])
    @cand_pool = @cand_pool.sort_by -> (pr) pr[0]
    @cand_pool.pop while @cand_pool.size > 4
    nil

  # TELOS: count-ranked descent on the incumbent. For a fixed chordal
  # completion the multiset of column counts is invariant across perfect
  # elimination orders, so Σc² is a function of the completion and its
  # steepest per-vertex handle is the exact count itself. Moves: PEEL —
  # splice the k fattest-count vertices to the end, order otherwise
  # untouched; STRIP — remove the k fattest, re-order the remainder with
  # AMD on its induced subgraph, append the removed last. A second rank
  # mode strips the top of the elimination tree (last-eliminated first).
  # Every move is scored by the exact oracle; descend while improving.
  -> telos_descent(order_in, flops_in, rounds)
    n = @pattern.rows
    m = @pattern.nnz
    ri = @fri
    ci = @fci
    cur = []
    i = 0
    while i < n
      cur.push(order_in[i])
      i += 1
    cur_f = flops_in
    rnd = 0
    while rnd < rounds
      perm = u32[n]
      i = 0
      while i < n
        perm[cur[i]] = i
        i += 1
      # Keep a stable owned count snapshot while later candidate scores reuse
      # the analysis workspace.
      counts = counts_under(perm)[1]
      # vertex ranking arrays: by count (desc), and by position (desc)
      idxs = []
      i = 0
      while i < n
        idxs.push([0 - counts[i], i])
        i += 1
      idxs = idxs.sort_by -> (pr) pr[0]
      best_cand = nil
      best_f = cur_f
      mode = 0
      while mode < 2
        kk = 1
        while kk <= 128
          # top-kk permuted labels to move
          markm = u32[n]
          t = 0
          while t < kk && t < n
            lbl = idxs[t][1]
            lbl = n - 1 - t if mode == 1
            markm[lbl] = 1
            t += 1
          cand = []
          i = 0
          while i < n
            cand.push(cur[i]) if markm[perm[cur[i]]] == 0
            i += 1
          i = 0
          while i < n
            cand.push(cur[i]) if markm[perm[cur[i]]] == 1
            i += 1
          cand_flops = flops_for_order(cand)
          if cand_flops < best_f
            best_f = cand_flops
            best_cand = cand
          kk = kk * 2
        mode += 1
      # COUNT-RELABEL: relabel the pattern by ascending exact incumbent
      # column count and re-run AMD — an objective-informed structured
      # relabel, distinct from the random multistart
      if rnd == 0
        rel = u32[n]
        t = 0
        while t < n
          rel[idxs[n - 1 - t][1]] = t
          t += 1
        rri = u32[m]
        rci = u32[m]
        k2 = 0
        while k2 < m
          rri[k2] = rel[perm[ri[k2]]]
          rci[k2] = rel[perm[ci[k2]]]
          k2 += 1
        sub2 = amd_core(n, rri, rci, m)
        relinv = u32[n]
        t = 0
        while t < n
          relinv[rel[t]] = t
          t += 1
        cand = []
        t = 0
        while t < n
          cand.push(cur[relinv[sub2[t]]])
          t += 1
        cand_flops = flops_for_order(cand)
        if cand_flops < best_f
          best_f = cand_flops
          best_cand = cand
      # STRIP: remove top-k by count, AMD the remainder, append removed
      sk = 0
      while sk < 5
        kk = 6
        kk = 24 if sk == 1
        kk = 48 if sk == 2
        kk = 64 if sk == 3
        kk = 96 if sk == 4
        if kk < n
          markm = u32[n]
          t = 0
          while t < kk
            markm[idxs[t][1]] = 1
            t += 1
          keep = []
          moved = []
          i = 0
          while i < n
            v = cur[i]
            if markm[perm[v]] == 0
              keep.push(v)
            else
              moved.push(v)
            i += 1
          lid = u32[n]
          i = 0
          while i < keep.size
            lid[keep[i]] = i + 1
            i += 1
          sri = []
          sci = []
          k2 = 0
          while k2 < m
            a = ri[k2]
            b = ci[k2]
            if a != b && lid[a] != 0 && lid[b] != 0
              sri.push(lid[a] - 1)
              sci.push(lid[b] - 1)
            k2 += 1
          sub = amd_core(keep.size, sri, sci, sri.size)
          cand = []
          i = 0
          while i < keep.size
            cand.push(keep[sub[i]])
            i += 1
          i = 0
          while i < moved.size
            cand.push(moved[i])
            i += 1
          cand_flops = flops_for_order(cand)
          if cand_flops < best_f
            best_f = cand_flops
            best_cand = cand
          i = 0
          while i < keep.size
            lid[keep[i]] = 0
            i += 1
        sk += 1
      break if best_cand == nil
      cur = best_cand
      cur_f = best_f
      rnd += 1
    [cur, cur_f]

  # RGSUB: the elimination-game ILS on elimination-tree SUBTREES of the
  # incumbent. The incumbent is postordered first (a flops-neutral
  # permutation of the same chordal completion), which makes every etree
  # subtree a contiguous block of positions; disjoint blocks in a size
  # window are ranked by exact Σc² contribution ÷ size^(3/4) and each
  # block's induced subgraph is refined independently with the ILS. Every
  # splice is certified by the exact global scorer. Returns [order, flops].
  # Refine queued disjoint blocks across a CPU/memory-capped native worker set,
  # then accept each sequentially on the exact global rescore. A worker
  # consumes a strided slice of the immutable jobs, avoiding repeated
  # launch/join waves.
  # Returns [cur, cur_flops].
  -> flush_blocks(pend, kind, ils_words, stream, cur, cur_flops)
    outs2 = []
    th2 = []
    pi = 0
    while pi < pend.size
      outs2.push([])
      pi += 1
    # The coordinator sleeps while workers run, so use every online CPU up to
    # a modest portability cap. Bound aggregate dense-game scratch to 128 MiB:
    # each rgreedy worker owns three n-by-ceil(n/32) u32 bit matrices plus
    # linear state. Small blocks can occupy the machine; 6k-terminal macro
    # blocks automatically fall back to fewer concurrent workers.
    workers = pend.size
    worker_cap = ccall("w_cpu_count")
    worker_cap = 32 if worker_cap > 32
    worker_cap = 1 if worker_cap < 1
    max_local = 1
    max_movable = 1
    max_local_edges = 1
    pi = 0
    while pi < pend.size
      jsz = pend[pi][5].size
      max_local = jsz if jsz > max_local
      jsz = pend[pi][2]
      max_movable = jsz if jsz > max_movable
      jsz = pend[pi][3].size
      max_local_edges = jsz if jsz > max_local_edges
      pi += 1
    # Include the private SparsePattern/SparseAnalysis COO copies and linear
    # state as well as the three dense game bitmaps. The edge term uses the
    # largest immutable queued job, so aggregate live worker scratch remains
    # within the cap even when every worker receives that shape.
    per_worker_bytes = SparseAnalysis.rgsub_worker_workspace_bytes(
      max_local, max_local_edges)
    return [cur, cur_flops] if per_worker_bytes > 134217728
    memory_cap = 134217728 / per_worker_bytes
    worker_cap = memory_cap if memory_cap < worker_cap
    workers = worker_cap if workers > worker_cap
    pi = 0
    while pi < workers
      worker_id = pi
      worker_count = workers
      jobs = pend
      worker_outs = outs2
      jkind = kind
      jils = ils_words
      jstream = stream
      th = Thread.new ->
        ji = worker_id
        while ji < jobs.size
          job = jobs[ji]
          jnelim = job[2]
          jbri = job[3]
          jbci = job[4]
          jseed = job[5]
          SparseAnalysis.refine_block(
            jkind, jseed.size, jnelim, jbri, jbci, jseed,
            jils, jstream, worker_outs[ji])
          ji += worker_count
      th2.push(th)
      pi += 1
    pi = 0
    while pi < th2.size
      th2[pi].join
      pi += 1
    # Workers are joined and `cur` is an rgsub-owned order. Mutate one block
    # in place, score it, and restore from this reusable typed segment on
    # rejection instead of allocating/copying an n-element candidate per job.
    old_segment = u32[max_movable]
    pi = 0
    while pi < pend.size
      job = pend[pi]
      lo2 = job[0]
      bn2 = job[2]
      res2 = outs2[pi]
      if res2.size > 0 && res2[0][1] < res2[0][2]
        ref = res2[0]
        k = 0
        while k < bn2
          old_segment[k] = cur[lo2 + k]
          k += 1
        k = 0
        while k < bn2
          cur[lo2 + k] = old_segment[ref[0][k]]
          k += 1
        cand_flops = flops_for_order(cur)
        if cand_flops < cur_flops
          cur_flops = cand_flops
        else
          k = 0
          while k < bn2
            cur[lo2 + k] = old_segment[k]
            k += 1
      pi += 1
    [cur, cur_flops]

  -> rgsub_refine(order_in, ils_words, stream, kmask = 1, others = nil, with_boundary = 0, rgreedy_rounds = 2)
    n = @pattern.rows
    m = @pattern.nnz
    none = 4294967295
    # Symmetric CSR adjacency once per call (typed): sparse patterns may store
    # only one triangle, while every subtree refiner needs the undirected
    # graph. Block extraction then costs the block's incident edges instead of
    # a full m-edge scan per block.
    xadj = u32[n + 1]
    k = 0
    while k < m
      a9 = @fri[k]
      b9 = @fci[k]
      if a9 != b9
        xadj[a9 + 1] += 1
        xadj[b9 + 1] += 1
      k += 1
    i = 0
    while i < n
      xadj[i + 1] += xadj[i]
      i += 1
    afill = u32[n]
    adjl = u32[xadj[n]]
    k = 0
    while k < m
      a9 = @fri[k]
      b9 = @fci[k]
      if a9 != b9
        adjl[xadj[a9] + afill[a9]] = b9
        afill[a9] += 1
        adjl[xadj[b9] + afill[b9]] = a9
        afill[b9] += 1
      k += 1
    perm = u32[n]
    i = 0
    while i < n
      perm[order_in[i]] = i
      i += 1
    data = counts_under(perm)
    parent = data[0]
    counts1 = data[1]
    # postorder the etree (children in ascending order via bucket lists)
    kid_head = u32[n]
    kid_next = u32[n]
    i = 0
    while i < n
      kid_head[i] = none
      i += 1
    i = n
    while i > 0
      i -= 1
      p = parent[i]
      if p != none
        kid_next[i] = kid_head[p]
        kid_head[p] = i
    post = u32[n]
    pc = 0
    stk = u32[n]
    sp = 0
    r = n
    while r > 0
      r -= 1
      if parent[r] == none
        stk[sp] = r
        sp += 1
    state2 = u32[n]
    while sp > 0
      v = stk[sp - 1]
      if state2[v] == 0
        state2[v] = 1
        c = kid_head[v]
        while c != none
          stk[sp] = c
          sp += 1
          c = kid_next[c]
      else
        sp -= 1
        post[pc] = v
        pc += 1
    # new order: original vertex of permuted label post[k] at position k
    inv = u32[n]
    i = 0
    while i < n
      inv[perm[i]] = i
      i += 1
    order2 = []
    k = 0
    while k < n
      order2.push(inv[post[k]])
      k += 1
    # An etree postorder preserves the filled graph and merely relabels its
    # columns. Derive the postordered parent/count arrays in O(n) instead of
    # rebuilding lower CSC + etree + counts for the same chordal completion.
    # Reuse dead work buffers: state2 becomes old-label -> post-position,
    # inv becomes parent2, and perm becomes counts2.
    postpos = state2
    k = 0
    while k < n
      postpos[post[k]] = k
      k += 1
    parent2 = inv
    counts2 = perm
    k = 0
    while k < n
      old_label = post[k]
      p = parent[old_label]
      parent2[k] = p == none ? none : postpos[p]
      counts2[k] = counts1[old_label]
      k += 1
    base_flops = ccall("__w_u32_flops", counts2)
    tsize = u32[n]
    i = 0
    while i < n
      tsize[i] = 1
      i += 1
    i = 0
    while i < n
      p = parent2[i]
      tsize[p] = tsize[p] + tsize[i] if p != none
      i += 1
    contrib = w64[n]
    i = 0
    while i < n
      contrib[i] = 0
      i += 1
    i = 0
    while i < n
      c = counts2[i]
      p = parent2[i]
      contrib[i] = contrib[i] + c * c
      i += 1
    # accumulate subtree contributions bottom-up
    i = 0
    while i < n
      p = parent2[i]
      contrib[p] = contrib[p] + contrib[i] if p != none
      i += 1
    # Two rounds. Round 0: subtree size in [32, 2400], ranked by
    # contrib/size — small concentrated pockets first. Round 1 (macro):
    # size in [700, 2400] ranked by raw contrib, few blocks — large
    # coherent subtrees that round 0's disjointness always crowds out
    # (a taken child position vetoes every ancestor).
    lid = u32[n]
    cur = order2
    cur_flops = base_flops
    # kind 2 = pool crossover: position of every vertex in the other
    # candidate; a block's vertices get re-sequenced in the other's
    # relative order (exact-safe by subtree closure, scored globally)
    # subtree band scales with n below the 2400 ceiling so mid-size rows
    # (n >= 1500) get proportionate blocks; macro band = top third
    hi_sz = n / 3
    hi_sz = 2400 if hi_sz > 2400
    mac_lo = hi_sz / 3
    pos_o = u32[n]
    cur_pos = u32[n]
    # fused phases over one shared setup (CSR, etree, postorder, subtree
    # sizes, contributions): phase 0/1 = rgreedy rounds, 2/3 = anneal
    # rounds, 4+ = one crossover pass per pool runner-up
    nphase = 4
    nphase += others.size if others != nil
    phase = 0
    while phase < nphase
      kind = 0
      round3 = phase
      if phase >= 4
        kind = 2
        round3 = 0
        other = others[phase - 4]
        i = 0
        while i < n
          pos_o[other[i]] = i
          i += 1
      elsif phase >= 2
        kind = 1
        round3 = phase - 2
      phase += 1
      next if kind == 0 && (kmask & 1) == 0
      next if kind == 1 && (kmask & 2) == 0
      next if kind == 2 && (kmask & 4) == 0
      next if kind == 0 && round3 >= rgreedy_rounds
      if with_boundary != 0 && kind == 0
        i = 0
        while i < n
          cur_pos[cur[i]] = i
          i += 1
      cands = []
      i = 0
      while i < n
        sz = tsize[i]
        if round3 == 0
          cands.push([0 - contrib[i] / sz, i]) if sz >= 32 && sz <= hi_sz
        else
          cands.push([0 - contrib[i], i]) if sz >= mac_lo && sz <= hi_sz && hi_sz >= 96
        i += 1
      cands = cands.sort_by -> (pr) pr[0]
      taken = u32[n]
      blocks = 0
      pend = []
      pend_bytes = 0
      queue_cap = 134217728 - SparseAnalysis.rgsub_coordinator_workspace_bytes(
        n, m)
      queue_cap = 0 if queue_cap < 0
      bcap = 64
      bcap = 16 if kind == 1
      bcap = 8 if round3 == 1
      ci2 = 0
      while ci2 < cands.size && blocks < bcap
        root = cands[ci2][1]
        ci2 += 1
        lo = root + 1 - tsize[root]
        hi = root
        # disjointness: skip if any position already taken
        clash = 0 == 1
        k = lo
        while k <= hi
          clash = 0 == 0 if taken[k] != 0
          k += 1
        next if clash
        k = lo
        while k <= hi
          taken[k] = 1
          k += 1
        blocks += 1
        if kind == 2
          seg = []
          k = lo
          while k <= hi
            seg.push([pos_o[cur[k]], cur[k]])
            k += 1
          seg = seg.sort_by -> (pr) pr[0]
          cand2 = []
          k = 0
          while k < n
            cand2.push(cur[k])
            k += 1
          k = 0
          while k <= hi - lo
            cand2[lo + k] = seg[k][1]
            k += 1
          cand_flops = flops_for_order(cand2)
          if cand_flops < cur_flops
            cur = cand2
            cur_flops = cand_flops
          next
        # Local IDs put movable subtree vertices first. In the boundary-aware
        # lane, append every still-live original neighbor as a passive
        # terminal. The worker sees those separator degrees and fill effects,
        # but rgreedy may eliminate only IDs 0...bn.
        bn = hi - lo + 1
        k = lo
        while k <= hi
          lid[cur[k]] = k - lo + 1
          k += 1
        bverts = []
        bad_boundary = 0 == 1
        if with_boundary != 0 && kind == 0
          k = lo
          while k <= hi
            a = cur[k]
            e9 = xadj[a]
            e9e = xadj[a + 1]
            while e9 < e9e
              b = adjl[e9]
              if lid[b] == 0
                if cur_pos[b] < lo
                  bad_boundary = 0 == 0
                elsif cur_pos[b] > hi
                  lid[b] = none
                  bverts.push(b)
              e9 += 1
            k += 1
          bverts = bverts.sort_by -> (v2) cur_pos[v2]
          k = 0
          while k < bverts.size
            lid[bverts[k]] = bn + k + 1
            k += 1
          # Three dense n-by-n bitsets live in each worker. Bound the passive
          # separator expansion before launching the phase worker set.
          local_cap = 3500
          local_cap = 6000 if round3 == 1
          bad_boundary = 0 == 0 if bn + bverts.size > local_cap
        if bad_boundary
          k = lo
          while k <= hi
            lid[cur[k]] = 0
            k += 1
          k = 0
          while k < bverts.size
            lid[bverts[k]] = 0
            k += 1
          next
        # Count local edges before allocating their buffers. Boundary vertices
        # may repeat the same passive-separator edges in several disjoint jobs,
        # so neither one job nor the queued phase is bounded by global m.
        local_edges = 0
        k = lo
        while k <= hi
          a = cur[k]
          e9 = xadj[a]
          e9e = xadj[a + 1]
          while e9 < e9e
            b = adjl[e9]
            if lid[b] != 0 && lid[a] < lid[b]
              local_edges += 1
            e9 += 1
          k += 1
        k = 0
        while k < bverts.size
          a = bverts[k]
          e9 = xadj[a]
          e9e = xadj[a + 1]
          while e9 < e9e
            b = adjl[e9]
            if lid[b] != 0 && lid[a] < lid[b]
              local_edges += 1
            e9 += 1
          k += 1
        local_n = bn + bverts.size
        worker_bytes = SparseAnalysis.rgsub_worker_workspace_bytes(
          local_n, local_edges)
        job_bytes = SparseAnalysis.rgsub_queued_job_workspace_bytes(
          local_n, local_edges)
        admissible = local_edges > 0 && worker_bytes <= 134217728 && job_bytes <= queue_cap
        if !admissible
          k = lo
          while k <= hi
            lid[cur[k]] = 0
            k += 1
          k = 0
          while k < bverts.size
            lid[bverts[k]] = 0
            k += 1
          next
        # Flush before allocating when retaining this job would exceed the
        # coordinator's remaining 128 MiB envelope. This keeps useful batches
        # parallel while bounding duplicated passive-separator edge storage.
        if pend.size > 0 && pend_bytes + job_bytes > queue_cap
          fb = flush_blocks(pend, kind, ils_words, stream, cur, cur_flops)
          cur = fb[0]
          cur_flops = fb[1]
          pend = []
          pend_bytes = 0
        # Exact-size typed buffers avoid the old boxed push growth and make
        # the queue accounting match the live representation.
        bri = u32[local_edges]
        bci = u32[local_edges]
        edge_pos = 0
        k = lo
        while k <= hi
          a = cur[k]
          e9 = xadj[a]
          e9e = xadj[a + 1]
          while e9 < e9e
            b = adjl[e9]
            if lid[b] != 0 && lid[a] < lid[b]
              bri[edge_pos] = lid[a] - 1
              bci[edge_pos] = lid[b] - 1
              edge_pos += 1
            e9 += 1
          k += 1
        k = 0
        while k < bverts.size
          a = bverts[k]
          e9 = xadj[a]
          e9e = xadj[a + 1]
          while e9 < e9e
            b = adjl[e9]
            if lid[b] != 0 && lid[a] < lid[b]
              bri[edge_pos] = lid[a] - 1
              bci[edge_pos] = lid[b] - 1
              edge_pos += 1
            e9 += 1
          k += 1
        # Identity seeds have a known final size and fit in u32. Allocate once
        # without boxed push growth; workers treat the buffer as read-only.
        bseed = u32[local_n]
        k = 0
        while k < local_n
          bseed[k] = k
          k += 1
        # local exact seed cost via a fresh sub-analysis is implicit: give
        # the ILS a generous incumbent (it re-derives the running sum)
        # clear lid for reuse (the block's edge lists are extracted)
        k = lo
        while k <= hi
          lid[cur[k]] = 0
          k += 1
        k = 0
        while k < bverts.size
          lid[bverts[k]] = 0
          k += 1
        # Queue the block. The phase flush partitions bounded immutable jobs
        # over its CPU/memory-capped native worker set and accepts results
        # sequentially on the exact global rescore (blocks are disjoint
        # position ranges, so their local proposals do not depend on earlier
        # splices in the same phase).
        pend.push([lo, hi, bn, bri, bci, bseed])
        pend_bytes += job_bytes
      if pend.size > 0
        fb = flush_blocks(pend, kind, ils_words, stream, cur, cur_flops)
        cur = fb[0]
        cur_flops = fb[1]
        pend = []
    [cur, cur_flops]

  # Order-space local descent: mutate the permutation directly —
  # adjacent-pair swaps swept left to right, then random segment
  # reversals as perturbations — accepting on exact Σc² (full rescore;
  # cheap at small n on the typed counts kernel). Reaches basins the
  # elimination game cannot: the winning pivot at a position may be far
  # from minimum degree, but a swap can still find it. Deterministic per
  # (seed_order, stream). Returns [best_order, best_flops].
  -> order_descent(order_in, flops_in, budget_scores, stream, perturb = 1)
    n = @pattern.rows
    cur = u32[n]
    i = 0
    while i < n
      cur[i] = order_in[i]
      i += 1
    cur_f = flops_in
    best = u32[n]
    i = 0
    while i < n
      best[i] = cur[i]
      i += 1
    best_f = cur_f
    scores = 0
    state = (48271 + stream * 8191) % 2147483646 + 1
    while scores < budget_scores
      improved = 0 == 1
      i = 0
      while i + 1 < n
        break if scores >= budget_scores
        t = cur[i]
        cur[i] = cur[i + 1]
        cur[i + 1] = t
        f = flops_for_typed_order(cur)
        scores += 1
        if f < cur_f
          cur_f = f
          improved = 0 == 0
        else
          t = cur[i]
          cur[i] = cur[i + 1]
          cur[i + 1] = t
        i += 1
      if cur_f < best_f
        best_f = cur_f
        i = 0
        while i < n
          best[i] = cur[i]
          i += 1
      if !improved
        break if perturb == 0
        # perturb: reverse a random segment, restart the sweep from best
        i = 0
        while i < n
          cur[i] = best[i]
          i += 1
        state = (state * 48271) % 2147483647
        a = state % n
        state = (state * 48271) % 2147483647
        len2 = 3 + state % 12
        b = a + len2
        b = n - 1 if b > n - 1
        while a < b
          t = cur[a]
          cur[a] = cur[b]
          cur[b] = t
          a += 1
          b -= 1
        cur_f = flops_for_typed_order(cur)
        scores += 1
    [best, best_f]

  # Simulated annealing on order space with EXACT scoring: every move is
  # priced by the Σc² kernel, so acceptance never chases a proxy. Move
  # classes are relocate (extract a vertex, reinsert anywhere — the move
  # adjacent-swap descent lacks) and short segment reversal. Threshold
  # accepting (accept if delta <= T) avoids transcendental math; T cools
  # quadratically from flops/40 to 0. Integer-only: frac ≤ 256 keeps
  # t0i*frac*frac under the 48-bit fixnum ceiling.
  # left-rotate arr[lo, hi) by k positions (three-reversal, in place)
  -> rot_range(arr, lo, hi, k)
    rev_range(arr, lo, lo + k)
    rev_range(arr, lo + k, hi)
    rev_range(arr, lo, hi)

  -> rev_range(arr, lo, hi)
    i = lo
    j = hi - 1
    while i < j
      t = arr[i]
      arr[i] = arr[j]
      arr[j] = t
      i += 1
      j -= 1

  -> anneal_refine(order_in, flops_in, budget_scores, stream)
    n = @pattern.rows
    cur = u32[n]
    i = 0
    while i < n
      cur[i] = order_in[i]
      i += 1
    cur_f = flops_in
    best = u32[n]
    i = 0
    while i < n
      best[i] = order_in[i]
      i += 1
    best_f = flops_in
    t0i = flops_in / 40
    state = (77551 + stream * 12289) % 2147483646 + 1
    scores = 0
    while scores < budget_scores
      rem = budget_scores - scores
      frac = rem * 256 / budget_scores
      tt = t0i * frac / 256 * frac / 256
      state = (state * 48271) % 2147483647
      mv = state % 10
      a = 0
      b = 0
      if mv < 6
        # relocate cur[a] to position b
        state = (state * 48271) % 2147483647
        a = state % n
        state = (state * 48271) % 2147483647
        b = state % n
        if a != b
          v = cur[a]
          if a < b
            i = a
            while i < b
              cur[i] = cur[i + 1]
              i += 1
          else
            i = a
            while i > b
              cur[i] = cur[i - 1]
              i -= 1
          cur[b] = v
      else
        # reverse cur[a..b]
        state = (state * 48271) % 2147483647
        a = state % n
        state = (state * 48271) % 2147483647
        b = a + 2 + state % 22
        b = n - 1 if b > n - 1
        lo = a
        hi = b
        while lo < hi
          t = cur[lo]
          cur[lo] = cur[hi]
          cur[hi] = t
          lo += 1
          hi -= 1
      f = flops_for_typed_order(cur)
      scores += 1
      if f <= cur_f + tt
        cur_f = f
        if f < best_f
          best_f = f
          i = 0
          while i < n
            best[i] = cur[i]
            i += 1
      else
        # revert: inverse relocate (b -> a) or re-reverse the segment
        if mv < 6
          if a != b
            v = cur[b]
            if b < a
              i = b
              while i < a
                cur[i] = cur[i + 1]
                i += 1
            else
              i = b
              while i > a
                cur[i] = cur[i - 1]
                i -= 1
            cur[a] = v
        else
          lo = a
          hi = b
          while lo < hi
            t = cur[lo]
            cur[lo] = cur[hi]
            cur[hi] = t
            lo += 1
            hi -= 1
    [best, best_f]
