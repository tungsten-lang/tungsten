+ SparseAnalysis
  # Best-of-many fill-reducing ordering: AMD's pivot choices read the
  # vertex numbering through its tie-breaks, so ordering a relabelled
  # copy Q·A·Qᵀ and composing back through Q is a genuinely different
  # minimum-degree ordering for the cost of one AMD pass — a randomized
  # restart with no second algorithm. Runs `restarts` deterministic
  # relabellings (LCG-seeded Fisher–Yates), scores every candidate with
  # the exact Σc² flop predictor, and returns the cheapest (predicted
  # fill breaks ties). restarts = 0 is plain `min_degree_ordering`.
  # #14 supervariable seeding: vertices with identical closed neighborhoods
  # are indistinguishable — any fill-optimal order can eliminate them
  # consecutively. Order the quotient graph (one representative per class,
  # class-to-class edges) with AMD/AMF, expand each representative into its
  # class, and let the exact scorer judge. Returns [] when compression is
  # weak (classes > 85% of n). Classes are found by sorting closed-adjacency
  # signatures (hash of sorted neighbor list incl. self).
  -> supervar_orders(nn, ri, ci, m)
    none = 4294967295
    deg = u32[nn]
    k = 0
    while k < m
      deg[ri[k]] += 1
      k += 1
    xadj = u32[nn + 1]
    i = 0
    while i < nn
      xadj[i + 1] = xadj[i] + deg[i] + 1
      i += 1
    fillc = u32[nn]
    adjl = u32[xadj[nn]]
    i = 0
    while i < nn
      adjl[xadj[i]] = i
      fillc[i] = 1
      i += 1
    k = 0
    while k < m
      a = ri[k]
      b = ci[k]
      if a != b
        adjl[xadj[a] + fillc[a]] = b
        fillc[a] += 1
      k += 1
    # signature: sorted closed neighborhood hashed (64-bit-safe mixing in
    # the 48-bit fixnum range) + length; exact equality verified on collision
    sig = []
    i = 0
    while i < nn
      lst = []
      p = xadj[i]
      while p < xadj[i] + fillc[i]
        lst.push(adjl[p])
        p += 1
      lst = lst.sort
      h = 1469598103
      j = 0
      while j < lst.size
        h = ((h ^ lst[j]) * 16777619) % 281474976710597
        j += 1
      sig.push([h * 4096 + (lst.size % 4096), i])
      i += 1
    sig = sig.sort_by -> (pr) pr[0]
    rep = u32[nn]
    i = 0
    while i < nn
      rep[i] = i
      i += 1
    cls_of = u32[nn]
    ncls = 0
    i = 0
    while i < nn
      j = i
      while j + 1 < nn && sig[j + 1][0] == sig[i][0]
        j += 1
      # exact verification within the run: compare closed lists
      t = i
      while t <= j
        v = sig[t][1]
        if t == i
          cls_of[v] = ncls
          rep[v] = v
        else
          u = sig[i][1]
          same = fillc[u] == fillc[v]
          if same
            la = []
            lb = []
            p = xadj[u]
            while p < xadj[u] + fillc[u]
              la.push(adjl[p])
              p += 1
            p = xadj[v]
            while p < xadj[v] + fillc[v]
              lb.push(adjl[p])
              p += 1
            la = la.sort
            lb = lb.sort
            # closed neighborhoods: replace self by the other
            q3 = 0
            while q3 < la.size && same
              x = la[q3]
              y = lb[q3]
              x = v if x == u
              y = v if y == u
              same = 0 == 1 if x != y
              q3 += 1
          if same
            cls_of[v] = ncls
            rep[v] = u
          else
            ncls += 1
            cls_of[v] = ncls
            rep[v] = v
        t += 1
      ncls += 1
      i = j + 1
    return [] if ncls * 100 > nn * 85 || ncls < 4
    # quotient graph edges between classes
    cid = u32[nn]
    i = 0
    while i < nn
      cid[i] = cls_of[i]
      i += 1
    qri = []
    qci = []
    k = 0
    while k < m
      a = cid[ri[k]]
      b = cid[ci[k]]
      if a != b
        qri.push(a)
        qci.push(b)
      k += 1
    i = 0
    while i < ncls
      qri.push(i)
      qci.push(i)
      i += 1
    # members per class (in index order) for expansion
    chead = u32[ncls]
    cnext = u32[nn]
    i = 0
    while i < ncls
      chead[i] = none
      i += 1
    i = nn
    while i > 0
      i -= 1
      c = cid[i]
      cnext[i] = chead[c]
      chead[c] = i
    outs = []
    qm = qri.size
    variant = 0
    while variant < 3
      qord = amd_core(ncls, qri, qci, qm) if variant == 0
      qord = amf_core(ncls, qri, qci, qm, 25) if variant == 1
      qord = amf_core(ncls, qri, qci, qm, 8025) if variant == 2
      full = []
      i = 0
      while i < ncls
        c = qord[i]
        v = chead[c]
        while v != none
          full.push(v)
          v = cnext[v]
        i += 1
      outs.push(full) if full.size == nn
      variant += 1
    outs

  # One subtree-block refinement on a private sub-analysis (thread worker).
  # Pushes [order, flops, seed_flops] into out.
  -> .refine_block(kind, bn, nelim, bri, bci, bseed, ils_words, stream, out)
    sub = SparseAnalysis.new(SparsePattern.new(bn, bn, bri, bci))
    seed_flops = sub.predicted_flops
    seed_flops = sub.predicted_prefix_flops(nelim) if nelim < bn
    ref = [bseed, seed_flops]
    if kind == 1
      bnz = bri.size
      bnz = 1000 if bnz < 1000
      ev = ils_words / (bnz * 4)
      ev = 50000 if ev > 50000
      ref = sub.anneal_refine(bseed, seed_flops, ev, stream) if ev > 200
    else
      if nelim < bn
        ref = sub.rgreedy_prefix_refine(
          bn, sub.typed_ri, sub.typed_ci, sub.pattern.nnz,
          bseed, seed_flops, ils_words, [stream, nelim])
      else
        ref = sub.rgreedy_refine(
          bn, sub.typed_ri, sub.typed_ci, sub.pattern.nnz,
          bseed, seed_flops, ils_words, stream)
    out.push([ref[0], ref[1], seed_flops])
    0

  -> typed_ri
    @fri

  -> typed_ci
    @fci

  # One relabel-multistart worker: seeds gi+1, gi+1+gt, ... on a private
  # analysis instance (class-level: a worker thread must not touch the
  # spawning instance's ivars). Returns [seed, kind(0 amd,1 amf,2 game),
  # flops, fill, order] entries; the caller merges them in seed order.
  -> .relabel_group(pat, gi, gt, restarts, use_game, alpha_diverse, res)
    n = pat.rows
    m = pat.nnz
    wa = SparseAnalysis.new(pat)
    ri = wa.typed_ri
    ci = wa.typed_ci
    q = u32[n]
    qinv = u32[n]
    ri2 = u32[m]
    ci2 = u32[m]
    seen_f = []
    extra = 0
    seed = 1 + gi
    r = gi
    while r < restarts + extra
      i = 0
      while i < n
        q[i] = i
        i += 1
      state = (seed * 2654435761) % 2147483646 + 1
      i = n - 1
      while i > 0
        state = (state * 48271) % 2147483647
        j = state % (i + 1)
        t = q[i]
        q[i] = q[j]
        q[j] = t
        i -= 1
      i = 0
      while i < n
        qinv[q[i]] = i
        i += 1
      k = 0
      while k < m
        ri2[k] = q[ri[k]]
        ci2[k] = q[ci[k]]
        k += 1
      cand = wa.amd_ordering_of(ri2, ci2, m)
      i = 0
      while i < n
        cand[i] = qinv[cand[i]]
        i += 1
      pred = wa.predictions_for_order(cand)
      res.push([seed, 0, pred[1], pred[0], cand])
      dupf = 0 == 1
      sf = 0
      while sf < seen_f.size
        dupf = 0 == 0 if seen_f[sf] == pred[1]
        sf += 1
      seen_f.push(pred[1])
      if dupf
        extra += gt if extra < restarts
        seed += gt
        r += gt
        next
      # Cost-neutral basin diversity: cycle the dense threshold across the
      # existing restart slots instead of launching additional candidates.
      alpha = 25
      if alpha_diverse != 0
        alpha = 50 if (seed & 3) == 2
        alpha = 100 if (seed & 3) == 3
        alpha = 0 - 1 if (seed & 3) == 0
      cand = wa.amf_core(n, ri2, ci2, m, alpha)
      i = 0
      while i < n
        cand[i] = qinv[cand[i]]
        i += 1
      pred = wa.predictions_for_order(cand)
      res.push([seed, 1, pred[1], pred[0], cand])
      if use_game
        cand = wa.game_ordering_of(ri2, ci2, m)
        i = 0
        while i < n
          cand[i] = qinv[cand[i]]
          i += 1
        pred = wa.predictions_for_order(cand)
        res.push([seed, 2, pred[1], pred[0], cand])
      seed += gt
      r += gt
    0

  # Dense bitset used by degree-3 core lifting.  Cap this single n-by-n
  # bitmap at 64 MiB (16,777,216 u32 words); the later whole-graph rgreedy
  # fallback has its own admission policy and remains available through
  # n=45,000.  Keeping the calculation here makes the allocation boundary
  # explicit and independently testable before any quadratic buffer exists.
  -> .core_lift_fits?(n)
    words = (n + 31) >> 5
    n * words <= 16777216

  # Worst-case bytes allocated by sparse_core_lift_reduce.  The live-edge hash
  # has capacity next_pow2(2*(m+3n+16)); every pivot of degree at most three
  # can append at most three fill edges.  The remaining terms cover the two
  # directed-edge pools, vertex/heap/output arrays, and conservative headers.
  # This is a resource model only: it contains no quality-derived shape band.
  -> .sparse_core_lift_workspace_bytes(n, m)
    return 0 - 1 if n <= 0 || m < 0
    max_edges = m + 3 * n + 16
    hash_cap = 16
    while hash_cap < 2 * max_edges
      hash_cap = hash_cap << 1
    return 0 - 1 if hash_cap > 16777216
    # 85*n includes the kernel-local core-id buffer; fixed slack covers all
    # typed-array headers and the four-word live-neighbor scratch.
    8 * hash_cap + 16 * max_edges + 85 * n + 8 * m + 4096

  -> .sparse_core_lift_workspace_fits?(n, m)
    bytes = SparseAnalysis.sparse_core_lift_workspace_bytes(n, m)
    bytes >= 0 && bytes <= 134217728

  # Capacity for the residual AMD's single preallocated quotient-graph pool.
  # The reducer's arrays may remain live until the candidate is rescored, so
  # count its full peak plus AMD's linear arrays.  Start with the exact initial
  # AMD pool and permit at most its ordinary first doubling when it fits.
  -> .sparse_core_lift_amd_iw_words(n, m, core_n, core_edges)
    reduce_bytes = SparseAnalysis.sparse_core_lift_workspace_bytes(n, m)
    return 0 - 1 if reduce_bytes < 0
    return 0 - 1 if core_n <= 0 || core_n >= n
    return 0 - 1 if core_edges < 0 || core_edges > m
    base_bytes = reduce_bytes + 116 * core_n + 4096
    initial_words = 4 * core_edges + core_n + 64
    available_words = (134217728 - base_bytes) / 4
    return 0 - 1 if available_words < initial_words
    target_words = 2 * initial_words
    return available_words if available_words < target_words
    target_words

  -> .sparse_core_lift_candidate_fits?(n, m, core_n, core_edges)
    SparseAnalysis.sparse_core_lift_amd_iw_words(
      n, m, core_n, core_edges) >= 0

  # Fail-closed admission for the large sparse block-cut sibling. The estimate
  # covers its simultaneously live flat CSR, Tarjan stacks/components, block
  # incidence, traversal, ordering, and largest local-AMD buffers. The
  # conservative base is 192*n + 32*m plus one MiB of headers/boxed records;
  # the separately computed AMD pool fills the remaining 128 MiB envelope.
  # `m` is intentionally the stored (pre-deduplication) count: duplicates,
  # opposite entries, and self entries only make the estimate conservative.
  # Local AMD gets a single bounded pool, so its
  # otherwise growable quotient graph cannot exceed this admission model.
  -> .biconn_amd_iw_words(n, m)
    return 0 - 1 if n <= 1 || m < 0
    base_bytes = 192 * n + 32 * m + 1048576
    initial_words = 4 * m + n + 64
    available_words = (134217728 - base_bytes) / 4
    return 0 - 1 if available_words < initial_words
    target_words = 2 * initial_words
    return available_words if available_words < target_words
    target_words

  -> .biconn_candidate_fits?(n, m)
    SparseAnalysis.biconn_amd_iw_words(n, m) >= 0

  # Portfolio admission helpers are deliberately functions of algorithmic
  # work/resource models only.  Keeping them explicit makes boundary tests
  # independent of any benchmark corpus.
  -> .rgsub_coordinator_workspace_bytes(n, m)
    return 0 - 1 if n <= 0 || m < 0
    # Include the boxed candidate array and sort_by's decorated copy at their
    # simultaneous peak, not just the flat CSR and score vectors.
    256 * n + 24 * m + 1048576

  -> .rgsub_worker_workspace_bytes(n, m)
    return 0 - 1 if n <= 0 || m < 0
    12 * n * ((n + 31) >> 5) + 144 * n + 32 * m + 4096

  -> .rgsub_queued_job_workspace_bytes(n, m)
    return 0 - 1 if n <= 0 || m < 0
    # Two exact-size u32 edge arrays, one u32 identity seed, the growable
    # result order retained until every worker joins, and conservative
    # typed-array/job/result headers. A polymorphic result can approach 2*n
    # slots, hence the additional 16*n bytes beyond the typed seed.
    8 * m + 20 * n + 4096

  -> .terminal_rgsub_portfolio_fits?(n, m, budget)
    return false if n <= 0 || m < 0 || budget <= 0
    # Coordinator CSR, etree/postorder, candidate records, and score buffers.
    # Worker-local dense bitmaps have their own aggregate cap in flush_blocks.
    return false if SparseAnalysis.rgsub_coordinator_workspace_bytes(
      n, m) > 134217728
    8 * (n + m) <= budget / 16

  -> .biconn_portfolio_fits?(n, m, budget)
    return false if budget <= 0
    return false if !SparseAnalysis.biconn_candidate_fits?(n, m)
    8 * n + 4 * m <= budget / 16

  # Exact sparse edge set for the large-matrix core lift.  Keys are
  # `lo * n + hi + 2`; zero is an empty slot and one a tombstone.  The 128 MiB
  # workspace check bounds n tightly enough that every key and hash operation
  # stays in signed i64. Open addressing is bounded by the table size so every
  # corruption/capacity failure closes the candidate lane without affecting
  # the incumbent.
  # Sparse degree-bounded exact elimination.  Unlike the dense n-by-n
  # bitmap lane, memory is O(nnz+n): adjacency is an append-only linked pool
  # and a live-edge hash set supplies exact fill membership.  Degree<=3 is a
  # useful invariant here: each pivot inserts at most three clique edges and
  # removes its degree edges, so the live edge count never increases.  The
  # append/hash capacities include all three possible *new* keys per pivot,
  # even though most are already present.
  #
  # Result layout:
  #   [prefix_u32, prefix_n, core_vertices_u32, core_n,
  #    core_ri_u32, core_ci_u32, core_edges, prefix_flops]
  # `core_ri/core_ci` contain one COO entry per undirected residual edge.
  -> .sparse_core_lift_reduce(n, ri, ci, m, max_row_degree = 3, max_core_n = nil, max_core_edges = nil)
    return nil if !SparseAnalysis.sparse_core_lift_workspace_fits?(n, m)
    return nil if ri.size < m || ci.size < m
    return nil if max_row_degree < 0 || max_row_degree > 3
    max_core_n = n if max_core_n == nil
    max_core_edges = m if max_core_edges == nil
    return nil if max_core_n <= 0 || max_core_n > n
    return nil if max_core_edges < 0 || max_core_edges > m

    max_edges_seen = m + 3 * n + 16
    hash_cap = 16
    while hash_cap < 2 * max_edges_seen
      hash_cap = hash_cap << 1
    return nil if hash_cap > 16777216
    directed_cap = 2 * max_edges_seen
    heap_cap = 4 * n + 16
    edge_keys = i64[hash_cap]
    to = u32[directed_cap]
    next_edge = u32[directed_cap]
    head = u32[n]
    degree = u32[n]
    alive = u8[n]
    heap_d = i64[heap_cap]
    heap_v = i64[heap_cap]
    prefix = u32[n]
    core_vertices = u32[n]
    core_ri = u32[m]
    core_ci = u32[m]
    stats = i64[4]
    ok = sparse_core_lift_kernel_unsafe(
      n, ri, ci, m, max_row_degree, max_core_n, max_core_edges,
      edge_keys, hash_cap - 1, to, next_edge, head, degree, alive,
      directed_cap, heap_d, heap_v, heap_cap, prefix, core_vertices,
      core_ri, core_ci, stats)
    return nil if ok == 0
    return [prefix, stats[0], core_vertices, stats[1],
            core_ri, core_ci, stats[2], stats[3]]

  -> best_ordering(restarts = 8, ils_words = 0, stream = 0, warm = nil, diverse_pool = 0, alpha_diverse = 0, watcher_minl = 0)
    n = @pattern.rows
    return [] if n == 0
    watch_o = nil
    watch_f = nil
    restarts = 12 if restarts < 12 && @pattern.nnz <= 400000
    best = min_degree_ordering
    pred = predictions_for_order(best)
    best_fill = pred[0]
    best_flops = pred[1]
    @pool_structural = diverse_pool == 0 ? 0 : 1
    base_hash = @pool_structural == 0 ? 0 : order_hash(best)
    @cand_pool = [[best_flops, best, base_hash]]
    # warm start: an inherited best-known order competes from the top and
    # seeds every downstream descent, so search rounds compound
    if warm != nil && warm.size == n
      pred = predictions_for_order(warm)
      pool_consider(pred[1], warm)
      if pred[1] < best_flops
        best = warm
        best_fill = pred[0]
        best_flops = pred[1]
    m = @pattern.nnz
    ri = @fri
    ci = @fci
    nvars = 3
    nvars = 12 if n <= 20000 && m <= 260000
    a10 = 0
    while a10 < nvars
      al = 25
      al = 50 if a10 == 1
      al = 100 if a10 == 2
      al = 1050 if a10 == 3
      al = 2050 if a10 == 4
      al = 3050 if a10 == 5
      al = 4050 if a10 == 6
      al = 5050 if a10 == 7
      al = 6050 if a10 == 8
      al = 7050 if a10 == 9
      al = 8050 if a10 == 10
      al = 9050 if a10 == 11
      cand = amf_core(n, ri, ci, m, al)
      if a10 == 0
        cand2x = amf_core(n, ri, ci, m, 0 - 1)
        pred = predictions_for_order(cand2x)
        pool_consider(pred[1], cand2x)
        if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
          best = cand2x
          best_fill = pred[0]
          best_flops = pred[1]
      pred = predictions_for_order(cand)
      pool_consider(pred[1], cand)
      if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
        best = cand
        best_fill = pred[0]
        best_flops = pred[1]
      a10 += 1
    use_game = n <= 4000
    if use_game
      cand = game_ordering_of(ri, ci, m)
      pred = predictions_for_order(cand)
      if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
        best = cand
        best_fill = pred[0]
        best_flops = pred[1]
    if n >= 2000 && n <= 50000
      cand = nd_ordering_of(n, ri, ci, m)
      pred = predictions_for_order(cand)
      if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
        best = cand
        best_fill = pred[0]
        best_flops = pred[1]
    if n >= 2000 && n <= 150000
      cand = nd_levelset_of(n, ri, ci, m)
      pred = predictions_for_order(cand)
      if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
        best = cand
        best_fill = pred[0]
        best_flops = pred[1]
    # #14 supervariable-compressed seeds: benched neutral (0 better / 0 worse
    # on b40) — disabled; supervar_orders kept for reference
    svo = []
    si = 0
    while si < svo.size
      cand = svo[si]
      pred = predictions_for_order(cand)
      pool_consider(pred[1], cand)
      if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
        best = cand
        best_fill = pred[0]
        best_flops = pred[1]
      si += 1
    q = u32[n]
    qinv = u32[n]
    ri2 = u32[m]
    ci2 = u32[m]
    seed = 1
    r = 0
    seen_f = []
    extra = 0
    while r < restarts + extra
      # deterministic Fisher–Yates from a 31-bit LCG
      i = 0
      while i < n
        q[i] = i
        i += 1
      state = (seed * 2654435761) % 2147483646 + 1
      i = n - 1
      while i > 0
        state = (state * 48271) % 2147483647
        j = state % (i + 1)
        t = q[i]
        q[i] = q[j]
        q[j] = t
        i -= 1
      i = 0
      while i < n
        qinv[q[i]] = i
        i += 1
      k = 0
      while k < m
        ri2[k] = q[ri[k]]
        ci2[k] = q[ci[k]]
        k += 1
      cand = amd_ordering_of(ri2, ci2, m)
      i = 0
      while i < n
        cand[i] = qinv[cand[i]]
        i += 1
      pred = predictions_for_order(cand)
      if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
        best = cand
        best_fill = pred[0]
        best_flops = pred[1]
      dupf = 0 == 1
      sf = 0
      while sf < seen_f.size
        dupf = 0 == 0 if seen_f[sf] == pred[1]
        sf += 1
      seen_f.push(pred[1])
      if dupf
        extra += 1 if extra < restarts
        seed += 1
        r += 1
        next
      # Diversify existing AMF restart slots without increasing the pass
      # count.  The exact scorer retains only a better composed ordering.
      alpha = 25
      if alpha_diverse != 0
        alpha = 50 if (seed & 3) == 2
        alpha = 100 if (seed & 3) == 3
        alpha = 0 - 1 if (seed & 3) == 0
      cand = amf_core(n, ri2, ci2, m, alpha)
      i = 0
      while i < n
        cand[i] = qinv[cand[i]]
        i += 1
      pred = predictions_for_order(cand)
      pool_consider(pred[1], cand)
      if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
        best = cand
        best_fill = pred[0]
        best_flops = pred[1]
      if use_game
        cand = game_ordering_of(ri2, ci2, m)
        i = 0
        while i < n
          cand[i] = qinv[cand[i]]
          i += 1
        pred = predictions_for_order(cand)
        if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
          best = cand
          best_fill = pred[0]
          best_flops = pred[1]
      seed += 1
      r += 1
    if n <= 25000
      cand = predcorr_ordering_of(n, ri, ci, m, 150000000)
      if cand.size == n
        pred = predictions_for_order(cand)
        if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
          best = cand
          best_fill = pred[0]
          best_flops = pred[1]
    core_lift_ok = SparseAnalysis.core_lift_fits?(n)
    if ils_words > 0 && n <= 150000 && core_lift_ok
      # CORE-LIFT: exactly eliminate every vertex whose live degree stays
      # <= 3 (ascending degree, then index) as one fixed prefix on the
      # bitset fill graph. The residual core is the exact fill graph after
      # the prefix, Σc² splits as prefix + core, and the ILS searches the
      # much smaller core instead of re-eliminating the periphery on
      # every restart.
      words = (n + 31) >> 5
      full = 4294967295
      adjc = u32[n * words]
      k = 0
      while k < m
        r = ri[k]
        c = ci[k]
        if r != c
          adjc[r * words + (c >> 5)] = adjc[r * words + (c >> 5)] | (1 << (c & 31))
          adjc[c * words + (r >> 5)] = adjc[c * words + (r >> 5)] | (1 << (r & 31))
        k += 1
      alivec = u32[words]
      i = 0
      while i < words
        alivec[i] = full
        i += 1
      tailb = n & 31
      alivec[words - 1] = (1 << tailb) - 1 if tailb != 0
      degc = u32[n]
      cntc = u32[n + 1]
      i = 0
      while i < n
        d = 0
        base = i * words
        wi = 0
        while wi < words
          d += ccall_nobox("__w_bit_ctpop_u32", adjc[base + wi])
          wi += 1
        degc[i] = d
        cntc[d] = cntc[d] + 1
        i += 1
      nbc = u32[words]
      nbrsc = u32[n]
      prefix_order = u32[n]
      pcount2 = 0
      prefix_cost = 0
      alive_left = n
      mind = 0
      while alive_left > 0
        while cntc[mind] == 0
          mind += 1
        break if mind > 3
        v = 4294967295
        wi = 0
        while wi < words
          aw = alivec[wi]
          while aw != 0
            u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", aw)
            if degc[u] == mind
              v = u
              break
            aw = aw & (aw - 1)
          break if v != 4294967295
          wi += 1
        cc = degc[v] + 1
        prefix_cost += cc * cc
        prefix_order[pcount2] = v
        pcount2 += 1
        cntc[mind] = cntc[mind] - 1
        alivec[v >> 5] = alivec[v >> 5] ^ (1 << (v & 31))
        alive_left -= 1
        vbase = v * words
        nbcnt = 0
        wi = 0
        while wi < words
          nw = adjc[vbase + wi] & alivec[wi]
          nbc[wi] = nw
          while nw != 0
            nbrsc[nbcnt] = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", nw)
            nbcnt += 1
            nw = nw & (nw - 1)
          wi += 1
        t = 0
        while t < nbcnt
          u = nbrsc[t]
          old_d = degc[u]
          if old_d == alive_left
            newdeg = old_d - 1
          else
            ubase = u * words
            added = 0
            wi = 0
            while wi < words
              aw = nbc[wi] & (adjc[ubase + wi] ^ full)
              if aw != 0
                adjc[ubase + wi] = adjc[ubase + wi] | aw
                added += ccall_nobox("__w_bit_ctpop_u32", aw)
              wi += 1
            uw = ubase + (u >> 5)
            ubit = 1 << (u & 31)
            if (adjc[uw] & ubit) != 0
              adjc[uw] = adjc[uw] ^ ubit
              added -= 1
            newdeg = old_d - 1 + added
          cntc[old_d] = cntc[old_d] - 1
          degc[u] = newdeg
          cntc[newdeg] = cntc[newdeg] + 1
          mind = newdeg if newdeg < mind
          t += 1
      core_n = alive_left
      if core_n >= 30 && core_n * 10 <= n * 9 && core_n <= 45000
        # remap the core and extract its (filled) edges
        cid2 = u32[n]
        core_vs = u32[core_n]
        ci2p = 0
        wi = 0
        while wi < words
          aw = alivec[wi]
          while aw != 0
            u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", aw)
            cid2[u] = ci2p
            core_vs[ci2p] = u
            ci2p += 1
            aw = aw & (aw - 1)
          wi += 1
        cri = []
        cci = []
        i = 0
        while i < core_n
          v = core_vs[i]
          vbase = v * words
          wi = 0
          while wi < words
            aw = adjc[vbase + wi] & alivec[wi]
            while aw != 0
              u = (wi << 5) + ccall_nobox("__w_bit_cttz_u32", aw)
              if u < v
                cri.push(cid2[v])
                cci.push(cid2[u])
              aw = aw & (aw - 1)
            wi += 1
          i += 1
        # seed: the incumbent's core vertices in incumbent order, glued
        # after the fixed prefix
        cseed = []
        gpos = u32[n]
        i = 0
        while i < n
          gpos[best[i]] = i
          i += 1
        ordv = []
        i = 0
        while i < core_n
          ordv.push([gpos[core_vs[i]], cid2[core_vs[i]]])
          i += 1
        ordv = ordv.sort_by -> (pr) pr[0]
        i = 0
        while i < core_n
          cseed.push(ordv[i][1])
          i += 1
        glue = []
        i = 0
        while i < pcount2
          glue.push(prefix_order[i])
          i += 1
        i = 0
        while i < core_n
          glue.push(core_vs[cseed[i]])
          i += 1
        gpred = predictions_for_order(glue)
        seed_core_cost = gpred[1] - prefix_cost
        # a reduced core earns proportionally more search: constant
        # effort per surviving vertex, capped at 8x
        cscale = n / core_n
        cscale = 8 if cscale > 8
        cscale = 1 if cscale < 1
        ref = rgreedy_refine(core_n, cri, cci, cri.size, cseed, seed_core_cost, ils_words * cscale, stream)
        cand2 = []
        i = 0
        while i < pcount2
          cand2.push(prefix_order[i])
          i += 1
        i = 0
        while i < core_n
          cand2.push(core_vs[ref[0][i]])
          i += 1
        pred = predictions_for_order(cand2)
        if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
          best = cand2
          best_fill = pred[0]
          best_flops = pred[1]
        if gpred[1] < best_flops
          best = glue
          best_fill = gpred[0]
          best_flops = gpred[1]
      elsif n <= 45000
        ref = rgreedy_refine(n, ri, ci, m, best, best_flops, ils_words, stream)
        if ref[1] < best_flops
          pred = predictions_for_order(ref[0])
          if pred[1] < best_flops
            best = ref[0]
            best_fill = pred[0]
            best_flops = pred[1]
    # Above the core-lift bitmap ceiling, avoid allocating its extra dense
    # matrix.  Preserve the pre-existing whole-graph ILS fallback for the
    # shapes admitted by its n<=45,000 policy.
    if ils_words > 0 && n <= 45000 && !core_lift_ok
      ref = rgreedy_refine(n, ri, ci, m, best, best_flops, ils_words, stream)
      if ref[1] < best_flops
        pred = predictions_for_order(ref[0])
        if pred[1] < best_flops
          best = ref[0]
          best_fill = pred[0]
          best_flops = pred[1]
    if ils_words > 0 && n > 1500 && n <= 150000
      # fused subtree refinement: rgreedy rounds + (n>9000) anneal rounds +
      # pool crossover passes on one shared etree/postorder setup
      kmask = 1
      kmask += 2 if n > 9000
      others = []
      if @cand_pool != nil
        px = 1
        while px < @cand_pool.size && px < 3
          others.push(@cand_pool[px][1]) if @cand_pool[px][1].size == n
          px += 1
      kmask += 4 if others.size > 0
      # The default portfolio spends one phase on subtree RGSUB. The macro
      # phase remains available to direct quality-focused callers: at the
      # smaller per-block portfolio budget it did not change the final winner
      # in the matched corpus, while adding 34-93% to this candidate lane.
      ref = rgsub_refine(best, ils_words / 8, stream, kmask, others, 1, 1)
      if ref[1] < best_flops
        pred = predictions_for_order(ref[0])
        if pred[1] < best_flops
          best = ref[0]
          best_fill = pred[0]
          best_flops = pred[1]
    if ils_words > 0
      pool_consider(best_flops, best)
      pool_n = @cand_pool.size
      pool_n = 1 if n > 8000
      pi3 = 0
      while pi3 < pool_n
        seedc = @cand_pool[pi3]
        ref = telos_descent(seedc[1], seedc[0], 6)
        if ref[1] < best_flops
          pred = predictions_for_order(ref[0])
          if pred[1] < best_flops
            best = ref[0]
            best_fill = pred[0]
            best_flops = pred[1]
        pi3 += 1
    if ils_words > 0 && n <= 45000
      # The optional watcher lane is a sibling descent from this identical
      # completion. Its deletion schedule can select a different basin, so
      # exact-score it independently and merge serially. It remains opt-in
      # until corpus benchmarks justify the second completion construction.
      watch_seed = best
      watch_seed_flops = best_flops
      minl_words = n * ((n + 31) >> 5)
      minl_workspace = u32[minl_words * 2]
      ref = minl_descent_workspace(
        best, best_flops, ils_words / 4, 0, 0, nil,
        minl_workspace, 0)
      if ref[1] < best_flops
        best = ref[0]
        pred = predictions_for_order(best)
        best_fill = pred[0]
        best_flops = pred[1]
      # Match the watcher's admission cap before paying for a duplicate dense
      # completion build. Its internal fill cap remains the second guard.
      if watcher_minl != 0 && n <= 30000
        ref = minl_descent_workspace(
          watch_seed, watch_seed_flops, ils_words / 4, 0, 2, nil,
          minl_workspace, 1)
        if ref[1] < watch_seed_flops
          watch_o = ref[0]
          watch_f = ref[1]
      # Runner-up completion descent: the pool's #2 order lives in a
      # different chordal-completion basin; descending it reaches minima
      # the incumbent's lattice cannot (frontier catalog item)
      if @cand_pool != nil && @cand_pool.size > 1
        ru = @cand_pool[1]
        use_runner = ru[0] != best_flops
        use_runner = ru[1] != best if @pool_structural != 0
        if use_runner
          ref = minl_descent_workspace(
            ru[1], ru[0], ils_words / 8, 0, 0, nil,
            minl_workspace, 1)
          if ref[1] < best_flops
            pred = predictions_for_order(ref[0])
            if pred[1] < best_flops
              best = ref[0]
              best_fill = pred[0]
              best_flops = pred[1]
      # #8 terminal repass with realizer rotation (upstream #48/#49: a
      # second completion pass with a different realizer wins on cells
      # the first pass left)
      ref = minl_descent_workspace(
        best, best_flops, ils_words / 8, 1, 0, nil,
        minl_workspace, 1)
      if ref[1] < best_flops
        pred = predictions_for_order(ref[0])
        if pred[1] < best_flops
          best = ref[0]
          best_fill = pred[0]
          best_flops = pred[1]
    if ils_words > 0 && n <= 1200
      ref = window_dp(best, best_flops, 10, 600000000)
      if ref[1] < best_flops
        pred = predictions_for_order(ref[0])
        if pred[1] < best_flops
          best = ref[0]
          best_fill = pred[0]
          best_flops = pred[1]
    if ils_words > 0 && n <= 2500
      hcb = 4 * n
      hcb = 3000 if hcb < 3000
      ref = order_descent(best, best_flops, hcb, stream)
      if ref[1] < best_flops
        pred = predictions_for_order(ref[0])
        if pred[1] < best_flops
          best = ref[0]
          best_fill = pred[0]
          best_flops = pred[1]
    if ils_words > 0 && n <= 9000
      nz3 = @pattern.nnz
      nz3 = 1000 if nz3 < 1000
      ab = ils_words / (nz3 * 4)
      ab = 200000 if ab > 200000
      ab = ab / 2 if n > 2500
      if ab > 500
        ref = anneal_refine(best, best_flops, ab, stream)
        if ref[1] < best_flops
          pred = predictions_for_order(ref[0])
          if pred[1] < best_flops
            best = ref[0]
            best_fill = pred[0]
            best_flops = pred[1]
    # Merge the watcher sibling only after the historical pipeline has run to
    # completion. An earlier merge can steer later nonlinear descents into a
    # worse basin even though the watcher itself was a strict local win.
    if watch_o != nil && watch_f < best_flops
      pred = predictions_for_order(watch_o)
      if pred[1] < best_flops
        best = watch_o
        best_fill = pred[0]
        best_flops = pred[1]
    # Additional sparse RGSUB rounds are terminal siblings. Running them in
    # the middle of the portfolio can steer the later nonlinear MINL/Telos
    # descents into a worse basin even when the local RGSUB splice is better.
    # Starting from the completed historical incumbent and exact-rescoring
    # every accepted round makes this lane globally monotone. Rebuild the
    # etree/postorder after each strict win and stop at the first fixed point.
    # Admit them only when the graph is sparse and one round's budget covers
    # eight full vertex/entry passes.  Dyadic stream splitting flips a distinct
    # high bit for each round; it is an a-priori partition of the 1024 streams,
    # not a seed selected from observed basins.
    if SparseAnalysis.terminal_rgsub_portfolio_fits?(n, m, ils_words)
      rgsub_outer = 1
      while rgsub_outer < 3
        lane = (stream & 1023) ^ (1 << (10 - rgsub_outer))
        rstream = (stream >> 10) * 1024 + lane
        ref = rgsub_refine(
          best, ils_words / 16, rstream, 1, nil, 1, 1)
        improved = 0 == 1
        if ref[1] < best_flops
          pred = predictions_for_order(ref[0])
          if pred[1] < best_flops
            best = ref[0]
            best_fill = pred[0]
            best_flops = pred[1]
            improved = 0 == 0
        break if !improved
        rgsub_outer += 1
    # Above the dense bitmap's resource-derived ceiling, try the O(nnz+n)
    # degree-3 reducer only when its exact worst-case workspace and a linear
    # work estimate fit the caller's budget.  Residual AMD has a second live-
    # workspace/work check below.  No matrix-size or benchmark-bucket band is
    # involved, and any failure leaves the incumbent untouched.
    core_lift_budget = ils_words / 16
    if core_lift_budget > 0 && !core_lift_ok && (
        SparseAnalysis.sparse_core_lift_workspace_fits?(n, m)) && (
        8 * (n + m) <= core_lift_budget)
      scl = SparseAnalysis.sparse_core_lift_reduce(n, ri, ci, m, 3)
      if scl != nil && scl[1] > 0 && (
          SparseAnalysis.sparse_core_lift_candidate_fits?(
            n, m, scl[3], scl[6])) && (
          8 * (n + m + scl[3] + scl[6]) <= core_lift_budget)
        prefix = scl[0]
        prefix_n = scl[1]
        core_vertices = scl[2]
        core_n = scl[3]
        core_ri = scl[4]
        core_ci = scl[5]
        core_m = scl[6]
        core_iw_cap = SparseAnalysis.sparse_core_lift_amd_iw_words(
          n, m, core_n, core_m)
        core_order = amd_core(
          core_n, core_ri, core_ci, core_m, 10, 1, 0, core_iw_cap)
        if core_order.size == core_n
          candidate = []
          i = 0
          while i < prefix_n
            candidate.push(prefix[i])
            i += 1
          i = 0
          while i < core_n
            candidate.push(core_vertices[core_order[i]])
            i += 1
          if candidate.size == n
            pred = predictions_for_order(candidate)
            if pred[1] < best_flops || (
              pred[1] == best_flops && pred[0] < best_fill)
              best = candidate
              best_fill = pred[0]
              best_flops = pred[1]
    # Large sparse one-dissection arm. Run this split-only structural pass
    # after the nonlinear portfolio: feeding a different seed into later
    # descents changes both their basin and allocation volume. Exact scoring
    # admits the result only as a final improvement, so no biconn workspace or
    # losing candidate is retained by the downstream pool.
    if SparseAnalysis.biconn_portfolio_fits?(n, m, ils_words)
      biconn_iw_cap = SparseAnalysis.biconn_amd_iw_words(n, m)
      cand = biconn_split_ordering(biconn_iw_cap)
      if cand.size == n
        pred = predictions_for_order(cand)
        if pred[1] < best_flops || (pred[1] == best_flops && pred[0] < best_fill)
          best = cand
          best_fill = pred[0]
          best_flops = pred[1]
    best

  # Populate the shared exact-score counts for an elimination ORDER.
  -> score_order_cached(order)
    n = @pattern.rows
    @pf_perm = u32[n] if @pf_perm == nil
    perm = @pf_perm
    i = 0
    while i < n
      perm[order[i]] = i
      i += 1
    counts_under_cached(perm)
    nil

  # Exact flop-only lane for search loops. Avoids allocating and indexing the
  # public two-element [fill, flops] result when only the objective is used.
  -> flops_for_order(order)
    return 0 if @pattern.rows == 0
    @score_lock.synchronize ->
      score_order_cached(order)
      ccall("__w_u32_flops", @cu_counts)

  # Same objective for a u32-typed order: the perm build runs in a typed
  # kernel instead of n dynamic dispatches (anneal/descent call this 10^5
  # times per matrix).
  -> flops_for_typed_order(order)
    n = @pattern.rows
    return 0 if n == 0
    @pf_perm = u32[n] if @pf_perm == nil
    @score_lock.synchronize ->
      ssi_build_perm(order, @pf_perm, n)
      counts_under_cached(@pf_perm)
      ccall("__w_u32_flops", @cu_counts)

  # Exact cost of an order prefix while the suffix remains live. Used by
  # boundary-aware subtree search, whose passive separator vertices affect
  # every pivot degree but are deliberately never eliminated by the worker.
  -> prefix_flops_for_order(order, nelim)
    return 0 if nelim <= 0 || @pattern.rows == 0
    @score_lock.synchronize ->
      score_order_cached(order)
      stop = nelim
      stop = @pattern.rows if stop > @pattern.rows
      f = 0
      i = 0
      while i < stop
        c = @cu_counts[i]
        f += c * c
        i += 1
      f

  # Predicted fill/flops of the pattern under an elimination ORDER (array
  # of old indices, first eliminated first). Returns [fill, flops].
  -> predictions_for_order(order)
    return [0, 0] if @pattern.rows == 0
    @score_lock.synchronize ->
      score_order_cached(order)
      ccall("__w_u32_fill_flops", @cu_counts)

  -> to_s
    "SparseAnalysis(n=" + @pattern.rows.to_s + " fill=" + predicted_fill.to_s + ")"

