use ../atomic_stop

-> wassat_affine_design_abs(x) (i64) i64
  x < 0 ? 0 - x : x

-> wassat_affine_design_poll(m, stop) (i64[] i64[]) i64
  m[1] += 1
  if wassat_stop_load(stop) != 0
    m[0] = 1
  elsif m[2] > 0 && clock_ms() >= m[2]
    m[0] = 2
  elsif m[3] + m[15] > 50000000
    m[0] = 3
  m[0]

# Signed DSU for choosing bit-coordinate representations. These are NOT
# consequences that may be substituted into the original Boolean formula.
-> wassat_affine_design_gauge_root(x, parent) (i64 i64[]) i64
  y = x; v = wassat_affine_design_abs(y)
  while parent[v] != v
    y = y < 0 ? 0 - parent[v] : parent[v]; v = wassat_affine_design_abs(y)
  parent[wassat_affine_design_abs(x)] = x < 0 ? 0 - y : y
  y

-> wassat_affine_design_gauge_join(a, b, parity, parent) (i64 i64 i64 i64[]) i64
  a = wassat_affine_design_gauge_root(a, parent); b = wassat_affine_design_gauge_root(b, parent)
  b = 0 - b if parity != 0
  return 0 if a == 0 - b
  if wassat_affine_design_abs(a) != wassat_affine_design_abs(b)
    if wassat_affine_design_abs(a) > wassat_affine_design_abs(b)
      parent[wassat_affine_design_abs(a)] = a < 0 ? 0 - b : b
    else
      parent[wassat_affine_design_abs(b)] = b < 0 ? 0 - a : a
  1

# Thirty-two-bit chunks stay inside the runtime's inline integer range when
# passed between helpers; a 64-bit sign-pattern mask would box as BigInts.
-> wassat_affine_design_pattern(masks, group, pat) (i64[] i64 i64) i64
  (masks[4 * group + pat / 32] & (1 << (pat % 32))) != 0 ? 1 : 0

# Eight length-seven clauses can establish equal(three-bit words)=>flag.
# Grouping is exact; hash collisions compare every support variable.
-> wassat_affine_design_equalities(lits, offs, lens, nc, m, stop) (i64[] i64[] i64[] i64 i64[] i64[])
  keys = i64[7 * 32768]; masks = i64[4 * 32768]; slots = i64[65536]
  scratch = i64[7]; signs = i64[7]; ng = 0; ci = 0
  while ci < nc
    return nil if (ci & 255) == 0 && wassat_affine_design_poll(m, stop) != 0
    if lens[ci] == 7
      j = 0
      while j < 7
        x = lits[offs[ci] + j]; v = wassat_affine_design_abs(x); s = x < 0 ? 1 : 0; k = j
        while k > 0 && scratch[k - 1] > v
          scratch[k] = scratch[k - 1]; signs[k] = signs[k - 1]; k -= 1
        scratch[k] = v; signs[k] = s; j += 1
      distinct = true; h = 0; pat = 0; j = 0
      while j < 7
        distinct = false if j > 0 && scratch[j] == scratch[j - 1]
        h = (h * 131 + scratch[j]) & 65535; pat |= signs[j] << j; j += 1
      if distinct
        tries = 0; found = false; g = 0
        while !found && tries < 128
          m[20] += 1; m[3] += 1
          g = slots[h] - 1
          if g < 0
            return nil if ng >= 32768
            g = ng; ng += 1; slots[h] = g + 1; j = 0
            while j < 7
              keys[7 * g + j] = scratch[j]; j += 1
            found = true
          else
            same = true; j = 0
            while j < 7 && same
              same = false if keys[7 * g + j] != scratch[j]; j += 1
            if same
              found = true
            else
              h = (h + 1) & 65535
          tries += 1
        return nil unless found
        masks[4 * g + pat / 32] |= 1 << (pat % 32)
    ci += 1; m[3] += 1
  m[4] = ng
  ops = i64[10 * ng]; patterns = i64[8]; sig = i64[7]; seen = i64[7]; deltas = i64[3]; np = 0; g = 0
  while g < ng
    return nil if (g & 63) == 0 && wassat_affine_design_poll(m, stop) != 0
    count = 0; pat = 0
    while pat < 128 && count <= 8
      if wassat_affine_design_pattern(masks, g, pat) != 0
        patterns[count] = pat if count < 8
        count += 1
      pat += 1; m[3] += 1
    if count == 8
      base = patterns[0]; i = 0; fixed = 0; pivot = -1
      while i < 7
        sig[i] = 0; seen[i] = 0; j = 0
        while j < 8
          sig[i] |= (((patterns[j] ^ base) >> i) & 1) << j; j += 1
        if sig[i] == 0
          fixed += 1; pivot = i
        i += 1
      if fixed == 1
        pairs = 0; good = true; i = 0
        while i < 7 && good
          if sig[i] != 0 && seen[i] == 0
            mate = -1; j = i + 1
            while j < 7
              if sig[j] == sig[i]
                good = false if mate >= 0
                mate = j
              j += 1
            if mate < 0 || pairs >= 3
              good = false
            else
              seen[i] = 1; seen[mate] = 1; deltas[pairs] = (1 << i) | (1 << mate)
              ops[10 * np + 1 + 3 * pairs] = keys[7 * g + i]
              ops[10 * np + 2 + 3 * pairs] = keys[7 * g + mate]
              ops[10 * np + 3 + 3 * pairs] = ((base >> i) ^ (base >> mate)) & 1
              pairs += 1
          i += 1
        good = false if pairs != 3
        test = 0
        while test < 8 && good
          pat = base; i = 0
          while i < 3
            pat ^= deltas[i] if ((test >> i) & 1) != 0
            i += 1
          good = false if wassat_affine_design_pattern(masks, g, pat) == 0
          test += 1; m[25] += 1
        if good
          e = keys[7 * g + pivot]; ops[10 * np] = ((base >> pivot) & 1) == 1 ? 0 - e : e
          np += 1; m[12] += 8
    g += 1
  m[5] = np
  np > 0 ? ops : nil

