# Finite clue search after complete original-clause verification. Boards use
# row-major order. A completion is only a reason to decline the refutation;
# this worker never publishes SAT. Search buffers are reused through recursion.

-> wassat_naked_pop(mask) (i64) i64
  n = 0
  while mask != 0
    mask = mask & (mask - 1); n += 1
  n

-> wassat_naked_put(cell, bit, values, rows, cols, boxes, trail, top, n, rank) (i64 i64 i64[] i64[] i64[] i64[] i32[] i64 i64 i64) i64
  row = cell / n; col = cell % n; box = row / rank * rank + col / rank
  values[cell] = bit; rows[row] = rows[row] | bit
  cols[col] = cols[col] | bit; boxes[box] = boxes[box] | bit
  trail[top] = cell
  top + 1

-> wassat_naked_undo(values, rows, cols, boxes, trail, top, mark, n, rank) (i64[] i64[] i64[] i64[] i32[] i64 i64 i64 i64)
  while top > mark
    top -= 1; cell = trail[top]; bit = values[cell]
    row = cell / n; col = cell % n; box = row / rank * rank + col / rank
    values[cell] = 0; rows[row] = rows[row] ^ bit
    cols[col] = cols[col] ^ bit; boxes[box] = boxes[box] ^ bit

-> wassat_naked_search(values, rows, cols, boxes, trail, clues, top, n, rank, m, stop, deadline, cap) (i64[] i64[] i64[] i64[] i32[] i8[] i64 i64 i64 i64[] i64[] i64 i64)
  m[0] += 1
  if m[0] > cap
    m[6] = 3
    return 0
  if (m[0] & 255) == 0
    m[6] = 1 if wassat_stop_load(stop) != 0
    m[6] = 2 if m[6] == 0 && deadline > 0 && clock_ms() >= deadline
    return 0 if m[6] != 0
  mark = top; full = (1 << n) - 1; best = -1; choices = 0; failed = false
  again = true
  while again && !failed
    again = false; best = -1; count = n + 1; cell = 0
    while cell < n * n && !failed
      if values[cell] == 0
        row = cell / n; col = cell % n; box = row / rank * rank + col / rank
        mask = full ^ (rows[row] | cols[col] | boxes[box])
        size = wassat_naked_pop(mask)
        if size == 0
          failed = true; m[4] += 1
        elsif size == 1
          top = wassat_naked_put(cell, mask, values, rows, cols, boxes, trail, top, n, rank)
          m[2] += 1; again = true
        elsif clues[cell] != 0 && size < count
          best = cell; choices = mask; count = size
      cell += 1
  m[7] = top if top > m[7]
  if m[15] > 0
    nonclues = 0; cell = 0
    while cell < n * n
      nonclues += 1 if clues[cell] == 0 && values[cell] != 0
      cell += 1
    m[10] = nonclues if nonclues > m[10]
  if !failed && top != n * n && best >= 0 && m[15] > 0
    # Any later progress must start with a non-clue cell. Count the distinct
    # already placed peer digits and give each unassigned clue peer credit
    # for one extra digit. This is an upper bound even when those clues clash.
    possible = false; missing = false; cell = 0; progress_choice = -1
    while cell < n * n && !possible
      if clues[cell] == 0 && values[cell] == 0
        missing = true; row = cell / n; col = cell % n
        box = row / rank * rank + col / rank
        known = wassat_naked_pop(rows[row] | cols[col] | boxes[box])
        unknown = 0; j = 0; pick = -1; pick_size = n + 1
        while j < n * n
          jr = j / n; jc = j % n
          if clues[j] != 0 && values[j] == 0 && (jr == row || jc == col || jr / rank == row / rank && jc / rank == col / rank)
            unknown += 1
            jb = jr / rank * rank + jc / rank
            sz = wassat_naked_pop(full ^ (rows[jr] | cols[jc] | boxes[jb]))
            if sz < pick_size
              pick = j; pick_size = sz
          j += 1
        m[8] += 1
        if known + unknown >= n - 1
          possible = true; progress_choice = pick
      cell += 1
    if missing && !possible
      failed = true; m[9] += 1
    elsif m[15] > 1 && progress_choice >= 0
      best = progress_choice; row = best / n; col = best % n
      box = row / rank * rank + col / rank
      choices = full ^ (rows[row] | cols[col] | boxes[box])
  if !failed
    if top == n * n
      m[5] += 1; m[6] = 4
    elsif best < 0
      m[3] += 1
    else
      while choices != 0 && m[6] == 0
        bit = choices & (0 - choices); choices = choices ^ bit; m[1] += 1
        next_top = wassat_naked_put(best, bit, values, rows, cols, boxes, trail, top, n, rank)
        z = wassat_naked_search(values, rows, cols, boxes, trail, clues, next_top, n, rank, m, stop, deadline, cap)
        z = wassat_naked_undo(values, rows, cols, boxes, trail, next_top, top, n, rank)
  z = wassat_naked_undo(values, rows, cols, boxes, trail, top, mark, n, rank)
  0

