# Labelled graphs immersed in a rose, their cone groups, and parity
# cancellation in group algebras over F_2.
#
# A signed alphabet has letters 0..nl-1 with a fixed-point-free involution inv.
# A RoseGraph has n vertices; vertex x carries an outgoing label set S_x, and
# nb[x*nl + t] is the endpoint of the edge leaving x with label t (or -1). The
# edge read backwards has label inv[t], so nb[nb[x*nl+t]*nl + inv[t]] = x.
# Attaching a cone to every component kills the labels of all closed walks:
# the cone group is G = F(T)/<<closed walk labels>>, and a vertex x of the
# component of a root r has the well-defined label g_x (any path r -> x).
#
# For two such graphs the "simultaneous-step graph" on A' x B' joins (x, y) to
# (x.t, y.t) for every common label t; g_x h_y^-1 is constant along its edges.
# If every vertex has odd degree |S_x ∩ S_y| then every component has even
# size, so sum_(x,y) g_x h_y^-1 = (sum g_x)(sum h_y^-1) vanishes over F_2.
#
#   use core/algebra/coned_graphs
#   g = RoseGraph.new(n, nl, inv); g.set_types(types); g.match(seed)

# ---- typed kernels ---------------------------------------------------------------

-> cg_rand(st) (i64[]) i64
  st[0] = (st[0] * 48271) % 2147483647
  st[0]

# BFS from src in the graph with the single edge (x, t) removed (both directions);
# returns the distance to dst (or -1 if > maxd). dist and queue are scratch of size n.
-> cg_dist_avoid(nb, n, nl, inv, src, dst, x, t, maxd, dist, queue) (i64[] i64 i64 i64[] i64 i64 i64 i64 i64 i64[] i64[]) i64
  i = 0
  while i < n
    dist[i] = -1
    i += 1
  y = nb[x * nl + t]
  ti = inv[t]
  dist[src] = 0
  queue[0] = src
  head = 0
  tail = 1
  res = -1
  while head < tail
    u = queue[head]
    head += 1
    du = dist[u]
    if u == dst
      res = du
      head = tail
    else
      if du < maxd
        l = 0
        while l < nl
          w = nb[u * nl + l]
          if w >= 0
            skip = 0
            if u == x && l == t
              skip = 1
            if u == y && l == ti
              skip = 1
            if skip == 0 && dist[w] < 0
              dist[w] = du + 1
              queue[tail] = w
              tail += 1
          l += 1
  res

# number of edges (counted from each tail with t < inv[t]) lying on a cycle of length < g
-> cg_bad_edges(nb, n, nl, inv, g, dist, queue, mark) (i64[] i64 i64 i64[] i64 i64[] i64[] i64[]) i64
  bad = 0
  x = 0
  while x < n
    t = 0
    while t < nl
      mark[x * nl + t] = 0
      y = nb[x * nl + t]
      if y >= 0 && t < inv[t]
        if y == x
          mark[x * nl + t] = 1
          bad += 1
        else
          d = cg_dist_avoid(nb, n, nl, inv, y, x, x, t, g - 2, dist, queue)
          if d >= 0
            mark[x * nl + t] = 1
            bad += 1
      t += 1
    x += 1
  bad

# union-find
-> cg_find(parent, a) (i64[] i64) i64
  r = a
  while parent[r] != r
    r = parent[r]
  c = a
  while parent[c] != r
    nx = parent[c]
    parent[c] = r
    c = nx
  r

