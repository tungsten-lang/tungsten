# Finite-dimensional algebras over small finite fields.
#
# An algebra is a basis with sparse structure constants over a field FdField
# (GF(2^k) for k <= 20, or GF(p) for a prime p < 2^20). Elements are stored as
# plain integers 0..|F|-1 and multiplied through log/antilog tables, so every
# hot loop is a typed i64 kernel below 2^47.
#
# The module layer is built for basic split algebras whose basis is adapted
# to a complete set of primitive orthogonal idempotents e_1, ..., e_r: every
# other basis vector lies in one corner e_i A e_j and in the radical. Then
#
#   * a projective module P = (+)_g A e_{i_g} has the basis {c : c e_{i_g} = c},
#   * the radical is the span of the non-idempotent basis vectors,
#   * a minimal projective resolution is computed by repeated tops of kernels,
#     and the number of copies of A e_i in degree n is dim Ext^n(M, S_i),
#   * Ext^n(M, N) for any finite module N comes from the Hom complex.
#
# Constructors: structure constants by hand, tensor products, trivial
# extensions A x DA, opposite algebras, and bounded quiver algebras with
# relations (all paths beyond a fixed length vanish).
#
#   use core/algebra/fd_algebra
#   k = FdField.gf2(16)
#   a = FdAlgebra.new(k, 3, ["e", "f", "u"]) ...
#
# Field elements of GF(2^k) are bit vectors of polynomials in the primitive
# element g = 2 (x mod the stored primitive polynomial); FdField#poly(bits)
# evaluates a polynomial with F_2 coefficients at any element.

# ---- typed field kernels ---------------------------------------------------

-> fda_mul(a, b, ex, lg) (i64 i64 i64[] i64[]) i64
  if a == 0 || b == 0
    return 0
  ex[lg[a] + lg[b]]

-> fda_add(a, b, p, two) (i64 i64 i64 i64) i64
  if two == 1
    return a ^ b
  s = a + b
  if s >= p
    s = s - p
  s

-> fda_neg(a, p, two) (i64 i64 i64) i64
  if two == 1 || a == 0
    return a
  p - a

# Reduced row echelon form of the rows x cols matrix m (row-major), in place.
# Pivots are normalized to 1; piv[0..rank-1] receive the pivot columns.
# Returns the rank. `ord` is |F| - 1.
-> fda_rref(m, rows, cols, piv, ex, lg, p, two, ord) (i64[] i64 i64 i64[] i64[] i64[] i64 i64 i64) i64
  r = 0
  c = 0
  while c < cols && r < rows
    sel = r
    while sel < rows && m[sel * cols + c] == 0
      sel += 1
    if sel < rows
      if sel != r
        j = c
        while j < cols
          t = m[sel * cols + j]
          m[sel * cols + j] = m[r * cols + j]
          m[r * cols + j] = t
          j += 1
      lv = lg[m[r * cols + c]]
      li = ord - lv
      if li == ord
        li = 0
      j = c
      while j < cols
        x = m[r * cols + j]
        if x != 0
          m[r * cols + j] = ex[lg[x] + li]
        j += 1
      i = 0
      while i < rows
        if i != r
          f = m[i * cols + c]
          if f != 0
            lf = lg[fda_neg(f, p, two)]
            j = c
            while j < cols
              x = m[r * cols + j]
              if x != 0
                y = ex[lf + lg[x]]
                z = m[i * cols + j]
                if two == 1
                  m[i * cols + j] = z ^ y
                else
                  s = z + y
                  if s >= p
                    s = s - p
                  m[i * cols + j] = s
              j += 1
        i += 1
      piv[r] = c
      r += 1
    c += 1
  r

# Incremental echelon basis: rows (flat, row-major, width n), prow[c] = row
# whose pivot (first nonzero, normalized to 1) is column c or -1, st[0] = rank.
# Reduces v in place; inserts it when it is independent. Returns 1 if inserted.
-> fda_insert(rows, prow, st, v, n, ex, lg, p, two, ord) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64 i64 i64) i64
  c = 0
  while c < n
    x = v[c]
    if x != 0
      r = prow[c]
      if r >= 0
        lf = lg[fda_neg(x, p, two)]
        j = c
        while j < n
          y = rows[r * n + j]
          if y != 0
            z = ex[lf + lg[y]]
            if two == 1
              v[j] = v[j] ^ z
            else
              s = v[j] + z
              if s >= p
                s = s - p
              v[j] = s
          j += 1
      else
        li = ord - lg[x]
        if li == ord
          li = 0
        rk = st[0]
        j = 0
        while j < n
          y = v[j]
          if y != 0
            rows[rk * n + j] = ex[lg[y] + li]
          else
            rows[rk * n + j] = 0
          j += 1
        prow[c] = rk
        st[0] = rk + 1
        return 1
    c += 1
  0

# out <- out + coef * v  (length n)
-> fda_axpy(out, v, coef, n, ex, lg, p, two) (i64[] i64[] i64 i64 i64[] i64[] i64 i64) i64
  if coef == 0
    return 0
  lc = lg[coef]
  i = 0
  while i < n
    x = v[i]
    if x != 0
      y = ex[lc + lg[x]]
      if two == 1
        out[i] = out[i] ^ y
      else
        s = out[i] + y
        if s >= p
          s = s - p
        out[i] = s
    i += 1
  0

