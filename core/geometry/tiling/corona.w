# Coronas and Heesch numbers.
#
# A corona of a patch P is a set of copies of the shape, pairwise disjoint and
# disjoint from P, that together cover every contact neighbour of P — the
# halo. The k-th corona of a shape S is a corona of the patch P_{k-1} formed by
# S and its first k-1 coronas. The Heesch number Hc(S) is the largest k for
# which coronas 1..k exist with every intermediate patch simply connected;
# Hh(S) additionally lets the outermost corona enclose holes, so
# Hh ∈ {Hc, Hc + 1}. A shape that tiles the plane has coronas at every depth
# and no Heesch number.
#
# Everything here is exact cover: the halo cells are the primary columns, any
# other cell a placement occupies is a secondary column (so placements cannot
# overlap there either), and each legal placement is a row. Every legal
# placement is enumerated by the completeness argument of the Heesch
# challenge verifier: a copy touching P without overlapping it puts some cell
# on the halo, so trying every orientation, every shape cell and every halo
# cell as that landing visits each placement at least once.
#
# Witnesses use heesch-sat's text format and are re-verified from scratch:
# corona levels are recomputed by breadth-first search from the central copy
# and never trusted from the file.

+ Corona
  # Every copy of `shape` disjoint from `patch_cells` and touching it, as
  # [orientation, tx, ty, cells], one per distinct cell set.
  -> .placements(shape, patch_cells)
    grid = shape.grid
    present = TilingGrid.index(patch_cells)
    halo = grid.halo(patch_cells)
    tried = {}
    seen = {}
    out = []
    si = 0
    while si < grid.orientation_count
      img = shape.image(si)
      hi = 0
      while hi < halo.size
        h = halo[hi]
        hi += 1
        ci = 0
        while ci < img.size
          tx = h[0] - img[ci][0]
          ty = h[1] - img[ci][1]
          ci += 1
          tk = "[si],[tx],[ty]"
          next if tried.key?(tk)
          tried[tk] = true
          next if !grid.translation_legal?(tx, ty)
          cells = []
          overlap = false
          j = 0
          while j < img.size
            c = [img[j][0] + tx, img[j][1] + ty]
            overlap = true if present.key?(TilingGrid.cell_key(c))
            cells.push(c)
            j += 1
          next if overlap
          ck = TilingGrid.key(cells)
          next if seen.key?(ck)
          seen[ck] = true
          out.push([si, tx, ty, cells])
      si += 1
    out

  # Build the exact-cover instance of the patch's halo: [cover, placements].
  -> .instance(shape, patch_cells)
    grid = shape.grid
    halo = grid.halo(patch_cells)
    placements = Corona.placements(shape, patch_cells)
    column = {}
    i = 0
    while i < halo.size
      column[TilingGrid.cell_key(halo[i])] = i + 1
      i += 1
    extra = halo.size
    rows = []
    p = 0
    while p < placements.size
      cells = placements[p][3]
      cols = []
      j = 0
      while j < cells.size
        k = TilingGrid.cell_key(cells[j])
        if !column.key?(k)
          extra += 1
          column[k] = extra
        cols.push(column[k])
        j += 1
      rows.push(cols)
      p += 1
    cover = ExactCover.new(extra, halo.size)
    p = 0
    while p < rows.size
      cover.add_row(rows[p])
      p += 1
    [cover, placements, halo]

  # Call `callback` with each corona of the patch (a list of placements) as
  # the exact-cover search finds it; the callback returns true to stop.
  # Holes are not checked here; see `hole_free?`.
  -> .each_cover(shape, patch_cells, callback)
    inst = Corona.instance(shape, patch_cells)
    return false if inst[2].size == 0
    placements = inst[1]
    visit = ->(rows)
      chosen = []
      j = 0
      while j < rows.size
        chosen.push(placements[rows[j]])
        j += 1
      callback.call(chosen)
    inst[0].each_solution(visit)

  # Up to `limit` coronas of the patch, each a list of placements.
  -> .covers(shape, patch_cells, limit)
    out = []
    visit = ->(cover)
      out.push(cover)
      out.size >= limit
    Corona.each_cover(shape, patch_cells, visit)
    out

  # Stream the coronas whose union with the patch is simply connected. This
  # is a direct search over halo cells (fewest candidates first) rather than
  # dancing links, because holes can be pruned as they form: once the partial
  # union encloses an empty cell that no still-compatible placement can fill,
  # the branch is dead. It is complete — every hole-free corona is reported —
  # and returns true if the callback stopped it.
  -> .each_hole_free_cover(shape, patch_cells, callback)
    grid = shape.grid
    halo = grid.halo(patch_cells)
    return false if halo.size == 0
    placements = Corona.placements(shape, patch_cells)
    by_cell = {}
    p = 0
    while p < placements.size
      cells = placements[p][3]
      j = 0
      while j < cells.size
        k = TilingGrid.cell_key(cells[j])
        by_cell[k] = [] if !by_cell.key?(k)
        by_cell[k].push(p)
        j += 1
      p += 1
    state = HoleFreeCoverSearch.new(grid, patch_cells, halo, placements, by_cell, callback)
    state.run

  -> .union(patch_cells, cover)
    out = []
    i = 0
    while i < patch_cells.size
      out.push(patch_cells[i])
      i += 1
    j = 0
    while j < cover.size
      cells = cover[j][3]
      k = 0
      while k < cells.size
        out.push(cells[k])
        k += 1
      j += 1
    out

  -> .hole_free?(grid, patch_cells, cover)
    grid.holes(Corona.union(patch_cells, cover)).size == 0

  # The affine map placing orientation `index` at (tx, ty).
  -> .transform_of(grid, index, tx, ty)
    o = grid.orientation(index)
    [o[0], o[1], o[2] + tx, o[3], o[4], o[5] + ty]

