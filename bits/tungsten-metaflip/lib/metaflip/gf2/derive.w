# The constructions of the derivation and composition pipeline on GF(2) schemes: block embedding, Kronecker
# products, coordinate projection, and shared-factor compression. Ports of
#
#   block, kronecker          benchmarks/matmul/metaflip/verify_composition_targets.py
#   drop_matrix, project      tools/screen_structured_parent_projections.py
#   parity, cofactor helpers, column_basis, matrix_factors, compress_shared
#                             benchmarks/matmul/metaflip/verify_cofactor_mergers.py
#
# A scheme here is a shape [n, m, p] and an Array of terms [u, v, w] of Integer masks (u: n x m, bit i*m+j;
# v: m x p, bit j*p+k; w: n x p, bit i*p+k), as in the Python tooling; every function returns new Arrays and
# keeps the orders the originals produce (they matter: the pipeline's outputs are compared byte for byte).
#
#   Derive.block(shape, terms, target, offsets)            the scheme placed at `offsets` inside the larger `target`
#   Derive.kronecker(left_shape, left, right_shape, right) the product scheme for the componentwise product shape
#   Derive.project(shape, terms, dimension, coordinate)    [shape', terms']: one coordinate deleted, equal terms
#                                                          cancelled in pairs, terms with a zero factor dropped;
#                                                          terms come back sorted
#   Derive.parity(terms)                                   the terms an odd number of times present, first-seen order
#   Derive.compress_shared(terms, max_bits = 256)          [terms', history]: rank factorisation of every group of terms
#                                                          that share a factor, repeated until nothing changes
#   Derive.matrix_factors(pairs, max_bits, reverse)        the canonical column-basis factorisation of sum l (x) r
#   Derive.refactor_shared(terms, axis, max_bits, reverse) every group refactored along one axis (the basis rewrite)
#   Derive.two_pass(terms, shape, mode)                    the two-pass basis rewrite of modes 6..17, then compression
#                                                          (screen_two_pass_basis_children.two_pass)
#   Derive.child(shape, terms, axis, coordinate)           [shape', terms', history]: the projection, compressed
#
# Terms are keyed by their hexadecimal text where the originals use tuples as dictionary keys.
use scheme

