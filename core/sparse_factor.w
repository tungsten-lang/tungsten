# Sparse pattern / analysis / factor separation.
#
# The one-shot `SparseMatrix.solve_qr` / `solve_chol` calls rebuild the COO,
# the ordering, and the whole symbolic factorization on every solve. These
# three types split that pipeline along its dependency chain
#
#   pattern → ordering/etree/counts (analysis) → symbolic → numeric factor
#
# so each stage is computed once and reused:
#   - `SparsePattern` is IMMUTABLE (owned copies at construction) — safe to
#     share between analyses and factors; changing structure means a new
#     pattern, which naturally invalidates everything downstream.
#   - `SparseAnalysis` derives the elimination tree, column counts, and the
#     predicted fill/flops for the pattern (result-only: no factor is built),
#     and gates factorization on an explicit memory budget.
#   - `SparseFactor` owns a retained Accelerate factorization handle:
#     factor once, `solve`/`solve_into` many times, `refactor` with new
#     values on the SAME pattern (numeric-only — Apple's SparseRefactor
#     reuses the symbolic analysis), `release` explicitly.

use core/mutex
use core/sparse_core_lift

+ SparsePattern
  # Structure-only, square-or-rectangular, from parallel COO index lists.
  # The i32 buffers are built here and never mutated afterwards.
  -> new(rows, cols, row_idx, col_idx)
    raise "SparsePattern: entry lists must match" if row_idx.size != col_idx.size
    @rows = rows
    @cols = cols
    @nnz = row_idx.size
    @ri = ccall("w_array_new_aligned", 33, @nnz)
    @ci = ccall("w_array_new_aligned", 33, @nnz)
    k = 0
    while k < @nnz
      r = row_idx[k]
      c = col_idx[k]
      raise "SparsePattern: index out of range" if r < 0 || r >= rows || c < 0 || c >= cols
      @ri[k] = r
      @ci[k] = c
      k += 1

  ro :rows, :cols, :nnz

  -> .from_matrix(m)
    trip = m.coo_typed
    SparsePattern.new(m.rows, m.cols, trip[0], trip[1])

  -> row_indices
    out = ccall("w_array_new_aligned", 33, @nnz)
    k = 0
    while k < @nnz
      out[k] = @ri[k]
      k += 1
    out

  -> col_indices
    out = ccall("w_array_new_aligned", 33, @nnz)
    k = 0
    while k < @nnz
      out[k] = @ci[k]
      k += 1
    out

  # Typed f64 value buffer aligned with this pattern's entry order.
  -> values_from(list)
    raise "SparsePattern: values length must equal nnz" if list.size != @nnz
    vv = ccall("w_array_new_aligned", -64, @nnz)
    k = 0
    while k < @nnz
      vv[k] = list[k] + ~0.0
      k += 1
    vv

  -> to_s
    "SparsePattern(" + @rows.to_s + "x" + @cols.to_s + " nnz=" + @nnz.to_s + ")"