+ WassatNakedSudoku
  -> search(node_cap = 1000000) (i64) i64
    return 0 if @meta[16] != 5 || node_cap < 1 || poll
    n = @n; rank = @rank
    clues = i8[@cells]; values = i64[@cells]; trail = i32[@cells]
    rows = i64[n]; cols = i64[n]; boxes = i64[n]; m = i64[16]
    @meta[30] += 13 * @cells + 24 * n + 128
    i = 0
    while i < @cells
      # The CNF declares I before J; transpose into the row-major kernel.
      clues[(i % n) * n + i / n] = 1 if @clues[i] != 0
      i += 1
    first = -1; first_count = 0; peer_count = 0; cell = 0
    while cell < @cells
      if clues[cell] == 0
        row = cell / n; col = cell % n; j = 0; count = 0
        while j < @cells
          jr = j / n; jc = j % n
          if clues[j] != 0 && (row == jr || col == jc || row / rank == jr / rank && col / rank == jc / rank)
            count += 1
          j += 1
        if count >= n - 1
          first = cell; first_count += 1; peer_count = count
      cell += 1
    @meta[29] = first
    # Without a possible first single, the first progress requirement already
    # contradicts the nonempty set of unfilled cells.
    return -1 if first_count == 0 && !poll
    return 0 if first_count != 1 || peer_count != n - 1
    # All peers of the unique possible first single must have distinct digits.
    # Normalize them using digit symmetry of the CHECKED semantic system; no
    # permutation of Boolean threshold literals is assumed.
    row = first / n; col = first % n; j = 0; bit = 1; top = 0
    while j < @cells
      jr = j / n; jc = j % n
      if clues[j] != 0 && (row == jr || col == jc || row / rank == jr / rank && col / rank == jc / rank)
        top = wassat_naked_put(j, bit, values, rows, cols, boxes, trail, top, n, rank)
        bit = bit << 1
      j += 1
    @meta[28] = top; m[15] = 2
    z = wassat_naked_search(values, rows, cols, boxes, trail, clues, top, n, rank, m, @stop, @deadline, node_cap)
    @meta[18] = m[0]; @meta[19] = m[1]; @meta[20] = m[2]
    @meta[21] = m[3]; @meta[22] = m[4]; @meta[23] = m[5]
    @meta[24] = m[7]; @meta[25] = m[8]; @meta[26] = m[9]; @meta[27] = m[10]
    @meta[0] = m[6] if m[6] != 0
    return 0 if poll || m[5] != 0 || m[6] != 0
    # Any candidate-change stage places a new non-clue value. An exhausted
    # closure bound smaller than the number of required progress stages
    # cannot reach the last stage or complete the board.
    return -1 if m[10] < @steps && m[10] < @cells - @nclues
    0
