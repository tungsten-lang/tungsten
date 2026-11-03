# Bounded original-clause refutation of order-encoded weighted rosters.
# Layout and additive-table inference only propose a proof. Every inequality,
# window and penalty used by the final counting bound is checked below.
+ WassatRoster
  ro :meta

  -> new(formula, @stop, @deadline, meta = nil)
    @nv = formula["nvars"]; @nc = formula["flat_ncl"]; @nl = formula["flat_nlits"]
    bind_flat(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"])
    @meta = meta == nil ? i64[64] : meta
    @tick = 0; @nd = 0; @nr = 0; @local_count = 0; @stamp = 0; @bool_stamp = 0
    @values_used = 0; @nleaf = 0; @constant = 0; @small = 0

  # Declare the immutable parser buffers once; every scan uses raw i64 loads.
  -> bind_flat(@lits, @offs, @lens) (i64[] i64[] i64[])
    0

  -> abs(x) (i64) i64
    x < 0 ? 0 - x : x

  -> poll
    @meta[1] += 1
    @meta[0] = 1 if wassat_stop_load(@stop) != 0
    @meta[0] = 2 if @deadline > 0 && clock_ms() >= @deadline && @meta[0] == 0
    @meta[0] != 0

  -> visit
    @tick += 1
    @meta[0] = 3 if @tick > 2000000000
    (@tick & 1023) == 0 ? poll : @meta[0] != 0

  -> allocate
    n = @nv + 1
    @local_cap = @nc < 1000000 ? @nc : 1000000
    @occ_cap = @nl < 2000000 ? @nl : 2000000
    @value_cap = 5 * n < 2000000 ? 5 * n : 2000000
    @table_cap = 64 * n < 1000000 ? 64 * n : 1000000
    hash_size = 1
    while hash_size < @local_cap
      hash_size *= 2
    @hash_mask = hash_size - 1
    @owner = i32[n]; @start = i32[n]; @length = i32[n]
    @upper = i32[n]; @upper_next = i32[@nc]; @parents = i32[3 * n]; @arity = i32[n]
    @root_slots = i32[8192]; @roots = i32[4096 * 5]; @root_done = i8[4096]
    @seen = i32[n]; @value_offset = i32[n]; @values = i32[@value_cap]; @hi = i32[@table_cap]
    @leaves = i32[256]; @leaf_mark = i32[n]; @work = i32[256]; @path = i32[256]
    @degree = i8[n]; @edge1 = i32[n]; @edge2 = i32[n]; @work_flag = i32[n]
    @primary = i8[n]; @selected = i8[n]; @dsu = i32[n]; @bad = i8[n]
    @local = i32[@local_cap]; @hash_next = i32[@local_cap]; @slots = i32[hash_size]
    @first = i32[n]; @occ_ref = i32[@occ_cap]; @occ_next = i32[@occ_cap]; @clause_seen = i32[@local_cap]
    @weights = i32[n]; @used_flag = i8[n]; @pref_seen = i32[n]
    @bool_vars = i32[12]; @bool_lo = i32[4096]; @bool_hi = i32[4096]; @bool_bad = i8[4096]; @bool_weights = i32[12]
    @bound_counts = i32[2049]; @eq = i32[2 * n]; @canon = i32[2 * n]; @windows = i8[256]
    @meta[30] = 4 * (23 * n + @nc + @value_cap + @table_cap + 3 * @local_cap + hash_size + 2 * @occ_cap + 33024) + 5 * n + 13568

  -> root_insert(a, b, c, bound) (i64 i64 i64 i64) i64
    if a > b
      t = a; a = b; b = t
    if b > c
      t = b; b = c; c = t
    if a > b
      t = a; a = b; b = t
    h = (a * 131 + b * 8191 + c * 65537 + bound) & 8191
    while @root_slots[h] != 0
      r = @root_slots[h] - 1; o = 5 * r
      if @roots[o] == a && @roots[o + 1] == b && @roots[o + 2] == c && @roots[o + 3] == bound
        @roots[o + 4] += 1; return 1
      return 0 if visit
      h = (h + 1) & 8191
    return 0 if @nr >= 4096
    o = 5 * @nr; @roots[o] = a; @roots[o + 1] = b; @roots[o + 2] = c
    @roots[o + 3] = bound; @roots[o + 4] = 1; @nr += 1; @root_slots[h] = @nr
    1

  -> decode
    return false if @nv < 1 || @nv > 1000000 || @nc < 1 || @nc > 10000000 || @nl < 1 || @nl > 40000000
    return false if @offs.size < @nc || @lens.size < @nc || @lits.size < @nl || poll
    allocate
    # Prefix recognition is conservative under renaming/reordering. A missing
    # link creates a smaller domain; links are never assumed from identifiers.
    ci = 0
    while ci < @nc && @lens[ci] == 2
      o = @offs[ci]; return false if o < 0 || o + 2 > @nl
      a = @lits[o]; b = @lits[o + 1]
      if a > b
        t = a; a = b; b = t
      break unless a < 0 && b == 1 - a
      v = 0 - a; return false if v < 1 || b > @nv
      @owner[v] = 1; ci += 1
      return false if visit
    return false if ci == 0
    @meta[2] = ci; v = 1
    while v <= @nv
      a = v
      while v < @nv && @owner[v] == 1
        v += 1
      d = @nd; @nd += 1; @start[d] = a; @length[d] = v - a + 1
      while a <= v
        @owner[a] = d; a += 1
      v += 1
    ci = 0
    while ci < @nc
      return false if visit
      o = @offs[ci]; n = @lens[ci]
      return false if n < 1 || n > 64 || o < 0 || o > @nl || n > @nl - o
      j = 0; pos = -1; positives = 0; numeric = true; distinct = true; bound = 1
      a = -1; b = -1; c = -1
      while j < n
        x = @lits[o + j]; v = abs(x); return false if v < 1 || v > @nv
        d = @owner[v]; numeric = false if @length[d] <= 1
        distinct = false if d == a || d == b || d == c
        a = d if j == 0; b = d if j == 1; c = d if j == 2
        bound += v - @start[d]
        if x > 0
          positives += 1; pos = d
        j += 1
      if numeric && distinct && n >= 2 && n <= 4
        return false if positives == 0 && n == 3 && root_insert(a, b, c, bound) == 0
        if positives == 1
          ok = true; j = 0
          while j < n
            d = @owner[abs(@lits[o + j])]; ok = false if @length[d] > @length[pos]; j += 1
          if ok
            @upper_next[ci] = @upper[pos]; @upper[pos] = ci + 1; j = 0
            while j < n
              d = @owner[abs(@lits[o + j])]
              if d != pos && @arity[pos] <= 3
                k = 0
                while k < @arity[pos] && @parents[3 * pos + k] != d
                  k += 1
                if k == @arity[pos]
                  @parents[3 * pos + k] = d if k < 3
                  @arity[pos] += 1
              j += 1
      ci += 1
    @meta[3] = @nd; @meta[4] = @nr
    true

  -> hour(d, vo, depth) (i64 i64 i64) i64
    return 0 if depth > 32 || @seen[d] == @stamp || poll
    @seen[d] = @stamp; @value_offset[d] = vo
    arity = @arity[d]; len = @length[d]; j = 1
    while j <= len
      return 0 if @values[vo + j] < @values[vo + j - 1] || @values[vo + j] > 1000000
      j += 1
    if arity == 0
      return 0 if @nleaf >= 256 || len < 1 || @values[vo] != 0 || @values[vo + len] <= @values[vo + len - 1]
      @leaves[@nleaf] = d; @nleaf += 1; @leaf_mark[d] = @stamp
      return 1
    return 0 if arity > 3
    p0 = @parents[3 * d]; p1 = @parents[3 * d + 1]; p2 = @parents[3 * d + 2]
    n0 = @length[p0] + 1; n1 = arity >= 2 ? @length[p1] + 1 : 1; n2 = arity == 3 ? @length[p2] + 1 : 1
    size = n0 * n1 * n2; s0 = n1 * n2; s1 = n2
    return 0 if size > @table_cap || @values_used + n0 + n1 + n2 > @value_cap
    i = 0
    while i < size
      @hi[i] = len; i += 1
    ref = @upper[d]
    while ref > 0
      return 0 if visit
      ci = ref - 1; ref = @upper_next[ci]; o = @offs[ci]; j = 0
      c0 = n0 - 1; c1 = n1 - 1; c2 = n2 - 1; bound = len
      while j < @lens[ci]
        x = @lits[o + j]; pd = @owner[abs(x)]; value = abs(x) - @start[pd]
        if x > 0
          return 0 if pd != d
          bound = value
        elsif pd == p0
          c0 = value
        elsif arity >= 2 && pd == p1
          c1 = value
        elsif arity == 3 && pd == p2
          c2 = value
        else
          return 0
        j += 1
      ix = c0 * s0 + c1 * s1 + c2; @hi[ix] = bound if bound < @hi[ix]
    axis = 0
    while axis < arity
      stride = axis == 0 ? s0 : (axis == 1 ? s1 : 1)
      dim = axis == 0 ? n0 : (axis == 1 ? n1 : n2)
      ix = size - 1
      while ix >= 0
        return 0 if visit
        if (ix / stride) % dim + 1 < dim && @hi[ix + stride] < @hi[ix]
          @hi[ix] = @hi[ix + stride]
        ix -= 1
      axis += 1
    b0 = @values_used; b1 = b0 + n0; b2 = b1 + n1; @values_used = b2 + n2
    base = @values[vo + @hi[0]]; j = 0
    while j < n0
      @values[b0 + j] = @values[vo + @hi[j * s0]]; j += 1
    j = 0
    while j < n1
      @values[b1 + j] = @values[vo + @hi[j * s1]] - base; j += 1
    j = 0
    while j < n2
      @values[b2 + j] = @values[vo + @hi[j]] - base; j += 1
    ix = 0
    while ix < size
      return 0 if visit
      total = @values[b0 + ix / s0]
      total += @values[b1 + (ix / s1) % n1] if arity >= 2
      total += @values[b2 + ix % n2] if arity == 3
      return 0 if @values[vo + @hi[ix]] != total
      ix += 1; @meta[5] += 1
    @meta[6] += 1
    return 0 if hour(p0, b0, depth + 1) == 0
    return 0 if arity >= 2 && hour(p1, b1, depth + 1) == 0
    return 0 if arity == 3 && hour(p2, b2, depth + 1) == 0
    1

  -> find_path
    return false if @nleaf < 3
    j = 0
    while j < @nleaf
      d = @leaves[j]; @degree[d] = 0; @work_flag[d] = 0; j += 1
    ci = 0
    while ci < @nc
      return false if visit
      if @lens[ci] == 2
        o = @offs[ci]; a = @lits[o]; b = @lits[o + 1]
        if a > 0 && b > 0
          da = @owner[a]; db = @owner[b]
          if @leaf_mark[da] == @stamp && @leaf_mark[db] == @stamp && da != db && a == @start[da] + @length[da] - 1 && b == @start[db] + @length[db] - 1
            return false if add_edge(da, db) == 0 || add_edge(db, da) == 0
          return false if add_work(a, b) == 0 || add_work(b, a) == 0
      ci += 1
    ends = 0; at = -1; j = 0
    while j < @nleaf
      d = @leaves[j]; return false if @work_flag[d] <= 0 || @degree[d] < 1 || @degree[d] > 2
      if @degree[d] == 1
        ends += 1; at = d
      j += 1
    return false if ends != 2
    last = -1; j = 0
    while at >= 0 && j < @nleaf
      @path[j] = at; @work[j] = @work_flag[at]
      following = @edge1[at]; following = @degree[at] == 2 ? @edge2[at] : -1 if following == last
      last = at; at = following; j += 1
    j == @nleaf && at == -1

  -> add_edge(a, b) (i64 i64) i64
    n = @degree[a]
    return 1 if (n >= 1 && @edge1[a] == b) || (n == 2 && @edge2[a] == b)
    return 0 if n >= 2
    if n == 0
      @edge1[a] = b
    else
      @edge2[a] = b
    @degree[a] += 1
    1

  -> add_work(v, h) (i64 i64) i64
    hd = @owner[h]; wd = @owner[v]
    if @leaf_mark[hd] == @stamp && @leaf_mark[wd] != @stamp && h == @start[hd] && @length[wd] >= 2 && v == @start[wd] + @length[wd] - 1
      return 0 if @work_flag[hd] != 0 && @work_flag[hd] != v
      @work_flag[hd] = v
    1

  -> root(v) (i64) i64
    while @dsu[v] != v
      @dsu[v] = @dsu[@dsu[v]]; v = @dsu[v]
    v

  -> prepare_components(small) (i64) i64
    return 1 if @small == small
    @small = small; v = 1
    while v <= @nv
      n = @length[@owner[v]]; @primary[v] = n >= 2 && n <= small ? 1 : 0
      @dsu[v] = v; v += 1
    ci = 0
    while ci < @nc
      return 0 if visit
      first = 0; j = 0; o = @offs[ci]
      while j < @lens[ci]
        v = abs(@lits[o + j])
        if @primary[v] == 0
          if first == 0
            first = v
          else
            @dsu[root(v)] = root(first)
        j += 1
      ci += 1
    1

  # Select an original-clause subset without assuming a person/block number.
  # The partition is a discovery optimization only; omission weakens the proof.
  -> local_subset
    small = 0; j = 0
    while j < @nleaf
      d = @path[j]; small = @length[d] if @length[d] > small
      d = @owner[@work[j]]; small = @length[d] if @length[d] > small; j += 1
    return false if prepare_components(small) == 0
    v = 0
    while v <= @nv
      @selected[v] = 0; @bad[v] = 0; @first[v] = 0; v += 1
    j = 0
    while j < @nleaf
      d = @path[j]; v = @start[d]
      while v < @start[d] + @length[d]
        @selected[v] = 1; v += 1
      d = @owner[@work[j]]; v = @start[d]
      while v < @start[d] + @length[d]
        @selected[v] = 1; v += 1
      j += 1
    ci = 0
    while ci < @nc
      return false if visit
      first = 0; outside = false; j = 0; o = @offs[ci]
      while j < @lens[ci]
        v = abs(@lits[o + j])
        if @primary[v] == 0
          first = v
        elsif @selected[v] == 0
          outside = true
        j += 1
      @bad[root(first)] = 1 if first != 0 && outside
      ci += 1
    @local_count = 0; occurrences = 0; ci = 0; j = 0
    while j <= @hash_mask
      @slots[j] = 0; j += 1
    while ci < @nc
      return false if visit
      first = 0; outside = false; j = 0; o = @offs[ci]; n = @lens[ci]
      while j < n
        v = abs(@lits[o + j])
        if @primary[v] == 0
          first = v
        elsif @selected[v] == 0
          outside = true
        j += 1
      if !outside && (first == 0 || @bad[root(first)] == 0)
        return false if @local_count >= @local_cap
        id = @local_count; @local_count += 1; @local[id] = ci
        if n <= 4
          h = clause_hash(ci); @hash_next[id] = @slots[h]; @slots[h] = id + 1
        j = 0
        while j < n
          d = @owner[abs(@lits[o + j])]; duplicate = false; k = 0
          while k < j
            duplicate = true if @owner[abs(@lits[o + k])] == d; k += 1
          unless duplicate
            return false if occurrences >= @occ_cap
            @occ_ref[occurrences] = id; @occ_next[occurrences] = @first[d]
            occurrences += 1; @first[d] = occurrences
          j += 1
      ci += 1
    @meta[7] = @local_count; @meta[8] = occurrences
    true

  -> lit_hash(x) (i64) i64
    # Only these low bits enter the clause table. Truncate before returning
    # through the boxed instance-method ABI to avoid temporary BigInts.
    y = x + 1000001; ((y * 2654435761) ^ (y * y * 131)) & 1048575

  -> clause_hash(ci) (i64) i64
    h = @lens[ci] * 65537; j = 0; o = @offs[ci]
    while j < @lens[ci]
      h += lit_hash(@lits[o + j]); j += 1
    h & @hash_mask

  # Exact comparison after hashing: collisions cannot establish a fact.
  -> has(a, b = 0, c = 0, d = 0)
    n = 1; n += 1 if b != 0; n += 1 if c != 0; n += 1 if d != 0
    return false if (b != 0 && b == a) || (c != 0 && (c == a || c == b)) || (d != 0 && (d == a || d == b || d == c))
    h = n * 65537 + lit_hash(a)
    h += lit_hash(b) if b != 0; h += lit_hash(c) if c != 0; h += lit_hash(d) if d != 0
    ref = @slots[h & @hash_mask]; @meta[9] += 1
    while ref > 0
      return false if visit
      id = ref - 1; ci = @local[id]; ref = @hash_next[id]; @meta[10] += 1
      if @lens[ci] == n
        hits = 0; o = @offs[ci]; j = 0
        while j < n
          x = @lits[o + j]
          hits |= 1 if x == a; hits |= 2 if x == b; hits |= 4 if x == c; hits |= 8 if x == d
          j += 1
        return true if hits == (1 << n) - 1
    false

  # Minimal violating tuples certify a signed rank-sum upper bound. A chain
  # variable at index k means rank <= k, as checked by the original prefix.
  -> inequality(a, b, c, bound) (i64 i64 i64 i64) i64
    da = abs(a) - 1; db = abs(b) - 1; dc = abs(c) - 1
    return 0 if da == db || da == dc || db == dc
    la = @length[da]; lb = @length[db]; lc = @length[dc]
    return 0 if la > 1024 || lb > 1024 || lc > 1024
    amin = a > 0 ? 0 : 0 - la; amax = a > 0 ? la : 0
    bmin = b > 0 ? 0 : 0 - lb; bmax = b > 0 ? lb : 0
    cmin = c > 0 ? 0 : 0 - lc; cmax = c > 0 ? lc : 0
    x = amin
    while x <= amax
      y = bmin
      while y <= bmax
        return 0 if visit
        z = bound + 1 - x - y
        if z >= cmin && z <= cmax
          p = 0; q = 0; r = 0
          p = a > 0 ? @start[da] + x - 1 : 0 - @start[da] + x if x > amin
          t = b > 0 ? @start[db] + y - 1 : 0 - @start[db] + y if y > bmin
          t = 0 if y == bmin
          if p == 0
            p = t
          else
            q = t
          t = c > 0 ? @start[dc] + z - 1 : 0 - @start[dc] + z if z > cmin
          t = 0 if z == cmin
          if p == 0
            p = t
          elsif q == 0
            q = t
          else
            r = t
          return 0 if p == 0 || !has(p, q, r)
        y += 1
      x += 1
    1

  -> bool_leaf(d) (i64) i64
    n = 0; ref = @first[d]
    while ref > 0
      return 0 if visit
      ci = @local[@occ_ref[ref - 1]]; ref = @occ_next[ref - 1]; o = @offs[ci]; j = 0; ok = true
      while j < @lens[ci]
        q = @owner[abs(@lits[o + j])]; ok = false if q != d && @length[q] != 1; j += 1
      if ok
        j = 0
        while j < @lens[ci]
          v = abs(@lits[o + j])
          if @owner[v] != d
            k = 0
            while k < n && @bool_vars[k] != v
              k += 1
            if k == n
              return 0 if n == 12
              @bool_vars[n] = v; n += 1
          j += 1
    return 0 if n < 1
    size = 1 << n; i = 0
    while i < size
      @bool_lo[i] = 0; @bool_hi[i] = @length[d]; @bool_bad[i] = 0; i += 1
    @bool_stamp += 1; which = -1
    while which < n
      q = which < 0 ? d : @owner[@bool_vars[which]]; ref = @first[q]
      while ref > 0
        return 0 if visit
        id = @occ_ref[ref - 1]; ref = @occ_next[ref - 1]
        if @clause_seen[id] != @bool_stamp
          @clause_seen[id] = @bool_stamp; ci = @local[id]; o = @offs[ci]; j = 0
          tr = 0; fa = 0; out = 0; outputs = 0; ok = true
          while j < @lens[ci]
            x = @lits[o + j]; v = abs(x)
            if @owner[v] == d
              out = x; outputs += 1
            else
              k = 0
              while k < n && @bool_vars[k] != v
                k += 1
              if k == n
                ok = false
              elsif x > 0
                fa |= 1 << k
              else
                tr |= 1 << k
            j += 1
          # Ignoring a clause only relaxes this local upper-bound proof.
          if ok && outputs <= 1
            mask = 0
            while mask < size
              return 0 if visit
              if (mask & tr) == tr && (mask & fa) == 0
                if outputs == 0
                  @bool_bad[mask] = 1
                elsif out > 0
                  v = out - @start[d]; @bool_hi[mask] = v if v < @bool_hi[mask]
                else
                  v = 0 - out - @start[d] + 1; @bool_lo[mask] = v if v > @bool_lo[mask]
              mask += 1
      which += 1
    all = size - 1; value = @bool_hi[all]; constant = value
    return 0 if @bool_bad[all] != 0 || @bool_lo[all] > value
    i = 0
    while i < n
      mask = all ^ (1 << i); weight = value - @bool_hi[mask]
      return 0 if @bool_bad[mask] != 0 || @bool_lo[mask] > @bool_hi[mask] || weight < 0 || weight > 64
      @bool_weights[i] = weight; constant -= weight; i += 1
    mask = 0
    while mask < size
      if @bool_bad[mask] == 0 && @bool_lo[mask] <= @bool_hi[mask]
        total = constant; i = 0
        while i < n
          total += @bool_weights[i] if (mask & (1 << i)) != 0; i += 1
        return 0 if @bool_hi[mask] > total
      mask += 1; @meta[11] += 1
    i = 0
    while i < n
      @weights[@bool_vars[i]] += @bool_weights[i]; i += 1
    @constant += constant; @meta[12] += 1
    1

  -> preference(d, depth) (i64 i64) i64
    return 0 if depth > 32 || @pref_seen[d] == @stamp || poll
    @pref_seen[d] = @stamp
    if @arity[d] == 2
      a = @parents[3 * d]; b = @parents[3 * d + 1]; j = 0
      while j < 2049
        @bound_counts[j] = 0; j += 1
      ref = @upper[d]
      while ref > 0
        return 0 if visit
        ci = ref - 1; ref = @upper_next[ci]
        if @lens[ci] == 3
          o = @offs[ci]; j = 0; bound = 0
          while j < 3
            x = @lits[o + j]; q = @owner[abs(x)]; v = abs(x) - @start[q]
            bound += x > 0 ? v : 0 - v; j += 1
          @bound_counts[bound + 1024] += 1 if bound >= -1024 && bound <= 1024
      best = -1; j = 0
      while j < 2049
        best = j if @bound_counts[j] > 0 && (best < 0 || @bound_counts[j] > @bound_counts[best]); j += 1
      if best >= 0 && inequality(0 - a - 1, 0 - b - 1, d + 1, best - 1024) == 1
        @constant += best - 1024
        return 0 if preference(a, depth + 1) == 0
        return preference(b, depth + 1)
    bool_leaf(d)

  -> eq_root(v) (i64) i64
    while @eq[v] != v
      @eq[v] = @eq[@eq[v]]; v = @eq[v]
    v

  -> literal_node(x) (i64) i64
    x > 0 ? 2 * x : 2 * (0 - x) + 1

  -> verify_windows
    i = 0
    while i < 2 * (@nv + 1)
      @eq[i] = i; @canon[i] = 0; i += 1
    i = 0
    while i < @local_count
      return false if visit
      ci = @local[i]
      if @lens[ci] == 2
        o = @offs[ci]; a = @lits[o]; b = @lits[o + 1]
        if has(0 - a, 0 - b)
          na = literal_node(a); nb = literal_node(b)
          @eq[eq_root(na ^ 1)] = eq_root(nb); @eq[eq_root(na)] = eq_root(nb ^ 1)
      i += 1
    i = 0
    while i < @nleaf
      p = eq_root(2 * @work[i]); n = eq_root(2 * @work[i] + 1)
      return false if p == n || @canon[p] != 0 || @canon[n] != 0
      @canon[p] = i + 1; @canon[n] = 0 - i - 1; @windows[i] = 0; i += 1
    i = 0
    while i < @local_count
      return false if visit
      ci = @local[i]
      if @lens[ci] == 3
        o = @offs[ci]; a = @canon[eq_root(literal_node(@lits[o]))]; b = @canon[eq_root(literal_node(@lits[o + 1]))]; c = @canon[eq_root(literal_node(@lits[o + 2]))]
        if a < 0 && b < 0 && c < 0
          a = 0 - a; b = 0 - b; c = 0 - c
          if a > b
            t = a; a = b; b = t
          if b > c
            t = b; b = c; c = t
          if a > b
            t = a; a = b; b = t
          @windows[a - 1] = 1 if b == a + 1 && c == b + 1
      i += 1
    i = 0
    while i + 2 < @nleaf
      return false if @windows[i] == 0
      i += 1
    true

  -> count_bound(required, budget) (i64 i64) i64
    v = 0
    while v <= @nv
      @used_flag[v] = 0; v += 1
    d = @path[0]; vo = @value_offset[d]; maximum = @values[vo + @length[d]]; second = @values[vo + @length[d] - 1]
    return 0 if maximum <= second || second < 0 || budget < 0 || budget > 256
    ew = -1; gw = -1; i = 0
    while i < @nleaf
      d = @path[i]; vo = @value_offset[d]
      return 0 if @values[vo] != 0 || @values[vo + @length[d]] != maximum || @values[vo + @length[d] - 1] != second
      return 0 unless has(@work[i], @start[d])
      if i + 1 < @nleaf
        e = @path[i + 1]; return 0 unless has(@start[d] + @length[d] - 1, @start[e] + @length[e] - 1)
        found = 0; v = 1
        while v <= @nv
          return 0 if (v & 1023) == 0 && poll
          if @weights[v] > 0 && has(0 - v, 0 - @work[i], 0 - @work[i + 1])
            return 0 if found != 0
            found = v
          v += 1
        return 0 if found == 0 || @used_flag[found] != 0
        @used_flag[found] = 1; ew = @weights[found] if ew == -1
        return 0 if @weights[found] != ew
      if i + 2 < @nleaf
        found = 0; v = 1
        while v <= @nv
          return 0 if (v & 1023) == 0 && poll
          if @weights[v] > 0 && has(0 - v, 0 - @work[i], @work[i + 1], 0 - @work[i + 2])
            return 0 if found != 0
            found = v
          v += 1
        return 0 if found == 0 || @used_flag[found] != 0
        @used_flag[found] = 1; gw = @weights[found] if gw == -1
        return 0 if @weights[found] != gw
      i += 1
    return 0 if ew <= 0 || gw <= 0 || !verify_windows
    # No three work days: W-P runs, with at least two off days between runs
    # except I single-off gaps. Thus 3W <= N+2+2P+I. Each pair loses M-L
    # hours from the individual maximum; its distinct penalty costs ew.
    upper = -1; p = 0
    while p <= @nleaf / 2 && ew * p <= budget
      i = 0
      while ew * p + gw * i <= budget
        w = (@nleaf + 2 + 2 * p + i) / 3; w = @nleaf if w > @nleaf
        h = maximum * w - (maximum - second) * p; upper = h if h > upper; i += 1
      p += 1
    @meta[13] = @nleaf; @meta[14] = required; @meta[15] = budget; @meta[16] = upper; @meta[17] = ew; @meta[18] = gw
    upper < required ? -1 : 0

  -> solve
    return 0 unless decode
    attempts = 0
    while attempts < 64 && !poll
      best = -1; r = 0
      while r < @nr
        if @root_done[r] == 0 && @roots[5 * r + 4] >= 8 && (best < 0 || @roots[5 * r + 3] > @roots[5 * best + 3])
          best = r
        r += 1
      break if best < 0
      @root_done[best] = 1; attempts += 1; @meta[19] = attempts; @stamp += 1
      @values_used = 0; @nleaf = 0; j = 0; ok = true
      while j < 3 && ok
        d = @roots[5 * best + j]; n = @length[d] + 1; vo = @values_used
        if n > 1025 || vo + n > @value_cap
          ok = false
        else
          @values_used += n; i = 0
          while i < n
            @values[vo + i] = i; i += 1
          ok = hour(d, vo, 0) == 1
        j += 1
      if ok && find_path && local_subset
        a = @roots[5 * best]; b = @roots[5 * best + 1]; c = @roots[5 * best + 2]; required = @roots[5 * best + 3]
        if inequality(0 - a - 1, 0 - b - 1, 0 - c - 1, 0 - required) == 1
          r = 0
          while r < @nr && !poll
            o = 5 * r; a = @roots[o]; b = @roots[o + 1]; c = @roots[o + 2]; bound = @roots[o + 3]
            if bound <= 128 && @roots[o + 4] >= 8 && @first[a] != 0 && @first[b] != 0 && @first[c] != 0 && inequality(0 - a - 1, 0 - b - 1, 0 - c - 1, 0 - bound) == 1
              @meta[20] += 1; @constant = 0; v = 0
              while v <= @nv
                @weights[v] = 0; @pref_seen[v] = 0; v += 1
              if preference(a, 0) == 1 && preference(b, 0) == 1 && preference(c, 0) == 1
                budget = @constant - bound; v = 1
                while v <= @nv
                  budget += @weights[v]; v += 1
                result = count_bound(required, budget)
                return -1 if result == -1 && !poll
            r += 1
    0
