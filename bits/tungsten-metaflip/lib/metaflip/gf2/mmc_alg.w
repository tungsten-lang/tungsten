# GF(2) bilinear matmul schemes with the composition primitives of matmulcatalog, re-implemented index for index (Compose,
# Recombination, SerendipitousBudProduct, NonCubicBilinearAlgorithm orientations). Port of tools/mmc_gf2_alg.py: the
# algebra half of the replay of the catalogue's recipes (catalogue.w); it does no I/O.
#
# A scheme is a Metaflip:Gf2:Scheme (n, m, p and the terms u, v, w as Integer masks; u: bit i*m+j, v: bit j*p+k, w: bit i*p+k,
# which is MFW1 and matmulcatalog's row-major layout). Every function returns new schemes and keeps the orders of the
# original (the replay indexes terms by position, so term order is part of the result).
#
#   MmcAlg.apply_orientation(a, code)      the code-th orientation (ORIENT_PERMS order)
#   MmcAlg.orient_by_perm(a, perm)         the orientation with permutation perm
#   MmcAlg.permute_axes(a, "ABC->XYZ")     SymmetryTransforms.permuteAxes; nil if the text is no bijection
#   MmcAlg.s3_orbit_with_perms(a)          [[scheme, "ABC->XYZ"], ...] without repeats, in SymmetryTransforms' order
#   MmcAlg.orientations(a)                 the distinct-shape orientations in LineageReplayer.orientations' order
#   MmcAlg.axis_permute(a, perm_a, perm_b, perm_c)   the indices of each axis permuted
#   MmcAlg.kron(outer, inner)              the Kronecker product scheme
#   MmcAlg.concat_cols / concat_rows / concat_inner_r(a, b)   ConcatCols (+p), ConcatRows (+n), SumInner (+m); a mismatch is
#                                          tried in every orientation (robustConcat); raises MmcError
#   MmcAlg.project(a, keepN, keepM, keepP) the sub-scheme on the kept indices of each axis
#   MmcAlg.recombination(base, allocA, allocB, allocC, lookup)    Recombination.constructWithAllocation (no peel);
#                                          lookup.call(shape) -> a scheme of exactly that shape, or nil
#   MmcAlg.serendipitous(outer, n2, m2, p2, resolve, rank_of)        SerendipitousBudProduct.productViaBudsBest over GF(2);
#                                          resolve.call(shape) -> a scheme oriented exactly (or nil), rank_of.call(shape) -> rank or nil
#   MmcAlg.clean(a)                        Scheme#cleaned
#
# `MmcError` stands for the ValueError of the original; its `to_s` is the original's message.
use scheme
use textx

+ MmcError < Error

