# Fast-mode arithmetic certificate for two AND-inverter circuits. Every gate
# and input alias is checked against original clauses. Canonical XOR/majority
# identities expose half/full adders; counted rewrites preserve a weighted
# integer sum. Equal initial sums and unique lower bit positions force the
# selected output bits equal, contradicting their unit clauses.
# This does not emit DRAT: proof modes must use the ordinary solver.
use atomic_stop

+ WassatAdderConservation
  ro :meta

  -> new(@stop, @deadline)
    # status, gates, nodes, XORs, majorities, operations, rewrites, visits,
    # stop (1 cancel, 2 deadline, 3 capacity), initial terms, target rank
    @meta = i64[11]

  -> allocate
    @scratch = i32[64]
    @kind = i8[32768]
    @offset = i32[32768]
    @width = i8[32768]
    @args = i32[131072]
    @slots = i32[65536]
    @nodes = 1
    @arg_count = 0
    @wp = i32[32768]
    @wd = i32[32768]
    @wp[1] = 1
    @potential = 0

  -> stopped?
    return true if @meta[8] != 0
    if wassat_stop_load(@stop) != 0
      @meta[8] = 1
    elsif @deadline > 0 && clock_ms() >= @deadline
      @meta[8] = 2
    @meta[8] != 0

  -> visit?
    @meta[7] += 1
    @meta[8] = 3 if @meta[7] > 2000000
    (@meta[7] & 255) == 0 ? stopped? : @meta[8] != 0

  -> abs(x)
    x < 0 ? 0 - x : x

  -> arg(v, i)
    @args[@offset[abs(v)] + i]

  # Exact interning: hash collisions always compare every argument.
  -> intern(kind, n)
    return 1 if visit?
    h = kind
    i = 0
    while i < n
      h = (h * 131 + @scratch[i] + 65536) & 65535
      i += 1
    while @slots[h] != 0
      v = @slots[h]
      same = @kind[v] == kind && @width[v] == n
      i = 0
      while i < n && same
        same = false if arg(v, i) != @scratch[i]
        i += 1
      return v if same
      return 1 if visit?
      h = (h + 1) & 65535
    if @nodes >= 32767 || @arg_count + n > 131072
      @meta[8] = 3
      return 1
    @nodes += 1
    v = @nodes
    @slots[h] = v
    @kind[v] = kind
    @width[v] = n
    @offset[v] = @arg_count
    @wp[v] = v
    i = 0
    while i < n
      @args[@arg_count] = @scratch[i]
      @arg_count += 1
      i += 1
    @meta[2] = @nodes
    v

  # Sorted symmetric difference; signed nodes denote Boolean complements.
  -> xor(a, b)
    n = 0
    parity = 0
    side = 0
    while side < 2
      x = side == 0 ? a : b
      if x < 0
        parity = parity ^ 1
        x = 0 - x
      if x == 1
        parity = parity ^ 1
      else
        width = @kind[x] == 3 ? @width[x] : 1
        j = 0
        while j < width
          y = @kind[x] == 3 ? arg(x, j) : x
          at = 0
          while at < n && @scratch[at] < y
            at += 1
          if at < n && @scratch[at] == y
            k = at
            while k + 1 < n
              @scratch[k] = @scratch[k + 1]
              k += 1
            n -= 1
          else
            if n >= 64
              @meta[8] = 3
              return 1
            k = n
            while k > at
              @scratch[k] = @scratch[k - 1]
              k -= 1
            @scratch[at] = y
            n += 1
          j += 1
      side += 1
    v = n == 0 ? -1 : (n == 1 ? @scratch[0] : intern(3, n))
    parity == 0 ? v : 0 - v

  -> majority(a, b, c)
    return a if a == b || a == c
    return b if b == c
    return c if a == 0 - b
    return b if a == 0 - c
    return a if b == 0 - c
    @scratch[0] = a
    @scratch[1] = b
    @scratch[2] = c
    i = 1
    while i < 3
      v = @scratch[i]
      j = i
      while j > 0 && abs(@scratch[j - 1]) > abs(v)
        @scratch[j] = @scratch[j - 1]
        j -= 1
      @scratch[j] = v
      i += 1
    inv = @scratch[0] < 0
    if inv
      i = 0
      while i < 3
        @scratch[i] = 0 - @scratch[i]
        i += 1
    v = intern(4, 3)
    inv ? 0 - v : v

  -> conjunction(a, b)
    return a if a == b
    return -1 if a == 0 - b || a == -1 || b == -1
    return b if a == 1
    return a if b == 1
    if a < 0 && b < 0 && @kind[0 - a] == 2 && @kind[0 - b] == 2
      x = arg(a, 0)
      y = arg(a, 1)
      z = arg(b, 0)
      t = arg(b, 1)
      if (x == 0 - z && y == 0 - t) || (x == 0 - t && y == 0 - z)
        @meta[3] += 1
        return xor(x, y)
      q = xor(x, y)
      if q == z || q == t
        @meta[4] += 1
        return 0 - majority(x, y, q == z ? t : z)
      q = xor(z, t)
      if q == x || q == y
        @meta[4] += 1
        return 0 - majority(z, t, q == x ? y : x)
    # Flatten only a temporary three-product window. Keeping the stored AND
    # binary preserves the two-level XOR recognizer above.
    p = 0
    q = 0
    r = 0
    if a > 0 && @kind[a] == 2
      p = arg(a, 0)
      q = arg(a, 1)
      r = b
    elsif b > 0 && @kind[b] == 2
      p = arg(b, 0)
      q = arg(b, 1)
      r = a
    if p < 0 && q < 0 && r < 0 && @kind[0 - p] == 2 && @kind[0 - q] == 2 && @kind[0 - r] == 2
      x = arg(p, 0)
      y = arg(p, 1)
      z = arg(q, 0)
      t = arg(q, 1)
      # Three distinct pairs xy, xz, yz, with signed inputs unchanged.
      third = 0
      third = t if z == x || z == y
      third = z if t == x || t == y
      if x != y && third != 0 && third != x && third != y
        u = arg(r, 0)
        v = arg(r, 1)
        missing = (z == x || t == x) ? y : x
        if (u == missing && v == third) || (v == missing && u == third)
          @meta[4] += 1
          return 0 - majority(x, y, third)
    @scratch[0] = a < b ? a : b
    @scratch[1] = a < b ? b : a
    intern(2, 2)

  -> binary_key(a, b)
    x = a < b ? a : b
    y = a < b ? b : a
    (x + @nv) * (2 * @nv + 1) + y + @nv + 1

  -> binary_slot(key)
    h = (key * 131) & 131071
    while @bins[h] != 0 && @bins[h] != key
      return 0 if visit?
      h = (h + 1) & 131071
    h

  -> has_binary?(a, b)
    key = binary_key(a, b)
    @bins[binary_slot(key)] == key

  -> root(parent, x)
    while parent[x] != x
      parent[x] = parent[parent[x]]
      x = parent[x]
    x

  -> alias(x)
    sign = x < 0 ? -1 : 1
    x = abs(x)
    while @alias[x] != x
      p = @alias[x]
      sign = 0 - sign if p < 0
      x = abs(p)
    sign * x

  -> weight(x)
    x = abs(x)
    @potential = 0
    while @wp[x] != x
      @potential += @wd[x]
      x = @wp[x]
    x

  -> link_weight(a, b, difference)
    ra = weight(a)
    da = @potential
    rb = weight(b)
    db = @potential
    return db - da == difference if ra == rb
    # IDs increase along the circuit; choosing the lower root bounds trees.
    if ra < rb
      @wp[rb] = ra
      @wd[rb] = difference + da - db
    else
      @wp[ra] = rb
      @wd[ra] = db - da - difference
    true

  -> run(formula)
    @nv = formula["nvars"]
    nc = formula["flat_ncl"]
    return 0 if @nv < 4 || @nv > 10000 || nc < 8 || nc > 40000 || stopped?
    lits = formula["flat_lits"]
    offs = formula["flat_offs"]
    lens = formula["flat_lens"]
    # Cheap shape admission before allocating the gate and binary indexes.
    units = i32[2]
    nu = 0
    ci = 0
    while ci < nc
      return 0 if visit?
      n = lens[ci]
      return 0 if n < 1 || n > 3
      if n == 1
        return 0 if nu == 2
        units[nu] = lits[offs[ci]]
        nu += 1
      ci += 1
    return 0 if nu != 2
    allocate
    @bins = i64[131072]
    gate = i32[@nv + 1]
    ga = i32[@nv + 1]
    gb = i32[@nv + 1]
    @alias = i32[@nv + 1]
    comp = i32[@nv + 1]
    expr = i32[@nv + 1]
    v = 1
    while v <= @nv
      @alias[v] = v
      comp[v] = v
      v += 1
    ci = 0
    while ci < nc
      return 0 if visit?
      n = lens[ci]
      off = offs[ci]
      j = 0
      while j < n
        v = abs(lits[off + j])
        return 0 if v < 1 || v > @nv
        j += 1
      if n == 2
        key = binary_key(lits[off], lits[off + 1])
        @bins[binary_slot(key)] = key
      elsif n == 3
        a = lits[off]
        b = lits[off + 1]
        o = lits[off + 2]
        if abs(a) > abs(o)
          t = a
          a = o
          o = t
        if abs(b) > abs(o)
          t = b
          b = o
          o = t
        v = abs(o)
        return 0 if gate[v] != 0 || abs(a) == v || abs(b) == v || abs(a) == abs(b)
        gate[v] = o
        ga[v] = 0 - a
        gb[v] = 0 - b
        @meta[1] += 1
      ci += 1
    ci = 0
    while ci < nc
      return 0 if visit?
      if lens[ci] == 2
        a = lits[offs[ci]]
        b = lits[offs[ci] + 1]
        if gate[abs(a)] == 0 && gate[abs(b)] == 0 && has_binary?(0 - a, 0 - b)
          ra = alias(a)
          rb = alias(0 - b)
          return 0 if ra == 0 - rb
          if abs(ra) != abs(rb)
            if abs(ra) < abs(rb)
              @alias[abs(rb)] = rb < 0 ? 0 - ra : ra
            else
              @alias[abs(ra)] = ra < 0 ? 0 - rb : rb
      ci += 1
    inputs = 0
    v = 1
    while v <= @nv
      return 0 if visit?
      if gate[v] == 0
        r = alias(v)
        if abs(r) == v
          inputs += 1
          return 0 if inputs > 64
          @scratch[0] = v
          expr[v] = intern(1, 1)
        else
          expr[v] = r < 0 ? 0 - expr[abs(r)] : expr[r]
      else
        a = ga[v]
        b = gb[v]
        return 0 unless has_binary?(0 - gate[v], a) && has_binary?(0 - gate[v], b)
        x = a < 0 ? 0 - expr[abs(a)] : expr[a]
        y = b < 0 ? 0 - expr[abs(b)] : expr[b]
        e = conjunction(x, y)
        expr[v] = gate[v] < 0 ? 0 - e : e
        comp[root(comp, v)] = root(comp, abs(a))
        comp[root(comp, v)] = root(comp, abs(b))
      v += 1
    return 0 if stopped?
    components = i32[2]
    targets = i32[2]
    side = 0
    while side < 2
      u = units[side]
      components[side] = root(comp, abs(u))
      targets[side] = u < 0 ? 0 - expr[abs(u)] : expr[u]
      side += 1
    return 0 if components[0] == components[1]
    seen = i8[65536]
    v = 1
    while v <= @nv
      if gate[v] != 0
        c = root(comp, v)
        side = 0
        while side < 2
          seen[side * 32768 + abs(expr[v])] = 1 if c == components[side]
          side += 1
      v += 1
    # Boolean integer identities: a+b = XOR(a,b) + 2*AND(a,b), and
    # a+b+c = XOR(a,b,c) + 2*MAJ(a,b,c). Complementing all three FA
    # inputs also complements its sum/carry. A candidate sum must occur
    # as a real gate output, not merely as an interned recognition probe.
    # Flat operations: side, arity, a, b, c (0 for HA), sum, carry.
    ops = i32[7 * 65536]
    count = 0
    limit = @nodes
    side = 0
    while side < 2
      v = 2
      while v <= limit
        return 0 if visit?
        if seen[side * 32768 + v] != 0 && (@kind[v] == 2 || @kind[v] == 4)
          a = arg(v, 0)
          b = arg(v, 1)
          c = @kind[v] == 4 ? arg(v, 2) : 0
          sum = xor(a, b)
          sum = xor(sum, c) if c != 0
          if seen[side * 32768 + abs(sum)] != 0
            return 0 unless link_weight(a, sum, 0) && link_weight(b, sum, 0) && link_weight(sum, v, 1)
            return 0 if c != 0 && !link_weight(c, sum, 0)
            sign = 1
            while sign >= (c == 0 ? 1 : -1)
              if count >= 65536
                @meta[8] = 3
                return 0
              at = 7 * count
              ops[at] = side
              ops[at + 1] = c == 0 ? 2 : 3
              ops[at + 2] = sign * a
              ops[at + 3] = sign * b
              ops[at + 4] = sign * c
              ops[at + 5] = sign * sum
              ops[at + 6] = sign * v
              count += 1
              sign -= 2
        v += 1
      side += 1
    @meta[5] = count
    return 0 if stopped?
    target_root = weight(targets[0])
    rank = @potential
    return 0 if weight(targets[1]) != target_root || @potential != rank
    # Weights are formal integer exponents constrained by the identities:
    # inputs/sum have equal weight and carry is one higher. They need not
    # be inferred from names or from any proposed multiplier bit layout.
    # Begin with exactly one copy of each common primary-input product.
    available = i32[131072]
    lowest = rank
    v = 2
    while v <= limit
      return 0 if visit?
      if @kind[v] == 2 && @kind[abs(arg(v, 0))] == 1 && @kind[abs(arg(v, 1))] == 1 && weight(v) == target_root
        a = seen[v]
        b = seen[32768 + v]
        return 0 if a != b
        if a != 0
          available[32768 + v] = 1
          available[98304 + v] = 1
          @meta[9] += 1
          lowest = @potential if @potential < lowest
      v += 1
    rank -= lowest
    @meta[10] = rank
    return 0 if @meta[9] == 0 || rank < 0 || rank > 62
    # Prefer full adders over half adders using the same pair. This changes
    # only the search order: the counted identity checks below are mandatory.
    pairs = {}
    oi = 0
    while oi < count
      return 0 if visit?
      at = 7 * oi
      if ops[at + 1] == 3
        i = 0
        while i < 3
          j = i + 1
          while j < 3
            a = ops[at + 2 + i]
            b = ops[at + 2 + j]
            key = ops[at] * 4294967296 + (a < b ? a + 32768 : b + 32768) * 65536 + (a < b ? b + 32768 : a + 32768)
            pairs[key] = true
            j += 1
          i += 1
      oi += 1
    used = i8[count]
    progress = true
    while progress
      progress = false
      oi = 0
      while oi < count
        return 0 if visit?
        at = 7 * oi
        if used[oi] == 0
          side = ops[at]
          n = ops[at + 1]
          a = ops[at + 2]
          b = ops[at + 3]
          key = side * 4294967296 + (a < b ? a + 32768 : b + 32768) * 65536 + (a < b ? b + 32768 : a + 32768)
          allowed = n == 3 || pairs[key] == nil
          base = side * 65536 + 32768
          i = 0
          while i < n && allowed
            x = ops[at + 2 + i]
            needed = 1
            j = 0
            while j < i
              needed += 1 if ops[at + 2 + j] == x
              j += 1
            allowed = false if available[base + x] < needed
            i += 1
          if allowed
            i = 0
            while i < n
              available[base + ops[at + 2 + i]] -= 1
              i += 1
            available[base + ops[at + 5]] += 1
            available[base + ops[at + 6]] += 1
            used[oi] = 1
            @meta[6] += 1
            progress = true
        oi += 1
    # Modulo 2^(rank+1), distinct nonnegative lower ranks sum to less than
    # 2^rank. Thus the sole bit at rank is determined by the common sum.
    required = i8[2]
    side = 0
    while side < 2
      ranks = i32[63]
      found = false
      x = 0 - @nodes
      while x <= @nodes
        return 0 if visit?
        copies = available[side * 65536 + 32768 + x]
        if copies > 0
          return 0 if weight(x) != target_root
          w = @potential - lowest
          return 0 if w < 0 || w > 62
          if w <= rank
            ranks[w] += copies
            return 0 if ranks[w] > 1
          if w == rank
            return 0 if abs(x) != abs(targets[side])
            required[side] = x == targets[side] ? 1 : 0
            found = true
        x += 1
      return 0 unless found
      side += 1
    return 0 if stopped? || required[0] == required[1]
    @meta[0] = -1
    -1

-> wassat_adder_conservation_refute(formula, stop, deadline = 0)
  checker = WassatAdderConservation.new(stop, deadline)
  checker.run(formula) if formula != nil
  checker.meta

-> wassat_adder_conservation_unsat?(formula)
  return false if env("WASSAT_ADDER_CONSERVATION") == "0"
  return false if formula["nvars"] < 4 || formula["nvars"] > 10000 || formula["flat_ncl"] > 40000
  started = clock_ms()
  meta = wassat_adder_conservation_refute(formula, i64[1], started + 100)
  if env("WASSAT_PROFILE") == "1"
    wassat_prof_note("adder_conservation status=[meta[0]] gates=[meta[1]] nodes=[meta[2]] xors=[meta[3]] majorities=[meta[4]] ops=[meta[5]] rewrites=[meta[6]] visits=[meta[7]] stop=[meta[8]] terms=[meta[9]] rank=[meta[10]] ms=[clock_ms() - started]")
  meta[0] == -1
