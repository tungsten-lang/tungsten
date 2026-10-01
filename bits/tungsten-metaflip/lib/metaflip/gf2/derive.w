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
    a = Metaflip:Gf2:Bits.to_hex(term[0])
    b = Metaflip:Gf2:Bits.to_hex(term[1])
    c = Metaflip:Gf2:Bits.to_hex(term[2])
    text = StringBuffer()
    text.append(a)
    text.append(",")
    text.append(b)
    text.append(",")
    text.append(c)
    key = text.to_s
    Metaflip:Gf2:Bits.release(a)
    Metaflip:Gf2:Bits.release(b)
    Metaflip:Gf2:Bits.release(c)
    Metaflip:Gf2:Bits.release(text)
    key

  # terms of a scheme: the ones an odd number of times present, in the order of their first occurrence.
  # (With no garbage collector the keys are freed as soon as they have been used; a Hash keeps the first key object
  # of an entry, so the equal key built for a repeat is ours to free.)
  -> .parity(terms)
    counts = {}
    order = []
    terms.each -> (term)
      key = Metaflip:Gf2:Derive.key(term)
      entry = counts[key]
      if entry == nil
        counts[key] = [1]
        order.push(term)
      else
        entry[0] = entry[0] + 1
        Metaflip:Gf2:Bits.release(key)
    result = order.select -> (term)
      probe = Metaflip:Gf2:Derive.key(term)
      odd = counts[probe][0] % 2 == 1
      Metaflip:Gf2:Bits.release(probe)
      odd
    counts.each -> (key, entry)
      Metaflip:Gf2:Bits.release(key)
      Metaflip:Gf2:Bits.release(entry)
    Metaflip:Gf2:Bits.release(counts)
    Metaflip:Gf2:Bits.release(order)
    result

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
  # (The operator results in between are freed as they are used up.)
  -> .drop_matrix(word, rows, cols, dimension, coordinate)
    if dimension == 0
      low_bit = 1 << (coordinate * cols)
      low_mask = low_bit - 1
      lower = word & low_mask
      high = word >> ((coordinate + 1) * cols)
      moved = high << (coordinate * cols)
      result = lower | moved
      [low_bit, low_mask, lower, high, moved].each -> (temporary)
        Metaflip:Gf2:Bits.release(temporary)
      return result
    old_bit = 1 << cols
    old_mask = old_bit - 1
    lower_bit = 1 << coordinate
    lower_mask = lower_bit - 1
    result = 0
    row = 0
    while row < rows
      shifted = word >> (row * cols)
      chunk = shifted & old_mask
      low = chunk & lower_mask
      high = chunk >> (coordinate + 1)
      high_moved = high << coordinate
      smaller = low | high_moved
      placed = smaller << (row * (cols - 1))
      grown = result | placed
      [shifted, chunk, low, high, high_moved, smaller, placed, result].each -> (temporary)
        Metaflip:Gf2:Bits.release(temporary)
      result = grown
      row += 1
    [old_bit, old_mask, lower_bit, lower_mask].each -> (temporary)
      Metaflip:Gf2:Bits.release(temporary)
    result

  # [shape', terms']: coordinate `coordinate` of axis `dimension` deleted from the two factors that carry it.
  -> .project(shape, terms, dimension, coordinate)
    raise "invalid deleted coordinate" if dimension < 0 || dimension > 2 || coordinate < 0 || coordinate >= shape[dimension] || shape[dimension] <= 1
    kept = []
    terms.each -> (term)
      row = []
      made = []
      3.times -> (position)
        left = Metaflip:Gf2:Derive.edge_rows(position)
        right = Metaflip:Gf2:Derive.edge_cols(position)
        if dimension == left
          row.push(Metaflip:Gf2:Derive.drop_matrix(term[position], shape[left], shape[right], 0, coordinate))
          made.push(row[position])
        elsif dimension == right
          row.push(Metaflip:Gf2:Derive.drop_matrix(term[position], shape[left], shape[right], 1, coordinate))
          made.push(row[position])
        else
          row.push(term[position])
      if row[0] != 0 && row[1] != 0 && row[2] != 0
        kept.push(row)
      else
        # a term that vanished: the masks made for it are ours
        made.each -> (mask)
          Metaflip:Gf2:Bits.release(mask)
        Metaflip:Gf2:Bits.release(row)
      Metaflip:Gf2:Bits.release(made)
    target = [shape[0], shape[1], shape[2]]
    target[dimension] = target[dimension] - 1
    odd = Metaflip:Gf2:Derive.parity(kept)
    ordered = odd.sort
    Metaflip:Gf2:Bits.release(odd)
    Metaflip:Gf2:Bits.release(kept)
    [target, ordered]

  # ---- shared-factor compression ---------------------------------------------------------

  # The first independent columns of `columns` (a Hash from column index to word), scanning the indices in
  # ascending (or, with `reverse`, descending) order: [basis, kept], the original words and their indices.
  # A reduced word is ours (every operator result is a new object) and is freed with the pivots.
  -> .column_basis(columns, reverse)
    keys = columns.keys
    ascending = keys.sort
    indices = reverse ? ascending.reverse : ascending
    basis = []
    kept = []
    pivots = {}
    fresh = []
    indices.each -> (j)
      word = columns[j]
      owned = false
      done = false
      while word != 0 && !done
        pivot = Metaflip:Gf2:Bits.high_bit_index(word) + 1
        if pivots.key?(pivot)
          reduced = word ^ pivots[pivot]
          Metaflip:Gf2:Bits.release(word) if owned
          word = reduced
          owned = true
        else
          pivots[pivot] = word
          fresh.push(word) if owned
          basis.push(columns[j])
          kept.push(j)
          done = true
    fresh.each -> (word)
      Metaflip:Gf2:Bits.release(word)
    Metaflip:Gf2:Bits.release(fresh)
    Metaflip:Gf2:Bits.release(pivots)
    Metaflip:Gf2:Bits.release(indices) if reverse
    Metaflip:Gf2:Bits.release(ascending)
    Metaflip:Gf2:Bits.release(keys)
    [basis, kept]

  # table[key] |= bit; the old value (an earlier result of this function) is freed.
  -> .or_into(table, key, bit)
    current = table.key?(key) ? table[key] : 0
    table[key] = current | bit
    Metaflip:Gf2:Bits.release(current)

  # The positions of the set bits of every value, each OR-ed with `1 << index_of(value)` into `table[position]`.
  -> .scatter(table, entries)
    entries.each -> (entry)
      positions = Metaflip:Gf2:Bits.positions(entry[0])
      bit = 1 << entry[1]
      positions.each -> (coordinate)
        Metaflip:Gf2:Derive.or_into(table, coordinate, bit)
      Metaflip:Gf2:Bits.release(bit)
      Metaflip:Gf2:Bits.release(positions)

  # Frees the values of a Hash of masks that are all ours, and the Hash.
  -> .release_values(table)
    table.each -> (key, value)
      Metaflip:Gf2:Bits.release(value)
    Metaflip:Gf2:Bits.release(table)

  # The factors [(left, right), ...] of sum over pairs of left (x) right, with the canonical column basis as the
  # left factors (solved by a separate row system, then reconstructed and compared with the input).
  # Ownership: `columns`, the row tables and the elimination work on masks made here (copies where a mask would
  # otherwise be shared), so everything but what the factors keep is freed at the end.
  -> .matrix_factors(pairs, max_bits, reverse)
    raise "max_bits out of range" if max_bits < 1 || max_bits > 4096
    columns = {}
    pairs.each -> (pair)
      raise "factor out of range" if Metaflip:Gf2:Bits.high_bit_index(pair[0]) >= max_bits || Metaflip:Gf2:Bits.high_bit_index(pair[1]) >= max_bits
      positions = Metaflip:Gf2:Bits.positions(pair[1])
      positions.each -> (j)
        current = columns.key?(j) ? columns[j] : 0
        columns[j] = current ^ pair[0]
        Metaflip:Gf2:Bits.release(current)
      Metaflip:Gf2:Bits.release(positions)
    chosen = Metaflip:Gf2:Derive.column_basis(columns, reverse)
    basis = chosen[0]
    coefficient_rows = {}
    right_rows = {}
    basis_entries = []
    basis.each_with_index -> (value, i)
      basis_entries.push([value, i])
    Metaflip:Gf2:Derive.scatter(coefficient_rows, basis_entries)
    column_entries = []
    columns.each -> (j, value)
      column_entries.push([value, j])
    Metaflip:Gf2:Derive.scatter(right_rows, column_entries)
    coordinates = {}
    coefficient_rows.keys.each -> (c)
      coordinates[c] = true
    right_rows.keys.each -> (c)
      coordinates[c] = true
    equations = {}
    ordered_coordinates = coordinates.keys.sort
    ordered_coordinates.each -> (coordinate)
      mask = 0
      mask = coefficient_rows[coordinate] | 0 if coefficient_rows.key?(coordinate)
      rhs = 0
      rhs = right_rows[coordinate] | 0 if right_rows.key?(coordinate)
      placed = false
      while mask != 0 && !placed
        pivot = Metaflip:Gf2:Bits.low_bit_index(mask)
        if equations.key?(pivot)
          row = equations[pivot]
          next_mask = mask ^ row[0]
          next_rhs = rhs ^ row[1]
          Metaflip:Gf2:Bits.release(mask)
          Metaflip:Gf2:Bits.release(rhs)
          mask = next_mask
          rhs = next_rhs
        else
          equations[pivot] = [mask, rhs]
          placed = true
      raise "inconsistent matrix coordinate system" if mask == 0 && rhs != 0
    raise "rank deficient coordinate system" if equations.size != basis.size
    solved = {}
    ascending_pivots = equations.keys.sort
    descending_pivots = ascending_pivots.reverse
    descending_pivots.each -> (pivot)
      row = equations[pivot]
      rhs = row[1] | 0
      bit = 1 << pivot
      flipped = row[0] ^ bit
      dependencies = Metaflip:Gf2:Bits.positions(flipped)
      dependencies.each -> (i)
        next_rhs = rhs ^ solved[i]
        Metaflip:Gf2:Bits.release(rhs)
        rhs = next_rhs
      Metaflip:Gf2:Bits.release(dependencies)
      Metaflip:Gf2:Bits.release(flipped)
      Metaflip:Gf2:Bits.release(bit)
      solved[pivot] = rhs
    factors = []
    basis.each_with_index -> (value, i)
      factors.push([value, solved[i]])
    actual = {}
    factors.each -> (factor)
      raise "zero factor" if factor[0] == 0 || factor[1] == 0
      positions = Metaflip:Gf2:Bits.positions(factor[1])
      positions.each -> (j)
        current = actual.key?(j) ? actual[j] : 0
        actual[j] = current ^ factor[0]
        Metaflip:Gf2:Bits.release(current)
      Metaflip:Gf2:Bits.release(positions)
    actual.each -> (j, value)
      raise "matrix factors do not reconstruct" if value != 0 && (!columns.key?(j) || columns[j] != value)
    columns.each -> (j, value)
      raise "matrix factors do not reconstruct" if value != 0 && (!actual.key?(j) || actual[j] != value)
    # everything the factors do not keep
    Metaflip:Gf2:Derive.release_values(actual)
    Metaflip:Gf2:Derive.release_values(coefficient_rows)
    Metaflip:Gf2:Derive.release_values(right_rows)
    equations.each -> (pivot, row)
      Metaflip:Gf2:Bits.release(row[0])
      Metaflip:Gf2:Bits.release(row[1])
      Metaflip:Gf2:Bits.release(row)
    Metaflip:Gf2:Bits.release(equations)
    in_basis = {}
    chosen[1].each -> (j)
      in_basis[j] = true
    columns.each -> (j, value)
      Metaflip:Gf2:Bits.release(value) if !in_basis.key?(j)
    Metaflip:Gf2:Derive.release_all(basis_entries)
    Metaflip:Gf2:Derive.release_all(column_entries)
    [columns, in_basis, solved, coordinates, ordered_coordinates, ascending_pivots, descending_pivots, basis, chosen[1], chosen].each -> (garbage)
      Metaflip:Gf2:Bits.release(garbage)
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
      entry = groups[key]
      if entry == nil
        entry = [term[axis], []]
        groups[key] = entry
      else
        Metaflip:Gf2:Bits.release(key)
      entry[1].push(term)
    groups

  # Frees the containers of groups_on's result (the terms and masks stay).
  -> .release_groups(groups)
    groups.each -> (key, entry)
      Metaflip:Gf2:Bits.release(key)
      Metaflip:Gf2:Bits.release(entry[1])
      Metaflip:Gf2:Bits.release(entry)
    Metaflip:Gf2:Bits.release(groups)

  # Every group of two or more terms sharing the factor on `axis` is replaced by its canonical factorisation, also when
  # the rank does not drop (the basis rewrite); [terms', changed] with one {fixed, before, after} per group whose terms changed.
  -> .refactor_shared(terms, axis, max_bits, reverse)
    other = [0, 1, 2].select -> (a)
      a != axis
    out = []
    changed = []
    groups = Metaflip:Gf2:Derive.groups_on(terms, axis)
    groups.each -> (key, entry)
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
        after = replacement.sort
        before = group.sort
        changed.push({"fixed" => entry[0], "before" => group.size, "after" => replacement.size}) if after != before
        Metaflip:Gf2:Bits.release(after)
        Metaflip:Gf2:Bits.release(before)
        replacement.each -> (term)
          out.push(term)
        Metaflip:Gf2:Derive.release_all(pairs)
        Metaflip:Gf2:Derive.release_all(factors)
        Metaflip:Gf2:Bits.release(replacement)
    result = Metaflip:Gf2:Derive.parity(out)
    Metaflip:Gf2:Bits.release(out)
    Metaflip:Gf2:Derive.release_groups(groups)
    raise "refactoring raised the rank" if result.size > terms.size
    [result, changed]

  # Frees an Array of small Arrays and the outer Array (what the small Arrays hold stays).
  -> .release_all(items)
    items.each -> (item)
      Metaflip:Gf2:Bits.release(item)
    Metaflip:Gf2:Bits.release(items)

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
        groups = Metaflip:Gf2:Derive.groups_on(current, axis)
        groups.each -> (key, entry)
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
            Metaflip:Gf2:Derive.release_all(pairs)
            Metaflip:Gf2:Derive.release_all(factors)
        stale = current
        current = Metaflip:Gf2:Derive.parity(ordered)
        Metaflip:Gf2:Bits.release(ordered)
        Metaflip:Gf2:Derive.release_groups(groups)
        Metaflip:Gf2:Bits.release(stale)
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
    # compress_shared worked on copies of the rows: the projection's own rows are done with
    Metaflip:Gf2:Derive.release_all(projected[1])
    [projected[0], compressed[0], compressed[1]]
