# Shuffling a choice encoding can rename its colors independently in every
# row. A complete matching of binary exclusions to one anchor row recovers a
# common color order. Two other rows are adjacent only if their ORIGINAL
# clauses forbid equal anchor colors in every coordinate.
use coloring

-> wassat_permuted_clique(formula, row_ids, owner, value, nb, width)
  return nil if nb <= width
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  nc = formula["flat_ncl"]
  mates = i8[nb*nb*width]; counts = i8[nb*nb]; ci = 0
  while ci < nc
    if lens[ci] == 2
      at = offs[ci]; x = lits[at]; y = lits[at+1]
      u = x.abs; v = y.abs; g = owner[u]; h = owner[v]
      if g != h
        a = x < 0 ? value[u] : 0-value[u]
        b = y < 0 ? value[v] : 0-value[v]
        # A literal that is true at many row values is a different relation.
        return nil if a <= 0 || b <= 0
        ab = (g*nb+h)*width+a-1; ba = (h*nb+g)*width+b-1
        if mates[ab] == 0 && mates[ba] == 0
          mates[ab] = b; mates[ba] = a
          counts[g*nb+h] += 1; counts[h*nb+g] += 1
        else
          return nil unless mates[ab] == b && mates[ba] == a
    elsif lens[ci] != width
      return nil
    ci += 1
  # Reuse scratch and one node budget over all possible anchor vertices.
  adj = i64[nb*nb]; candidates = i64[(width+1)*nb]; clique = i64[width]
  pm = i64[3]; pm[1] = WASSAT_COLORING_NODE_CAP
  root = 0
  while root+width < nb && pm[0] < pm[1]
    count = 0; g = root+1
    while g < nb
      if counts[root*nb+g] == width
        candidates[count] = g; count += 1
      g += 1
    if count >= width
      i = 0
      while i < count
        g = candidates[i]; j = i+1
        while j < count
          h = candidates[j]; k = 0
          if counts[g*nb+h] == width
            while k < width
              a = mates[(root*nb+g)*width+k]
              b = mates[(root*nb+h)*width+k]
              break unless mates[(g*nb+h)*width+a-1] == b
              k += 1
          edge = k == width ? 1 : 0
          adj[g*nb+h] = edge; adj[h*nb+g] = edge
          j += 1
        i += 1
      if wassat_coloring_clique_dfs(adj, nb, width, candidates, count, 0, clique, pm) == 1
        rows = []; choices = []
        i = 0
        while i <= width
          g = i == 0 ? root : clique[i-1]
          rows.push(row_ids[g]); j = 0
          while j < width
            col = i == 0 ? j : mates[(root*nb+g)*width+j]-1
            choices.push(lits[offs[row_ids[g]-1]+col]); j += 1
          i += 1
        return {"rows": rows, "choices": choices}
    root += 1
  nil
