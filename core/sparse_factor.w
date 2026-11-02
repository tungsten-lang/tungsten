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
use sparse_factor/core_lift

# Exact Gilbert–Ng–Peyton column counts under an optional relabeling, on
# caller-owned typed buffers. Typed signature: the compiler types every
# array access as an inline u32 load/store (a 20x difference versus the
# same loop over ivar-loaded arrays, whose type is unknown at the read).
# has_perm = 0 means identity (perm is then a 1-element dummy).
-> ssi_counts_kernel(perm, has_perm, ri, ci, rows, ptr, idx, parent, ancestor, counts, mark, n, m) (u32[] i64 u32[] u32[] u32[] u32[] u32[] u32[] u32[] u32[] u32[] i64 i64) i64
  none = 4294967295
  i = 0
  while i < n
    rows[i] = 0
    i += 1
  k = 0
  while k < m
    a = ri[k]
    b = ci[k]
    if has_perm != 0
      a = perm[a]
      b = perm[b]
    if a > b
      rows[a] = rows[a] + 1
    elsif b > a
      rows[b] = rows[b] + 1
    k += 1
  run = 0
  i = 0
  while i < n
    ptr[i] = run
    run += rows[i]
    rows[i] = 0
    i += 1
  ptr[n] = run
  k = 0
  while k < m
    a = ri[k]
    b = ci[k]
    if has_perm != 0
      a = perm[a]
      b = perm[b]
    if a > b
      idx[ptr[a] + rows[a]] = b
      rows[a] = rows[a] + 1
    elsif b > a
      idx[ptr[b] + rows[b]] = a
      rows[b] = rows[b] + 1
    k += 1
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
  0

# perm[order[i]] = i for a typed order — the per-score prologue that the
# generic scorer must run through boxed dispatch because `order` may be a
# plain list there. Typed refiners (anneal, descent, subtree) use this lane.
-> ssi_build_perm(order, perm, n) (u32[] u32[] i64) i64
  i = 0
  while i < n
    perm[order[i]] = i
    i += 1
  0

# Window-DP transition: degree of window vertex wl[pick] after eliminating
# the `subset` of window vertices (fill closure inside the window), on
# bitset rows. Typed kernel for the same reason as ssi_counts_kernel.
-> ssi_window_state_degree(adj, alive, scratch, words, wl, kwin, subset, pick) (u32[] u32[] u32[] i64 u32[] i64 i64 i64) i64
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
      @cu_noperm = u32[1]
    # the whole kernel runs in a typed-signature function: arrays loaded
    # from ivars have no static type here, and every read would dispatch
    if perm == nil
      ssi_counts_kernel(@cu_noperm, 0, @fri, @fci, @cu_rows, @cu_ptr, @cu_idx, @cu_parent, @cu_anc, @cu_counts, @cu_mark, n, m)
    else
      ssi_counts_kernel(perm, 1, @fri, @fci, @cu_rows, @cu_ptr, @cu_idx, @cu_parent, @cu_anc, @cu_counts, @cu_mark, n, m)
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


use core/sparse_factor/amd
use core/sparse_factor/nested_dissection
use core/sparse_factor/graph_orderings
use core/sparse_factor/local_search
use core/sparse_factor/portfolio

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