# The hole-pruned corona search behind `Corona.each_hole_free_cover`.
+ HoleFreeCoverSearch
  -> new(@grid, @patch_cells, @halo, @placements, @by_cell, @callback)
    @patch_index = TilingGrid.index(@patch_cells)
    @covered = {}
    @union = []
    i = 0
    while i < @patch_cells.size
      @union.push(@patch_cells[i])
      i += 1
    @chosen = []
    @stopped = false

  -> run
    step
    @stopped

  -> available?(p)
    cells = @placements[p][3]
    j = 0
    while j < cells.size
      return false if @covered.key?(TilingGrid.cell_key(cells[j]))
      j += 1
    true

  # Candidates for a cell: placements containing it that avoid covered cells.
  -> candidates(key)
    out = []
    list = @by_cell.fetch(key, nil)
    return out if list == nil
    i = 0
    while i < list.size
      out.push(list[i]) if available?(list[i])
      i += 1
    out

  -> step
    return nil if @stopped
    # Prune: an enclosed empty cell that no compatible placement can fill.
    holes = @grid.holes(@union)
    h = 0
    while h < holes.size
      return nil if candidates(TilingGrid.cell_key(holes[h])).size == 0
      h += 1
    # Uncovered halo cell with the fewest candidates.
    best = nil
    best_cands = nil
    i = 0
    while i < @halo.size
      k = TilingGrid.cell_key(@halo[i])
      if !@covered.key?(k)
        cands = candidates(k)
        if best == nil || cands.size < best_cands.size
          best = k
          best_cands = cands
      i += 1
    if best == nil
      @stopped = true if @callback.call(@chosen.dup)
      return nil
    return nil if best_cands.size == 0
    c = 0
    while c < best_cands.size && !@stopped
      p = best_cands[c]
      c += 1
      cells = @placements[p][3]
      j = 0
      while j < cells.size
        @covered[TilingGrid.cell_key(cells[j])] = true
        @union.push(cells[j])
        j += 1
      @chosen.push(@placements[p])
      step
      @chosen.pop
      j = 0
      while j < cells.size
        @covered.delete(TilingGrid.cell_key(cells[j]))
        @union.pop
        j += 1
    nil

