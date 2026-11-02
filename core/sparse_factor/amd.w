+ SparseAnalysis
  # Minimum-degree ordering on the quotient graph: approximate minimum
  # degree in the style of Amestoy, Davis & Duff (1996) — supervariables
  # with hash-based indistinguishability merging, element absorption
  # (aggressive), and mass elimination. The explicit elimination game this
  # replaces materialized every clique — Θ(fill) time and Θ(n²/32) bitset
  # memory, quadratic on dense endgames — while the quotient graph stays
  # O(nnz)-sized, the near-linear inner loop production orderings use, so
  # patterns with n in the hundreds of thousands order in well under a
  # second. Deterministic: head-insertion bucket lists and index-order
  # scans fix every tie. Returns the elimination order (old indices),
  # eliminated supervariable blocks expanded lowest index first.
  -> min_degree_ordering
    return [] if @pattern.rows == 0
    amd_ordering_of(@fri, @fci, @pattern.nnz)

  # The quotient-graph AMD core over explicit COO index arrays (same
  # vertex count as the pattern). Split out so relabelled copies of the
  # pattern can be ordered without constructing a new SparsePattern.
  -> amd_ordering_of(ri, ci, m)
    amd_core(@pattern.rows, ri, ci, m)

  # Same core over an arbitrary vertex count — nested dissection uses it
  # to order induced subgraphs and separators.
  -> amd_core(nn, ri, ci, m, dense_alpha = 10, aggressive = 1, tie_mode = 0, max_iw_words = 0)
    n = nn
    none = 4294967295
    # --- symmetric, deduped, diagonal-free adjacency in one u32 pool ---
    len = u32[n]
    k = 0
    while k < m
      r = ri[k]
      c = ci[k]
      if r != c
        len[r] = len[r] + 1
        len[c] = len[c] + 1
      k += 1
    pe = u32[n]
    total = 0
    i = 0
    while i < n
      pe[i] = total
      total += len[i]
      len[i] = 0
      i += 1
    iwlen = total * 2 + n + 64
    # Optional bounded lane for speculative portfolio candidates.  Allocate
    # the complete cap once so a grow cannot leave both old and new buffers
    # live.  The ordinary public AMD path passes zero and retains its existing
    # geometric growth behavior.
    return [] if max_iw_words < 0
    return [] if max_iw_words > 0 && iwlen > max_iw_words
    iwlen = max_iw_words if max_iw_words > 0
    iw = u32[iwlen]
    k = 0
    while k < m
      r = ri[k]
      c = ci[k]
      if r != c
        iw[pe[r] + len[r]] = c
        len[r] = len[r] + 1
        iw[pe[c] + len[c]] = r
        len[c] = len[c] + 1
      k += 1
    mark = u32[n]
    i = 0
    while i < n
      p = pe[i]
      stop = p + len[i]
      q = p
      while p < stop
        j = iw[p]
        if mark[j] != i + 1
          mark[j] = i + 1
          iw[q] = j
          q += 1
        p += 1
      len[i] = q - pe[i]
      i += 1
    pfree = total
    # --- quotient-graph state ---
    nv = u32[n]        # supervariable size; 0 = absorbed or mass-eliminated
    degree = u32[n]    # variables: approx external degree; elements: |Le|
    elen = u32[n]      # leading element count in each variable's list
    w = u32[n]         # |Le \ Lme| for elements initialized this pivot
    einit = u32[n]     # pivot generation that initialized w[e]
    mark2 = u32[n]     # supervariable-comparison marks, own generation
    absorbed = u32[n]  # absorption parent (vars → principal, elems → element)
    inlme = u32[n]     # pivot-generation mark: member of the current Lme
    head = u32[n]      # degree buckets (head-insert, doubly linked)
    dtail = u32[n]     # bucket tails when tie_mode=1 (FIFO)
    dnext = u32[n]
    dlast = u32[n]
    hhead = u32[n]     # supervariable-detection hash buckets
    hnext = u32[n]
    hash_ = u32[n]
    scratch = u32[n]
    pivots = u32[n]
    i = 0
    while i < n
      nv[i] = 1
      degree[i] = len[i]
      absorbed[i] = none
      head[i] = none
      dtail[i] = none
      hhead[i] = none
      i += 1
    # Dense-row deferral (reference AMD, dense_alpha = 10): a variable
    # whose degree exceeds min(max(16, floor(10·sqrt(n))), n) is removed
    # from the graph up front (nv = 0 hides it from every scan) and
    # appended after the last pivot block.
    dense_t = n
    if dense_alpha >= 0
      s = 0
      dense_target = dense_alpha * dense_alpha * n
      while (s + 1) * (s + 1) <= dense_target
        s += 1
      dense_t = s
      dense_t = 16 if dense_t < 16
      dense_t = n if dense_t > n
    densemark = u32[n]
    nel = 0
    ndense = 0
    # LIFO head-insert in ascending index order — the reference
    # tie-break: the bucket head is the highest-index variable.
    i = 0
    while i < n
      d = degree[i]
      if d > dense_t
        densemark[i] = 1
        nv[i] = 0
        nel += 1
        ndense += 1
      elsif tie_mode == 1
        dnext[i] = none
        dlast[i] = dtail[d]
        if dtail[d] == none
          head[d] = i
        else
          dnext[dtail[d]] = i
        dtail[d] = i
      else
        dnext[i] = head[d]
        dlast[i] = none
        dlast[head[d]] = i if head[d] != none
        head[d] = i
      i += 1
    cmpgen = 1
    mindeg = 0
    pcount = 0
    pgen = 1
    while nel < n
      while head[mindeg] == none
        mindeg += 1
      me = head[mindeg]
      head[mindeg] = dnext[me]
      dlast[dnext[me]] = none if dnext[me] != none
      dtail[mindeg] = none if head[mindeg] == none
      nel += nv[me]
      pivots[pcount] = me
      pcount += 1
      # --- assemble Lme: still-alive union of me's variables and of the
      # variables of me's elements; members leave the degree lists ---
      if pfree + n + 1 > iwlen
        return [] if max_iw_words > 0
        nlen = iwlen * 2
        nlen = pfree + n + n + 64 if nlen < pfree + n + n + 64
        niw = u32[nlen]
        q = 0
        while q < pfree
          niw[q] = iw[q]
          q += 1
        iw = niw
        iwlen = nlen
      lme = pfree
      degme = 0
      p = pe[me] + elen[me]
      stop = pe[me] + len[me]
      while p < stop
        j = iw[p]
        if j != me && nv[j] > 0 && inlme[j] != pgen
          inlme[j] = pgen
          degme += nv[j]
          dn = dnext[j]
          dl = dlast[j]
          if dl == none
            head[degree[j]] = dn
          else
            dnext[dl] = dn
          dlast[dn] = dl if dn != none
          dtail[degree[j]] = dl if tie_mode == 1 && dn == none
          iw[pfree] = j
          pfree += 1
        p += 1
      p = pe[me]
      stop = pe[me] + elen[me]
      while p < stop
        e = iw[p]
        if absorbed[e] == none
          q = pe[e]
          qstop = pe[e] + len[e]
          while q < qstop
            j = iw[q]
            if j != me && nv[j] > 0 && inlme[j] != pgen
              inlme[j] = pgen
              degme += nv[j]
              dn = dnext[j]
              dl = dlast[j]
              if dl == none
                head[degree[j]] = dn
              else
                dnext[dl] = dn
              dlast[dn] = dl if dn != none
              dtail[degree[j]] = dl if tie_mode == 1 && dn == none
              iw[pfree] = j
              pfree += 1
            q += 1
          absorbed[e] = me
        p += 1
      lme_end = pfree
      pe[me] = lme
      len[me] = lme_end - lme
      elen[me] = 0
      # --- scan 1: w[e] ← |Le \ Lme| for every element reachable from
      # Lme, gated by an explicit per-pivot generation so a stale value
      # can never be misread (clamped at zero: nv grows after an element
      # is built, so the subtraction can overshoot) ---
      p = lme
      while p < lme_end
        i2 = iw[p]
        nvi = nv[i2]
        q = pe[i2]
        qs = q + elen[i2]
        while q < qs
          e = iw[q]
          if absorbed[e] == none
            if einit[e] == pgen
              sub = w[e]
              sub = nvi if nvi < sub
              w[e] = w[e] - sub
            else
              einit[e] = pgen
              base = 0
              base = degree[e] - nvi if nvi <= degree[e]
              w[e] = base
          q += 1
        p += 1
      # --- scan 2: approximate degrees, aggressive element absorption,
      # mass elimination, list rebuild as [me, elements…, variables…] ---
      p = lme
      while p < lme_end
        i2 = iw[p]
        if nv[i2] != 0
          nvi = nv[i2]
          deg = 0
          scnt = 0
          q = pe[i2]
          qs = q + elen[i2]
          while q < qs
            e = iw[q]
            if absorbed[e] == none
              dext = w[e]
              if dext > 0
                deg += dext
                scratch[scnt] = e
                scnt += 1
              else
                # |Le \ Lme| = 0: me swallows e (aggressive absorption)
                if aggressive != 0
                  absorbed[e] = me
                else
                  scratch[scnt] = e
                  scnt += 1
            q += 1
          kept_elems = scnt
          q = pe[i2] + elen[i2]
          qs = pe[i2] + len[i2]
          while q < qs
            j = iw[q]
            if j != me && nv[j] > 0 && inlme[j] != pgen
              deg += nv[j]
              scratch[scnt] = j
              scnt += 1
            q += 1
          if scnt == 0
            # Li ⊆ Lme: i eliminates with the pivot (mass elimination);
            # it leaves the element being built, and its block joins me's
            absorbed[i2] = me
            nel += nvi
            degme -= nvi
            nv[me] = nv[me] + nvi
            nv[i2] = 0
            elen[i2] = 0
            len[i2] = 0
          else
            # keep min(old bound, freshly summed neighborhood); the
            # current element's degme − nv term is added at re-insertion,
            # after mass elimination settles degme and supervariable
            # merging settles nv
            degree[i2] = deg if deg < degree[i2]
            wpos = pe[i2]
            iw[wpos] = me
            wpos += 1
            hsum = 0
            t = 0
            while t < scnt
              iw[wpos] = scratch[t]
              hsum += scratch[t]
              wpos += 1
              t += 1
            elen[i2] = kept_elems + 1
            len[i2] = scnt + 1
            hsh = hsum % n
            hash_[i2] = hsh
            hnext[i2] = hhead[hsh]
            hhead[hsh] = i2
        p += 1
      # --- scan 3: supervariable detection — identical lists merge ---
      p = lme
      while p < lme_end
        i2 = iw[p]
        if nv[i2] != 0
          hsh = hash_[i2]
          a = hhead[hsh]
          hhead[hsh] = none
          while a != none
            an = hnext[a]
            if nv[a] != 0
              q = pe[a]
              qs = q + len[a]
              while q < qs
                mark2[iw[q]] = cmpgen
                q += 1
              b = an
              while b != none
                bn = hnext[b]
                if nv[b] != 0 && len[b] == len[a] && elen[b] == elen[a]
                  same = 1
                  q = pe[b]
                  qs2 = q + len[b]
                  while q < qs2
                    if mark2[iw[q]] != cmpgen
                      same = 0
                      break
                    q += 1
                  if same == 1
                    nv[a] = nv[a] + nv[b]
                    nv[b] = 0
                    absorbed[b] = a
                    elen[b] = 0
                    len[b] = 0
                b = bn
              cmpgen += 1
            a = an
        p += 1
      # --- finalize: survivors re-enter the degree lists ---
      p = lme
      while p < lme_end
        i2 = iw[p]
        if nv[i2] != 0
          d = degree[i2] + degme - nv[i2]
          cap = n - nel - nv[i2]
          d = cap if cap < d
          degree[i2] = d
          if tie_mode == 1
            dnext[i2] = none
            dlast[i2] = dtail[d]
            if dtail[d] == none
              head[d] = i2
            else
              dnext[dtail[d]] = i2
            dtail[d] = i2
          else
            dnext[i2] = head[d]
            dlast[i2] = none
            dlast[head[d]] = i2 if head[d] != none
            head[d] = i2
          mindeg = d if d < mindeg
          hhead[hash_[i2]] = none
        p += 1
      degree[me] = degme
      pgen += 1
    # --- expand pivot blocks: a variable eliminates at the first PIVOT on
    # its absorption chain (variable-merge and mass-elimination links only —
    # element-absorption links between eliminated pivots are assembly-tree
    # edges and must not move a block to a later pivot); blocks in
    # elimination order, ascending original index inside each block ---
    slot = u32[n]
    t = 0
    while t < n
      slot[t] = none
      t += 1
    t = 0
    while t < pcount
      slot[pivots[t]] = t
      t += 1
    gcount = u32[n]
    v = 0
    while v < n
      if densemark[v] == 0
        r = v
        while slot[r] == none
          r = absorbed[r]
        c2 = v
        while slot[c2] == none
          nxt = absorbed[c2]
          absorbed[c2] = r
          c2 = nxt
        gcount[slot[r]] = gcount[slot[r]] + 1
      v += 1
    pos = u32[n]
    run = 0
    t = 0
    while t < pcount
      pos[t] = run
      run += gcount[t]
      t += 1
    out = u32[n]
    v = 0
    while v < n
      if densemark[v] == 0
        r = v
        r = absorbed[v] if slot[v] == none
        s2 = slot[r]
        out[pos[s2]] = v
        pos[s2] = pos[s2] + 1
      v += 1
    k = n - ndense
    v = 0
    while v < n
      if densemark[v] == 1
        out[k] = v
        k += 1
      v += 1
    order = []
    k = 0
    while k < n
      order.push(out[k])
      k += 1
    order

  -> amf_core(nn, ri, ci, m, alpha10)
    # alpha10 packs a metric-variant id in its thousands digit:
    # 0 = AMF RMF; 1 SqDiv; 2 SqPure; 3 Ammf; 4 AmindNorm; 5 DegSqrt;
    # 6 DegP075; 7 DegP125; 8 DegPlusDegme; 9 DegDivNvDegme
    mvar = alpha10 / 1000
    alpha10 = alpha10 % 1000 if alpha10 >= 0
    n = nn
    none = 4294967295
    # --- symmetric, deduped, diagonal-free adjacency in one u32 pool ---
    len = u32[n]
    k = 0
    while k < m
      r = ri[k]
      c = ci[k]
      if r != c
        len[r] = len[r] + 1
        len[c] = len[c] + 1
      k += 1
    pe = u32[n]
    total = 0
    i = 0
    while i < n
      pe[i] = total
      total += len[i]
      len[i] = 0
      i += 1
    iwlen = total * 2 + n + 64
    iw = u32[iwlen]
    k = 0
    while k < m
      r = ri[k]
      c = ci[k]
      if r != c
        iw[pe[r] + len[r]] = c
        len[r] = len[r] + 1
        iw[pe[c] + len[c]] = r
        len[c] = len[c] + 1
      k += 1
    mark = u32[n]
    i = 0
    while i < n
      p = pe[i]
      stop = p + len[i]
      q = p
      while p < stop
        j = iw[p]
        if mark[j] != i + 1
          mark[j] = i + 1
          iw[q] = j
          q += 1
        p += 1
      len[i] = q - pe[i]
      i += 1
    pfree = total
    # --- quotient-graph state ---
    nv = u32[n]        # supervariable size; 0 = absorbed or mass-eliminated
    degree = u32[n]    # variables: approx external degree; elements: |Le|
    elen = u32[n]      # leading element count in each variable's list
    w = u32[n]         # |Le \ Lme| for elements initialized this pivot
    einit = u32[n]     # pivot generation that initialized w[e]
    mark2 = u32[n]     # supervariable-comparison marks, own generation
    absorbed = u32[n]  # absorption parent (vars → principal, elems → element)
    inlme = u32[n]     # pivot-generation mark: member of the current Lme
    head = u32[2 * n + 2]  # fine buckets [0..n], coarse above
    wf = w64[n]        # AMF working-fill accumulator / quantized score
    bkt = u32[n]       # the bucket each live vertex is filed under
    dnext = u32[n]
    dlast = u32[n]
    hhead = u32[n]     # supervariable-detection hash buckets
    hnext = u32[n]
    hash_ = u32[n]
    scratch = u32[n]
    pivots = u32[n]
    i = 0
    while i < n
      nv[i] = 1
      degree[i] = len[i]
      absorbed[i] = none
      head[i] = none
      hhead[i] = none
      wf[i] = 0
      i += 1
    i = n
    while i < 2 * n + 2
      head[i] = none
      i += 1
    # Dense-row deferral (reference AMD, dense_alpha = 10): a variable
    # whose degree exceeds min(max(16, floor(10·sqrt(n))), n) is removed
    # from the graph up front (nv = 0 hides it from every scan) and
    # appended after the last pivot block.
    if alpha10 < 0
      dense_t = n - 2
      dense_t = 16 if dense_t < 16
    else
      s = 0
      while (s + 1) * (s + 1) <= alpha10 * alpha10 * n
        s += 1
      dense_t = s / 10
      dense_t = 16 if dense_t < 16
      dense_t = n if dense_t > n
    densemark = u32[n]
    nel = 0
    ndense = 0
    # LIFO head-insert in ascending index order — the reference
    # tie-break: the bucket head is the highest-index variable.
    i = 0
    while i < n
      d = degree[i]
      if d > dense_t
        densemark[i] = 1
        nv[i] = 0
        nel += 1
        ndense += 1
      else
        bkt[i] = d
        dnext[i] = head[d]
        dlast[i] = none
        dlast[head[d]] = i if head[d] != none
        head[d] = i
      i += 1
    cmpgen = 1
    mindeg = 0
    pcount = 0
    pgen = 1
    while nel < n
      while head[mindeg] == none
        mindeg += 1
      me = head[mindeg]
      if mindeg > n
        # coarse bucket: linear scan for the smallest exact score
        cbest = wf[me]
        cv2 = dnext[me]
        while cv2 != none
          if wf[cv2] < cbest
            cbest = wf[cv2]
            me = cv2
          cv2 = dnext[cv2]
      if dlast[me] == none
        head[mindeg] = dnext[me]
      else
        dnext[dlast[me]] = dnext[me]
      dlast[dnext[me]] = dlast[me] if dnext[me] != none
      nel += nv[me]
      pivots[pcount] = me
      pcount += 1
      # --- assemble Lme: still-alive union of me's variables and of the
      # variables of me's elements; members leave the degree lists ---
      if pfree + n + 1 > iwlen
        nlen = iwlen * 2
        nlen = pfree + n + n + 64 if nlen < pfree + n + n + 64
        niw = u32[nlen]
        q = 0
        while q < pfree
          niw[q] = iw[q]
          q += 1
        iw = niw
        iwlen = nlen
      lme = pfree
      degme = 0
      p = pe[me] + elen[me]
      stop = pe[me] + len[me]
      while p < stop
        j = iw[p]
        if j != me && nv[j] > 0 && inlme[j] != pgen
          inlme[j] = pgen
          degme += nv[j]
          dn = dnext[j]
          dl = dlast[j]
          if dl == none
            head[bkt[j]] = dn
          else
            dnext[dl] = dn
          dlast[dn] = dl if dn != none
          iw[pfree] = j
          pfree += 1
        p += 1
      p = pe[me]
      stop = pe[me] + elen[me]
      while p < stop
        e = iw[p]
        if absorbed[e] == none
          q = pe[e]
          qstop = pe[e] + len[e]
          while q < qstop
            j = iw[q]
            if j != me && nv[j] > 0 && inlme[j] != pgen
              inlme[j] = pgen
              degme += nv[j]
              dn = dnext[j]
              dl = dlast[j]
              if dl == none
                head[bkt[j]] = dn
              else
                dnext[dl] = dn
              dlast[dn] = dl if dn != none
              iw[pfree] = j
              pfree += 1
            q += 1
          absorbed[e] = me
        p += 1
      lme_end = pfree
      pe[me] = lme
      len[me] = lme_end - lme
      elen[me] = 0
      # --- scan 1: w[e] ← |Le \ Lme| for every element reachable from
      # Lme, gated by an explicit per-pivot generation so a stale value
      # can never be misread (clamped at zero: nv grows after an element
      # is built, so the subtraction can overshoot) ---
      p = lme
      while p < lme_end
        i2 = iw[p]
        nvi = nv[i2]
        q = pe[i2]
        qs = q + elen[i2]
        while q < qs
          e = iw[q]
          if absorbed[e] == none
            if einit[e] == pgen
              sub = w[e]
              sub = nvi if nvi < sub
              w[e] = w[e] - sub
            else
              einit[e] = pgen
              base = 0
              base = degree[e] - nvi if nvi <= degree[e]
              w[e] = base
              wf[e] = 0
          q += 1
        p += 1
      # --- scan 2: approximate degrees, aggressive element absorption,
      # mass elimination, list rebuild as [me, elements…, variables…] ---
      p = lme
      while p < lme_end
        i2 = iw[p]
        if nv[i2] != 0
          nvi = nv[i2]
          deg = 0
          wf3 = 0
          wf4 = 0
          scnt = 0
          q = pe[i2]
          qs = q + elen[i2]
          while q < qs
            e = iw[q]
            if absorbed[e] == none
              dext = w[e]
              if dext > 0
                wf[e] = dext * (2 * degree[e] - dext - 1) if wf[e] == 0
                wf4 += wf[e]
                deg += dext
                scratch[scnt] = e
                scnt += 1
              else
                # |Le \ Lme| = 0: me swallows e (aggressive absorption)
                absorbed[e] = me
            q += 1
          kept_elems = scnt
          q = pe[i2] + elen[i2]
          qs = pe[i2] + len[i2]
          while q < qs
            j = iw[q]
            if j != me && nv[j] > 0 && inlme[j] != pgen
              deg += nv[j]
              wf3 += nv[j]
              scratch[scnt] = j
              scnt += 1
            q += 1
          if scnt == 0
            # Li ⊆ Lme: i eliminates with the pivot (mass elimination);
            # it leaves the element being built, and its block joins me's
            absorbed[i2] = me
            nel += nvi
            degme -= nvi
            nv[me] = nv[me] + nvi
            nv[i2] = 0
            elen[i2] = 0
            len[i2] = 0
          else
            # keep min(old bound, freshly summed neighborhood); the
            # current element's degme − nv term is added at re-insertion,
            # after mass elimination settles degme and supervariable
            # merging settles nv
            if degree[i2] < deg
              wf3 = 0
              wf4 = 0
            else
              degree[i2] = deg
            wf[i2] = wf4 + 2 * nvi * wf3
            wpos = pe[i2]
            iw[wpos] = me
            wpos += 1
            hsum = 0
            t = 0
            while t < scnt
              iw[wpos] = scratch[t]
              hsum += scratch[t]
              wpos += 1
              t += 1
            elen[i2] = kept_elems + 1
            len[i2] = scnt + 1
            hsh = hsum % n
            hash_[i2] = hsh
            hnext[i2] = hhead[hsh]
            hhead[hsh] = i2
        p += 1
      # --- scan 3: supervariable detection — identical lists merge ---
      p = lme
      while p < lme_end
        i2 = iw[p]
        if nv[i2] != 0
          hsh = hash_[i2]
          a = hhead[hsh]
          hhead[hsh] = none
          while a != none
            an = hnext[a]
            if nv[a] != 0
              q = pe[a]
              qs = q + len[a]
              while q < qs
                mark2[iw[q]] = cmpgen
                q += 1
              b = an
              while b != none
                bn = hnext[b]
                if nv[b] != 0 && len[b] == len[a] && elen[b] == elen[a]
                  same = 1
                  q = pe[b]
                  qs2 = q + len[b]
                  while q < qs2
                    if mark2[iw[q]] != cmpgen
                      same = 0
                      break
                    q += 1
                  if same == 1
                    wf[a] = wf[b] if wf[b] > wf[a]
                    nv[a] = nv[a] + nv[b]
                    nv[b] = 0
                    absorbed[b] = a
                    elen[b] = 0
                    len[b] = 0
                b = bn
              cmpgen += 1
            a = an
        p += 1
      # --- finalize: survivors re-enter the degree lists ---
      p = lme
      while p < lme_end
        i2 = iw[p]
        if nv[i2] != 0
          nvi2 = nv[i2]
          di = degree[i2]
          nleft = n - nel
          if di + degme > nleft
            rmf1 = di * (di - 1 + 2 * degme) - wf[i2]
            nd2 = nleft - nvi2
            degree[i2] = nd2
            dmn = degme - nvi2
            rmfn = nd2 * (nd2 - 1) - dmn * (dmn - 1)
            rmf = rmfn
            rmf = rmf1 if rmf1 < rmf
          else
            degree[i2] = di + degme - nvi2
            rmf = di * (di - 1 + 2 * degme) - wf[i2]
          if mvar == 0
            rmf = rmf / (nvi2 + 1)
          elsif mvar == 1
            rmf = di * di / (nvi2 + 1)
          elsif mvar == 2
            rmf = di * di
          elsif mvar == 3
            dd = di
            dd = 1 if dd < 1
            rmf = rmf / dd
          elsif mvar == 4
            rmf = (di * (di - 1) - wf[i2]) / (nvi2 + 1)
          else
            sq = 0
            sq += 1 while (sq + 1) * (sq + 1) <= di
            q4 = 0
            q4 += 1 while (q4 + 1) * (q4 + 1) <= sq
            rmf = sq if mvar == 5
            rmf = sq * q4 if mvar == 6
            rmf = di * q4 if mvar == 7
            rmf = di + degme / (nvi2 + 1) if mvar == 8
            rmf = (di + degme / 2) / (nvi2 + 1) if mvar == 9
          rmf = 1 if rmf < 1
          rmf = 2147483645 if rmf > 2147483645
          wf[i2] = rmf
          d = rmf
          if d > n
            pas = n / 8
            pas = 1 if pas < 1
            d = n + (d - n) / pas
            d = 2 * n if d > 2 * n
          bkt[i2] = d
          dnext[i2] = head[d]
          dlast[i2] = none
          dlast[head[d]] = i2 if head[d] != none
          head[d] = i2
          mindeg = d if d < mindeg
          hhead[hash_[i2]] = none
        p += 1
      degree[me] = degme
      pgen += 1
    # --- expand pivot blocks: a variable eliminates at the first PIVOT on
    # its absorption chain (variable-merge and mass-elimination links only —
    # element-absorption links between eliminated pivots are assembly-tree
    # edges and must not move a block to a later pivot); blocks in
    # elimination order, ascending original index inside each block ---
    slot = u32[n]
    t = 0
    while t < n
      slot[t] = none
      t += 1
    t = 0
    while t < pcount
      slot[pivots[t]] = t
      t += 1
    gcount = u32[n]
    v = 0
    while v < n
      if densemark[v] == 0
        r = v
        while slot[r] == none
          r = absorbed[r]
        c2 = v
        while slot[c2] == none
          nxt = absorbed[c2]
          absorbed[c2] = r
          c2 = nxt
        gcount[slot[r]] = gcount[slot[r]] + 1
      v += 1
    pos = u32[n]
    run = 0
    t = 0
    while t < pcount
      pos[t] = run
      run += gcount[t]
      t += 1
    out = u32[n]
    v = 0
    while v < n
      if densemark[v] == 0
        r = v
        r = absorbed[v] if slot[v] == none
        s2 = slot[r]
        out[pos[s2]] = v
        pos[s2] = pos[s2] + 1
      v += 1
    k = n - ndense
    v = 0
    while v < n
      if densemark[v] == 1
        out[k] = v
        k += 1
      v += 1
    order = []
    k = 0
    while k < n
      order.push(out[k])
      k += 1
    order

  # Exact minimum-degree by the explicit elimination game on bitset
  # rows (lowest-index tie-break). Quadratic in time and memory — kept
  # ONLY as a small-n portfolio arm for `best_ordering`, where its
  # different (often better) pivot basins complement quotient-graph AMD
  # on patterns up to a few thousand vertices.
  -> game_ordering_of(ri, ci, m)
    n = @pattern.rows
    words = (n + 31) >> 5
    full = 4294967295
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
    cnt = u32[n + 1]
    i = 0
    while i < n
      d = 0
      base = i * words
      wi = 0
      while wi < words
        d += ccall_nobox("__w_bit_ctpop_u32", adj[base + wi])
        wi += 1
      deg[i] = d
      cnt[d] = cnt[d] + 1
      i += 1
    nb = u32[words]
    nbrs = u32[n]
    order = []
    alive_cnt = n
    mindeg = 0
    while alive_cnt > 0
      while cnt[mindeg] == 0
        mindeg += 1
      v = -1
      wi = 0
      while wi < words
        aw = alive[wi]
        while aw != 0
          u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", aw)
          if deg[u] == mindeg
            v = u
            break
          aw = aw & (aw - 1)
        break if v >= 0
        wi += 1
      order.push(v)
      cnt[mindeg] = cnt[mindeg] - 1
      alive[v >> 5] = alive[v >> 5] ^ (1 << (v & 31))
      alive_cnt -= 1
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
      t = 0
      while t < nbcnt
        u = nbrs[t]
        old_d = deg[u]
        if old_d == alive_cnt
          newdeg = old_d - 1
        else
          ubase = u * words
          added = 0
          wi = 0
          while wi < words
            aw = nb[wi] & (adj[ubase + wi] ^ full)
            if aw != 0
              adj[ubase + wi] = adj[ubase + wi] | aw
              added += ccall_nobox("__w_bit_ctpop_u32", aw)
            wi += 1
          uw = ubase + (u >> 5)
          ubit = 1 << (u & 31)
          if (adj[uw] & ubit) != 0
            adj[uw] = adj[uw] ^ ubit
            added -= 1
          newdeg = old_d - 1 + added
        deg[u] = newdeg
        cnt[old_d] = cnt[old_d] - 1
        cnt[newdeg] = cnt[newdeg] + 1
        mindeg = newdeg if newdeg < mindeg
        t += 1
    order