+ Metaflip:Gf2:MmcAlg
  # ---- bit remaps -------------------------------------------------------------------------------

  # The mask with bit table[b] set for every set bit b of x (table entries below zero drop the bit).
  -> .remap(x, table)
    positions = Metaflip:Gf2:Bits.positions(x)
    target = []
    positions.each -> (b)
      target.push(table[b]) if table[b] >= 0
    y = Metaflip:Gf2:Bits.from_positions(target)
    Metaflip:Gf2:Bits.release(positions)
    Metaflip:Gf2:Bits.release(target)
    y

  # place the bits of an (? x ci) matrix into rows of width `cols` (bit ib*ci+jb -> ib*cols+jb)
  -> .spread(x, ci, cols)
    return x if ci == cols
    positions = Metaflip:Gf2:Bits.positions(x)
    target = []
    positions.each -> (b)
      target.push((b / ci) * cols + b % ci)
    y = Metaflip:Gf2:Bits.from_positions(target)
    Metaflip:Gf2:Bits.release(positions)
    Metaflip:Gf2:Bits.release(target)
    y

  # row-major (R x oldc) -> (R x newc), columns shifted by `off`
  -> .rewidth(x, oldc, newc, off)
    return x if oldc == newc && off == 0
    positions = Metaflip:Gf2:Bits.positions(x)
    target = []
    positions.each -> (b)
      target.push((b / oldc) * newc + off + b % oldc)
    y = Metaflip:Gf2:Bits.from_positions(target)
    Metaflip:Gf2:Bits.release(positions)
    Metaflip:Gf2:Bits.release(target)
    y

  # ---- orientations -------------------------------------------------------------------------------

  -> .apply_orientation(a, code)
    a.oriented(Metaflip:Gf2:Scheme.orient_perms[code])

  -> .orient_by_perm(a, perm)
    a.oriented(perm)

  # SymmetryTransforms.permuteAxes ("ABC->XYZ" or "NMP->XYZ"); nil when it is not a bijection
  -> .permute_axes(a, perm)
    arrow = perm.index("->")
    return nil if arrow == nil || perm.size - arrow - 2 < 3
    target = perm.slice(arrow + 2, 3).replace("N", "A").replace("M", "B").replace("P", "C")
    return a if target == "ABC"
    return a.transpose if target == "CBA"
    return a.cyclic_shift if target == "BCA"
    return a.cyclic_shift.cyclic_shift if target == "CAB"
    return a.cyclic_shift.transpose if target == "ACB"
    return a.transpose.cyclic_shift if target == "BAC"
    nil

  # the exact content of a scheme, as a key
  -> .content_key(a)
    parts = [a.n.to_s, a.m.to_s, a.p.to_s]
    a.terms.each -> (term)
      parts.push(Metaflip:Gf2:Bits.to_hex(term[0]) + " " + Metaflip:Gf2:Bits.to_hex(term[1]) + " " + Metaflip:Gf2:Bits.to_hex(term[2]))
    parts.join("\n")

  # SymmetryTransforms.s3OrbitWithPerms order (dedup by exact content)
  -> .s3_orbit_with_perms(a)
    out = []
    seen = {}
    current = a
    tag = "ABC"
    3.times -> (round)
      reversed = tag.slice(2, 1) + tag.slice(1, 1) + tag.slice(0, 1)
      [[current, "ABC->" + tag], [current.transpose, "ABC->" + reversed]].each -> (pair)
        key = Metaflip:Gf2:MmcAlg.content_key(pair[0])
        if !seen.key?(key)
          seen[key] = true
          out.push(pair)
      current = current.cyclic_shift
      tag = tag.slice(1, 2) + tag.slice(0, 1)
    out

  # LineageReplayer.orientations: distinct-shape orientations in its fixed order
  -> .orientations(a)
    n = a.n
    m = a.m
    p = a.p
    out = []
    seen = {}
    [[n, m, p], [n, p, m], [m, n, p], [m, p, n], [p, n, m], [p, m, n]].each -> (shape)
      key = shape.join("x")
      if !seen.key?(key)
        o = a.orient_as(shape)
        if o != nil
          seen[key] = true
          out.push(o)
    out

  -> .axis_permute(a, perm_a, perm_b, perm_c)
    n = a.n
    m = a.m
    p = a.p
    tu = []
    n.times -> (i)
      m.times -> (j)
        tu.push(perm_a[i] * m + perm_b[j])
    tv = []
    m.times -> (j)
      p.times -> (l)
        tv.push(perm_b[j] * p + perm_c[l])
    tw = []
    n.times -> (i)
      p.times -> (l)
        tw.push(perm_a[i] * p + perm_c[l])
    terms = a.terms.map -> (term)
      [Metaflip:Gf2:MmcAlg.remap(term[0], tu), Metaflip:Gf2:MmcAlg.remap(term[1], tv), Metaflip:Gf2:MmcAlg.remap(term[2], tw)]
    Metaflip:Gf2:Scheme.from_terms(n, m, p, terms)

  # ---- Kronecker product ---------------------------------------------------------------------------------

  # Compose.kronFactor on one column: outer (ro x co) (x) inner (ri x ci)
  -> .kron_bits(xo, xi, ro, co, ri, ci)
    cols = co * ci
    spread = Metaflip:Gf2:MmcAlg.spread(xi, ci, cols)
    outer_positions = Metaflip:Gf2:Bits.positions(xo)
    y = 0
    outer_positions.each -> (b)
      shifted = spread << ((b / co) * ri * cols + (b % co) * ci)
      joined = y | shifted
      Metaflip:Gf2:Bits.release(shifted)
      Metaflip:Gf2:Bits.release(y)
      y = joined
    Metaflip:Gf2:Bits.release(outer_positions)
    y

  -> .kron(o, i)
    terms = []
    inner_terms = i.terms
    o.terms.each -> (a)
      inner_terms.each -> (b)
        terms.push([Metaflip:Gf2:MmcAlg.kron_bits(a[0], b[0], o.n, o.m, i.n, i.m), Metaflip:Gf2:MmcAlg.kron_bits(a[1], b[1], o.m, o.p, i.m, i.p), Metaflip:Gf2:MmcAlg.kron_bits(a[2], b[2], o.n, o.p, i.n, i.p)])
    Metaflip:Gf2:Scheme.from_terms(o.n * i.n, o.m * i.m, o.p * i.p, terms)

  # ---- concatenation ---------------------------------------------------------------------------------------

  # ConcatCols (+p)
  -> .concat_right(l, r)
    raise MmcError.new("concatRight shape mismatch") if l.n != r.n || l.m != r.m
    p1 = l.p
    p2 = r.p
    p = p1 + p2
    terms = l.terms.map -> (t)
      [t[0], Metaflip:Gf2:MmcAlg.rewidth(t[1], p1, p, 0), Metaflip:Gf2:MmcAlg.rewidth(t[2], p1, p, 0)]
    r.terms.each -> (t)
      terms.push([t[0], Metaflip:Gf2:MmcAlg.rewidth(t[1], p2, p, p1), Metaflip:Gf2:MmcAlg.rewidth(t[2], p2, p, p1)])
    Metaflip:Gf2:Scheme.from_terms(l.n, l.m, p, terms)

  # ConcatRows (+n)
  -> .concat_below(top, bottom)
    raise MmcError.new("concatBelow shape mismatch") if top.m != bottom.m || top.p != bottom.p
    n1 = top.n
    terms = top.terms.map -> (t)
      [t[0], t[1], t[2]]
    bottom.terms.each -> (t)
      terms.push([t[0] << (n1 * top.m), t[1], t[2] << (n1 * top.p)])
    Metaflip:Gf2:Scheme.from_terms(n1 + bottom.n, top.m, top.p, terms)

  # SumInner (+m)
  -> .concat_inner(l, r)
    raise MmcError.new("concatInner shape mismatch") if l.n != r.n || l.p != r.p
    m1 = l.m
    m2 = r.m
    m = m1 + m2
    terms = l.terms.map -> (t)
      [Metaflip:Gf2:MmcAlg.rewidth(t[0], m1, m, 0), t[1], t[2]]
    r.terms.each -> (t)
      terms.push([Metaflip:Gf2:MmcAlg.rewidth(t[0], m2, m, m1), t[1] << (m1 * l.p), t[2]])
    Metaflip:Gf2:Scheme.from_terms(l.n, m, l.p, terms)

  -> .robust_concat(a, b, axis)
    found = nil
    Metaflip:Gf2:MmcAlg.orientations(a).each -> (oa)
      Metaflip:Gf2:MmcAlg.orientations(b).each -> (ob)
        if found == nil
          if axis == "P" && oa.n == ob.n && oa.m == ob.m
            found = Metaflip:Gf2:MmcAlg.concat_right(oa, ob)
          elsif axis == "N" && oa.m == ob.m && oa.p == ob.p
            found = Metaflip:Gf2:MmcAlg.concat_below(oa, ob)
          elsif axis == "M" && oa.n == ob.n && oa.p == ob.p
            found = Metaflip:Gf2:MmcAlg.concat_inner(oa, ob)
    raise MmcError.new("robustConcat: no compatible orientation " + Metaflip:Gf2:MmcAlg.repr(a) + " " + Metaflip:Gf2:MmcAlg.repr(b)) if found == nil
    found

  # Alg.__repr__: "Alg<n,m,p>=rank"
  -> .repr(a)
    "Alg<" + a.n.to_s + "," + a.m.to_s + "," + a.p.to_s + ">=" + a.rank.to_s

  -> .concat_cols(a, b)
    return Metaflip:Gf2:MmcAlg.concat_right(a, b) if a.n == b.n && a.m == b.m
    Metaflip:Gf2:MmcAlg.robust_concat(a, b, "P")

  -> .concat_rows(a, b)
    return Metaflip:Gf2:MmcAlg.concat_below(a, b) if a.m == b.m && a.p == b.p
    Metaflip:Gf2:MmcAlg.robust_concat(a, b, "N")

  -> .concat_inner_r(a, b)
    return Metaflip:Gf2:MmcAlg.concat_inner(a, b) if a.n == b.n && a.p == b.p
    Metaflip:Gf2:MmcAlg.robust_concat(a, b, "M")

  # ---- projection ------------------------------------------------------------------------------------------

  # inverse index table: position -> new index or -1
  -> .inverse(keep, dim)
    table = []
    dim.times -> (i)
      table.push(0 - 1)
    keep.each_with_index -> (k, i)
      table[k] = i
    table

  # bit b of an (rows x old_cols) matrix -> its index in the (kept rows x new_cols) matrix, or -1
  -> .keep_table(inv_rows, inv_cols, old_cols, new_cols)
    table = []
    (inv_rows.size * old_cols).times -> (b)
      r = inv_rows[b / old_cols]
      c = inv_cols[b % old_cols]
      table.push(r >= 0 && c >= 0 ? r * new_cols + c : 0 - 1)
    table

  -> .project(a, keep_n, keep_m, keep_p)
    n2 = keep_n.size
    m2 = keep_m.size
    p2 = keep_p.size
    # (the original would build a scheme with an empty axis, which no recipe does and Scheme refuses)
    raise MmcError.new("projection onto an empty index list") if n2 == 0 || m2 == 0 || p2 == 0
    inv_n = Metaflip:Gf2:MmcAlg.inverse(keep_n, a.n)
    inv_m = Metaflip:Gf2:MmcAlg.inverse(keep_m, a.m)
    inv_p = Metaflip:Gf2:MmcAlg.inverse(keep_p, a.p)
    tu = Metaflip:Gf2:MmcAlg.keep_table(inv_n, inv_m, a.m, m2)
    tv = Metaflip:Gf2:MmcAlg.keep_table(inv_m, inv_p, a.p, p2)
    tw = Metaflip:Gf2:MmcAlg.keep_table(inv_n, inv_p, a.p, p2)
    out = []
    a.terms.each -> (t)
      u = Metaflip:Gf2:MmcAlg.remap(t[0], tu)
      if u != 0
        v = Metaflip:Gf2:MmcAlg.remap(t[1], tv)
        if v != 0
          w = Metaflip:Gf2:MmcAlg.remap(t[2], tw)
          out.push([u, v, w]) if w != 0
    Metaflip:Gf2:Scheme.from_terms(n2, m2, p2, out)

  # ---- recombination -----------------------------------------------------------------------------------------

  # the largest row and column allocation of the cells set in x (a matrix with `cols` columns)
  -> .max_alloc(x, cols, row_alloc, col_alloc)
    mr = 0
    mc = 0
    positions = Metaflip:Gf2:Bits.positions(x)
    positions.each -> (b)
      i = b / cols
      j = b % cols
      mr = row_alloc[i] if row_alloc[i] > mr
      mc = col_alloc[j] if col_alloc[j] > mc
    Metaflip:Gf2:Bits.release(positions)
    [mr, mc]

  -> .recomb_subshapes(base, alloc_a, alloc_b, alloc_c)
    base.terms.map -> (t)
      uu = Metaflip:Gf2:MmcAlg.max_alloc(t[0], base.m, alloc_a, alloc_b)
      vv = Metaflip:Gf2:MmcAlg.max_alloc(t[1], base.p, alloc_b, alloc_c)
      ww = Metaflip:Gf2:MmcAlg.max_alloc(t[2], base.p, alloc_a, alloc_c)
      [uu[0] < ww[0] ? uu[0] : ww[0], uu[1] < vv[0] ? uu[1] : vv[0], vv[1] < ww[1] ? vv[1] : ww[1]]

  -> .cumulative(a)
    c = [0]
    a.each -> (x)
      c.push(c.last + x)
    c

  # the brs x bcs block of ones in a matrix with `cols` columns (cached in `cache`)
  -> .block_mask(brs, bcs, cols, cache)
    key = brs.to_s + "," + bcs.to_s + "," + cols.to_s
    return cache[key] if cache.key?(key)
    positions = []
    brs.times -> (i)
      bcs.times -> (j)
        positions.push(i * cols + j)
    mask = Metaflip:Gf2:Bits.from_positions(positions)
    Metaflip:Gf2:Bits.release(positions)
    cache[key] = mask
    mask

  -> .embed(base_x, sub_x, base_cols, sub_cols, row_alloc, col_alloc, cum_r, cum_c, target_cols, cache)
    s = Metaflip:Gf2:MmcAlg.spread(sub_x, sub_cols, target_cols)
    y = 0
    positions = Metaflip:Gf2:Bits.positions(base_x)
    positions.each -> (b)
      ib = b / base_cols
      jb = b % base_cols
      cell = s & Metaflip:Gf2:MmcAlg.block_mask(row_alloc[ib], col_alloc[jb], target_cols, cache)
      shifted = cell << (cum_r[ib] * target_cols + cum_c[jb])
      joined = y | shifted
      Metaflip:Gf2:Bits.release(cell)
      Metaflip:Gf2:Bits.release(shifted)
      Metaflip:Gf2:Bits.release(y)
      y = joined
    Metaflip:Gf2:Bits.release(positions)
    y

  -> .recombination(base, alloc_a, alloc_b, alloc_c, lookup)
    if base.n != alloc_a.size || base.m != alloc_b.size || base.p != alloc_c.size
      raise MmcError.new("allocation length must equal base dim")
    shapes = Metaflip:Gf2:MmcAlg.recomb_subshapes(base, alloc_a, alloc_b, alloc_c)
    ta = alloc_a.sum
    tb = alloc_b.sum
    tc = alloc_c.sum
    ca = Metaflip:Gf2:MmcAlg.cumulative(alloc_a)
    cb = Metaflip:Gf2:MmcAlg.cumulative(alloc_b)
    cc = Metaflip:Gf2:MmcAlg.cumulative(alloc_c)
    cache = {}
    terms = []
    base.terms.each_with_index -> (t, index)
      size = shapes[index]
      if size[0] != 0 && size[1] != 0 && size[2] != 0
        sub = lookup.call(size)
        if sub == nil || sub.n != size[0] || sub.m != size[1] || sub.p != size[2]
          raise MmcError.new("missing sub-algorithm " + Metaflip:Gf2:MmcAlg.tuple_repr(size))
        sub.terms.each -> (s)
          terms.push([Metaflip:Gf2:MmcAlg.embed(t[0], s[0], base.m, size[1], alloc_a, alloc_b, ca, cb, tb, cache), Metaflip:Gf2:MmcAlg.embed(t[1], s[1], base.p, size[2], alloc_b, alloc_c, cb, cc, tc, cache), Metaflip:Gf2:MmcAlg.embed(t[2], s[2], base.p, size[2], alloc_a, alloc_c, ca, cc, tc, cache)])
    Metaflip:Gf2:Scheme.from_terms(ta, tb, tc, terms)

  # Python's repr of a tuple of ints: "(2, 3, 4)"
  -> .tuple_repr(values)
    "(" + values.map(-> (v) v.to_s).join(", ") + (values.size == 1 ? "," : "") + ")"

  # ---- the serendipitous product -----------------------------------------------------------------------------

  -> .orderings
    [["U", "V", "W"], ["U", "W", "V"], ["V", "U", "W"], ["V", "W", "U"], ["W", "U", "V"], ["W", "V", "U"]]

  -> .factor_index(type)
    return 0 if type == "U"
    return 1 if type == "V"
    2

  # Greedy bud decomposition over GF(2): terms sharing an identical (nonzero) factor. [buds, trivial]; a bud is [type, [term indices]].
  -> .find_buds(outer, order)
    rank = outer.rank
    used = []
    rank.times -> (l)
      used.push(false)
    terms = outer.terms
    buds = []
    order.each -> (type)
      fi = Metaflip:Gf2:MmcAlg.factor_index(type)
      groups = {}
      keys = []
      terms.each_with_index -> (term, l)
        if !used[l]
          key = Metaflip:Gf2:Bits.to_hex(term[fi])
          if !groups.key?(key)
            groups[key] = []
            keys.push(key)
          groups[key].push(l)
      keys.each -> (key)
        group = groups[key]
        if group.size >= 2
          group.each -> (l)
            used[l] = true
          buds.push([type, group])
    trivial = []
    rank.times -> (l)
      trivial.push(l) if !used[l]
    [buds, trivial]

  -> .enlarged_shape(type, k, n2, m2, p2)
    [type == "V" ? k * n2 : n2, type == "W" ? k * m2 : m2, type == "U" ? k * p2 : p2]

  # block l of an (k*R x C)-shaped matrix word: rows l*R .. (l+1)*R of width C
  -> .row_block(x, l, r, c)
    shifted = x >> (l * r * c)
    mask_bit = 1 << (r * c)
    mask = mask_bit - 1
    block = shifted & mask
    [shifted, mask_bit, mask].each -> (temporary)
      Metaflip:Gf2:Bits.release(temporary)
    block

  # column block l (width c) of an r x (k*c) matrix -> r x c
  -> .col_block(x, l, r, k, c)
    y = 0
    mask_bit = 1 << c
    mask = mask_bit - 1
    width = k * c
    r.times -> (row)
      shifted = x >> (row * width + l * c)
      cell = shifted & mask
      placed = cell << (row * c)
      joined = y | placed
      [shifted, cell, placed, y].each -> (temporary)
        Metaflip:Gf2:Bits.release(temporary)
      y = joined
    Metaflip:Gf2:Bits.release(mask_bit)
    Metaflip:Gf2:Bits.release(mask)
    y

  -> .build_bud_block(outer, type, indices, s3, n2, m2, p2)
    n1 = outer.n
    m1 = outer.m
    p1 = outer.p
    k = indices.size
    fi = Metaflip:Gf2:MmcAlg.factor_index(type)
    terms = outer.terms
    shared = terms[indices[0]][fi]
    out = []
    s3.terms.each -> (s)
      u = 0
      v = 0
      w = 0
      if type == "U"
        u = Metaflip:Gf2:MmcAlg.kron_bits(shared, s[0], n1, m1, n2, m2)
        indices.each_with_index -> (t, l)
          row = terms[t]
          v = v ^ Metaflip:Gf2:MmcAlg.kron_bits(row[1], Metaflip:Gf2:MmcAlg.col_block(s[1], l, m2, k, p2), m1, p1, m2, p2)
          w = w ^ Metaflip:Gf2:MmcAlg.kron_bits(row[2], Metaflip:Gf2:MmcAlg.col_block(s[2], l, n2, k, p2), n1, p1, n2, p2)
      elsif type == "V"
        v = Metaflip:Gf2:MmcAlg.kron_bits(shared, s[1], m1, p1, m2, p2)
        indices.each_with_index -> (t, l)
          row = terms[t]
          u = u ^ Metaflip:Gf2:MmcAlg.kron_bits(row[0], Metaflip:Gf2:MmcAlg.row_block(s[0], l, n2, m2), n1, m1, n2, m2)
          w = w ^ Metaflip:Gf2:MmcAlg.kron_bits(row[2], Metaflip:Gf2:MmcAlg.row_block(s[2], l, n2, p2), n1, p1, n2, p2)
      else
        w = Metaflip:Gf2:MmcAlg.kron_bits(shared, s[2], n1, p1, n2, p2)
        indices.each_with_index -> (t, l)
          row = terms[t]
          u = u ^ Metaflip:Gf2:MmcAlg.kron_bits(row[0], Metaflip:Gf2:MmcAlg.col_block(s[0], l, n2, k, m2), n1, m1, n2, m2)
          v = v ^ Metaflip:Gf2:MmcAlg.kron_bits(row[1], Metaflip:Gf2:MmcAlg.row_block(s[1], l, m2, p2), m1, p1, m2, p2)
      out.push([u, v, w])
    out

  -> .serendipitous(outer, n2, m2, p2, resolve, rank_of)
    r2 = rank_of.call([n2, m2, p2])
    raise MmcError.new("no inner <" + n2.to_s + "," + m2.to_s + "," + p2.to_s + ">") if r2 == nil
    candidates = []
    Metaflip:Gf2:MmcAlg.orderings.each -> (order)
      found = Metaflip:Gf2:MmcAlg.find_buds(outer, order)
      buds = found[0]
      trivial = found[1]
      if buds.size > 0
        cost = trivial.size * r2
        ok = true
        buds.each -> (bud)
          if ok
            enlarged = rank_of.call(Metaflip:Gf2:MmcAlg.enlarged_shape(bud[0], bud[1].size, n2, m2, p2))
            if enlarged == nil
              ok = false
            else
              cost += enlarged
        candidates.push([cost, order, buds, trivial]) if ok
    ordered = Textx.sort_by(candidates) -> (candidate) candidate[0]
    s2 = resolve.call([n2, m2, p2])
    terms_of_t1 = outer.terms
    result = nil
    ordered.each -> (candidate)
      if result == nil && candidate[0] < outer.rank * r2
        buds = candidate[2]
        trivial = candidate[3]
        terms = []
        failed = false
        trivial.each -> (i)
          single = Metaflip:Gf2:Scheme.from_terms(outer.n, outer.m, outer.p, [terms_of_t1[i]])
          Metaflip:Gf2:MmcAlg.kron(single, s2).terms.each -> (term)
            terms.push(term)
        buds.each -> (bud)
          if !failed
            s3 = resolve.call(Metaflip:Gf2:MmcAlg.enlarged_shape(bud[0], bud[1].size, n2, m2, p2))
            if s3 == nil
              failed = true
            else
              Metaflip:Gf2:MmcAlg.build_bud_block(outer, bud[0], bud[1], s3, n2, m2, p2).each -> (term)
                terms.push(term)
        result = Metaflip:Gf2:Scheme.from_terms(outer.n * n2, outer.m * m2, outer.p * p2, terms) if !failed
    return result if result != nil
    Metaflip:Gf2:MmcAlg.kron(outer, s2)

  # ---- cleanup ---------------------------------------------------------------------------------------------------

  # Drops terms with a zero factor and cancels identical terms in pairs (mod 2).
  -> .clean(a)
    a.cleaned