# out[c] = sum_a v[a] * mu(b, a, c): left multiplication by basis vector b
-> fda_lmul(b, v, out, d, ptr, ci, cv, ex, lg, p, two) (i64 i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  i = 0
  while i < d
    out[i] = 0
    i += 1
  a = 0
  while a < d
    x = v[a]
    if x != 0
      lx = lg[x]
      k = ptr[b * d + a]
      e = ptr[b * d + a + 1]
      while k < e
        y = ex[lx + lg[cv[k]]]
        c = ci[k]
        if two == 1
          out[c] = out[c] ^ y
        else
          s = out[c] + y
          if s >= p
            s = s - p
          out[c] = s
        k += 1
    a += 1
  0

# out[c] = sum_a v[a] * mu(a, b, c): right multiplication by basis vector b
-> fda_rmul(b, v, out, d, ptr, ci, cv, ex, lg, p, two) (i64 i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  i = 0
  while i < d
    out[i] = 0
    i += 1
  a = 0
  while a < d
    x = v[a]
    if x != 0
      lx = lg[x]
      k = ptr[a * d + b]
      e = ptr[a * d + b + 1]
      while k < e
        y = ex[lx + lg[cv[k]]]
        c = ci[k]
        if two == 1
          out[c] = out[c] ^ y
        else
          s = out[c] + y
          if s >= p
            s = s - p
          out[c] = s
        k += 1
    a += 1
  0

# ---- the field ---------------------------------------------------------------

+ FdField
  # GF(2^k) with a primitive polynomial (bit mask including x^k)
  -> .gf2(k)
    polys = {1 => 3, 2 => 7, 3 => 11, 4 => 19, 5 => 37, 6 => 67, 7 => 137, 8 => 285, 9 => 529, 10 => 1033,
             11 => 2053, 12 => 4179, 13 => 8219, 14 => 17475, 15 => 32771, 16 => 69643, 17 => 131081,
             18 => 262273, 19 => 524327, 20 => 1048585}
    raise "FdField.gf2: k must be in 1..20" if !polys.key?(k)
    FdField.new(2, k, polys[k])

  -> .prime(p)
    raise "FdField.prime: p must be a prime below 2^20" if p < 2 || p >= 1048576 || !p.prime?
    return FdField.gf2(1) if p == 2
    FdField.new(p, 1, 0)

  -> new(@p, @k, @poly)
    @two = 0
    @two = 1 if @p == 2
    @size = @p ** @k
    @ord = @size - 1
    @ex = i64[2 * @size + 2]
    @lg = i64[@size + 1]
    if @two == 1
      x = 1
      i = 0
      while i < @ord
        @ex[i] = x
        @lg[x] = i
        x = x << 1
        x = x ^ @poly if (x & @size) != 0
        i += 1
      raise "FdField: polynomial is not primitive" if x != 1
    else
      g = primitive_root(@p)
      x = 1
      i = 0
      while i < @ord
        @ex[i] = x
        @lg[x] = i
        x = (x * g) % @p
        i += 1
    i = @ord
    while i < 2 * @size + 2
      @ex[i] = @ex[i - @ord]
      i += 1
    # every nonzero element has a logarithm
    seen = 0
    i = 1
    while i < @size
      seen += 1 if @ex[@lg[i]] == i
      i += 1
    raise "FdField: log table is not a bijection" if seen != @ord
    self

  -> primitive_root(p)
    fs = []
    m = p - 1
    d = 2
    while d * d <= m
      if m % d == 0
        fs.push(d)
        while m % d == 0
          m = m / d
      d += 1
    fs.push(m) if m > 1
    g = 2
    while true
      ok = true
      fs.each ->(f)
        ok = false if FdField.modpow(g, (p - 1) / f, p) == 1
      return g if ok
      g += 1

  ro :p, :k, :size, :ord, :ex, :lg, :two

  -> .modpow(b, e, m)
    r = 1
    x = b % m
    while e > 0
      r = (r * x) % m if (e & 1) == 1
      x = (x * x) % m
      e = e >> 1
    r

  -> characteristic
    @p

  -> to_s
    return "GF(" + @p.to_s + ")" if @k == 1
    "GF(" + @p.to_s + "^" + @k.to_s + ")"

  -> gen
    return 2 if @two == 1
    @ex[1]

  -> add(a, b)
    fda_add(a, b, @p, @two)

  -> neg(a)
    fda_neg(a, @p, @two)

  -> sub(a, b)
    fda_add(a, fda_neg(b, @p, @two), @p, @two)

  -> mul(a, b)
    fda_mul(a, b, @ex, @lg)

  -> inv(a)
    raise "FdField: inverse of zero" if a == 0
    e = @ord - @lg[a]
    e = 0 if e == @ord
    @ex[e]

  -> div(a, b)
    mul(a, inv(b))

  -> pow(a, n)
    return 1 if n == 0
    return 0 if a == 0
    e = (@lg[a] * (n % @ord)) % @ord
    @ex[e]

  # multiplicative order of a nonzero element
  -> order_of(a)
    l = @lg[a]
    @ord / l.gcd(@ord)

  # element from an integer (prime field) or an F_2-polynomial bit mask in g
  -> from_int(n)
    return n % @p if @two == 0
    n & 1

  # evaluate sum_i bit_i x^i at x (char 2), or sum c_i x^i for a coefficient array
  -> poly(bits, x)
    acc = 0
    pw = 1
    b = bits
    while b != 0
      acc = acc ^ pw if (b & 1) == 1
      pw = mul(pw, x)
      b = b >> 1
    acc

  -> poly_coeffs(coeffs, x)
    acc = 0
    i = coeffs.size - 1
    while i >= 0
      acc = add(mul(acc, x), from_int(coeffs[i]))
      i -= 1
    acc

  -> elt_s(a)
    return a.to_s if @k == 1
    return "0" if a == 0
    "g^" + @lg[a].to_s

# ---- dense linear algebra helpers --------------------------------------------

# Reduce v in place against an echelon basis (see fda_insert); when track = 1,
# coefs[r] receives the multiple of row r that was subtracted. Returns 1 if a
# nonzero residual remains, 0 if v lay in the span.
-> fda_reduce(rows, prow, v, n, coefs, track, ex, lg, p, two) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64 i64) i64
  left = 0
  c = 0
  while c < n
    x = v[c]
    if x != 0
      r = prow[c]
      if r >= 0
        if track == 1
          coefs[r] = x
        lf = lg[fda_neg(x, p, two)]
        j = c
        while j < n
          y = rows[r * n + j]
          if y != 0
            z = ex[lf + lg[y]]
            if two == 1
              v[j] = v[j] ^ z
            else
              s = v[j] + z
              if s >= p
                s = s - p
              v[j] = s
          j += 1
      else
        left = 1
    c += 1
  left

# An incrementally built subspace of F^n in echelon form. Memory is one
# rank x n slab that grows geometrically; nothing is allocated per vector.
+ FdSpan
  -> new(@field, @n)
    @cap = 8
    @cap = @n if @n < 8
    @cap = 1 if @cap < 1
    @rows = i64[@cap * @n + 1]
    @prow = i64[@n + 1]
    @st = i64[2]
    @buf = i64[@n + 1]
    j = 0
    while j < @n
      @prow[j] = -1
      j += 1
    self

  ro :n

  -> rank
    @st[0]

  -> grow
    nc = @cap * 2
    nc = @n if nc > @n
    return self if nc <= @cap
    nr = i64[nc * @n + 1]
    i = 0
    lim = @st[0] * @n
    while i < lim
      nr[i] = @rows[i]
      i += 1
    @rows = nr
    @cap = nc
    self

  # insert v (not modified); true if it enlarged the span
  -> add(v)
    j = 0
    while j < @n
      @buf[j] = v[j]
      j += 1
    grow if @st[0] >= @cap
    f = @field
    fda_insert(@rows, @prow, @st, @buf, @n, f.ex, f.lg, f.p, f.two, f.ord) == 1

  -> contains?(v)
    j = 0
    while j < @n
      @buf[j] = v[j]
      j += 1
    f = @field
    fda_reduce(@rows, @prow, @buf, @n, @buf, 0, f.ex, f.lg, f.p, f.two) == 0

  # coefficients of v in the stored rows (v must lie in the span)
  -> coords(v)
    j = 0
    while j < @n
      @buf[j] = v[j]
      j += 1
    out = i64[@st[0] + 1]
    f = @field
    left = fda_reduce(@rows, @prow, @buf, @n, out, 1, f.ex, f.lg, f.p, f.two)
    raise "FdSpan: vector not in the span" if left != 0
    out

  -> row(r)
    v = i64[@n + 1]
    j = 0
    while j < @n
      v[j] = @rows[r * @n + j]
      j += 1
    v

  -> basis
    out = []
    r = 0
    while r < @st[0]
      out.push(row(r))
      r += 1
    out

+ FdLinear
  -> .rank(field, vecs, n)
    sp = FdSpan.new(field, n)
    vecs.each ->(v)
      sp.add(v)
    sp.rank

  # a basis of the span (echelon rows, not reduced) and their pivot columns
  -> .span(field, vecs, n)
    sp = FdSpan.new(field, n)
    vecs.each ->(v)
      sp.add(v)
    b = sp.basis
    pivs = []
    b.each ->(v)
      c = 0
      while c < n && v[c] == 0
        c += 1
      pivs.push(c)
    [b, pivs]

  # reduced row echelon basis of the span: [rows, pivot columns]
  -> .rref(field, vecs, n)
    return [[], []] if vecs.size == 0 || n == 0
    m = i64[vecs.size * n + 1]
    r = 0
    while r < vecs.size
      v = vecs[r]
      j = 0
      while j < n
        m[r * n + j] = v[j]
        j += 1
      r += 1
    piv = i64[vecs.size + n + 1]
    rk = fda_rref(m, vecs.size, n, piv, field.ex, field.lg, field.p, field.two, field.ord)
    rows = []
    pivs = []
    i = 0
    while i < rk
      v = i64[n + 1]
      j = 0
      while j < n
        v[j] = m[i * n + j]
        j += 1
      rows.push(v)
      pivs.push(piv[i])
      i += 1
    [rows, pivs]

  # vectors of cand that extend the span of base (greedy, in order)
  -> .extend(field, base, cand, n)
    sp = FdSpan.new(field, n)
    base.each ->(v)
      sp.add(v)
    chosen = []
    cand.each ->(v)
      chosen.push(v) if sp.add(v)
    chosen

  # kernel of the rows x cols matrix m (row-major, destroyed): basis vectors of
  # length cols
  -> .kernel_flat(field, m, rows, cols)
    out = []
    return out if cols == 0
    piv = i64[rows + cols + 1]
    r = 0
    r = fda_rref(m, rows, cols, piv, field.ex, field.lg, field.p, field.two, field.ord) if rows > 0
    is_piv = i64[cols + 1]
    i = 0
    while i < r
      is_piv[piv[i]] = 1
      i += 1
    j = 0
    while j < cols
      if is_piv[j] == 0
        v = i64[cols + 1]
        v[j] = 1
        i = 0
        while i < r
          v[piv[i]] = field.neg(m[i * cols + j])
          i += 1
        out.push(v)
      j += 1
    out

  # kernel of the map whose columns are cols (each of length n_rows)
  -> .kernel(field, cols, n_rows)
    nc = cols.size
    m = i64[n_rows * nc + 1]
    j = 0
    while j < nc
      col = cols[j]
      i = 0
      while i < n_rows
        m[i * nc + j] = col[i]
        i += 1
      j += 1
    FdLinear.kernel_flat(field, m, n_rows, nc)

# ---- the algebra ---------------------------------------------------------------

+ FdAlgebra
  -> new(@field, @dim, @names)
    @prod = {}
    @frozen = false
    @idem = []
    self

  ro :field, :dim, :names, :idem, :ptr, :ci, :cv, :lcorner, :rcorner, :arrows

  -> index(name)
    i = 0
    while i < @dim
      return i if @names[i] == name
      i += 1
    raise "FdAlgebra: no basis element " + name

  # accumulate coefficient coeff of basis c in the product a*b
  -> set(a, b, c, coeff)
    raise "FdAlgebra: frozen" if @frozen
    key = a * @dim + b
    h = @prod[key]
    if h == nil
      h = {}
      @prod[key] = h
    old = h[c]
    old = 0 if old == nil
    h[c] = @field.add(old, coeff)
    self

  -> set_idempotents(list)
    @idem = list
    self

  -> freeze
    return self if @frozen
    d = @dim
    @ptr = i64[d * d + 1]
    total = 0
    @prod.each ->(key, h)
      h.each ->(c, v)
        total += 1 if v != 0
    @ci = i64[total + 1]
    @cv = i64[total + 1]
    k = 0
    key = 0
    while key < d * d
      @ptr[key] = k
      h = @prod[key]
      if h != nil
        cs = []
        h.each ->(c, v)
          cs.push(c) if v != 0
        cs = cs.sort
        cs.each ->(c)
          @ci[k] = c
          @cv[k] = h[c]
          k += 1
      key += 1
    @ptr[d * d] = k
    @frozen = true
    @tmp_a = i64[d]
    @tmp_b = i64[d]
    compute_corners if @idem.size > 0
    self

  -> nnz
    @ptr[@dim * @dim]

  # coefficient of c in a*b
  -> coef(a, b, c)
    k = @ptr[a * @dim + b]
    e = @ptr[a * @dim + b + 1]
    while k < e
      return @cv[k] if @ci[k] == c
      k += 1
    0

  -> unit_vector(i)
    v = i64[@dim]
    v[i] = 1
    v

  # product of two element vectors
  -> mul_vec(x, y)
    out = i64[@dim]
    tmp = i64[@dim]
    b = 0
    while b < @dim
      if y[b] != 0
        fda_rmul(b, x, tmp, @dim, @ptr, @ci, @cv, @field.ex, @field.lg, @field.p, @field.two)
        fda_axpy(out, tmp, y[b], @dim, @field.ex, @field.lg, @field.p, @field.two)
      b += 1
    out

  -> lmul(b, v)
    out = i64[@dim]
    fda_lmul(b, v, out, @dim, @ptr, @ci, @cv, @field.ex, @field.lg, @field.p, @field.two)
    out

  -> rmul(v, b)
    out = i64[@dim]
    fda_rmul(b, v, out, @dim, @ptr, @ci, @cv, @field.ex, @field.lg, @field.p, @field.two)
    out

  -> vec_eq(x, y)
    i = 0
    while i < @dim
      return false if x[i] != y[i]
      i += 1
    true

  -> zero_vec?(x)
    i = 0
    while i < @dim
      return false if x[i] != 0
      i += 1
    true

  # the identity element (sum of the idempotents)
  -> one
    v = i64[@dim]
    @idem.each ->(i)
      v[i] = 1
    v

  -> verify_unit
    u = one
    b = 0
    while b < @dim
      e = unit_vector(b)
      return false if !vec_eq(mul_vec(u, e), e) || !vec_eq(mul_vec(e, u), e)
      b += 1
    true

  # (ab)c = a(bc) on all basis triples (or on triples with a < limit)
  -> verify_associative(limit = nil)
    lim = @dim
    lim = limit if limit != nil && limit < @dim
    bad = 0
    a = 0
    while a < lim
      ea = unit_vector(a)
      b = 0
      while b < @dim
        ab = rmul(ea, b)
        c = 0
        while c < @dim
          left = rmul(ab, c)
          bc = rmul(unit_vector(b), c)
          right = mul_vec(ea, bc)
          bad += 1 if !vec_eq(left, right)
          c += 1
        b += 1
      a += 1
    bad

  # e_i * b = b  iff  the product list of (e_i, b) is exactly [(b, 1)]
  -> exact_hit?(a, b, target)
    k = @ptr[a * @dim + b]
    e = @ptr[a * @dim + b + 1]
    e == k + 1 && @ci[k] == target && @cv[k] == 1

  -> compute_corners
    @lcorner = i64[@dim]
    @rcorner = i64[@dim]
    b = 0
    while b < @dim
      @lcorner[b] = -1
      @rcorner[b] = -1
      i = 0
      while i < @idem.size
        ei = @idem[i]
        @lcorner[b] = i if exact_hit?(ei, b, b)
        @rcorner[b] = i if exact_hit?(b, ei, b)
        i += 1
      raise "FdAlgebra: basis element " + @names[b] + " is not in a corner" if @lcorner[b] < 0 || @rcorner[b] < 0
      b += 1
    # columns of A e_i and positions inside them
    @cols = []
    @pos = i64[@dim]
    i = 0
    while i < @idem.size
      cl = []
      b = 0
      while b < @dim
        if @rcorner[b] == i
          @pos[b] = cl.size
          cl.push(b)
        b += 1
      @cols.push(cl)
      i += 1
    @is_idem = i64[@dim]
    @idem.each ->(e)
      @is_idem[e] = 1
    compute_arrows
    self

  -> cols(i)
    @cols[i]

  -> pos(b)
    @pos[b]

  -> idempotent?(b)
    @is_idem[b] == 1

  # radical basis (non-idempotent basis vectors)
  -> radical_basis
    out = []
    b = 0
    while b < @dim
      out.push(b) if @is_idem[b] == 0
      b += 1
    out

  # dims of J, J^2, J^3, ... until zero; J^k = J^(k-1) * arrows
  -> radical_power_dims(maxp = 60)
    d = @dim
    f = @field
    rows = i64[d * d + 1]
    prow = i64[d + 1]
    st = i64[2]
    buf = i64[d + 1]
    out = i64[d + 1]
    j = 0
    while j < d
      prow[j] = -1
      j += 1
    radical_basis.each ->(b)
      j = 0
      while j < d
        buf[j] = 0
        j += 1
      buf[b] = 1
      fda_insert(rows, prow, st, buf, d, f.ex, f.lg, f.p, f.two, f.ord)
    dims = [st[0]]
    k = 1
    while st[0] > 0 && k < maxp
      rows2 = i64[d * d + 1]
      prow2 = i64[d + 1]
      st2 = i64[2]
      j = 0
      while j < d
        prow2[j] = -1
        j += 1
      r = 0
      while r < st[0]
        @arrows.each ->(a)
          j = 0
          while j < d
            buf[j] = rows[r * d + j]
            j += 1
          fda_rmul(a, buf, out, d, @ptr, @ci, @cv, f.ex, f.lg, f.p, f.two)
          fda_insert(rows2, prow2, st2, out, d, f.ex, f.lg, f.p, f.two, f.ord)
        r += 1
      rows = rows2
      prow = prow2
      st = st2
      dims.push(st[0])
      k += 1
    dims

  # a basis of J/J^2 made of basis vectors (generators of J as a one- or
  # two-sided ideal); J^2 is spanned by the products of radical basis vectors
  -> compute_arrows
    d = @dim
    f = @field
    rows = i64[d * d + 1]
    prow = i64[d + 1]
    st = i64[2]
    buf = i64[d + 1]
    j = 0
    while j < d
      prow[j] = -1
      j += 1
    rad = radical_basis
    rad.each ->(a)
      rad.each ->(b)
        k = @ptr[a * d + b]
        e = @ptr[a * d + b + 1]
        if k < e
          j = 0
          while j < d
            buf[j] = 0
            j += 1
          while k < e
            buf[@ci[k]] = @cv[k]
            k += 1
          fda_insert(rows, prow, st, buf, d, f.ex, f.lg, f.p, f.two, f.ord)
    @j2dim = st[0]
    @arrows = []
    rad.each ->(b)
      j = 0
      while j < d
        buf[j] = 0
        j += 1
      buf[b] = 1
      @arrows.push(b) if fda_insert(rows, prow, st, buf, d, f.ex, f.lg, f.p, f.two, f.ord) == 1
    self

  # symmetric trace check: lambda given as a vector of values on the basis.
  # returns [symmetric?, rank of the Gram matrix]
  -> trace_form(lambda)
    gram = []
    sym = true
    a = 0
    while a < @dim
      row = i64[@dim]
      b = 0
      while b < @dim
        ab = rmul(unit_vector(a), b)
        ba = rmul(unit_vector(b), a)
        s = 0
        t = 0
        c = 0
        while c < @dim
          s = @field.add(s, @field.mul(ab[c], lambda[c]))
          t = @field.add(t, @field.mul(ba[c], lambda[c]))
          c += 1
        sym = false if s != t
        row[b] = s
        b += 1
      gram.push(row)
      a += 1
    [sym, FdLinear.rank(@field, gram, @dim)]

  # ---- constructions ----

  -> opposite
    nm = []
    @names.each ->(s)
      nm.push(s + "°")
    o = FdAlgebra.new(@field, @dim, nm)
    a = 0
    while a < @dim
      b = 0
      while b < @dim
        k = @ptr[a * @dim + b]
        e = @ptr[a * @dim + b + 1]
        while k < e
          o.set(b, a, @ci[k], @cv[k])
          k += 1
        b += 1
      a += 1
    o.set_idempotents(@idem)
    o.freeze

  # A (x) B with basis a(x)b at index a * dim(B) + b
  -> tensor(other)
    d2 = other.dim
    nm = []
    @names.each ->(s)
      other.names.each ->(t)
        nm.push(s + "⊗" + t)
    out = FdAlgebra.new(@field, @dim * d2, nm)
    a = 0
    while a < @dim
      b = 0
      while b < @dim
        k = @ptr[a * @dim + b]
        e = @ptr[a * @dim + b + 1]
        if k < e
          a2 = 0
          while a2 < d2
            b2 = 0
            while b2 < d2
              k2 = other.ptr[a2 * d2 + b2]
              e2 = other.ptr[a2 * d2 + b2 + 1]
              if k2 < e2
                i = k
                while i < e
                  j = k2
                  while j < e2
                    out.set(a * d2 + a2, b * d2 + b2, @ci[i] * d2 + other.ci[j], @field.mul(@cv[i], other.cv[j]))
                    j += 1
                  i += 1
              b2 += 1
            a2 += 1
        b += 1
      a += 1
    id = []
    @idem.each ->(i)
      other.idem.each ->(j)
        id.push(i * d2 + j)
    out.set_idempotents(id)
    out.freeze

  # trivial extension A x DA: basis a (index a) and a* (index dim + a)
  #   a * b^* = sum_c mu(c, a, b) c^*,   b^* * a = sum_c mu(a, c, b) c^*
  -> trivial_extension(star_names = nil)
    d = @dim
    nm = []
    @names.each ->(s)
      nm.push(s)
    i = 0
    while i < d
      if star_names != nil
        nm.push(star_names[i])
      else
        nm.push(@names[i] + "*")
      i += 1
    out = FdAlgebra.new(@field, 2 * d, nm)
    a = 0
    while a < d
      b = 0
      while b < d
        k = @ptr[a * d + b]
        e = @ptr[a * d + b + 1]
        while k < e
          c = @ci[k]
          v = @cv[k]
          out.set(a, b, c, v)
          # mu(a, b, c) = v contributes: b * c^* has a^* with coefficient v (c^* evaluated on a b)
          #   (b c^*)(x) = c^*(x b): x = a gives v -> coefficient of a^* in b * c^*
          out.set(b, d + c, d + a, v)
          #   (c^* a)(x) = c^*(a x): x = b gives v -> coefficient of b^* in c^* * a
          out.set(d + c, a, d + b, v)
          k += 1
        b += 1
      a += 1
    out.set_idempotents(@idem)
    out.freeze

  # the standard trace on a trivial extension: lambda(a, phi) = phi(1)
  -> te_trace
    lam = i64[2 * @dim]
    @idem.each ->(i)
      lam[@dim + i] = 1
    lam

  # bounded quiver algebra: vertices 0..nv-1, arrows [src, tgt] (composition
  # right to left: a path p = a_k ... a_1 starts at src(a_1)), relations as
  # lists of [coeff, [arrow indices in order of composition, last arrow first]],
  # and every path of length > maxlen set to zero.
  -> .quiver(field, nv, arrows, relations, maxlen, arrow_names = nil)
    paths = []        # each path: [src, tgt, [arrows last-first]]
    v = 0
    while v < nv
      paths.push([v, v, []])
      v += 1
    layer = []
    i = 0
    while i < arrows.size
      layer.push([arrows[i][0], arrows[i][1], [i]])
      i += 1
    len = 1
    while len <= maxlen && layer.size > 0
      layer.each ->(pp)
        paths.push(pp)
      nxt = []
      layer.each ->(pp)
        i = 0
        while i < arrows.size
          if arrows[i][0] == pp[1]
            w = [i]
            pp[2].each ->(x)
              w.push(x)
            nxt.push([pp[0], arrows[i][1], w])
          i += 1
      layer = nxt
      len += 1
    np = paths.size
    key = {}
    i = 0
    while i < np
      key[FdAlgebra.path_key(paths[i])] = i
      i += 1
    # ideal: span of u * rho * w for paths u, w
    gens = []
    relations.each ->(rel)
      paths.each ->(w)
        paths.each ->(u)
          vec = i64[np]
          nz = false
          rel.each ->(term)
            coeff = term[0]
            word = term[1]
            rs = arrows[word[word.size - 1]][0]
            rt = arrows[word[0]][1]
            if w[1] == rs && u[0] == rt
              full = []
              u[2].each ->(x)
                full.push(x)
              word.each ->(x)
                full.push(x)
              w[2].each ->(x)
                full.push(x)
              if full.size <= maxlen
                src = w[0]
                src = rs if w[2].size == 0
                k = key[FdAlgebra.path_key([src, 0, full])]
                if k != nil
                  vec[k] = field.add(vec[k], coeff)
                  nz = true
          gens.push(vec) if nz
    sp = FdLinear.rref(field, gens, np)
    ideal = sp[0]
    pivots = sp[1]
    is_piv = {}
    pivots.each ->(c)
      is_piv[c] = true
    # quotient basis: non-pivot paths (normal form = reduce by the RREF rows)
    qb = []
    i = 0
    while i < np
      qb.push(i) if !is_piv[i]
      i += 1
    names = []
    qb.each ->(i)
      names.push(FdAlgebra.path_name(paths[i], arrows, nv, arrow_names))
    alg = FdAlgebra.new(field, qb.size, names)
    qpos = {}
    j = 0
    while j < qb.size
      qpos[qb[j]] = j
      j += 1
    piv_row = {}
    j = 0
    while j < pivots.size
      piv_row[pivots[j]] = ideal[j]
      j += 1
    a = 0
    while a < qb.size
      pa = paths[qb[a]]
      b = 0
      while b < qb.size
        pb = paths[qb[b]]
        # product pa * pb (pb first): needs tgt(pb) = src(pa)
        if pb[1] == pa[0]
          full = []
          pa[2].each ->(x)
            full.push(x)
          pb[2].each ->(x)
            full.push(x)
          if full.size <= maxlen
            k = key[FdAlgebra.path_key([pb[0], 0, full])]
            if k != nil
              if is_piv[k]
                row = piv_row[k]
                # path_k = - sum_{nonpivot c} row[c] path_c
                c = 0
                while c < np
                  if c != k && row[c] != 0
                    alg.set(a, b, qpos[c], field.neg(row[c]))
                  c += 1
              else
                alg.set(a, b, qpos[k], 1)
        b += 1
      a += 1
    id = []
    v = 0
    while v < nv
      id.push(qpos[v])
      v += 1
    bp = []
    qb.each ->(i)
      bp.push(paths[i])
    alg.set_paths(bp, arrows)
    alg.set_idempotents(id)
    alg.freeze

  # basis paths of a quiver algebra: [src, tgt, arrows last-first]
  -> set_paths(@paths, @qarrows)
    self

  ro :paths, :qarrows

  # split square-zero extension D x X for a D-bimodule X with basis x_0..x_(n-1):
  # lmats[b] (n x n, column j = b x_j) and rmats[b] (column j = x_j b) for the
  # basis vectors b of D; X * X = 0. Basis: D's basis, then X's.
  -> square_zero_extension(xdim, xnames, lmats, rmats)
    d = @dim
    nm = []
    @names.each ->(s)
      nm.push(s)
    xnames.each ->(s)
      nm.push(s)
    out = FdAlgebra.new(@field, d + xdim, nm)
    a = 0
    while a < d
      b = 0
      while b < d
        k = @ptr[a * d + b]
        e = @ptr[a * d + b + 1]
        while k < e
          out.set(a, b, @ci[k], @cv[k])
          k += 1
        b += 1
      lm = lmats[a]
      rm = rmats[a]
      j = 0
      while j < xdim
        i = 0
        while i < xdim
          out.set(a, d + j, d + i, lm[i * xdim + j]) if lm[i * xdim + j] != 0
          out.set(d + j, a, d + i, rm[i * xdim + j]) if rm[i * xdim + j] != 0
          i += 1
        j += 1
      a += 1
    out.set_idempotents(@idem)
    out.freeze

  -> .path_key(pp)
    s = pp[0].to_s + ":"
    pp[2].each ->(x)
      s = s + x.to_s + "."
    s

  -> .path_name(pp, arrows, nv, arrow_names)
    return "e" + pp[0].to_s if pp[2].size == 0
    s = ""
    pp[2].each ->(x)
      if arrow_names != nil
        s = s + arrow_names[x]
      else
        s = s + "a" + x.to_s
    s

# ---- modules over a frozen basic algebra --------------------------------------

# A finite module given by the matrices of all basis vectors (column j of
# act[b] is b * m_j).
+ FdModule
  -> new(@alg, @dim, @act)
    @field = @alg.field
    self

  ro :alg, :dim, :act

  # the simple module at idempotent number i
  -> .simple(alg, i)
    acts = []
    b = 0
    while b < alg.dim
      m = i64[1]
      m[0] = 1 if b == alg.idem[i]
      acts.push(m)
      b += 1
    FdModule.new(alg, 1, acts)

  # the left module A e_i (basis = alg.cols(i))
  -> .projective(alg, i)
    cl = alg.cols(i)
    n = cl.size
    acts = []
    b = 0
    while b < alg.dim
      m = i64[n * n + 1]
      j = 0
      while j < n
        w = alg.lmul(b, alg.unit_vector(cl[j]))
        r = 0
        while r < n
          m[r * n + j] = w[cl[r]]
          r += 1
        j += 1
      acts.push(m)
      b += 1
    FdModule.new(alg, n, acts)

  # the regular left module A
  -> .regular(alg)
    n = alg.dim
    acts = []
    b = 0
    while b < n
      m = i64[n * n + 1]
      j = 0
      while j < n
        w = alg.lmul(b, alg.unit_vector(j))
        r = 0
        while r < n
          m[r * n + j] = w[r]
          r += 1
        j += 1
      acts.push(m)
      b += 1
    FdModule.new(alg, n, acts)

  # a representation of a quiver algebra: vdims[v] = dimension at vertex v,
  # amats[k] = matrix of arrow k (row-major, dim(tgt) x dim(src))
  -> .from_representation(alg, vdims, amats)
    nv = vdims.size
    off = []
    t = 0
    vdims.each ->(x)
      off.push(t)
      t += x
    n = t
    f = alg.field
    acts = []
    alg.paths.each ->(pp)
      m = i64[n * n + 1]
      src = pp[0]
      tgt = pp[1]
      ds = vdims[src]
      # start with the identity on the source space, apply arrows first-to-last
      cur = i64[ds * ds + 1]
      i = 0
      while i < ds
        cur[i * ds + i] = 1
        i += 1
      rows = ds
      k = pp[2].size - 1
      while k >= 0
        ar = pp[2][k]
        at = alg.qarrows[ar][1]
        dt = vdims[at]
        am = amats[ar]
        nxt = i64[dt * ds + 1]
        r = 0
        while r < dt
          c = 0
          while c < ds
            acc = 0
            j = 0
            while j < rows
              acc = f.add(acc, f.mul(am[r * rows + j], cur[j * ds + c]))
              j += 1
            nxt[r * ds + c] = acc
            c += 1
          r += 1
        cur = nxt
        rows = dt
        k -= 1
      r = 0
      while r < vdims[tgt]
        c = 0
        while c < ds
          m[(off[tgt] + r) * n + off[src] + c] = cur[r * ds + c]
          c += 1
        r += 1
      acts.push(m)
    FdModule.new(alg, n, acts)

  # a module over a quotient D, inflated along big -> D (basis of D first,
  # all other basis vectors of big act by zero)
  -> .inflate(big, m)
    acts = []
    b = 0
    while b < big.dim
      if b < m.alg.dim
        acts.push(m.act[b])
      else
        acts.push(i64[m.dim * m.dim + 1])
      b += 1
    FdModule.new(big, m.dim, acts)

  # act[a] act[b] = sum_c mu(a,b,c) act[c] for all basis pairs; returns failures
  -> verify_module
    f = @field
    n = @dim
    bad = 0
    a = 0
    while a < @alg.dim
      b = 0
      while b < @alg.dim
        lhs = i64[n * n + 1]
        ma = @act[a]
        mb = @act[b]
        r = 0
        while r < n
          c = 0
          while c < n
            acc = 0
            j = 0
            while j < n
              x = ma[r * n + j]
              acc = f.add(acc, f.mul(x, mb[j * n + c])) if x != 0
              j += 1
            lhs[r * n + c] = acc
            c += 1
          r += 1
        k = @alg.ptr[a * @alg.dim + b]
        e = @alg.ptr[a * @alg.dim + b + 1]
        while k < e
          mc = @act[@alg.ci[k]]
          co = @alg.cv[k]
          j = 0
          while j < n * n
            lhs[j] = f.sub(lhs[j], f.mul(co, mc[j])) if mc[j] != 0
            j += 1
          k += 1
        j = 0
        ok = true
        while j < n * n
          ok = false if lhs[j] != 0
          j += 1
        bad += 1 if !ok
        b += 1
      a += 1
    bad

  -> apply(b, v)
    out = i64[@dim + 1]
    m = @act[b]
    j = 0
    while j < @dim
      if v[j] != 0
        r = 0
        while r < @dim
          x = m[r * @dim + j]
          out[r] = @field.add(out[r], @field.mul(x, v[j])) if x != 0
          r += 1
      j += 1
    out

  # e_i M as an FdSpan
  -> corner(i)
    e = @alg.idem[i]
    sp = FdSpan.new(@field, @dim)
    j = 0
    while j < @dim
      u = i64[@dim + 1]
      u[j] = 1
      sp.add(apply(e, u))
      j += 1
    sp

# Minimal projective resolution. Degree n has generators gens[n] (idempotent
# numbers) and, for n >= 1, images imgs[n][g] in P_{n-1} coordinates.
# Scratch vectors are reused, so memory is dominated by the kernels themselves.
+ FdResolution
  -> new(@alg, @maxdeg)
    @field = @alg.field
    @gens = []
    @imgs = []
    @offs = []
    @dims = []
    @full = i64[@alg.dim + 1]
    @res = i64[@alg.dim + 1]
    @complete = false
    self

  ro :alg, :gens, :imgs, :dims, :maxdeg

  -> .of_simple(alg, i, maxdeg)
    r = FdResolution.new(alg, maxdeg)
    r.start_simple(i)

  -> .of_module(alg, m, maxdeg)
    r = FdResolution.new(alg, maxdeg)
    r.start_module(m)

  -> set_degree(n, gl, il)
    @gens.push(gl)
    @imgs.push(il)
    offs = []
    t = 0
    gl.each ->(i)
      offs.push(t)
      t += @alg.cols(i).size
    @offs.push(offs)
    @dims.push(t)
    self

  -> start_simple(i)
    set_degree(0, [i], [])
    # Omega^1 = rad(A e_i): basis vectors c in cols(i) other than e_i
    cl = @alg.cols(i)
    k = []
    j = 0
    while j < cl.size
      if cl[j] != @alg.idem[i]
        v = i64[cl.size + 1]
        v[j] = 1
        k.push(v)
      j += 1
    run_from(k)

  -> start_module(m)
    gl = []
    lifts = []
    i = 0
    while i < @alg.idem.size
      sp = FdSpan.new(@field, m.dim)
      @alg.arrows.each ->(a)
        if @alg.lcorner[a] == i
          j = 0
          while j < m.dim
            u = i64[m.dim + 1]
            u[j] = 1
            sp.add(m.apply(a, u))
            j += 1
      base = sp.rank
      ci = m.corner(i)
      r = 0
      while r < ci.rank
        v = ci.row(r)
        if sp.add(v)
          gl.push(i)
          lifts.push(v)
        r += 1
      i += 1
    set_degree(0, gl, [])
    @top_lifts = lifts
    colsv = []
    g = 0
    while g < gl.size
      @alg.cols(gl[g]).each ->(c)
        colsv.push(m.apply(c, lifts[g]))
      g += 1
    run_from(FdLinear.kernel(@field, colsv, m.dim))

  # out <- b * v for a vector v of P_n
  -> act_into(n, b, v, out)
    gl = @gens[n]
    d = @alg.dim
    full = @full
    res = @res
    j = 0
    while j < @dims[n]
      out[j] = 0
      j += 1
    g = 0
    while g < gl.size
      cl = @alg.cols(gl[g])
      o = @offs[n][g]
      nz = false
      j = 0
      while j < cl.size
        if v[o + j] != 0
          nz = true
        j += 1
      if nz
        j = 0
        while j < d
          full[j] = 0
          j += 1
        j = 0
        while j < cl.size
          full[cl[j]] = v[o + j]
          j += 1
        fda_lmul(b, full, res, d, @alg.ptr, @alg.ci, @alg.cv, @field.ex, @field.lg, @field.p, @field.two)
        j = 0
        while j < cl.size
          out[o + j] = res[cl[j]]
          j += 1
      g += 1
    out

  -> act(n, b, v)
    act_into(n, b, v, i64[@dims[n] + 1])

  # out <- e_i v
  -> corner_into(n, i, v, out)
    gl = @gens[n]
    g = 0
    while g < gl.size
      cl = @alg.cols(gl[g])
      o = @offs[n][g]
      j = 0
      while j < cl.size
        if @alg.lcorner[cl[j]] == i
          out[o + j] = v[o + j]
        else
          out[o + j] = 0
        j += 1
      g += 1
    out

  # given a basis of the kernel K of P_n -> P_(n-1) (or -> M), continue to maxdeg
  -> run_from(kbasis)
    k = kbasis
    n = 0
    while n < @maxdeg && k.size > 0
      dn = @dims[n]
      t1 = i64[dn + 1]
      t2 = i64[dn + 1]
      gl = []
      lifts = []
      i = 0
      while i < @alg.idem.size
        sp = FdSpan.new(@field, dn)
        @alg.arrows.each ->(a)
          if @alg.lcorner[a] == i
            src = @alg.rcorner[a]
            k.each ->(v)
              corner_into(n, src, v, t1)
              act_into(n, a, t1, t2)
              sp.add(t2)
        k.each ->(v)
          corner_into(n, i, v, t1)
          if sp.add(t1)
            gl.push(i)
            lifts.push(sp.row(sp.rank - 1))
        i += 1
      set_degree(n + 1, gl, lifts)
      # matrix of d_(n+1): column (g, c) is c * lift_g
      nc = @dims[n + 1]
      m = i64[dn * nc + 1]
      col = 0
      g = 0
      while g < gl.size
        @alg.cols(gl[g]).each ->(c)
          act_into(n, c, lifts[g], t2)
          r = 0
          while r < dn
            m[r * nc + col] = t2[r]
            r += 1
          col += 1
        g += 1
      k = FdLinear.kernel_flat(@field, m, dn, nc)
      n += 1
    @complete = (k.size == 0)
    self

  # true when the resolution terminated (finite projective dimension)
  -> finite?
    @complete

  -> length
    @gens.size - 1

  # dim Ext^n(M, S_i): rows n, columns i
  -> ext_simple_table
    out = []
    @gens.each ->(gl)
      row = []
      i = 0
      while i < @alg.idem.size
        c = 0
        gl.each ->(x)
          c += 1 if x == i
        row.push(c)
        i += 1
      out.push(row)
    out

  # dims of Ext^n(M, N) for a finite module N, n = 0 .. (computed length)
  -> ext_dims(nmod)
    f = @field
    cb = []
    i = 0
    while i < @alg.idem.size
      cb.push(nmod.corner(i))
      i += 1
    homdim = []
    n = 0
    while n < @gens.size
      t = 0
      @gens[n].each ->(i)
        t += cb[i].rank
      homdim.push(t)
      n += 1
    val = i64[nmod.dim + 1]
    ranks = []
    n = 0
    while n + 1 < @gens.size
      sp = FdSpan.new(f, homdim[n + 1])
      gl = @gens[n]
      gl1 = @gens[n + 1]
      g = 0
      while g < gl.size
        cl = @alg.cols(gl[g])
        o = @offs[n][g]
        r0 = 0
        while r0 < cb[gl[g]].rank
          bv = cb[gl[g]].row(r0)
          img = i64[homdim[n + 1] + 1]
          pos = 0
          h = 0
          while h < gl1.size
            lift = @imgs[n + 1][h]
            j = 0
            while j < nmod.dim
              val[j] = 0
              j += 1
            j = 0
            while j < cl.size
              if lift[o + j] != 0
                w = nmod.apply(cl[j], bv)
                fda_axpy(val, w, lift[o + j], nmod.dim, f.ex, f.lg, f.p, f.two)
              j += 1
            cbh = cb[gl1[h]]
            if cbh.rank > 0
              co = cbh.coords(val)
              j = 0
              while j < cbh.rank
                img[pos + j] = co[j]
                j += 1
            pos += cbh.rank
            h += 1
          sp.add(img)
          r0 += 1
        g += 1
      ranks.push(sp.rank)
      n += 1
    out = []
    n = 0
    while n + 1 < @gens.size
      r_in = 0
      r_in = ranks[n - 1] if n > 0
      out.push(homdim[n] - ranks[n] - r_in)
      n += 1
    if @complete
      last = @gens.size - 1
      r_in = 0
      r_in = ranks[last - 1] if last > 0
      out.push(homdim[last] - r_in)
    out
