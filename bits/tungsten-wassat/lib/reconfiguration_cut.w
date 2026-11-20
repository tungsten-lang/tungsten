# At a time cut, k removals cannot vacate k+1 distinct starting vertices.
# If every pair of goal vertices needs that many vacancies, at most one goal
# can be occupied. The remaining additions must then accommodate all others.
use reconfiguration

-> wassat_jump_clause(out, row)
  out.append(row.join(" "))
  out.append(" 0\n")

# Assuming both goal vertices, each listed blocker must use a removal slot.
# Split on the injection for the first blockers. The final two collide by UP.
-> wassat_jump_split(out, guard, blockers, removal, used, depth)
  if depth + 1 < removal.size
    i = 0
    while i < removal.size
      bit = 1 << i
      if (used & bit) == 0
        guard.push(0 - removal[i] - blockers[depth])
        wassat_jump_split(out, guard, blockers, removal, used | bit, depth + 1)
        guard.pop
      i += 1
  wassat_jump_clause(out, guard)

# Cook's extended-resolution pigeonhole reduction. Drop the last pigeon p
# and last hole h. If i occupied h, it can inherit the hole occupied by p.
# z(i,j) is defined as q(i,j) OR (q(i,h) AND q(p,j)).
-> wassat_jump_pigeonhole(out, matrix, nv)
  q = matrix
  fresh = nv
  while q.size > 2
    m = q.size - 1
    next_rows = []
    i = 0
    while i < m
      row = []
      j = 0
      while j < m - 1
        fresh += 1
        a = q[i][j]
        b = q[i][m-1]
        c = q[m][j]
        out.append("[fresh] [-a] 0\n[fresh] [-b] [-c] 0\n[-fresh] [a] [b] 0\n[-fresh] [a] [c] 0\n")
        row.push(fresh)
        j += 1
      wassat_jump_clause(out, row)
      k = 0
      while k < i
        j = 0
        while j < m - 1
          x = row[j]
          y = next_rows[k][j]
          c = q[m][j]
          out.append("[-x] [-y] [c] 0\n[-x] [-y] 0\n")
          j += 1
        k += 1
      next_rows.push(row)
      i += 1
    q = next_rows
  out.append("0\n")

