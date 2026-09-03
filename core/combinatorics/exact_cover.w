# Exact cover by dancing links (Knuth's Algorithm X, DLX).
#
# An exact cover instance is a 0/1 matrix. A solution is a set of rows that
# covers every *primary* column exactly once and every *secondary* column at
# most once. Secondary columns model "optional" constraints — the classic use
# is a region a piece may leave empty.
#
# The matrix is stored as a sparse torus of doubly-linked nodes held in flat
# integer arrays: `left/right/up/down` are neighbour indices, `column` is the
# node's column header and `row_of` its row id. Node 0 is the root header,
# nodes 1..column_count are the column headers, and data nodes follow.
#
# Covering a column unlinks it from the header ring and unlinks every node of
# every row meeting it from their own columns; uncovering relinks in exactly
# the reverse order. Because each node keeps its own neighbour pointers while
# unlinked, the relink is exact and the structure is restored perfectly on
# backtrack — the "dancing" of the name.
#
# Branching always takes a primary column of minimum remaining size (Knuth's
# S-heuristic), which keeps the search tree narrow.

+ ExactCover
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> new(column_count, primary_count)
    if !ExactCover.integer?(column_count) || column_count < 0
      raise "exact cover needs a nonnegative column count"
    if !ExactCover.integer?(primary_count) || primary_count < 0 || primary_count > column_count
      raise "primary column count must lie between 0 and the column count"
    @column_count = column_count
    @primary_count = primary_count
    @left = []
    @right = []
    @up = []
    @down = []
    @column = []
    @row_of = []
    @size = []
    @row_count = 0
    # Root header plus one header per column.
    i = 0
    while i <= column_count
      @left.push(i)
      @right.push(i)
      @up.push(i)
      @down.push(i)
      @column.push(i)
      @row_of.push(0 - 1)
      @size.push(0)
      i += 1
    # Primary columns join the root ring; secondary ones stay self-linked so
    # the search never branches on them, though they still block collisions.
    previous = 0
    i = 1
    while i <= primary_count
      @left[i] = previous
      @right[previous] = i
      previous = i
      i += 1
    @right[previous] = 0
    @left[0] = previous

  -> column_count
    @column_count

  -> row_count
    @row_count

  # Append a row covering the given column indices (1-based). Returns the
  # row id, which is what `solve` reports back.
  -> add_row(columns)
    if columns.class_name != "Array" || columns.size == 0
      raise "an exact cover row needs a nonempty array of column indices"
    row = @row_count
    @row_count += 1
    first = 0 - 1
    i = 0
    while i < columns.size
      c = columns[i]
      if !ExactCover.integer?(c) || c < 1 || c > @column_count
        raise "exact cover column index [c] is out of range"
      node = @left.size
      @column.push(c)
      @row_of.push(row)
      @size.push(0)
      # Splice to the bottom of column c.
      @up.push(@up[c])
      @down.push(c)
      @down[@up[c]] = node
      @up[c] = node
      @size[c] += 1
      # Splice into the row ring.
      if first < 0
        first = node
        @left.push(node)
        @right.push(node)
      else
        @left.push(@left[first])
        @right.push(first)
        @right[@left[first]] = node
        @left[first] = node
      i += 1
    row

  -> cover(c)
    @right[@left[c]] = @right[c]
    @left[@right[c]] = @left[c]
    i = @down[c]
    while i != c
      j = @right[i]
      while j != i
        @down[@up[j]] = @down[j]
        @up[@down[j]] = @up[j]
        @size[@column[j]] -= 1
        j = @right[j]
      i = @down[i]

  -> uncover(c)
    i = @up[c]
    while i != c
      j = @left[i]
      while j != i
        @size[@column[j]] += 1
        @down[@up[j]] = j
        @up[@down[j]] = j
        j = @left[j]
      i = @up[i]
    @right[@left[c]] = c
    @left[@right[c]] = c

  # Primary column with the fewest remaining rows, or -1 when none remain.
  -> choose_column
    best = 0 - 1
    best_size = 0
    c = @right[0]
    while c != 0
      if best < 0 || @size[c] < best_size
        best = c
        best_size = @size[c]
      c = @right[c]
    best

  -> search
    if @right[0] == 0
      @solutions.push(ExactCover.copy_ints(@stack))
      return @solutions.size >= @limit
    c = choose_column
    return false if @size[c] == 0
    cover(c)
    stop = false
    r = @down[c]
    while r != c && !stop
      @stack.push(@row_of[r])
      j = @right[r]
      while j != r
        cover(@column[j])
        j = @right[j]
      stop = search()
      j = @left[r]
      while j != r
        uncover(@column[j])
        j = @left[j]
      @stack.pop
      r = @down[r]
    uncover(c)
    stop

  -> .copy_ints(values)
    out = []
    i = 0
    while i < values.size
      out.push(values[i])
      i += 1
    out

  -> prepare(limit)
    @solutions = []
    @stack = []
    @limit = limit

  # First solution as an array of row ids, or nil when none exists.
  -> solve
    prepare(1)
    search()
    return nil if @solutions.size == 0
    @solutions[0]

  -> solvable?
    solve != nil

  # Up to `limit` solutions.
  -> solve_all(limit)
    prepare(limit)
    search()
    @solutions

  -> count_solutions(limit)
    solve_all(limit).size

  # Streaming search: call `callback` with each solution (an array of row
  # ids) as it is found, without accumulating them; the callback returns
  # true to stop the search early. Returns true if it was stopped.
  -> each_solution(callback)
    @stack = []
    @visit = callback
    search_each()

  -> search_each
    if @right[0] == 0
      return @visit.call(ExactCover.copy_ints(@stack))
    c = choose_column
    return false if @size[c] == 0
    cover(c)
    stop = false
    r = @down[c]
    while r != c && !stop
      @stack.push(@row_of[r])
      j = @right[r]
      while j != r
        cover(@column[j])
        j = @right[j]
      stop = search_each()
      j = @left[r]
      while j != r
        uncover(@column[j])
        j = @left[j]
      @stack.pop
      r = @down[r]
    uncover(c)
    stop
