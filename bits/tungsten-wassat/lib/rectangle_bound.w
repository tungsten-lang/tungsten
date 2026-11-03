# Complete square-grid coloring clauses, invariant under signed variable,
# cell, color, clause and literal permutations. Fast-only counting certificate.
use atomic_stop

# Exact header admission is only a cheap candidate test, never a certificate.
-> wassat_rectangle_shape(nv, nc) (i64 i64) i64
  return 0 if nv < 18 || nv > 8192 || nc < 1 || nc > 2000000
  k = 2
  while k <= 8
    n = 3
    while n <= 32
      cells = n*n
      pairs = n*(n-1)/2
      return n*16+k if nv == cells*k && nc == cells*(1+k*(k-1)/2)+k*pairs*pairs
      n += 1
    k += 1
  0

# m: 0 verdict,1 stop reason,2 polls,3 clause visits,4 literal visits,
# 5 side,6 colors,7 cells,8 AMOs,9 domains,10 rectangles,11 unions,
# 12 pair updates,13 grid pair checks,14 checked rectangle/color tuples,
# 15 minimum row pairs,16 total minimum,17 capacity,18 per-color baseline,
# 19 per-color capacity,20 increment,21 residue,22 bound kind,
# 23 conservative scratch bytes,24 ms,25 complete recognition,26 phase.
-> wassat_rectangle_stop(m, stop, deadline) (i64[] i64[] i64) i64
  m[2] += 1
  if wassat_stop_load(stop) != 0
    m[1] = 1
    return 1
  if deadline > 0 && clock_ms() >= deadline
    m[1] = 2
    return 1
  0

-> wassat_rectangle_root(parent, v) (i32[] i64) i64
  while parent[v] != v
    parent[v] = parent[parent[v]]
    v = parent[v]
  v