# simultaneous-step graph on listA x listB (ia, ib: index of a vertex in its list or -1).
# Fills parent (union-find over na*nb nodes) and returns the number of nodes of even degree;
# st[0] receives the number of odd-degree nodes.
-> cg_product(nba, nbb, nl, la, lb, na, nbn, ia, ib, parent, st) (i64[] i64[] i64 i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  i = 0
  while i < na * nbn
    parent[i] = i
    i += 1
  even = 0
  odd = 0
  p = 0
  while p < na
    x = la[p]
    q = 0
    while q < nbn
      y = lb[q]
      deg = 0
      t = 0
      while t < nl
        x2 = nba[x * nl + t]
        y2 = nbb[y * nl + t]
        if x2 >= 0 && y2 >= 0
          deg += 1
          p2 = ia[x2]
          q2 = ib[y2]
          ra = cg_find(parent, p * nbn + q)
          rb = cg_find(parent, p2 * nbn + q2)
          if ra != rb
            parent[ra] = rb
        t += 1
      if deg % 2 == 0
        even += 1
      else
        odd += 1
      q += 1
    p += 1
  st[0] = odd
  even

# ---- the graph ---------------------------------------------------------------------

+ RoseGraph
  -> new(@n, @nl, inv_list)
    @inv = i64[@nl + 1]
    i = 0
    while i < @nl
      @inv[i] = inv_list[i]
      i += 1
    @nb = i64[@n * @nl + 1]
    @has = i64[@n * @nl + 1]
    i = 0
    while i < @n * @nl
      @nb[i] = -1
      i += 1
    @dist = i64[@n + 1]
    @queue = i64[@n + 1]
    @mark = i64[@n * @nl + 1]
    self

  ro :n, :nl, :nb, :has, :inv, :mark

  # types[x] = list of outgoing labels of x
  -> set_types(types)
    x = 0
    while x < @n
      types[x].each ->(t)
        @has[x * @nl + t] = 1
      x += 1
    self

  -> deg(x)
    d = 0
    t = 0
    while t < @nl
      d += @has[x * @nl + t]
      t += 1
    d

  # letter frequencies: count of vertices carrying t
  -> letter_count(t)
    c = 0
    x = 0
    while x < @n
      c += @has[x * @nl + t]
      x += 1
    c

  # one uniform random bijection Y_t -> Y_(inv t) for every inverse pair
  -> match(st)
    t = 0
    while t < @nl
      if t < @inv[t]
        u = @inv[t]
        ya = []
        yb = []
        x = 0
        while x < @n
          ya.push(x) if @has[x * @nl + t] == 1
          yb.push(x) if @has[x * @nl + u] == 1
          x += 1
        raise "RoseGraph.match: unbalanced letter " + t.to_s if ya.size != yb.size
        k = yb.size - 1
        while k > 0
          j = cg_rand(st) % (k + 1)
          tmp = yb[k]
          yb[k] = yb[j]
          yb[j] = tmp
          k -= 1
        k = 0
        while k < ya.size
          @nb[ya[k] * @nl + t] = yb[k]
          @nb[yb[k] * @nl + u] = ya[k]
          k += 1
      t += 1
    self

  -> bad_edges(g)
    cg_bad_edges(@nb, @n, @nl, @inv, g, @dist, @queue, @mark)

  # switching (as in Lemma prescriptions): replace a bad edge x-t->y and a random
  # edge u-t->z by x-t->z and u-t->y when that lowers the number of bad edges
  -> repair(g, st, max_rounds)
    cur = bad_edges(g)
    round = 0
    while cur > 0 && round < max_rounds
      x = 0
      found = false
      while x < @n && !found
        t = 0
        while t < @nl && !found
          if @mark[x * @nl + t] == 1
            found = true
            bx = x
            bt = t
          t += 1
        x += 1
      ti = @inv[bt]
      y = @nb[bx * @nl + bt]
      # candidate partner edges with the same label
      tries = 0
      improved = false
      while tries < 40 && !improved
        u = cg_rand(st) % @n
        if @has[u * @nl + bt] == 1 && u != bx
          z = @nb[u * @nl + bt]
          @nb[bx * @nl + bt] = z
          @nb[z * @nl + ti] = bx
          @nb[u * @nl + bt] = y
          @nb[y * @nl + ti] = u
          nxt = bad_edges(g)
          if nxt < cur
            cur = nxt
            improved = true
          else
            @nb[u * @nl + bt] = z
            @nb[z * @nl + ti] = u
            @nb[bx * @nl + bt] = y
            @nb[y * @nl + ti] = bx
            nxt = bad_edges(g)
        tries += 1
      round += 1
    cur

  # girth (shortest cycle length, loops count as 1), searched up to maxg
  -> girth(maxg)
    g = 1
    while g <= maxg
      return g if bad_edges(g + 1) > 0
      g += 1
    maxg + 1

  # component id per vertex; returns [ids (i64[]), sizes]
  -> components
    comp = i64[@n + 1]
    x = 0
    while x < @n
      comp[x] = -1
      x += 1
    sizes = []
    c = 0
    x = 0
    while x < @n
      if comp[x] < 0
        comp[x] = c
        stack = [x]
        size = 0
        while stack.size > 0
          u = stack.pop
          size += 1
          t = 0
          while t < @nl
            w = @nb[u * @nl + t]
            if w >= 0 && comp[w] < 0
              comp[w] = c
              stack.push(w)
            t += 1
        sizes.push(size)
        c += 1
      x += 1
    [comp, sizes]

  # vertices of the component of root, in BFS order, with abelianized labels:
  # pairs: rep[k] = representative letter of inverse pair k, pair_of[t] = k,
  # sign_of[t] = +1 or -1. Returns [vertices, ab (flat len*r), relations (list of i64[r])]
  -> cone_data(root, r, pair_of, sign_of)
    idx = i64[@n + 1]
    x = 0
    while x < @n
      idx[x] = -1
      x += 1
    verts = [root]
    idx[root] = 0
    ab = []
    ab.push(i64[r + 1])
    rels = []
    head = 0
    while head < verts.size
      u = verts[head]
      au = ab[idx[u]]
      t = 0
      while t < @nl
        w = @nb[u * @nl + t]
        if w >= 0
          if idx[w] < 0
            idx[w] = verts.size
            v = i64[r + 1]
            k = 0
            while k < r
              v[k] = au[k]
              k += 1
            v[pair_of[t]] = v[pair_of[t]] + sign_of[t]
            verts.push(w)
            ab.push(v)
          elsif t < @inv[t]
            # every edge read once: relation ab(u) + e(t) - ab(w)
            aw = ab[idx[w]]
            rel = i64[r + 1]
            k = 0
            while k < r
              rel[k] = au[k] - aw[k]
              k += 1
            rel[pair_of[t]] = rel[pair_of[t]] + sign_of[t]
            nz = false
            k = 0
            while k < r
              nz = true if rel[k] != 0
              k += 1
            rels.push(rel) if nz
        t += 1
      head += 1
    [verts, ab, rels, idx]

# ---- cone-group relators as words ------------------------------------------------------

+ RoseWords
  # column of letter t: 2 * pair + (0 for the representative, 1 for its inverse)
  -> .column(t, pair_of, sign_of)
    c = 2 * pair_of[t]
    c += 1 if sign_of[t] < 0
    c

  # BFS tree words (columns) from root and the freely reduced relator of every
  # non-tree edge of root's component: path(root,u) t path(root,w)^-1
  -> .cycle_words(g, root, pair_of, sign_of)
    n = g.n
    nl = g.nl
    nb = g.nb
    inv = g.inv
    par = i64[n + 1]
    plab = i64[n + 1]
    dep = i64[n + 1]
    x = 0
    while x < n
      par[x] = -2
      x += 1
    par[root] = -1
    order = [root]
    head = 0
    while head < order.size
      u = order[head]
      t = 0
      while t < nl
        w = nb[u * nl + t]
        if w >= 0 && par[w] == -2
          par[w] = u
          plab[w] = t
          dep[w] = dep[u] + 1
          order.push(w)
        t += 1
      head += 1
    words = []
    order.each ->(u)
      t = 0
      while t < nl
        w = nb[u * nl + t]
        if w >= 0 && t < inv[t] && !(par[w] == u && plab[w] == t) && !(par[u] == w && plab[u] == inv[t])
          wd = []
          # path root -> u
          pu = []
          y = u
          while par[y] >= 0
            pu.push(RoseWords.column(plab[y], pair_of, sign_of))
            y = par[y]
          k = pu.size - 1
          while k >= 0
            wd.push(pu[k])
            k -= 1
          wd.push(RoseWords.column(t, pair_of, sign_of))
          # path w -> root (inverse letters, walking up)
          y = w
          while par[y] >= 0
            wd.push(RoseWords.column(inv[plab[y]], pair_of, sign_of))
            y = par[y]
          rd = CosetEnumeration.reduce(wd)
          words.push(rd) if rd.size > 0
        t += 1
    words

# ---- abelian quotient of the cone group ---------------------------------------------

# Z^r modulo the lattice spanned by relation vectors, kept in Hermite form by
# integer row operations; canonical coordinates through the Smith form.
+ ConeAbelianization
  -> new(@r)
    @rows = []
    @prow = []
    k = 0
    while k < @r
      @prow.push(-1)
      k += 1
    self

  ro :r

  # reduce v column by column; a 2x2 unimodular combination clears v at an
  # existing pivot, otherwise v becomes the row of a new pivot
  -> add(v0)
    v = []
    k = 0
    while k < @r
      v.push(v0[k])
      k += 1
    c = 0
    while c < @r
      if v[c] != 0
        i = @prow[c]
        if i < 0
          @prow[c] = @rows.size
          @rows.push(v)
          return self
        row = @rows[i]
        a = row[c]
        b = v[c]
        xg = SmithNormalForm.xgcd(a, b)
        g = xg[0]
        s = xg[1]
        t = xg[2]
        nr = []
        nv = []
        k = 0
        while k < @r
          nr.push(s * row[k] + t * v[k])
          nv.push((b / g) * row[k] - (a / g) * v[k])
          k += 1
        @rows[i] = nr
        v = nv
      c += 1
    self

  -> rank
    @rows.size

  # invariant factors and the transform from Z^r to canonical coordinates
  -> finish
    a = []
    k = 0
    while k < @r
      row = []
      @rows.each ->(hrow)
        row.push(hrow[k])
      row.push(0) if @rows.size == 0
      a.push(row)
      k += 1
    @dec = SmithNormalForm.decompose(a)
    @u = @dec.left
    dg = @dec.diagonal
    @d = []
    k = 0
    while k < @r
      if k < dg.size && k < dg[0].size
        @d.push(dg[k][k])
      else
        @d.push(0)
      k += 1
    self

  ro :d

  -> invariants
    out = []
    @d.each ->(x)
      out.push(x) if x != 1
    out

  # canonical coordinates of v: (U v)_k mod d_k (free coordinates kept)
  -> canon(v)
    out = []
    k = 0
    while k < @r
      s = 0
      j = 0
      while j < @r
        s = s + @u[k][j] * v[j]
        j += 1
      dk = @d[k]
      if dk == 1
        s = 0
      elsif dk > 1
        s = s % dk
        s += dk if s < 0
      out.push(s)
      k += 1
    out

  -> key(v)
    canon(v).join(",")