# Heesch numbers by depth-first search over hole-free patches. Each node
# asks whether any corona exists (raising the hole-permitted depth) and then
# streams the simply connected ones (up to `cover_limit` of them) as children.
# Reaching `max_level` stops the search: `hc` is then a lower bound, which
# makes `HeeschNumber.new(shape, k)` a fast "find a k-corona witness". The search is exhaustive — and `hc` exact —
# only when no limit was hit, which `exhaustive?` reports honestly.
+ HeeschNumber
  -> shape
    @shape

  -> new(shape, max_level = 6, cover_limit = 20000, node_limit = 5000)
    raise "Heesch numbers are defined for hole-free shapes" if !shape.hole_free?
    @shape = shape
    @max_level = max_level
    @cover_limit = cover_limit
    @node_limit = node_limit
    @hc = 0
    @hh = 0
    @exhaustive = true
    @nodes = 0
    @witness = [[0, @shape.grid.orientation(0)]]
    @hh_witness = @witness
    @stopped = false
    @computed = false

  -> hc
    compute
    @hc

  -> hh
    compute
    @hh

  -> exhaustive?
    compute
    @exhaustive

  -> nodes
    compute
    @nodes

  # Placements [level, [a,b,c,d,e,f]] of the deepest simply connected patch.
  -> witness
    compute
    @witness

  # Placements of a patch reaching the hole-permitted depth `hh`.
  -> hh_witness
    compute
    @hh_witness

  -> compute
    return self if @computed
    @computed = true
    search(@shape.cells, 0, @witness)
    @hh = @hc if @hh < @hc
    self

  -> search(patch_cells, depth, placements)
    @nodes += 1
    if @nodes > @node_limit
      @exhaustive = false
      return nil
    if depth > @hc
      @hc = depth
      @witness = placements
    if depth >= @max_level
      @exhaustive = false
      @stopped = true
      return nil
    grid = @shape.grid
    if depth + 1 > @hh
      any = Corona.covers(@shape, patch_cells, 1)
      if any.size > 0
        @hh = depth + 1
        @hh_witness = HeeschNumber.extend(grid, placements, depth + 1, any[0])
    examined = 0
    visit = ->(cover)
      examined += 1
      search(Corona.union(patch_cells, cover), depth + 1, HeeschNumber.extend(grid, placements, depth + 1, cover))
      @stopped || examined >= @cover_limit || @nodes > @node_limit
    stopped = Corona.each_hole_free_cover(@shape, patch_cells, visit)
    @exhaustive = false if stopped
    nil

  -> .extend(grid, placements, level, cover)
    out = []
    i = 0
    while i < placements.size
      out.push(placements[i])
      i += 1
    j = 0
    while j < cover.size
      p = cover[j]
      out.push([level, Corona.transform_of(grid, p[0], p[1], p[2])])
      j += 1
    out

  # heesch-sat witness text for the deepest simply connected patch.
  -> witness_text
    compute
    CoronaWitness.text(@shape, @hc, @hh, [@witness], @hh > @hc ? [@hh_witness] : [])