-> wassat_rectangle_check(lits, offs, lens, nv, nc, shape, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) i64
  return 0 if shape == 0 || wassat_rectangle_stop(m,stop,deadline) != 0
  n = shape/16; k = shape%16; cells = n*n; npairs = n*(n-1)/2
  nrect = k*npairs*npairs
  m[5] = n; m[6] = k; m[7] = cells
  m[23] = 131072 + 64*(nv+cells+n) + 8*nrect + 4*cells*cells
  return 0 if offs.size < nc || lens.size < nc
  pol = i8[nv+1]
  degree = i8[nv+1]
  adjacent = i32[(nv+1)*k]
  owner = i32[nv+1]
  members = i32[nv]
  parent = i32[nv+1]
  colors = i8[nv+1]
  root_color = i8[nv+1]
  domains = i8[cells]
  rects = i32[nrect]
  pairs = i32[cells*cells]
  row = i16[cells]
  col = i16[cells]
  grid = i32[cells]
  row0 = i32[n]
  col0 = i32[n]
  covered = i8[nrect]
  vs = i32[8]
  gs = i32[8]
  # For k>2 only AMO clauses are binary. For k=2 only rectangle
  # clauses have width four. Both reveal each variable's choice polarity.
  m[26] = 1; ci = 0
  while ci < nc
    return 0 if (ci & 511) == 0 && wassat_rectangle_stop(m,stop,deadline) != 0
    width = lens[ci]; off = offs[ci]
    return 0 if (width != 2 && width != 4 && width != k) || off < 0 || off > lits.size || width > lits.size-off
    j = 0
    while j < width
      l = lits[off+j]; v = l < 0 ? 0-l : l
      return 0 if v < 1 || v > nv
      if (k == 2 && width == 4) || (k > 2 && width == 2)
        p = l > 0 ? -1 : 1
        return 0 if pol[v] != 0 && pol[v] != p
        pol[v] = p
      m[4] += 1; j += 1
    m[3] += 1; ci += 1
  v = 1
  while v <= nv
    return 0 if pol[v] == 0
    parent[v] = v; v += 1
  m[26] = 2; ci = 0
  while ci < nc
    return 0 if (ci & 511) == 0 && wassat_rectangle_stop(m,stop,deadline) != 0
    if lens[ci] == 2
      a = lits[offs[ci]]; b = lits[offs[ci]+1]
      va = a < 0 ? 0-a : a; vb = b < 0 ? 0-b : b
      sa = a > 0 ? pol[va] : 0-pol[va]; sb = b > 0 ? pol[vb] : 0-pol[vb]
      return 0 if va == vb || sa != sb
      if sa == -1
        da = degree[va]; db = degree[vb]
        return 0 if da >= k-1 || db >= k-1
        j = 0
        while j < da
          return 0 if adjacent[va*k+j] == vb
          j += 1
        adjacent[va*k+da] = vb; adjacent[vb*k+db] = va
        degree[va] += 1; degree[vb] += 1; m[8] += 1
      else
        return 0 unless k == 2 && sa == 1
    m[3] += 1; ci += 1
  return 0 if m[8] != cells*k*(k-1)/2
  m[26] = 3; g = 0; v = 1
  while v <= nv
    return 0 if (v & 255) == 0 && wassat_rectangle_stop(m,stop,deadline) != 0
    return 0 if degree[v] != k-1
    if owner[v] == 0
      return 0 if g >= cells
      members[g*k] = v; owner[v] = g+1; j = 0
      while j < k-1
        u = adjacent[v*k+j]
        return 0 if owner[u] != 0
        members[g*k+j+1] = u; owner[u] = g+1; j += 1
      g += 1
    v += 1
  return 0 if g != cells
  v = 1
  while v <= nv
    j = 0
    while j < k-1
      return 0 if owner[adjacent[v*k+j]] != owner[v]
      j += 1
    v += 1
  m[26] = 4; ci = 0; nr = 0
  while ci < nc
    return 0 if (ci & 511) == 0 && wassat_rectangle_stop(m,stop,deadline) != 0
    width = lens[ci]; off = offs[ci]; plus = 0; minus = 0; j = 0
    while j < width
      l = lits[off+j]; v = l < 0 ? 0-l : l; sign = l > 0 ? pol[v] : 0-pol[v]
      plus += 1 if sign == 1; minus += 1 if sign == -1
      vs[j] = v; gs[j] = owner[v]-1
      h = 0
      while h < j
        return 0 if vs[h] == v
        h += 1
      j += 1
    if plus == width && width == k
      g = gs[0]; j = 1
      while j < width
        return 0 if gs[j] != g
        j += 1
      return 0 if domains[g] != 0
      domains[g] = 1; m[9] += 1
    elsif minus == width && width == 2
      return 0 if gs[0] != gs[1]
    elsif minus == 4 && width == 4
      return 0 if nr >= nrect
      j = 0; root = wassat_rectangle_root(parent,(vs[0] ## i64))
      while j < 4
        u = wassat_rectangle_root(parent,(vs[j] ## i64)); parent[u] = root; m[11] += 1
        h = 0
        while h < j
          a = gs[j]; b = gs[h]
          return 0 if a == b
          pairs[a*cells+b] += 1; pairs[b*cells+a] += 1; m[12] += 2
          h += 1
        j += 1
      rects[nr] = ci; nr += 1
    else
      return 0
    m[3] += 1; ci += 1
  m[10] = nr
  return 0 if nr != nrect || m[9] != cells
  m[26] = 5; color_count = 0; v = 1
  while v <= nv
    root = wassat_rectangle_root(parent,v)
    if root_color[root] == 0
      color_count += 1
      return 0 if color_count > k
      root_color[root] = color_count
    colors[v] = root_color[root]; v += 1
  return 0 if color_count != k
  g = 0
  while g < cells
    mask = 0; j = 0
    while j < k
      bit = 1 << colors[members[g*k+j]]
      return 0 if (mask & bit) != 0
      mask |= bit; j += 1
    g += 1
  m[26] = 6; frequent = k*(n-1); a = 0
  while a < cells
    return 0 if (a & 7) == 0 && wassat_rectangle_stop(m,stop,deadline) != 0
    degree_a = 0; b = 0
    while b < cells
      if a != b
        count = pairs[a*cells+b]
        return 0 if count != k && count != frequent
        degree_a += 1 if count == frequent
        m[13] += 1
      b += 1
    return 0 if degree_a != 2*(n-1)
    a += 1
  neighbor = -1; a = 1
  while a < cells && neighbor < 0
    neighbor = a if pairs[a] == frequent
    a += 1
  return 0 if neighbor < 0
  row0[0] = 0; col0[0] = 0; rn = 1; cn = 1; a = 1
  while a < cells
    if pairs[a] == frequent
      if a == neighbor || pairs[neighbor*cells+a] == frequent
        return 0 if rn >= n
        row0[rn] = a; rn += 1
      else
        return 0 if cn >= n
        col0[cn] = a; cn += 1
    a += 1
  return 0 if rn != n || cn != n
  a = 0
  while a < cells
    return 0 if (a & 31) == 0 && wassat_rectangle_stop(m,stop,deadline) != 0
    rr = -1; cc = -1; j = 0
    while j < n
      cc = j if row0[j] == a
      rr = j if col0[j] == a
      j += 1
    if cc >= 0
      rr = 0
    elsif rr >= 0
      cc = 0
    else
      j = 0
      while j < n
        if pairs[a*cells+row0[j]] == frequent
          return 0 if cc >= 0
          cc = j
        if pairs[a*cells+col0[j]] == frequent
          return 0 if rr >= 0
          rr = j
        j += 1
    return 0 if rr < 0 || cc < 0 || grid[rr*n+cc] != 0
    row[a] = rr; col[a] = cc; grid[rr*n+cc] = a+1
    a += 1
  m[26] = 7; at = 0
  while at < nr
    return 0 if (at & 511) == 0 && wassat_rectangle_stop(m,stop,deadline) != 0
    ci = rects[at]; off = offs[ci]; rlo = n; rhi = -1; clo = n; chi = -1; c = 0; j = 0
    while j < 4
      l = lits[off+j]; v = l < 0 ? 0-l : l; g = owner[v]-1
      return 0 if j > 0 && colors[v] != c
      c = colors[v]; rr = row[g]; cc = col[g]
      rlo = rr if rr < rlo; rhi = rr if rr > rhi
      clo = cc if cc < clo; chi = cc if cc > chi
      gs[j] = g; j += 1
    return 0 if rlo == rhi || clo == chi
    mask = 0; j = 0
    while j < 4
      rr = row[gs[j]]; cc = col[gs[j]]
      return 0 if (rr != rlo && rr != rhi) || (cc != clo && cc != chi)
      bit = 1 << ((rr == rhi ? 2 : 0)+(cc == chi ? 1 : 0))
      return 0 if (mask & bit) != 0
      mask |= bit; j += 1
    return 0 if mask != 15
    rp = rlo*(2*n-rlo-1)/2+rhi-rlo-1
    cp = clo*(2*n-clo-1)/2+chi-clo-1
    idx = (rp*npairs+cp)*k+c-1
    return 0 if idx < 0 || idx >= nrect || covered[idx] != 0
    covered[idx] = 1; m[14] += 1; at += 1
  # Cardinality plus injectivity above establishes complete coverage.
  return 0 if m[14] != nrect || wassat_rectangle_stop(m,stop,deadline) != 0
  m[25] = 1; m[26] = 8
  q = n / k; rem = n % k
  lower = rem*q*(q+1)/2+(k-rem)*q*(q-1)/2
  m[15] = lower; m[16] = n*lower; m[17] = k*npairs
  if m[16] > m[17]
    m[22] = 1
    return -1
  if m[16] == m[17] && q > 0
    # Equality forces every row to have only q/q+1 cells per color and
    # every same-color column pair to occur exactly once. For each color,
    # pairs = n*C(q,2) + q*(number of rows having q+1 cells of this color).
    baseline = n*q*(q-1)/2
    m[18] = baseline; m[19] = npairs; m[20] = q
    m[21] = (npairs-baseline)%q
    if npairs < baseline || m[21] != 0
      m[22] = 2
      return -1
  0

-> wassat_rectangle_refute(formula, m, stop, deadline = 0)
  return 0 if m.size < 32 || stop.size < 2 || !formula.has_key?("flat_ncl")
  started = clock_ms(); i = 0
  while i < 32
    m[i] = 0; i += 1
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  shape = wassat_rectangle_shape(nv,nc)
  result = wassat_rectangle_check(formula["flat_lits"],formula["flat_offs"],formula["flat_lens"],nv,nc,shape,m,stop,deadline)
  result = 0 if wassat_rectangle_stop(m,stop,deadline) != 0
  m[0] = result; m[24] = clock_ms()-started
  result

# Admission reserves only an otherwise unused worker. All clause decoding
# and scratch allocation happen inside that worker, beside the solving arms.
-> wassat_rectangle_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_RECTANGLE_BOUND")
  return nil if mode == "0" || System.cpu_count <= workers || wassat_race_round1_conflicts != 0
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  shape = wassat_rectangle_shape(formula["nvars"],formula["flat_ncl"])
  return nil if shape == 0
  scratch = 33554432
  return nil unless wassat_race_memory_fits?(formula,cdcl,sls,pre,extra+scratch)
  {"rectangle_bound": true, "meta": i64[32], "scratch": scratch}

-> wassat_rectangle_arm(formula, m, stop, res, base, nv)
  started = clock_ms(); res[base+nv+6] = started
  result = wassat_rectangle_refute(formula,m,stop,started+1000)
  res[base+nv+5] = clock_ms()
  if result == -1 && !wassat_stop_requested?(stop)
    z = ccall("__w_arr_store_rel",res,base,-1)
    z = wassat_stop_publish(stop,-1)
  0

-> wassat_rectangle_profile(m)
  wassat_prof_note("race.rectangle_bound status=[m[0]] stopped=[m[1]] polls=[m[2]] clause_visits=[m[3]] literal_visits=[m[4]] side=[m[5]] colors=[m[6]] cells=[m[7]] AMOs=[m[8]] domains=[m[9]] rectangles=[m[10]] unions=[m[11]] pair_updates=[m[12]] grid_pairs=[m[13]] checked=[m[14]] row_min=[m[15]] total_min=[m[16]] capacity=[m[17]] color_base=[m[18]] color_capacity=[m[19]] increment=[m[20]] residue=[m[21]] reason=[m[22]] scratch=[m[23]] ms=[m[24]] recognized=[m[25]] phase=[m[26]]")
