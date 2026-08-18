# The Conway criterion: a sufficient condition for a tile to tile the plane.
#
# Packing asks whether finitely many pieces fit in a box. This asks the
# infinite question — whether one shape, repeated, covers the whole plane —
# and answers it for a large class of tiles without any search over placements.
#
# A closed topological disk satisfies the criterion when its boundary splits
# into six consecutive arcs A, B, C, D, E, F such that A and D are congruent
# by translation, and each of B, C, E, F is centrally symmetric about its own
# midpoint. Any tile meeting it tiles the plane by translations and half
# turns. The condition is *sufficient, not necessary*: a shape failing it may
# still tile, so a false answer here means "not decided", never "cannot tile".
#
# Walking the boundary turns both conditions into statements about the step
# sequence, and both become exact and local:
#
#   centrally symmetric   the arc's steps read the same forwards and
#                         backwards — a palindrome, since a half turn about
#                         the midpoint carries the arc onto itself reversed
#   translation congruent  A's steps are the negated reverse of D's, which is
#                         what it means for two arcs traversed oppositely
#                         around the boundary to be translates
#
# The search runs over the start and length of A and the start of D, then asks
# whether each remaining gap splits into two palindromes — with palindromes
# precomputed, that is cubic in the boundary length rather than a sixfold
# combinatorial sweep.

+ ConwayCriterion
  -> .cell_key(x, y)
    "[x],[y]"

  # The boundary of a polyomino as a closed walk, returned as its sequence of
  # unit steps. Edges are emitted with the interior on the left, so the walk
  # is counter-clockwise and closes on itself.
  -> .boundary_steps(cells)
    present = {}
    i = 0
    while i < cells.size
      present[ConwayCriterion.cell_key(cells[i][0], cells[i][1])] = true
      i += 1
    # Directed boundary edges, keyed by their start point.
    starts = {}
    i = 0
    while i < cells.size
      x = cells[i][0]
      y = cells[i][1]
      i += 1
      if !present.key?(ConwayCriterion.cell_key(x, y - 1))
        starts[ConwayCriterion.cell_key(x, y)] = [x + 1, y]
      if !present.key?(ConwayCriterion.cell_key(x + 1, y))
        starts[ConwayCriterion.cell_key(x + 1, y)] = [x + 1, y + 1]
      if !present.key?(ConwayCriterion.cell_key(x, y + 1))
        starts[ConwayCriterion.cell_key(x + 1, y + 1)] = [x, y + 1]
      if !present.key?(ConwayCriterion.cell_key(x - 1, y))
        starts[ConwayCriterion.cell_key(x, y + 1)] = [x, y]
      i = i
    # Start from the lowest, then leftmost boundary corner.
    best = nil
    i = 0
    while i < cells.size
      candidate = [cells[i][0], cells[i][1]]
      if best == nil || candidate[1] < best[1] || (candidate[1] == best[1] && candidate[0] < best[0])
        best = candidate
      i += 1
    origin = [best[0], best[1]]
    steps = []
    current = [origin[0], origin[1]]
    guard = 0
    walking = true
    while walking
      nxt = starts.fetch(ConwayCriterion.cell_key(current[0], current[1]), nil)
      raise "boundary walk broke: the region is not a single closed loop" if nxt == nil
      steps.push([nxt[0] - current[0], nxt[1] - current[1]])
      current = nxt
      guard += 1
      raise "boundary walk did not close" if guard > 100000
      walking = false if current[0] == origin[0] && current[1] == origin[1]
    steps

  # Is the arc of `length` steps starting at `from` a palindrome?
  -> .palindrome?(steps, from, length)
    n = steps.size
    a = 0
    b = length - 1
    while a < b
      p = steps[(from + a) % n]
      q = steps[(from + b) % n]
      return false if p[0] != q[0] || p[1] != q[1]
      a += 1
      b -= 1
    true

  # Are the two arcs translates of one another, traversed oppositely?
  -> .translate_match?(steps, from_a, from_d, length)
    n = steps.size
    i = 0
    while i < length
      p = steps[(from_a + i) % n]
      q = steps[(from_d + length - 1 - i) % n]
      return false if p[0] != 0 - q[0] || p[1] != 0 - q[1]
      i += 1
    true

  # Can the arc of `length` steps from `from` be cut into two palindromes?
  -> .splits_into_palindromes?(table, n, from, length)
    cut = 0
    while cut <= length
      first = table[((from % n) * (n + 1)) + cut]
      if first
        second = table[(((from + cut) % n) * (n + 1)) + (length - cut)]
        return true if second
      cut += 1
    false

  -> .palindrome_table(steps)
    n = steps.size
    table = []
    from = 0
    while from < n
      length = 0
      while length <= n
        table.push(ConwayCriterion.palindrome?(steps, from, length))
        length += 1
      from += 1
    table

  # Does the boundary satisfy the criterion?
  -> .satisfied_by_steps?(steps)
    n = steps.size
    return false if n == 0
    table = ConwayCriterion.palindrome_table(steps)
    from_a = 0
    while from_a < n
      length = 0
      while length <= n / 2
        # D starts somewhere after A ends, leaving room for both gaps.
        offset = length
        while offset + length <= n
          from_d = (from_a + offset) % n
          if ConwayCriterion.translate_match?(steps, from_a, from_d, length)
            gap_one = offset - length
            gap_two = n - offset - length
            if ConwayCriterion.splits_into_palindromes?(table, n, (from_a + length) % n, gap_one)
              if ConwayCriterion.splits_into_palindromes?(table, n, (from_d + length) % n, gap_two)
                return true
          offset += 1
        length += 1
      from_a += 1
    false

  # Does this polyomino satisfy the criterion? Shapes with holes are not
  # topological disks, so the criterion does not apply and the answer is
  # false by definition rather than by search.
  -> .satisfied?(shape)
    return false if shape.holes > 0
    ConwayCriterion.satisfied_by_steps?(ConwayCriterion.boundary_steps(shape.cells))

  -> .boundary_length(shape)
    ConwayCriterion.boundary_steps(shape.cells).size