-> wassat_affine_design_decode(formula, m, stop)
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv < 1 || nv > 100000 || nc < 1 || nc > 500000 || nl < 1 || nl > 2000000
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  return nil if lits.size < nl || offs.size < nc || lens.size < nc || wassat_affine_design_poll(m, stop) != 0
  ci = 0
  while ci < nc
    return nil if (ci & 255) == 0 && wassat_affine_design_poll(m, stop) != 0
    o = offs[ci]; n = lens[ci]
    return nil if o < 0 || n < 1 || o > nl || n > nl - o
    j = 0
    while j < n
      return nil if (j & 1023) == 0 && wassat_affine_design_poll(m, stop) != 0
      v = wassat_affine_design_abs(lits[o + j]); return nil if v < 1 || v > nv
      j += 1; m[3] += 1
    ci += 1
  ops = wassat_affine_design_equalities(lits, offs, lens, nc, m, stop)
  return nil if ops == nil
  ng = m[5]; io = i64[nv + 2]; incidences = i64[6 * ng]; cursor = i64[nv + 1]; gauge = i64[nv + 1]; g = 0
  while g < ng
    i = 0
    while i < 3
      a = ops[10 * g + 1 + 3 * i]; b = ops[10 * g + 2 + 3 * i]
      io[a + 1] += 1; io[b + 1] += 1; i += 1
    g += 1
  v = 1
  while v <= nv
    io[v + 1] += io[v]; cursor[v] = io[v]; gauge[v] = v; v += 1
  g = 0
  while g < ng
    return nil if (g & 127) == 0 && wassat_affine_design_poll(m, stop) != 0
    i = 0
    while i < 3
      a = ops[10 * g + 1 + 3 * i]; b = ops[10 * g + 2 + 3 * i]; p = ops[10 * g + 3 + 3 * i]
      incidences[cursor[a]] = g; cursor[a] += 1; incidences[cursor[b]] = g; cursor[b] += 1
      return nil if wassat_affine_design_gauge_join(a, b, p, gauge) == 0
      i += 1
    g += 1
  # Incidence signatures propose words; every comparison ID is compared.
  slots = i64[2048]; reps = i64[512]; widths = i64[512]; words = i64[3 * 512]; which = i64[nv + 1]; nw = 0; v = 1
  while v <= nv
    return nil if (v & 255) == 0 && wassat_affine_design_poll(m, stop) != 0
    len = io[v + 1] - io[v]
    if len > 0
      h = len; i = io[v]
      while i < io[v + 1]
        h = (h * 131 + incidences[i] + 1) & 2047; i += 1; m[26] += 1; m[3] += 1
      found = false; tries = 0; w = 0
      while !found && tries < 128
        w = slots[h] - 1
        if w < 0
          return nil if nw >= 512
          w = nw; nw += 1; slots[h] = w + 1; reps[w] = v; found = true
        else
          u = reps[w]; same = io[u + 1] - io[u] == len; i = 0
          while i < len && same
            same = false if incidences[io[u] + i] != incidences[io[v] + i]
            i += 1; m[26] += 1; m[3] += 1
          if same
            found = true
          else
            h = (h + 1) & 2047
        tries += 1; m[3] += 1
      return nil if !found || widths[w] >= 3
      words[3 * w + widths[w]] = v; widths[w] += 1; which[v] = w + 1
    v += 1
  w = 0
  while w < nw
    return nil if widths[w] != 3
    w += 1
  m[6] = nw
  # Choose coordinates and flips; no logical substitution follows this DSU.
  coords = i64[nv + 1]; phases = i64[nv + 1]; roots = i64[nv + 1]; nr = 0; w = 0
  while w < nw
    used = 0; i = 0
    while i < 3
      v = words[3 * w + i]; r = wassat_affine_design_gauge_root(v, gauge); root = wassat_affine_design_abs(r)
      if roots[root] == 0
        nr += 1; roots[root] = nr
      c = roots[root] - 1; return nil if c >= 3 || (used & (1 << c)) != 0
      used |= 1 << c; coords[v] = c; phases[v] = r < 0 ? 1 : 0; i += 1
    w += 1
  return nil if nr != 3
  m[7] = nr
  edges = i64[nw * nw]; rw_parent = i64[nw + 1]; pl_parent = i64[nw + 1]; i = 1
  while i <= nw
    rw_parent[i] = i; pl_parent[i] = i; i += 1
  g = 0
  while g < ng
    u = which[ops[10 * g + 1]] - 1; v = which[ops[10 * g + 2]] - 1
    return nil if u < 0 || v < 0 || u == v || which[wassat_affine_design_abs(ops[10 * g])] != 0
    i = 0
    while i < 3
      a = which[ops[10 * g + 1 + 3 * i]] - 1; b = which[ops[10 * g + 2 + 3 * i]] - 1
      return nil unless (a == u && b == v) || (a == v && b == u)
      i += 1
    return nil if edges[u * nw + v] != 0
    edges[u * nw + v] = g + 1; edges[v * nw + u] = g + 1; g += 1
  # Graph components are proposals only. Complete comparator coverage, domains
  # and original implication proofs are checked after constructing the grid.
  u = 0
  while u < nw
    return nil if wassat_affine_design_poll(m, stop) != 0
    v = u + 1
    while v < nw
      if edges[u * nw + v] != 0
        k = 0; common = false
        while k < nw && !common
          common = true if edges[u * nw + k] != 0 && edges[v * nw + k] != 0
          k += 1; m[3] += 1; m[27] += 1
        z = wassat_affine_design_gauge_join(u + 1, v + 1, 0, rw_parent) if common
      v += 1
    u += 1
  round_id = i64[nw]; round_size = i64[nw]; root_id = i64[nw + 1]; rounds = 0; u = 0
  while u < nw
    root = wassat_affine_design_gauge_root(u + 1, rw_parent)
    if root_id[root] == 0
      rounds += 1; root_id[root] = rounds
    r = root_id[root] - 1; round_id[u] = r; round_size[r] += 1; u += 1
  return nil if rounds < 2 || rounds > 8 || nw != rounds * rounds * rounds
  nplayers = rounds * rounds; r = 0
  while r < rounds
    return nil if round_size[r] != nplayers
    r += 1
  u = 0
  while u < nw
    v = u + 1
    while v < nw
      z = wassat_affine_design_gauge_join(u + 1, v + 1, 0, pl_parent) if edges[u * nw + v] != 0 && round_id[u] != round_id[v]
      v += 1
    u += 1
  player_id = i64[nw]; player_size = i64[nw]; proot_id = i64[nw + 1]; players = 0; u = 0
  grid = i64[nw]
  while u < nw
    root = wassat_affine_design_gauge_root(u + 1, pl_parent)
    if proot_id[root] == 0
      players += 1; proot_id[root] = players
    p = proot_id[root] - 1; return nil if p >= nplayers
    player_id[u] = p; player_size[p] += 1; at = round_id[u] * nplayers + p
    return nil if grid[at] != 0
    grid[at] = u + 1; u += 1
  return nil if players != nplayers
  p = 0
  while p < players
    return nil if player_size[p] != rounds
    p += 1
  equality = i64[rounds * players * players]; r = 0
  while r < rounds
    return nil if wassat_affine_design_poll(m, stop) != 0
    p = 0
    while p < players
      u = grid[r * players + p] - 1; return nil if u < 0
      t = p + 1
      while t < players
        v = grid[r * players + t] - 1; return nil if v < 0
        g = edges[u * nw + v] - 1; return nil if g < 0
        equality[r * players * players + p * players + t] = ops[10 * g]
        t += 1
      p += 1
    r += 1
  m[8] = rounds; m[9] = players
  {"words": words, "which": which, "coordinates": coords, "phases": phases, "grid": grid, "equalities": equality, "nwords": nw, "rounds": rounds, "players": players}
