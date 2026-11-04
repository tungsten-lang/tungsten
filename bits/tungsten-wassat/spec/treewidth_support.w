+ TreewidthFixture
  ro :clauses, :nv, :counter_start, :fill_start, :orientation_start
  -> new(n, edges, bound)
    @clauses = []; @n = n; @base = 2; @ab = 2 + n * (n - 1) / 2
    i = 0
    while i < n
      j = 0
      while j < n
        if i != j
          k = 0
          while k < n
            @clauses.push([-self.ord(i, j), -self.ord(j, k), self.ord(i, k)]) if k != i && k != j
            k += 1
        j += 1
      i += 1
    edges.each ->(edge) @clauses.push([self.arc(edge[0], edge[1]), self.arc(edge[1], edge[0])])
    @fill_start = @clauses.size
    i = 0
    while i < n
      j = 0
      while j < n
        if i != j
          k = 0
          while k < n
            @clauses.push([-self.arc(k, i), -self.arc(k, j), self.arc(i, j), self.arc(j, i)]) if k != i && k != j
            k += 1
        j += 1
      i += 1
    @orientation_start = @clauses.size
    i = 0
    while i < n
      j = 0
      while j < n
        @clauses.push([-self.ord(i, j), -self.arc(j, i)]) if i != j
        j += 1
      i += 1
    i = 0
    while i < n
      j = 0
      while j < n
        @clauses.push(i == j ? [-self.arc(i, i)] : [-self.arc(j, i), -self.arc(i, j)])
        j += 1
      i += 1
    @counter_start = @clauses.size
    @nv = @ab + n * n - 1; stride = bound + 1; v = 0
    while v < n
      cb = @nv + 1; @nv += (n - 1) * stride
      i = 0
      while i < n - 1
        @clauses.push([-self.arc(v, i), cb + i * stride]); i += 1
      j = 1
      while j < stride
        @clauses.push([-cb - j]); j += 1
      i = 1
      while i < n - 1
        j = 0
        while j < stride
          @clauses.push([-cb - (i - 1) * stride - j, cb + i * stride + j]); j += 1
        i += 1
      i = 1
      while i < n - 1
        j = 1
        while j < stride
          @clauses.push([-self.arc(v, i), -cb - (i - 1) * stride - j + 1, cb + i * stride + j]); j += 1
        i += 1
      limit = stride
      while limit >= bound
        i = 1
        while i < n
          @clauses.push([-self.arc(v, i), -cb - (i - 1) * stride - limit + 1]); i += 1
        limit -= 1
      v += 1

  -> ord(i, j)
    return @base + i * (2 * @n - i - 1) / 2 + j - i - 1 if i < j
    -self.ord(j, i)

  -> arc(i, j)
    @ab + i * @n + j

  -> flat
    nl = 0
    @clauses.each ->(c) nl += c.size
    nc = @clauses.size; lits = i64[nl]; offs = i64[nc]; lens = i64[nc]
    i = 0; p = 0
    @clauses.each ->(c)
      offs[i] = p; lens[i] = c.size
      c.each ->(x)
        lits[p] = x; p += 1
      i += 1
    { "nvars": @nv, "flat_ncl": nc, "flat_nlits": nl,
      "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

-> treewidth_clique(n, bound)
  edges = []; i = 0
  while i < n
    j = i + 1
    while j < n
      edges.push([i, j]); j += 1
    i += 1
  TreewidthFixture.new(n, edges, bound)