+ WassatJumpCut
  -> new(f)
    @nv = f["nvars"]
    @nc = f["flat_ncl"]
    @lits = f["flat_lits"]
    @offs = f["flat_offs"]
    @lens = f["flat_lens"]
    @meta = i64[32]
    @starts = i64[WASSAT_RECONF_MAX_STATES]
    @initial = []
    @goals = []
    @removal = []
    @addition = []
    @blockers = []

  -> id(a, b, c, len)
    wassat_rc_clause(@lits, @offs, @lens, @table, a, b, c, len, 0, @meta)

  # Product-encoded move selectors: selecting a vertex forces its two
  # coordinates. Distinct coordinates in either dimension conflict.
  -> selector(base, n, width)
    v = 0
    while v < n
      return false if id(-base-v, base+n+(v % width), 0, 2) == 0
      return false if id(-base-v, base+n+width+(v / width), 0, 2) == 0
      v += 1
    off = 0
    while off <= width
      count = off == 0 ? width : (n + width - 1) / width
      i = 0
      while i < count
        j = i + 1
        while j < count
          return false if id(-base-n-off-i, -base-n-off-j, 0, 2) == 0
          j += 1
        i += 1
      off += width
    true

  -> prepare
    fixed = i8[@nv + 1]
    initial = i64[8]
    goal = i64[8]
    adj = i64[WASSAT_RECONF_MAX_VERTICES * 8]
    n = wassat_reconf_prepare(@lits, @offs, @lens, @nv, @nc, fixed, @starts, initial, goal, adj, @meta, i64[1], 0)
    return false if n == 0
    v = 0
    while v < n
      mask = 1 << (v & 63)
      @initial.push(v) if (initial[v >> 6] & mask) != 0
      @goals.push(v) if (goal[v >> 6] & mask) != 0
      v += 1
    horizon = @meta[4]
    # Leave |goal|-2 additions after the cut. Bound enumeration and proof size.
    cut = horizon - @goals.size + 2
    return false if @goals.size < 3 || @goals.size > 56 || cut < 1 || cut > 4 || cut >= horizon
    @mid = @starts[cut-1] + 1
    words = (n + 63) / 64
    i = 0
    while i < @goals.size
      u = @goals[i]
      j = i + 1
      while j < @goals.size
        w = @goals[j]
        blockers = []
        index_x = 0
        while index_x < @initial.size
          x = @initial[index_x]
          neighbors = adj[u*words+(x >> 6)] | adj[w*words+(x >> 6)]
          blockers.push(x) if (neighbors & (1 << (x & 63))) != 0
          break if blockers.size > cut
          index_x += 1
        return false unless blockers.size > cut
        @blockers.push(blockers)
        j += 1
      i += 1
    size = 1
    while size < 2 * @nc
      size *= 2
    @table = i32[size]
    ci = 0
    while ci < @nc
      len = @lens[ci]
      if len >= 1 && len <= 3
        off = @offs[ci]
        b = len >= 2 ? @lits[off+1] : 0
        c = len == 3 ? @lits[off+2] : 0
        return false if wassat_rc_clause(@lits, @offs, @lens, @table, @lits[off], b, c, len, ci+1, @meta) == 0
      ci += 1
    width = 1
    while width*width < n
      width += 1
    k = 0
    while k < horizon
      base = @starts[k] + n + 1
      if k < cut
        base += n + width + (n + width - 1) / width
        @removal.push(base)
        index_x = 0
        while index_x < @initial.size
          x = @initial[index_x]
          now = @starts[k]+1+x
          if k == 0
            return false if id(now, base+x, 0, 2) == 0
          else
            return false if id(0 - @starts[k-1]-1-x, now, base+x, 3) == 0
          index_x += 1
      else
        @addition.push(base)
        index_x = 0
        while index_x < @goals.size
          x = @goals[index_x]
          return false if id(@starts[k-1]+1+x, 0 - @starts[k]-1-x, base+x, 3) == 0
          index_x += 1
      return false unless selector(base, n, width)
      k += 1
    true

  -> drat
    out = StringBuffer()
    index_x = 0
    while index_x < @initial.size
      x = @initial[index_x]
      row = [@mid+x]
      index_base = 0
      while index_base < @removal.size
        base = @removal[index_base]
        row.push(base+x)
        index_base += 1
      wassat_jump_clause(out, row)
      index_x += 1
    pair = 0
    i = 0
    while i < @goals.size
      j = i + 1
      while j < @goals.size
        guard = [0 - @mid - @goals[i], 0 - @mid - @goals[j]]
        wassat_jump_split(out, guard, @blockers[pair], @removal, 0, 0)
        pair += 1
        j += 1
      i += 1
    q = []
    index_x = 0
    while index_x < @goals.size
      x = @goals[index_x]
      row = [@mid+x]
      index_base = 0
      while index_base < @addition.size
        base = @addition[index_base]
        row.push(base+x)
        index_base += 1
      wassat_jump_clause(out, row)
      q.push(row)
      index_x += 1
    wassat_jump_pigeonhole(out, q, @nv)
    out.to_s

-> wassat_jump_cut(formula, emit)
  nc = formula["flat_ncl"]
  nv = formula["nvars"]
  return nil if nc < 16 || nc > 3000000 || nv < 16 || nv > 750000
  lens = formula["flat_lens"] ## i64[]
  return nil unless lens[0] == 2 && lens[nc-1] == 1
  return nil if wassat_reconf_large_prefix(formula["flat_lits"], formula["flat_offs"], lens, nc) == 0
  cut = WassatJumpCut.new(formula)
  return nil unless cut.prepare
  emit ? cut.drat : ""
