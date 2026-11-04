# Decode a conservative order-domain layout, then prove its semantic rules.
# Identifier arithmetic proposes the map; original clauses certify every use.
+ WassatNakedSudoku
  -> decode
    return false if @nv < 1 || @nv > 1000000 || @nc < 1 || @nc > 3000000 || @nl < 1 || @nl > 12000000
    return false if @offs.size < @nc || @lens.size < @nc || @lits.size < @nl || poll
    starts = i32[8192]; lengths = i32[8192]; domains = 0; end_var = 0; ci = 0
    while ci < @nc && @lens[ci] == 2
      return false if visit
      o = @offs[ci]; return false if o < 0 || o > @nl - 2
      a = @lits[o]; b = @lits[o + 1]
      if a > b
        t = a; a = b; b = t
      break unless a < 0 && b == 1 - a
      v = 0 - a; return false if b > @nv
      if domains > 0 && v == end_var
        lengths[domains - 1] += 1
      else
        return false if v != end_var + 1 || domains >= 8192
        starts[domains] = v; lengths[domains] = 2; domains += 1
      end_var = b; ci += 1
    return false if domains < 2
    @n = lengths[0] + 1
    return false unless @n == 4 || @n == 9
    @rank = @n == 4 ? 2 : 3; @cells = @n * @n
    d = 0
    while d < domains && lengths[d] == @n - 1
      d += 1
    @nclues = d
    return false if d < 1 || d >= @cells || (domains - d) % @cells != 0
    @steps = (domains - d) / @cells
    return false if @steps < 1 || @steps > 64
    while d < domains
      return false if lengths[d] != @n
      d += 1
    @x0end = @nclues * (@n - 1); @xend = end_var
    return false if @xend != @x0end + @steps * @cells * @n
    @ystart = @xend + 1; @ny = (@steps + 1) * @cells * @n
    @yend = @xend + @ny
    return false if @yend >= @nv
    @domain = i32[@xend + 1]; @clues = i32[@cells]; @clue_seen = i8[@nclues]
    @roles = i8[@nv + 1]; @rules = i32[4 * @ny]
    @ns = i32[@steps * @cells * @n]; @wide = i32[@steps]; @wide_seen = i8[@steps]
    @meta[30] = 65536 + 4 * (@xend + 1 + @cells + 4 * @ny + @steps * @cells * @n + @steps) + @nclues + @nv + 1 + @steps
    @meta[10] = @rank; @meta[11] = @steps; @meta[12] = @nclues
    d = 0
    while d < domains
      v = starts[d]; last = v + lengths[d]
      while v < last
        @domain[v] = d + 1; v += 1
      d += 1
    ci = 0; wide_count = 0; expected_offset = 0
    while ci < @nc
      return false if visit
      o = @offs[ci]; len = @lens[ci]
      return false if len < 1 || len > 1024 || o < 0 || o > @nl || len > @nl - o
      return false if o != expected_offset
      expected_offset += len
      j = 0
      while j < len
        v = abs(@lits[o + j]); return false if v < 1 || v > @nv
        j += 1
      # Clue proposals use the first-value implication at stage one. All
      # values, both directions and all later stages are checked afterward.
      if len == 3
        neg = 0; small = 0; big = 0; j = 0
        while j < 3
          v = @lits[o + j]
          if v < 0
            neg = v
          elsif v <= @x0end
            small = v
          else
            big = v
          j += 1
        if neg != 0 && small > 0 && big > @x0end && big < @x0end + 1 + @cells * @n && neg == 0 - big - 1 && (big - @x0end - 1) % @n == 0 && (small - 1) % (@n - 1) == 0
          cell = (big - @x0end - 1) / @n
          return false if @clues[cell] != 0 && @clues[cell] != small
          @clues[cell] = small
      # Candidate iff not(any of four elimination rules), with persistence.
      if len == 5 || len == 6
        yy = 0; neg = 0; positives = 0; zs = 0; j = 0
        while j < len
          v = @lits[o + j]
          if v < 0
            neg += 1
          else
            positives += 1
            yy = v if v >= @ystart && v <= @yend
            zs += 1 if v > @yend
          j += 1
        if yy > 0 && positives == 5 && zs == 4 && neg == len - 5
          return false if @rules[4 * (yy - @ystart)] != 0
          # Relative rule order is a proposal and is certified below.
          j = 0; k = 0
          while j < len
            z = @lits[o + j]
            if z > @yend
              return false if @roles[z] != 0
              @roles[z] = 1; @rules[4 * (yy - @ystart) + k] = z; k += 1
              @zmax = z if z > @zmax
            j += 1
          @int_end = ci if ci < @int_end
      # The reverse naked-single implication is one positive clause with
      # every OTHER candidate of one cell and one strategy witness.
      if len == @n
        yy = -1; z = 0; found = 0; mask = 0; valid = true; j = 0
        while j < len && valid
          v = @lits[o + j]
          if v >= @ystart && v <= @yend
            slot = v - @ystart; group = (slot / (@cells * @n)) * @cells + slot % @cells
            yy = group if yy < 0
            digit = (slot % (@cells * @n)) / @cells
            valid = false if group != yy || (mask & (1 << digit)) != 0
            mask = mask | (1 << digit); found += 1
          elsif v > @yend && z == 0
            z = v
          else
            valid = false
          j += 1
        if valid && found == @n - 1 && z > 0 && yy / @cells < @steps
          digit = 0
          while digit < @n && (mask & (1 << digit)) != 0
            digit += 1
          index = yy / @cells * @cells * @n + yy % @cells * @n + digit
          return false if @ns[index] != 0 || @roles[z] != 0
          @ns[index] = z; @roles[z] = 2; @zmax = z if z > @zmax
      if len == (@cells - @nclues) * @n + 1
        return false if wide_count >= @steps
        @wide[wide_count] = ci; wide_count += 1
      ci += 1
    return false if expected_offset != @nl || wide_count != @steps || @zmax <= @yend
    count = 0; cell = 0
    while cell < @cells
      if @clues[cell] > 0
        index = (@clues[cell] - 1) / (@n - 1)
        return false if @clue_seen[index] != 0
        @clue_seen[index] = 1; count += 1
      cell += 1
    return false if count != @nclues
    stage = 0
    while stage <= @steps
      cell = 0
      while cell < @cells
        digit = 0
        while digit < @n
          r = @rules[4 * (stage * @cells * @n + digit * @cells + cell)]
          expected = stage == 0 || @clues[cell] == 0
          return false if (r != 0) != expected
          if stage > 0
            z = @ns[(stage - 1) * @cells * @n + cell * @n + digit]
            return false if (z != 0) != (@clues[cell] == 0)
          digit += 1
        cell += 1
      stage += 1
    build_index

  -> y(stage, cell, digit) (i64 i64 i64) i64
    @ystart + stage * @cells * @n + digit * @cells + cell

  # Add x=value (a conjunction of up to two order thresholds), or its
  # negation (a disjunction), to the current OR-of-conjunctions query.
  -> value_term(stage, cell, digit, invert = false) (i64 i64 i64 bool)
    a = 0; b = 0; size = 0
    if stage == 0 && @clues[cell] == 0
      size = digit == 0 ? 0 : -1
    elsif stage == 0 && digit == 0
      size = -1
    else
      low = stage == 0 ? 1 : 0
      start = stage == 0 ? @clues[cell] : @x0end + 1 + @n * ((stage - 1) * @cells + cell)
      if digit > low
        a = 0 - start - digit + low + 1; size = 1
      if digit < @n
        v = start + digit - low
        if size == 0
          a = v
        else
          b = v
        size += 1
    if invert
      @taut = true if size == -1
      term(0 - a) if size > 0
      term(0 - b) if size > 1
    else
      @taut = true if size == 0
      term(a, b) if size > 0
    0

  -> check_placements
    stage = 1
    while stage <= @steps
      @meta[13] = stage; cell = 0
      while cell < @cells
        digit = 0
        while digit < @n
          begin_query; value_term(stage, cell, digit + 1, true)
          value_term(stage - 1, cell, digit + 1)
          z = @ns[(stage - 1) * @cells * @n + cell * @n + digit]
          term(z) if z > 0
          return false unless require_query
          begin_query; value_term(stage - 1, cell, digit + 1, true)
          value_term(stage, cell, digit + 1)
          return false unless require_query
          if z > 0
            begin_query; term(0 - z); value_term(stage, cell, digit + 1)
            return false unless require_query
            begin_query; term(z); other = 0
            while other < @n
              term(y(stage - 1, cell, other)) if other != digit
              other += 1
            return false unless require_query
            other = 0
            while other < @n
              if other != digit
                begin_query; term(0 - z); term(0 - y(stage - 1, cell, other))
                return false unless require_query
              other += 1
          digit += 1
        cell += 1
      stage += 1
    true

  -> rule_member(cell, other, kind) (i64 i64 i64) bool
    return other == cell if kind == 0
    return false if other == cell
    row = cell % @n; col = cell / @n; r = other % @n; c = other / @n
    return row == r if kind == 1
    return col == c if kind == 2
    row / @rank == r / @rank && col / @rank == c / @rank

  -> check_rule(stage, cell, digit, kind, z) (i64 i64 i64 i64 i64) bool
    begin_query; term(0 - z)
    other = 0
    while other < @cells
      if rule_member(cell, other, kind)
        if kind == 0
          n = 0
          while n < @n
            value_term(stage, other, n + 1) if n != digit
            n += 1
        else
          value_term(stage, other, digit + 1)
      other += 1
    return false unless require_query
    other = 0
    while other < @cells
      if rule_member(cell, other, kind)
        if kind == 0
          n = 0
          while n < @n
            if n != digit
              begin_query; term(z); value_term(stage, other, n + 1, true)
              return false unless require_query
            n += 1
        else
          begin_query; term(z); value_term(stage, other, digit + 1, true)
          return false unless require_query
      other += 1
    true

  -> check_candidates
    stage = 0
    while stage <= @steps
      @meta[14] = stage; cell = 0
      while cell < @cells
        begin_query; digit = 0
        while digit < @n
          term(y(stage, cell, digit)); digit += 1
        return false unless require_query
        digit = 0
        while digit < @n
          yy = y(stage, cell, digit)
          if stage > 0 && @clues[cell] != 0
            yp = y(stage - 1, cell, digit)
            begin_query; term(0 - yy); term(yp)
            return false unless require_query
            begin_query; term(0 - yp); term(yy)
            return false unless require_query
          else
            begin_query; term(yy); kind = 0
            while kind < 4
              term(@rules[4 * (yy - @ystart) + kind]); kind += 1
            term(0 - y(stage - 1, cell, digit)) if stage > 0
            return false unless require_query
            kind = 0
            while kind < 4
              z = @rules[4 * (yy - @ystart) + kind]
              begin_query; term(0 - yy); term(0 - z)
              return false unless require_query
              return false unless check_rule(stage, cell, digit, kind, z)
              kind += 1
            if stage > 0
              begin_query; term(0 - yy); term(y(stage - 1, cell, digit))
              return false unless require_query
          digit += 1
        cell += 1
      stage += 1
    true

  -> check_progress
    seen = i8[@cells * @n]; w = 0
    @meta[30] += @cells * @n
    while w < @steps
      return false if poll
      ci = @wide[w]; o = @offs[ci]; len = @lens[ci]; g = 0 - @lits[o + len - 1]
      return false if g <= @zmax || ci == 0 || @lens[ci - 1] != 2
      pair = @offs[ci - 1]
      return false if @lits[pair] != g
      h = @lits[pair + 1]; return false if h <= @zmax
      i = 0
      while i < @cells * @n
        seen[i] = 0; i += 1
      stage = -1; i = 0
      while i < len - 1
        diff = @lits[o + i]; base = ci + 1 + 5 * i
        return false if diff <= @zmax || base + 4 >= @nc
        j = 0
        while j < 5
          return false if @lens[base + j] != 4
          j += 1
        p = @offs[base]; a = @lits[p]; b = @lits[p + 1]
        return false if a <= @zmax || b <= @zmax
        old = @lits[@offs[base + 1]]; cur = 0 - @lits[@offs[base + 2]]
        return false if old < @ystart || cur > @yend || cur != old + @cells * @n
        k = (old - @ystart) / (@cells * @n) + 1
        stage = k if stage < 0
        return false if k != stage || k > @steps
        offset = (old - @ystart) % (@cells * @n)
        return false if seen[offset] != 0 || @clues[offset % @cells] != 0
        seen[offset] = 1
        @query[0] = a; @query[1] = b; @query[2] = 0 - diff; @query[3] = 0 - g
        return false unless has_clause(4)
        @query[0] = old; @query[1] = 0 - a
        return false unless has_clause(4)
        @query[0] = 0 - cur
        return false unless has_clause(4)
        @query[0] = 0 - old; @query[1] = 0 - b
        return false unless has_clause(4)
        @query[0] = cur
        return false unless has_clause(4)
        i += 1
      return false if stage < 1 || @wide_seen[stage - 1] != 0
      @wide_seen[stage - 1] = 1; cell = 0
      while cell < @cells
        if @clues[cell] == 0
          zero = @x0end + 1 + @n * ((stage - 1) * @cells + cell)
          @query[0] = 0 - h; @query[1] = 0 - zero
          return false unless has_clause(2)
        cell += 1
      @meta[15] += 1; w += 1
    true

  -> check_body
    @meta[16] = 1
    return false unless decode
    @meta[16] = 2
    return false unless check_placements
    @meta[16] = 3
    return false unless check_candidates
    @meta[16] = 4
    return false unless check_progress
    @meta[16] = 5
    @meta[17] = @kernel_state[0]
    !poll

  -> check
    result = check_body
    @meta[17] = @kernel_state == nil ? @work : @kernel_state[0]
    result
