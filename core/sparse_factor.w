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

  # Symmetric-structure analysis: elimination tree + column counts of the
  # Cholesky factor for the pattern (entries interpreted as the union of
  # both triangles), and the derived predictions. Result-only — no numeric
  # work, no factor. Deterministic.
  -> new(@pattern)
    raise "SparseAnalysis: square pattern required" if @pattern.rows != @pattern.cols
    n = @pattern.rows
    data = SparseAnalysis.etree_counts(n, SparseAnalysis.lower_adjacency(@pattern, nil))
    @parent = data[0]
    @counts = data[1]
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
    ri = @pattern.row_indices
    ci = @pattern.col_indices
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

  -> .symmetric_adjacency(pattern)
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
      if r != c
        adj[r].push(c)
        adj[c].push(r)
      k += 1
    i = 0
    while i < n
      adj[i] = adj[i].sort.uniq
      i += 1
    adj

  # Canonical symmetric adjacency is immutable analysis state. Peeling,
  # minimum degree, and any later symbolic pass share this one construction.
  # Keep the cached object private: Arrays are mutable, so returning it would
  # let an observer silently corrupt every later analysis operation.
  -> ensure_symmetric_adjacency
    if @symmetric_adj == nil
      @symmetric_adj = SparseAnalysis.symmetric_adjacency(@pattern)
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

  # The scan wins tiny graphs through lower constant overhead; the heap wins
  # once repeated O(n) minima dominate.  The crossover is benchmarked in
  # benchmarks/linalg/tungsten/sparse_ordering_bench.w.
  -> min_degree_ordering
    if @pattern.rows < 384
      min_degree_ordering_scan
    else
      min_degree_ordering_heap

  # Predicted fill/flops of the pattern under an elimination ORDER (array
  # of old indices, first eliminated first). Returns [fill, flops].
  -> predictions_for_order(order)
    n = @pattern.rows
    perm = []
    i = 0
    while i < n
      perm.push(0)
      i += 1
    i = 0
    while i < n
      perm[order[i]] = i
      i += 1
    data = SparseAnalysis.etree_counts(
      n, SparseAnalysis.lower_adjacency(@pattern, perm))
    counts = data[1]
    fill = 0
    flops = 0
    counts.each -> (c)
      fill += c
      flops += c * c
    [fill, flops]

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
