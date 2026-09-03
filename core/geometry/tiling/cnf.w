# CNF encodings of corona questions, for an external SAT solver.
#
# Two formulas, both over placement variables (one per distinct copy of the
# shape), emitted as clause lists and DIMACS text so that wassat can solve
# them and wrat can check an UNSAT certificate:
#
#   corona(shape, patch)   "the patch has a corona": every halo cell is
#                          covered by a chosen placement, no two chosen
#                          placements share a cell. Holes are allowed, so
#                          UNSAT proves no corona at all; a model decodes to
#                          a corona that the witness verifier can check.
#
#   weak(shape, m)         the multilevel formula of the Heesch challenge
#                          encoder (revision 2, clause families 1, 2, 4, 5, 6
#                          with pairwise at-most-one): a weak m-configuration
#                          exists. Every genuine hole-permitted m-corona patch
#                          is a weak configuration, so UNSAT proves Hh <= m-1
#                          and hence that the shape does not tile the plane.
#                          The converse fails — a model is a candidate only.
#
# Variables are numbered level-major in placement order; `decode` turns a
# model back into [level, transform] placements with the central copy first.

+ CoronaCnf
  -> new(@shape, @levels, @clauses, @kind) ro

  # ---- construction ------------------------------------------------------

  -> .corona(shape, patch_cells)
    placements = Corona.placements(shape, patch_cells)
    halo = shape.grid.halo(patch_cells)
    cover = {}
    p = 0
    while p < placements.size
      cells = placements[p][3]
      j = 0
      while j < cells.size
        k = TilingGrid.cell_key(cells[j])
        cover[k] = [] if !cover.key?(k)
        cover[k].push(p + 1)
        j += 1
      p += 1
    clauses = []
    h = 0
    while h < halo.size
      clauses.push(cover.fetch(TilingGrid.cell_key(halo[h]), []).dup)
      h += 1
    CoronaCnf.add_pairwise(clauses, cover)
    CoronaCnf.new(shape, [placements], clauses, :corona)

  -> .add_pairwise(clauses, cover)
    keys = cover.keys
    i = 0
    while i < keys.size
      vs = cover[keys[i]]
      a = 0
      while a < vs.size
        b = a + 1
        while b < vs.size
          clauses.push([0 - vs[a], 0 - vs[b]])
          b += 1
        a += 1
      i += 1
    nil

  # Placement universes per level: level 1 touches the shape; level l >= 2
  # touches some level-(l-1) placement, avoids the shape and does not touch
  # it. Each level is a list of [orientation, tx, ty, cells].
  -> .universes(shape, m)
    grid = shape.grid
    tile = shape.cells
    tile_index = TilingGrid.index(tile)
    tile_halo = TilingGrid.index(grid.halo(tile))
    levels = [Corona.placements(shape, tile)]
    l = 2
    while l <= m
      prev = levels[l - 2]
      status = {}
      found = []
      found_index = {}
      q = 0
      while q < prev.size
        qcells = prev[q][3]
        qindex = TilingGrid.index(qcells)
        targets = grid.halo(qcells)
        si = 0
        while si < grid.orientation_count
          img = shape.image(si)
          t = 0
          while t < targets.size
            ci = 0
            while ci < img.size
              tx = targets[t][0] - img[ci][0]
              ty = targets[t][1] - img[ci][1]
              ci += 1
              key = "[si],[tx],[ty]"
              cells = status.fetch(key, nil)
              if cells == nil
                if !grid.translation_legal?(tx, ty)
                  status[key] = false
                  next
                cells = shape.placed(si, tx, ty)
                bad = false
                j = 0
                while j < cells.size
                  ck = TilingGrid.cell_key(cells[j])
                  bad = true if tile_index.key?(ck) || tile_halo.key?(ck)
                  j += 1
                cells = false if bad
                status[key] = cells
              next if cells == false
              hit = false
              j = 0
              while j < cells.size
                hit = true if qindex.key?(TilingGrid.cell_key(cells[j]))
                j += 1
              next if hit
              ck = TilingGrid.key(cells)
              next if found_index.key?(ck)
              found_index[ck] = true
              found.push([si, tx, ty, cells])
            t += 1
          si += 1
        q += 1
      levels.push(found)
      l += 1
    levels

  -> .weak(shape, m)
    raise "m must be at least 1" if m < 1
    grid = shape.grid
    tile = shape.cells
    tile_index = TilingGrid.index(tile)
    levels = CoronaCnf.universes(shape, m)
    offsets = []
    off = 0
    l = 0
    while l < levels.size
      offsets.push(off)
      off += levels[l].size
      l += 1
    total = off
    # cell -> ascending variable list, all levels
    cover = {}
    level_of = []
    level_of.push(0)
    l = 0
    while l < levels.size
      i = 0
      while i < levels[l].size
        v = offsets[l] + i + 1
        level_of.push(l + 1)
        cells = levels[l][i][3]
        j = 0
        while j < cells.size
          k = TilingGrid.cell_key(cells[j])
          cover[k] = [] if !cover.key?(k)
          cover[k].push(v)
          j += 1
        i += 1
      l += 1
    clauses = []
    # family 1: the shape's halo is covered by level-1 placements
    halo = grid.halo(tile)
    h = 0
    while h < halo.size
      vs = cover.fetch(TilingGrid.cell_key(halo[h]), [])
      clause = []
      j = 0
      while j < vs.size
        clause.push(vs[j]) if level_of[vs[j]] == 1
        j += 1
      clauses.push(clause)
      h += 1
    # family 2: at most one placement per cell
    CoronaCnf.add_pairwise(clauses, cover)
    # touching relation between consecutive levels, and against lower levels
    touch = CoronaCnf.touch_tables(grid, levels, offsets, cover, level_of)
    # family 4: a level-l placement touches some level-(l-1) placement
    l = 1
    while l < levels.size
      i = 0
      while i < levels[l].size
        v = offsets[l] + i + 1
        clause = [0 - v]
        below = touch[v].fetch(l, [])
        j = 0
        while j < below.size
          clause.push(below[j])
          j += 1
        clauses.push(clause)
        i += 1
      l += 1
    # family 5: a level-l placement touches nothing at levels 1..l-2
    l = 2
    while l < levels.size
      i = 0
      while i < levels[l].size
        v = offsets[l] + i + 1
        lower = 1
        while lower <= l - 1
          ws = touch[v].fetch(lower, [])
          j = 0
          while j < ws.size
            clauses.push([0 - v, 0 - ws[j]])
            j += 1
          lower += 1
        i += 1
      l += 1
    # family 6: halo cells of a placement at level l <= m-1 are covered by
    # levels l-1, l or l+1
    l = 0
    while l < levels.size - 1
      i = 0
      while i < levels[l].size
        v = offsets[l] + i + 1
        qhalo = grid.halo(levels[l][i][3])
        h = 0
        while h < qhalo.size
          hk = TilingGrid.cell_key(qhalo[h])
          h += 1
          next if tile_index.key?(hk)
          clause = [0 - v]
          ws = cover.fetch(hk, [])
          j = 0
          while j < ws.size
            lw = level_of[ws[j]]
            clause.push(ws[j]) if lw >= l && lw <= l + 2
            j += 1
          clauses.push(clause)
        i += 1
      l += 1
    CoronaCnf.new(shape, levels, clauses, :weak)

  # touch[v] = { level => [variables at that level touching placement v] }
  # for every level 1..(level of v) - 1, over disjoint pairs.
  -> .touch_tables(grid, levels, offsets, cover, level_of)
    touch = {}
    l = 0
    while l < levels.size
      i = 0
      while i < levels[l].size
        v = offsets[l] + i + 1
        cells = levels[l][i][3]
        own = TilingGrid.index(cells)
        table = {}
        seen = {}
        j = 0
        while j < cells.size
          nbs = grid.contact_neighbours(cells[j])
          n = 0
          while n < nbs.size
            ws = cover.fetch(TilingGrid.cell_key(nbs[n]), [])
            w = 0
            while w < ws.size
              cand = ws[w]
              w += 1
              lw = level_of[cand]
              next if lw >= l + 1 || seen.key?(cand)
              seen[cand] = true
              # disjointness: the candidate must not cover any own cell
              ccells = levels[lw - 1][cand - offsets[lw - 1] - 1][3]
              overlap = false
              c = 0
              while c < ccells.size
                overlap = true if own.key?(TilingGrid.cell_key(ccells[c]))
                c += 1
              next if overlap
              table[lw] = [] if !table.key?(lw)
              table[lw].push(cand)
            n += 1
          j += 1
        touch[v] = table
        i += 1
      l += 1
    touch

  # ---- access -------------------------------------------------------------

  -> variable_count
    n = 0
    l = 0
    while l < @levels.size
      n += @levels[l].size
      l += 1
    n

  -> clause_count
    @clauses.size

  -> placement_of(v)
    l = 0
    while l < @levels.size
      if v <= @levels[l].size
        return [l + 1, @levels[l][v - 1]]
      v -= @levels[l].size
      l += 1
    nil

  -> dimacs
    lines = ["p cnf [variable_count] [@clauses.size]"]
    i = 0
    while i < @clauses.size
      lines.push(@clauses[i].join(" ") + " 0")
      i += 1
    lines.join("\n") + "\n"

  # A model (list of signed literals, or a hash variable -> bool) as
  # witness placements [level, transform], central copy first.
  -> decode(model)
    truth = CoronaCnf.truth(model)
    grid = @shape.grid
    out = [[0, grid.orientation(0)]]
    v = 1
    n = variable_count
    while v <= n
      if truth.fetch(v, false)
        lp = placement_of(v)
        out.push([lp[0], Corona.transform_of(grid, lp[1][0], lp[1][1], lp[1][2])])
      v += 1
    out

  -> .truth(model)
    return model if model.class_name == "Hash"
    truth = {}
    i = 0
    while i < model.size
      lit = model[i]
      truth[lit.abs] = lit > 0
      i += 1
    truth

  -> satisfied?(model)
    truth = CoronaCnf.truth(model)
    i = 0
    while i < @clauses.size
      clause = @clauses[i]
      ok = false
      j = 0
      while j < clause.size
        lit = clause[j]
        ok = true if truth.fetch(lit.abs, false) == (lit > 0)
        j += 1
      return false if !ok
      i += 1
    true

  # The assignment corresponding to witness placements [level, transform]:
  # true for the variable of each placement present, false elsewhere. Raises
  # if a placement is outside the universe of its level.
  -> assignment_of(placements)
    truth = {}
    index = {}
    l = 0
    while l < @levels.size
      i = 0
      while i < @levels[l].size
        index["[l + 1]|" + TilingGrid.key(@levels[l][i][3])] = CoronaCnf.var_of(@levels, l, i)
        i += 1
      l += 1
    i = 0
    while i < placements.size
      level = placements[i][0]
      i += 1
      next if level == 0
      cells = @shape.transformed(placements[i - 1][1])
      key = "[level]|" + TilingGrid.key(cells)
      raise "placement at level [level] is not in the universe" if !index.key?(key)
      truth[index[key]] = true
    truth

  -> .var_of(levels, l, i)
    v = i + 1
    k = 0
    while k < l
      v += levels[k].size
      k += 1
    v