# Witness patches in heesch-sat's text format:
#
#   H x1 y1 ...            the shape
#   ~ hc hh P              claimed Heesch numbers and the number of patches
#   N                      placements in the first patch
#   level <a,b,c,d,e,f>    one placement per line, level 0 = the central copy
#
# A second patch, present when hh = hc + 1, shows the extra hole-permitted
# corona. Lines starting with `#` (the Heesch challenge's optional blocks)
# end the witness.
+ CoronaWitness
  -> .parse(text)
    lines = []
    text.split("\n").each ->(raw)
      line = raw.strip
      lines.push(line) if line != "" && line[0] != "#"
    raise "witness needs a shape line and a claim line" if lines.size < 2
    shape = Polyform.parse(lines[0])
    claim = CoronaWitness.tokens(lines[1])
    raise "claim line must read '~ hc hh P'" if claim.size != 4 || claim[0] != "~"
    hc = claim[1].to_i
    hh = claim[2].to_i
    count = claim[3].to_i
    patches = []
    at = 2
    p = 0
    while p < count
      raise "witness ends before patch [p + 1]" if at >= lines.size
      n = lines[at].to_i
      at += 1
      patch = []
      i = 0
      while i < n
        raise "patch [p + 1] declares [n] placements but the file ends" if at >= lines.size
        patch.push(CoronaWitness.parse_placement(lines[at]))
        at += 1
        i += 1
      patches.push(patch)
      p += 1
    { "shape": shape, "hc": hc, "hh": hh, "patches": patches }

  -> .tokens(line)
    out = []
    line.split(" ").each ->(t)
      u = t.strip
      out.push(u) if u != ""
    out

  # "level <a,b,c,d,e,f>" -> [level, [a, b, c, d, e, f]]
  -> .parse_placement(line)
    toks = CoronaWitness.tokens(line)
    raise "bad placement line: [line]" if toks.size != 2
    body = toks[1].gsub("<", "").gsub(">", "")
    parts = body.split(",")
    raise "bad transform in: [line]" if parts.size != 6
    xf = []
    i = 0
    while i < 6
      xf.push(parts[i].strip.to_i)
      i += 1
    [toks[0].to_i, xf]

  -> .placement_text(level, xf)
    "[level] <[xf[0]],[xf[1]],[xf[2]],[xf[3]],[xf[4]],[xf[5]]>"

  -> .text(shape, hc, hh, patches, extra_patches)
    all = []
    i = 0
    while i < patches.size
      all.push(patches[i])
      i += 1
    i = 0
    while i < extra_patches.size
      all.push(extra_patches[i])
      i += 1
    out = [shape.to_s, "~ [hc] [hh] [all.size]"]
    p = 0
    while p < all.size
      out.push("[all[p].size]")
      j = 0
      while j < all[p].size
        out.push(CoronaWitness.placement_text(all[p][j][0], all[p][j][1]))
        j += 1
      p += 1
    out.join("\n") + "\n"

  # Verify one patch: placements [level, xf]. Returns a hash with the
  # recomputed `levels`, the number of complete coronas `depth`, whether the
  # outermost corona encloses holes, and the patch cells; raises with a
  # stable code on any defect.
  -> .verify_patch(shape, placements)
    grid = shape.grid
    n = placements.size
    central = 0 - 1
    i = 0
    while i < n
      raise "XFORM_NOT_SYMMETRY: placement [i] is not a motion of the [grid.name] grid" if !grid.transform_legal?(placements[i][1])
      if placements[i][0] == 0
        raise "PATCH_MULTIPLE_CENTRAL: placements [central] and [i] both claim level 0" if central >= 0
        central = i
      i += 1
    raise "PATCH_NO_CENTRAL_TILE: no level-0 placement" if central < 0
    tiles = []
    owner = {}
    i = 0
    while i < n
      cells = shape.transformed(placements[i][1])
      j = 0
      while j < cells.size
        k = TilingGrid.cell_key(cells[j])
        raise "PATCH_OVERLAP: cell [k] is occupied by placements [owner[k]] and [i]" if owner.key?(k)
        owner[k] = i
        j += 1
      tiles.push(cells)
      i += 1
    # Recompute levels by breadth-first search from the central copy.
    level = []
    i = 0
    while i < n
      level.push(0 - 1)
      i += 1
    level[central] = 0
    frontier = TilingGrid.index(tiles[central])
    pending = n - 1
    cur = 0
    while pending > 0
      cur += 1
      newly = []
      i = 0
      while i < n
        if level[i] < 0
          if CoronaWitness.touches_index?(grid, tiles[i], frontier)
            newly.push(i)
        i += 1
      break if newly.size == 0
      frontier = {}
      j = 0
      while j < newly.size
        level[newly[j]] = cur
        pending -= 1
        cells = tiles[newly[j]]
        k = 0
        while k < cells.size
          frontier[TilingGrid.cell_key(cells[k])] = true
          k += 1
        j += 1
    i = 0
    while i < n
      raise "PATCH_ORPHAN_TILE: placement [i] is disconnected from the patch" if level[i] < 0
      raise "PATCH_LEVEL_MISMATCH: placement [i] is labelled level [placements[i][0]], recomputed [level[i]]" if level[i] != placements[i][0]
      i += 1
    max_level = 0
    i = 0
    while i < n
      max_level = level[i] if level[i] > max_level
      i += 1
    # Surround condition: each corona covers the halo of the patch below it.
    inner = []
    inner_index = {}
    CoronaWitness.add_cells(inner, inner_index, tiles[central])
    l = 1
    outer_holes = false
    while l <= max_level
      ring = []
      ring_index = {}
      i = 0
      while i < n
        CoronaWitness.add_cells(ring, ring_index, tiles[i]) if level[i] == l
        i += 1
      halo = grid.halo(inner)
      h = 0
      while h < halo.size
        raise "PATCH_GAP: corona [l] leaves [TilingGrid.cell_key(halo[h])] uncovered" if !ring_index.key?(TilingGrid.cell_key(halo[h]))
        h += 1
      CoronaWitness.add_cells(inner, inner_index, ring)
      holes = grid.holes(inner)
      if holes.size > 0
        raise "PATCH_HOLE_IN_CORONA: the patch through corona [l] encloses empty cells" if l < max_level
        outer_holes = true
      l += 1
    { "levels": level, "depth": max_level, "outer_holes": outer_holes, "patch_cells": inner }

  -> .touches_index?(grid, cells, index)
    i = 0
    while i < cells.size
      nbs = grid.contact_neighbours(cells[i])
      j = 0
      while j < nbs.size
        return true if index.key?(TilingGrid.cell_key(nbs[j]))
        j += 1
      i += 1
    false

  -> .add_cells(list, index, cells)
    i = 0
    while i < cells.size
      k = TilingGrid.cell_key(cells[i])
      if !index.key?(k)
        index[k] = true
        list.push(cells[i])
      i += 1
    nil

  # Verify a parsed witness: the established lower bounds hc and hh (never
  # more than the patches prove, whatever the claim line says), plus the
  # verified first patch.
  -> .verify(parsed)
    shape = parsed["shape"]
    patches = parsed["patches"]
    hc = 0
    hh = 0
    first = nil
    if patches.size >= 1
      first = CoronaWitness.verify_patch(shape, patches[0])
      if first["outer_holes"]
        hc = first["depth"] - 1
        hh = first["depth"]
      else
        hc = first["depth"]
        hh = first["depth"]
    if patches.size >= 2
      second = CoronaWitness.verify_patch(shape, patches[1])
      hh = second["depth"] if second["depth"] > hh
    { "shape": shape, "hc": hc, "hh": hh, "hc_claimed": parsed["hc"], "hh_claimed": parsed["hh"],
      "patch": first, "claim_met": hc >= parsed["hc"] && hh >= parsed["hh"] }

  -> .verify_text(text)
    CoronaWitness.verify(CoronaWitness.parse(text))