+ Metaflip:Gf2:Derive
  # ---- helpers --------------------------------------------------------------------------

  # The two axes a matrix of each factor position joins: u (0, 1), v (1, 2), w (0, 2).
  -> .edge_rows(position)
    position == 1 ? 1 : 0

  -> .edge_cols(position)
    position == 0 ? 1 : 2

  # The key of a term in dictionaries: the hexadecimal text of its three masks.
  -> .key(term)
    Metaflip:Gf2:Bits.to_hex(term[0]) + "," + Metaflip:Gf2:Bits.to_hex(term[1]) + "," + Metaflip:Gf2:Bits.to_hex(term[2])

  # terms of a scheme: the ones an odd number of times present, in the order of their first occurrence.
  -> .parity(terms)
    counts = {}
    order = []
    terms.each -> (term)
      key = Metaflip:Gf2:Derive.key(term)
      if counts.key?(key)
        counts[key] = counts[key] + 1
      else
        counts[key] = 1
        order.push(term)
    order.select -> (term)
      counts[Metaflip:Gf2:Derive.key(term)] % 2 == 1

  # ---- block and Kronecker --------------------------------------------------------------

  # The bits of `word` (a matrix with `cols` columns) moved into a matrix with `target_cols` columns, starting at
  # row `row_offset` and column `col_offset`.
  -> .shift_matrix(word, cols, target_cols, row_offset, col_offset)
    positions = Metaflip:Gf2:Bits.positions(word)
    moved = []
    positions.each -> (bit)
      moved.push((bit / cols + row_offset) * target_cols + bit % cols + col_offset)
    result = Metaflip:Gf2:Bits.from_positions(moved)
    Metaflip:Gf2:Bits.release(positions)
    Metaflip:Gf2:Bits.release(moved)
    result

  # The terms of a scheme for `shape`, placed at `offsets` of the larger `target` shape.
  -> .block(shape, terms, target, offsets)
    3.times -> (axis)
      raise "block does not fit" if offsets[axis] < 0 || shape[axis] + offsets[axis] > target[axis]
    terms.map -> (term)
      row = []
      3.times -> (position)
        r = Metaflip:Gf2:Derive.edge_rows(position)
        c = Metaflip:Gf2:Derive.edge_cols(position)
        row.push(Metaflip:Gf2:Derive.shift_matrix(term[position], shape[c], target[c], offsets[r], offsets[c]))
      row

  # The product of two schemes: terms (l, r) in left-major order, each factor the Kronecker product of the
  # factors of l and r for the componentwise product of the shapes.
  -> .kronecker(left_shape, left, right_shape, right)
    right_bits = right.map -> (r)
      [Metaflip:Gf2:Bits.positions(r[0]), Metaflip:Gf2:Bits.positions(r[1]), Metaflip:Gf2:Bits.positions(r[2])]
    out = []
    left.each -> (l)
      left_bits = [Metaflip:Gf2:Bits.positions(l[0]), Metaflip:Gf2:Bits.positions(l[1]), Metaflip:Gf2:Bits.positions(l[2])]
      right_bits.each -> (rb)
        row = []
        3.times -> (position)
          er = Metaflip:Gf2:Derive.edge_rows(position)
          ec = Metaflip:Gf2:Derive.edge_cols(position)
          lc = left_shape[ec]
          rr = right_shape[er]
          rc = right_shape[ec]
          bits = []
          left_bits[position].each -> (i)
            base = (i / lc * rr) * (lc * rc) + (i % lc) * rc
            rb[position].each -> (j)
              bits.push(base + (j / rc) * (lc * rc) + j % rc)
          row.push(Metaflip:Gf2:Bits.from_positions(bits))
          Metaflip:Gf2:Bits.release(bits)
        out.push(row)
      left_bits.each -> (positions)
        Metaflip:Gf2:Bits.release(positions)
      Metaflip:Gf2:Bits.release(left_bits)
    right_bits.each -> (triple)
      triple.each -> (positions)
        Metaflip:Gf2:Bits.release(positions)
      Metaflip:Gf2:Bits.release(triple)
    Metaflip:Gf2:Bits.release(right_bits)
    out

  # ---- coordinate projection ------------------------------------------------------------

  # Deletes row `coordinate` (dimension 0) or column `coordinate` (dimension 1) of a row-major rows x cols matrix word.
  -> .drop_matrix(word, rows, cols, dimension, coordinate)
    if dimension == 0
      lower = word & ((1 << (coordinate * cols)) - 1)
      return lower | ((word >> ((coordinate + 1) * cols)) << (coordinate * cols))
    old_mask = (1 << cols) - 1
    lower_mask = (1 << coordinate) - 1
    result = 0
    row = 0
    while row < rows
      chunk = (word >> (row * cols)) & old_mask
      smaller = (chunk & lower_mask) | ((chunk >> (coordinate + 1)) << coordinate)
      result = result | (smaller << (row * (cols - 1)))
      row += 1
    result

  # [shape', terms']: coordinate `coordinate` of axis `dimension` deleted from the two factors that carry it.
  -> .project(shape, terms, dimension, coordinate)
    raise "invalid deleted coordinate" if dimension < 0 || dimension > 2 || coordinate < 0 || coordinate >= shape[dimension] || shape[dimension] <= 1
    kept = []
    terms.each -> (term)
      row = []
      3.times -> (position)
        left = Metaflip:Gf2:Derive.edge_rows(position)
        right = Metaflip:Gf2:Derive.edge_cols(position)
        if dimension == left
          row.push(Metaflip:Gf2:Derive.drop_matrix(term[position], shape[left], shape[right], 0, coordinate))
        elsif dimension == right
          row.push(Metaflip:Gf2:Derive.drop_matrix(term[position], shape[left], shape[right], 1, coordinate))
        else
          row.push(term[position])
      kept.push(row) if row[0] != 0 && row[1] != 0 && row[2] != 0
    target = [shape[0], shape[1], shape[2]]
    target[dimension] = target[dimension] - 1
    [target, Metaflip:Gf2:Derive.parity(kept).sort]

  # ---- shared-factor compression ---------------------------------------------------------

  # The first independent columns of `columns` (a Hash from column index to word), scanning the indices in
  # ascending (or, with `reverse`, descending) order; each kept column is the original word.
  -> .column_basis(columns, reverse)
    indices = columns.keys.sort
    indices = indices.reverse if reverse
    basis = []
    pivots = {}
    indices.each -> (j)
      word = columns[j]
      done = false
      while word != 0 && !done
        pivot = Metaflip:Gf2:Bits.high_bit_index(word) + 1
        if pivots.key?(pivot)
          word = word ^ pivots[pivot]
        else
          pivots[pivot] = word
          basis.push(columns[j])
          done = true
    basis

  # The factors [(left, right), ...] of sum over pairs of left (x) right, with the canonical column basis as the
  # left factors (solved by a separate row system, then reconstructed and compared with the input).
  -> .matrix_factors(pairs, max_bits, reverse)
    raise "max_bits out of range" if max_bits < 1 || max_bits > 4096
    columns = {}
    pairs.each -> (pair)
      raise "factor out of range" if Metaflip:Gf2:Bits.high_bit_index(pair[0]) >= max_bits || Metaflip:Gf2:Bits.high_bit_index(pair[1]) >= max_bits
      Metaflip:Gf2:Bits.positions(pair[1]).each -> (j)
        current = columns.key?(j) ? columns[j] : 0
        columns[j] = current ^ pair[0]
    basis = Metaflip:Gf2:Derive.column_basis(columns, reverse)
    coefficient_rows = {}
    right_rows = {}
    basis.each_with_index -> (value, i)
      Metaflip:Gf2:Bits.positions(value).each -> (coordinate)
        current = coefficient_rows.key?(coordinate) ? coefficient_rows[coordinate] : 0
        coefficient_rows[coordinate] = current | (1 << i)
    columns.each -> (j, value)
      Metaflip:Gf2:Bits.positions(value).each -> (coordinate)
        current = right_rows.key?(coordinate) ? right_rows[coordinate] : 0
        right_rows[coordinate] = current | (1 << j)
    coordinates = {}
    coefficient_rows.keys.each -> (c)
      coordinates[c] = true
    right_rows.keys.each -> (c)
      coordinates[c] = true
    equations = {}
    coordinates.keys.sort.each -> (coordinate)
      mask = coefficient_rows.key?(coordinate) ? coefficient_rows[coordinate] : 0
      rhs = right_rows.key?(coordinate) ? right_rows[coordinate] : 0
      placed = false
      while mask != 0 && !placed
        pivot = Metaflip:Gf2:Bits.low_bit_index(mask)
        if equations.key?(pivot)
          row = equations[pivot]
          mask = mask ^ row[0]
          rhs = rhs ^ row[1]
        else
          equations[pivot] = [mask, rhs]
          placed = true
      raise "inconsistent matrix coordinate system" if mask == 0 && rhs != 0
    raise "rank deficient coordinate system" if equations.size != basis.size
    solved = {}
    equations.keys.sort.reverse.each -> (pivot)
      row = equations[pivot]
      rhs = row[1]
      Metaflip:Gf2:Bits.positions(row[0] ^ (1 << pivot)).each -> (i)
        rhs = rhs ^ solved[i]
      solved[pivot] = rhs
    factors = []
    basis.each_with_index -> (value, i)
      factors.push([value, solved[i]])
    actual = {}
    factors.each -> (factor)
      raise "zero factor" if factor[0] == 0 || factor[1] == 0
      Metaflip:Gf2:Bits.positions(factor[1]).each -> (j)
        current = actual.key?(j) ? actual[j] : 0
        actual[j] = current ^ factor[0]
    actual.each -> (j, value)
      raise "matrix factors do not reconstruct" if value != 0 && (!columns.key?(j) || columns[j] != value)
    columns.each -> (j, value)
      raise "matrix factors do not reconstruct" if value != 0 && (!actual.key?(j) || actual[j] != value)
    factors

  # A term with `fixed` on `axis` and the two factors `left`, `right` on the other two axes in ascending order.
  -> .term_on(axis, fixed, left, right)
    other = [0, 1, 2].select -> (a)
      a != axis
    row = [0, 0, 0]
    row[axis] = fixed
    row[other[0]] = left
    row[other[1]] = right
    row

  # Groups of terms by the factor on `axis`, in order of first occurrence: a Hash from the factor's text to
  # [factor, [terms]].
  -> .groups_on(terms, axis)
    groups = {}
    terms.each -> (term)
      key = Metaflip:Gf2:Bits.to_hex(term[axis])
      groups[key] = [term[axis], []] if !groups.key?(key)
      groups[key][1].push(term)
    groups

  # Every group of two or more terms sharing the factor on `axis` is replaced by its canonical factorisation, also when
  # the rank does not drop (the basis rewrite); [terms', changed] with one {fixed, before, after} per group whose terms changed.
  -> .refactor_shared(terms, axis, max_bits, reverse)
    other = [0, 1, 2].select -> (a)
      a != axis
    out = []
    changed = []
    Metaflip:Gf2:Derive.groups_on(terms, axis).each -> (key, entry)
      group = entry[1]
      if group.size < 2
        group.each -> (term)
          out.push(term)
      else
        pairs = group.map -> (term)
          [term[other[0]], term[other[1]]]
        factors = Metaflip:Gf2:Derive.matrix_factors(pairs, max_bits, reverse)
        replacement = factors.map -> (factor)
          Metaflip:Gf2:Derive.term_on(axis, entry[0], factor[0], factor[1])
        if replacement.sort != group.sort
          changed.push({"fixed" => entry[0], "before" => group.size, "after" => replacement.size})
        replacement.each -> (term)
          out.push(term)
    result = Metaflip:Gf2:Derive.parity(out)
    raise "refactoring raised the rank" if result.size > terms.size
    [result, changed]

  # Repeats, over the three axes in turn, the rank factorisation of every group of terms that share a factor until
  # a whole pass removes nothing: [terms', history], one {axis, fixed, before, after} per group that shrank.
  -> .compress_shared(terms, max_bits)
    raise "max_bits out of range" if max_bits < 1 || max_bits > 4096
    current = terms.map -> (term)
      [term[0], term[1], term[2]]
    history = []
    done = false
    while !done
      before = current.size
      3.times -> (axis)
        other = [0, 1, 2].select -> (a)
          a != axis
        ordered = []
        Metaflip:Gf2:Derive.groups_on(current, axis).each -> (key, entry)
          group = entry[1]
          trivial = group.size < 2 || (group.size == 2 && group[0][other[0]] != group[1][other[0]] && group[0][other[1]] != group[1][other[1]])
          if trivial
            group.each -> (term)
              ordered.push(term)
          else
            pairs = group.map -> (term)
              [term[other[0]], term[other[1]]]
            factors = Metaflip:Gf2:Derive.matrix_factors(pairs, max_bits, false)
            raise "compression raised the rank" if factors.size > group.size
            if factors.size == group.size
              group.each -> (term)
                ordered.push(term)
            else
              history.push({"axis" => axis, "fixed" => entry[0], "before" => group.size, "after" => factors.size})
              factors.each -> (factor)
                ordered.push(Metaflip:Gf2:Derive.term_on(axis, entry[0], factor[0], factor[1]))
        current = Metaflip:Gf2:Derive.parity(ordered)
      raise "compression raised the rank" if current.size > before
      done = true if current.size == before
    [current, history]

  # The widest matrix of a shape, in bits: the `max_bits` that the screens pass.
  -> .width(shape)
    [shape[0] * shape[1], shape[1] * shape[2], shape[0] * shape[2]].max

  # The orders in which the three axes are visited by the basis modes: itertools.permutations(range(3)).
  -> .axis_orders
    [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]

  # The same terms in the same order.
  -> .same_sequence?(a, b)
    return false if a.size != b.size
    same = true
    a.each_with_index -> (term, i)
      same = false if term[0] != b[i][0] || term[1] != b[i][1] || term[2] != b[i][2]
    same

  # Basis mode 6..17: the axes in order (mode - 6) / 2 of the permutations, column scans descending for an odd mode; at
  # most two rounds of the rewrite (the second is skipped when the first returned the terms in their original order),
  # then shared-factor compression.
  -> .two_pass(terms, shape, mode)
    raise "two-pass mode outside 6..17" if mode < 6 || mode >= 18
    width = Metaflip:Gf2:Derive.width(shape)
    order = Metaflip:Gf2:Derive.axis_orders[(mode - 6) / 2]
    reverse = mode % 2 == 1
    current = terms
    rounds = 0
    done = false
    while rounds < 2 && !done
      order.each -> (axis)
        current = Metaflip:Gf2:Derive.refactor_shared(current, axis, width, reverse)[0]
      done = true if Metaflip:Gf2:Derive.same_sequence?(current, terms)
      rounds += 1
    Metaflip:Gf2:Derive.compress_shared(current, width)[0]

  # The projection child the screens build: delete a coordinate, then compress at the width of the smaller shape.
  -> .child(shape, terms, axis, coordinate)
    projected = Metaflip:Gf2:Derive.project(shape, terms, axis, coordinate)
    compressed = Metaflip:Gf2:Derive.compress_shared(projected[1], Metaflip:Gf2:Derive.width(projected[0]))
    [projected[0], compressed[0], compressed[1]]