+ SparseAnalysis
  # Lower-triangle adjacency (sorted, deduped) of a pattern under an
  # optional relabeling `perm` (perm[old] = new position; nil = identity).
  -> .lower_adjacency(pattern, perm)
    n = pattern.rows
    adj = []
    i = 0
    while i < n
      adj.push([])
      i += 1
    ri = pattern.row_indices
    ci = pattern.col_indices
    k = 0
    while k < pattern.nnz
      r = ri[k]
      c = ci[k]
      if perm != nil
        r = perm[r]
        c = perm[c]
      if r > c
        adj[r].push(c)
      elsif c > r
        adj[c].push(r)
      k += 1
    i = 0
    while i < n
      adj[i] = adj[i].sort.uniq
      i += 1
    adj

  # Liu etree + exact column counts over a lower adjacency.
  # Returns [parent, counts].
  -> .etree_counts(n, adj)
    parent = []
    ancestor = []
    i = 0
    while i < n
      parent.push(-1)
      ancestor.push(-1)
      i += 1
    i = 0
    while i < n
      adj[i].each -> (j)
        r = j
        while r != -1 && r != i
          next_r = ancestor[r]
          ancestor[r] = i
          parent[r] = i if parent[r] == -1
          r = next_r
      i += 1
    counts = []
    mark = []
    i = 0
    while i < n
      counts.push(1)
      mark.push(-1)
      i += 1
    i = 0
    while i < n
      mark[i] = i
      adj[i].each -> (j)
        r = j
        while r != -1 && mark[r] != i
          counts[r] += 1
          mark[r] = i
          r = parent[r]
      i += 1
    [parent, counts]

  # Typed etree + exact column-count kernel: the pattern's lower triangle
  # under an optional relabeling (perm[old] = new, nil = identity) in CSC
  # form on u32 arrays, then Liu's elimination tree with path compression
  # and row-subtree column counts. Duplicate entries are harmless (the
  # row-subtree mark dedupes) and rows need no sorting. All work and result
  # buffers are analysis-owned and overwritten in full. The public wrapper
  # below copies the result when a caller needs to retain it; exact scoring
  # reads these buffers directly and therefore allocates nothing here.
  -> counts_under_cached(perm)
    n = @pattern.rows
    none = 4294967295
    ri = @fri
    ci = @fci
    m = @pattern.nnz
    # scratch reused across calls (counts_under runs once per candidate
    # score — the anneal/descent arms call it 10^5 times per matrix)
    if @cu_rows == nil
      @cu_rows = u32[n]
      @cu_ptr = u32[n + 1]
      @cu_idx = u32[m + 1]
      @cu_anc = u32[n]
      @cu_mark = u32[n]
      @cu_parent = u32[n]
      @cu_counts = u32[n]
    rows = @cu_rows
    i = 0
    while i < n
      rows[i] = 0
      i += 1
    k = 0
    while k < m
      a = ri[k]
      b = ci[k]
      if perm != nil
        a = perm[a]
        b = perm[b]
      if a > b
        rows[a] = rows[a] + 1
      elsif b > a
        rows[b] = rows[b] + 1
      k += 1
    ptr = @cu_ptr
    run = 0
    i = 0
    while i < n
      ptr[i] = run
      run += rows[i]
      rows[i] = 0
      i += 1
    ptr[n] = run
    idx = @cu_idx
    k = 0
    while k < m
      a = ri[k]
      b = ci[k]
      if perm != nil
        a = perm[a]
        b = perm[b]
      if a > b
        idx[ptr[a] + rows[a]] = b
        rows[a] = rows[a] + 1
      elsif b > a
        idx[ptr[b] + rows[b]] = a
        rows[b] = rows[b] + 1
      k += 1
    parent = @cu_parent
    ancestor = @cu_anc
    i = 0
    while i < n
      parent[i] = none
      ancestor[i] = none
      i += 1
    i = 0
    while i < n
      p = ptr[i]
      stop = ptr[i + 1]
      while p < stop
        r = idx[p]
        while r != none && r != i
          nxt = ancestor[r]
          ancestor[r] = i
          parent[r] = i if parent[r] == none
          r = nxt
        p += 1
      i += 1
    counts = @cu_counts
    mark = @cu_mark
    i = 0
    while i < n
      counts[i] = 1
      mark[i] = 0
      i += 1
    i = 0
    while i < n
      mark[i] = i + 1
      p = ptr[i]
      stop = ptr[i + 1]
      while p < stop
        r = idx[p]
        while r != none && mark[r] != i + 1
          counts[r] = counts[r] + 1
          mark[r] = i + 1
          r = parent[r]
        p += 1
      i += 1
    nil

  # Public owned-result API. Each call returns fresh parent/count buffers, so
  # a later score or counts query cannot mutate a result retained by a caller.
  # parent uses 4294967295 for an elimination-tree root.
  -> counts_under(perm)
    n = @pattern.rows
    @score_lock.synchronize ->
      counts_under_cached(perm)
      parent = u32[n]
      counts = u32[n]
      i = 0
      while i < n
        parent[i] = @cu_parent[i]
        counts[i] = @cu_counts[i]
        i += 1
      [parent, counts]

  # Symmetric-structure analysis: elimination tree + column counts of the
  # Cholesky factor for the pattern (entries interpreted as the union of
  # both triangles), and the derived predictions. Result-only — no numeric
  # work, no factor. Deterministic.
  -> new(@pattern)
    raise "SparseAnalysis: square pattern required" if @pattern.rows != @pattern.cols
    # Exact scoring reuses large typed workspaces. Serialize access on a
    # shared analysis so public read-like queries remain deterministic; RGSUB
    # workers still use private analyses and therefore never contend here.
    @score_lock = Mutex.new()
    n = @pattern.rows
    # typed copies of the pattern's index arrays: the ccall-backed
    # originals pay a dynamic dispatch per read, and the scoring and
    # portfolio paths read them tens of times per ordering
    @fri = u32[@pattern.nnz + 1]
    @fci = u32[@pattern.nnz + 1]
    ri0 = @pattern.row_indices
    ci0 = @pattern.col_indices
    k = 0
    while k < @pattern.nnz
      @fri[k] = ri0[k]
      @fci[k] = ci0[k]
      k += 1
    counts_under_cached(nil)
    tparent = @cu_parent
    tcounts = @cu_counts
    @parent = []
    @counts = []
    i = 0
    while i < n
      p = tparent[i]
      p = -1 if p == 4294967295
      @parent.push(p)
      @counts.push(tcounts[i])
      i += 1
    @component_ids = nil
    @component_count = 0
    @symmetric_adj = nil

  ro :pattern, :parent, :counts

  # Predicted nonzeros of the Cholesky factor L.
  -> predicted_fill
    total = 0
    @counts.each -> (c)
      total += c
    total

  # Predicted factorization flops (sum of squared column counts — the same
  # objective the fill-reducing-ordering literature scores).
  -> predicted_flops
    total = 0
    @counts.each -> (c)
      total += c * c
    total

  # Exact identity-order prefix objective. Sparse block refiners always seed
  # with [0...n), whose counts were already computed by the constructor; do
  # not rebuild the etree merely to score that same prefix again.
  -> predicted_prefix_flops(limit)
    total = 0
    i = 0
    while i < limit
      c = @counts[i]
      total += c * c
      i += 1
    total

  # Cap-aware gate: raise BEFORE factorization when the predicted factor
  # would exceed `budget_elements` stored nonzeros.
  -> check_budget(budget_elements)
    fill = predicted_fill
    if fill > budget_elements
      raise "SparseAnalysis: predicted fill " + fill.to_s + " exceeds budget " + budget_elements.to_s
    fill

  # Connected components of the symmetric pattern (union-find, path
  # halving, deterministic canonical ids by first appearance). Returns the
  # per-vertex component id array; component_count is set alongside.
  -> ensure_components
    return nil if @component_ids != nil
    n = @pattern.rows
    root = []
    i = 0
    while i < n
      root.push(i)
      i += 1
    # Analysis owns immutable typed structural buffers for its lifetime.
    # Reusing them avoids materializing two fresh inspection snapshots.
    ri = @fri
    ci = @fci
    k = 0
    while k < @pattern.nnz
      a = ri[k]
      while root[a] != a
        root[a] = root[root[a]]
        a = root[a]
      b = ci[k]
      while root[b] != b
        root[b] = root[root[b]]
        b = root[b]
      if a < b
        root[b] = a
      elsif b < a
        root[a] = b
      k += 1
    ids = []
    seen = {}
    count = 0
    i = 0
    while i < n
      a = i
      while root[a] != a
        a = root[a]
      canon = seen[a]
      if canon == nil
        canon = count
        seen[a] = canon
        count += 1
      ids.push(canon)
      i += 1
    @component_ids = ids
    @component_count = count
    nil

  -> components
    ensure_components
    @component_ids.dup

  -> component_count
    ensure_components
    @component_count

  # Low-degree peeling: vertices of current degree <= 1 eliminate with no
  # fill. Returns [prefix, rest] — the zero-fill elimination prefix (in
  # deterministic peel order) and the remaining vertices in index order.
  -> peel_order
    n = @pattern.rows
    ensure_symmetric_adjacency
    adj = @symmetric_adj
    degree = []
    removed = []
    i = 0
    while i < n
      degree.push(adj[i].size)
      removed.push(false)
      i += 1
    prefix = []
    queue = []
    i = 0
    while i < n
      queue.push(i) if degree[i] <= 1
      i += 1
    qi = 0
    while qi < queue.size
      v = queue[qi]
      qi += 1
      next if removed[v]
      removed[v] = true
      prefix.push(v)
      adj[v].each -> (u)
        if !removed[u]
          degree[u] -= 1
          queue.push(u) if degree[u] <= 1
    rest = []
    i = 0
    while i < n
      rest.push(i) if !removed[i]
      i += 1
    [prefix, rest]

  -> .symmetric_adjacency_of(n, m, ri, ci)
    adj = []
    i = 0
    while i < n
      adj.push([])
      i += 1
    k = 0
    while k < m
      r = ri[k]
      c = ci[k]
      if r != c
        adj[r].push(c)
        adj[c].push(r)
      k += 1
    i = 0
    while i < n
      adj[i] = adj[i].sort.uniq
      i += 1
    adj

  # Pattern-based public helper preserves its owned-inspection semantics.
  -> .symmetric_adjacency(pattern)
    ri = pattern.row_indices
    ci = pattern.col_indices
    SparseAnalysis.symmetric_adjacency_of(
      pattern.rows, pattern.nnz, ri, ci)

  # Canonical symmetric adjacency is immutable analysis state. Peeling,
  # minimum degree, and any later symbolic pass share this one construction.
  # Keep the cached object private: Arrays are mutable, so returning it would
  # let an observer silently corrupt every later analysis operation.
  -> ensure_symmetric_adjacency
    if @symmetric_adj == nil
      @symmetric_adj = SparseAnalysis.symmetric_adjacency_of(
        @pattern.rows, @pattern.nnz, @fri, @fci)
    nil

  # Public inspection retains the pre-cache value semantics: a caller owns
  # the returned nested Arrays and cannot mutate the analysis cache.
  -> symmetric_adjacency
    ensure_symmetric_adjacency
    out = []
    @symmetric_adj.each -> (row)
      out.push(row.dup)
    out

  -> .md_heap_less?(ad, av, bd, bv)
    ad < bd || (ad == bd && av < bv)

  # Binary min-heap entry keyed by (current degree, vertex).  Updates are
  # lazy: a changed vertex receives a new entry and stale entries are skipped
  # when popped.  This keeps the elimination loop deterministic without the
  # O(n) live-vertex scan at every step.
  -> .md_heap_push(heap_d, heap_v, degree, vertex)
    i = heap_d.size
    heap_d.push(degree)
    heap_v.push(vertex)
    while i > 0
      parent = (i - 1) / 2
      break if !SparseAnalysis.md_heap_less?(degree, vertex, heap_d[parent], heap_v[parent])
      heap_d[i] = heap_d[parent]
      heap_v[i] = heap_v[parent]
      i = parent
    heap_d[i] = degree
    heap_v[i] = vertex
    nil

  # Exact minimum-degree ordering by the elimination game (lowest-index
  # tie-break, deterministic): repeatedly eliminate the minimum-degree
  # vertex, connecting its remaining neighbors into a clique. Returns the
  # elimination order (old indices). Intended for moderate n — this is the
  # respectable baseline ordering, not an approximate-MD implementation.
  -> min_degree_ordering_scan
    n = @pattern.rows
    adj = []
    ensure_symmetric_adjacency
    @symmetric_adj.each -> (row)
      set = {}
      row.each -> (u)
        set[u] = true
      adj.push(set)
    alive = []
    i = 0
    while i < n
      alive.push(true)
      i += 1
    order = []
    step = 0
    while step < n
      best = -1
      best_deg = n + 1
      v = 0
      while v < n
        if alive[v] && adj[v].size < best_deg
          best_deg = adj[v].size
          best = v
        v += 1
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
      step += 1
    order

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
  -> .window_state_degree(adj, alive, scratch, words, wl, kwin, subset, pick)
    full = 4294967295
    v = wl[pick]
    vbase = v * words
    wi = 0
    while wi < words
      scratch[wi] = adj[vbase + wi] & alive[wi]
      wi += 1
    reach = 0
    t = 0
    while t < kwin
      bit = 1 << t
      if (subset & bit) != 0
        u = wl[t]
        if (scratch[u >> 5] & (1 << (u & 31))) != 0
          reach = reach | bit
      t += 1
    old_reach = 0 - 1
    while old_reach != reach
      old_reach = reach
      t = 0
      while t < kwin
        if (reach & (1 << t)) != 0
          u = wl[t]
          ubase = u * words
          t2 = 0
          while t2 < kwin
            bit2 = 1 << t2
            if (subset & bit2) != 0 && (reach & bit2) == 0
              x = wl[t2]
              if (adj[ubase + (x >> 5)] & (1 << (x & 31))) != 0
                reach = reach | bit2
            t2 += 1
        t += 1
    t = 0
    while t < kwin
      if (reach & (1 << t)) != 0
        u = wl[t]
        ubase = u * words
        wi = 0
        while wi < words
          scratch[wi] = scratch[wi] | (adj[ubase + wi] & alive[wi])
          wi += 1
      t += 1
    t = 0
    while t < kwin
      if (subset & (1 << t)) != 0
        u = wl[t]
        scratch[u >> 5] = scratch[u >> 5] & (full ^ (1 << (u & 31)))
      t += 1
    scratch[v >> 5] = scratch[v >> 5] & (full ^ (1 << (v & 31)))
    degree = 0
    wi = 0
    while wi < words
      degree += ccall_nobox("__w_bit_ctpop_u32", scratch[wi])
      wi += 1
    degree

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
        wl = []
        t = 0
        while t < kwin
          wl.push(cur[pos + t])
          t += 1
        s2 = 1
        dpc[0] = 0
        while s2 < nstates
          dpc[s2] = 4611686018427387903
          s2 += 1
        s2 = 0
        while s2 < nstates
          if dpc[s2] < 4611686018427387903
            t = 0
            while t < kwin
              bit = 1 << t
              if (s2 & bit) == 0
                v = wl[t]
                d = SparseAnalysis.window_state_degree(
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
          d = SparseAnalysis.window_state_degree(
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
    cur = []
    i = 0
    while i < n
      cur.push(order_in[i])
      i += 1
    cur_f = flops_in
    best = cur
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
        f = flops_for_order(cur)
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
        best = []
        i = 0
        while i < n
          best.push(cur[i])
          i += 1
      if !improved
        break if perturb == 0
        # perturb: reverse a random segment, restart the sweep from best
        cur = []
        i = 0
        while i < n
          cur.push(best[i])
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
        cur_f = flops_for_order(cur)
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
    cur = []
    i = 0
    while i < n
      cur.push(order_in[i])
      i += 1
    cur_f = flops_in
    best = order_in
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
      f = flops_for_order(cur)
      scores += 1
      if f <= cur_f + tt
        cur_f = f
        if f < best_f
          best_f = f
          best = []
          i = 0
          while i < n
            best.push(cur[i])
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


+ SparseFactor
  # kind 0 = QR (any shape), 1 = Cholesky (SPD; upper-triangle convention,
  # both triangles accepted — Accelerate sums duplicates).
  -> new(@pattern, values, @kind)
    vv = @pattern.values_from(values)
    # Keep factor-private structural snapshots. SparsePattern exposes only
    # owned copies, so callers cannot invalidate the retained native handle;
    # refactors reuse these snapshots without another allocation.
    @row_indices = @pattern.row_indices
    @col_indices = @pattern.col_indices
    @handle = ccall("w_sparse_factor_new_f64", @kind, @pattern.rows, @pattern.cols,
                    @row_indices, @col_indices, vv)
    @released = false

  ro :pattern, :kind

  -> .cholesky(pattern, values)
    SparseFactor.new(pattern, values, 1)

  -> .qr(pattern, values)
    SparseFactor.new(pattern, values, 0)

  # Typed fast lane: solve into a caller-owned f64 buffer (length >= cols)
  # from a caller-owned f64 RHS (length >= rows). No list conversion.
  -> solve_into(b_f64, x_f64)
    raise "SparseFactor: released" if @released
    ccall("w_sparse_factor_solve_f64", @handle, b_f64, x_f64)
    x_f64

  # List-of-Float convenience lane.
  -> solve(b)
    raise "SparseFactor: RHS length must equal rows" if b.size != @pattern.rows
    bb = ccall("w_array_new_aligned", -64, @pattern.rows)
    xx = ccall("w_array_new_aligned", -64, @pattern.cols)
    i = 0
    while i < @pattern.rows
      bb[i] = b[i] + ~0.0
      i += 1
    solve_into(bb, xx)
    out = []
    i = 0
    while i < @pattern.cols
      out.push(xx[i])
      i += 1
    out

  # Numeric-only refactorization: same pattern, new values. The symbolic
  # analysis inside the retained handle is reused (SparseRefactor).
  -> refactor(values)
    raise "SparseFactor: released" if @released
    vv = @pattern.values_from(values)
    ccall("w_sparse_factor_refactor_f64", @handle, @row_indices,
          @col_indices, vv)
    self

  -> release
    if !@released
      ccall("w_sparse_factor_release_f64", @handle)
      @released = true
    self

  -> to_s
    "SparseFactor(" + (@kind == 1 ? "cholesky" : "qr") + " " + @pattern.to_s + ")"

+ SparseBlockFactor
  # Component-blocked SPD Cholesky. Component factors and their RHS/result
  # scratch are retained. Independent blocks may run on joined workers, but
  # small components stay sequential because launch cost dominates.
  -> new(@pattern, values, force_parallel = nil)
    analysis = SparseAnalysis.new(@pattern)
    ids = analysis.components
    @ncomp = analysis.component_count
    n = @pattern.rows
    @locals = []
    @vertex_lists = []
    c = 0
    while c < @ncomp
      @vertex_lists.push([])
      c += 1
    i = 0
    while i < n
      c = ids[i]
      @locals.push(@vertex_lists[c].size)
      @vertex_lists[c].push(i)
      i += 1
    comp_ri = []
    comp_ci = []
    comp_vv = []
    c = 0
    while c < @ncomp
      comp_ri.push([])
      comp_ci.push([])
      comp_vv.push([])
      c += 1
    ri = @pattern.row_indices
    ci = @pattern.col_indices
    k = 0
    while k < @pattern.nnz
      r = ri[k]
      c = ids[r]
      comp_ri[c].push(@locals[r])
      comp_ci[c].push(@locals[ci[k]])
      comp_vv[c].push(values[k])
      k += 1
    @factors = []
    @rhs_buffers = []
    @out_buffers = []
    c = 0
    while c < @ncomp
      @factors.push(nil)
      sub_n = @vertex_lists[c].size
      @rhs_buffers.push(ccall("w_array_new_aligned", -64, sub_n))
      @out_buffers.push(ccall("w_array_new_aligned", -64, sub_n))
      c += 1
    automatic = @ncomp >= 2 && @ncomp <= 8 && @pattern.nnz >= 8192
    @parallel = force_parallel == nil ? automatic : force_parallel
    @released = false
    if @parallel
      workers = []
      c = 0
      while c < @ncomp
        comp = c
        sub_n = @vertex_lists[comp].size
        sri = comp_ri[comp]
        sci = comp_ci[comp]
        svv = comp_vv[comp]
        factors = @factors
        worker = Thread.new ->
          factors[comp] = SparseFactor.cholesky(
            SparsePattern.new(sub_n, sub_n, sri, sci), svv)
        workers.push(worker)
        c += 1
      workers.each -> (worker)
        worker.join
    else
      c = 0
      while c < @ncomp
        sub_n = @vertex_lists[c].size
        @factors[c] = SparseFactor.cholesky(
          SparsePattern.new(sub_n, sub_n, comp_ri[c], comp_ci[c]), comp_vv[c])
        c += 1

  ro :pattern, :ncomp, :parallel

  -> solve(b)
    raise "SparseBlockFactor: RHS length must equal rows" if b.size != @pattern.rows
    n = @pattern.rows
    out_buf = ccall("w_array_new_aligned", -64, n)
    solve_into(b, out_buf)
    out = []
    i = 0
    while i < n
      out.push(out_buf[i])
      i += 1
    out

  # Caller-owned output lane. Component buffers are single-flight mutable
  # scratch, matching SparseFactor's retained-handle solve contract.
  -> solve_into(b, out_buf)
    raise "SparseBlockFactor: released" if @released
    raise "SparseBlockFactor: RHS length must equal rows" if b.size != @pattern.rows
    if @parallel
      workers = []
      c = 0
      while c < @ncomp
        comp = c
        verts = @vertex_lists[comp]
        factor = @factors[comp]
        bb = @rhs_buffers[comp]
        xx = @out_buffers[comp]
        worker = Thread.new ->
          m = verts.size
          i = 0
          while i < m
            bb[i] = b[verts[i]] + ~0.0
            i += 1
          factor.solve_into(bb, xx)
          i = 0
          while i < m
            out_buf[verts[i]] = xx[i]
            i += 1
        workers.push(worker)
        c += 1
      workers.each -> (worker)
        worker.join
    else
      c = 0
      while c < @ncomp
        verts = @vertex_lists[c]
        m = verts.size
        bb = @rhs_buffers[c]
        xx = @out_buffers[c]
        i = 0
        while i < m
          bb[i] = b[verts[i]] + ~0.0
          i += 1
        @factors[c].solve_into(bb, xx)
        i = 0
        while i < m
          out_buf[verts[i]] = xx[i]
          i += 1
        c += 1
    out_buf

  -> release
    if !@released
      c = 0
      while c < @ncomp
        @factors[c].release if @factors[c] != nil
        c += 1
      @released = true
    self

  -> to_s
    "SparseBlockFactor(" + @ncomp.to_s + " components, " + @pattern.to_s + ")"
