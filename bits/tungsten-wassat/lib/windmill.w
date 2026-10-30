# Structural recognizer and cooperative SAT-only lane for the
# "allowable-sequence windmill" family (e.g. SC2026 `as-p61-l22-o8-II-568`):
# a median-pivot windmill over an odd number of labelled points, encoded as
# a grid of per-column tri-state cells (left of the median / right of it /
# the median itself) that a sequence of rich lines rewrites one row at a time.
#
# Clean-room provenance: everything below is derived from clause incidence in
# the DIMACS formula plus propositional resolution consequences of the
# verified ladder clauses. Zero variable numbers, instance hashes, or witness
# tables are hard-coded:
#
#   1. Exactly-one triples on consecutive variables (a, a+1, a+2) with their
#      three pairwise negative binaries are the state cells at stride 3*cols.
#   2. Carry-over clauses (g, -s, s') with s' = s + stride name one guard
#      variable g per (transition r, column c): the line-membership grid.
#   3. The first state row is fixed by units (h left, 1 median, h right);
#      the last row is reversed with the median column free.
#   4. Each transition row has a P pair (p, p+1), an inactive flag f, and a
#      T triple (t, t+1, t+2) recovered from clause incidence.
#   5. When per-pair monotone swap ladders V[0..rows-1, pair] are present
#      with verified (-G[r,c1], -G[r,c2], +V[r,p]), (-G[r,c1], -G[r,c2], -V[r+1,p])
#      and (+V[r,p], -V[r+1,p]) clauses across all 0 <= r < rows-1, 4-literal
#      2x2 rectangle clauses (-G[r1,c1], -G[r1,c2], -G[r2,c1], -G[r2,c2]) and
#      short (G, S) projected pair-cut conflict clauses follow by direct
#      resolution along V[*, p], while surviving cut positions fit in a 64-bit
#      mask per pair.
#   6. Taint propagation from {G, S, V} isolates the exact pure-(P, T) master
#      subformula (row-mode clauses + global mode counters), enabling fast
#      Hamming-ball (P, T) exploration filtered by the V-free flux oracle and
#      full-CNF refutation oracle alongside core-guided column + free-(P, T)
#      neighborhood repair of low-violation @best_phase incumbents.
#
# Strictly SAT-only: every published model is verified against the complete
# original formula via wassat_model_satisfies?; any miss or budget exhaustion
# returns status 0 so ordinary proof-producing search continues untouched.

use ../../../core/bit_ops
use cnf
use policy
use atomic_stop
use solver
use preprocess
use structural_pruning

WASSAT_WINDMILL_MIN_COLS = 7
WASSAT_WINDMILL_MAX_COLS = 401
WASSAT_WINDMILL_MIN_ROWS = 4
WASSAT_WINDMILL_MAX_ROWS = 200
WASSAT_WINDMILL_MIRROR_PROBE_CONFLICTS = 5000
WASSAT_WINDMILL_DEFAULT_CAP = 80000000
WASSAT_WINDMILL_ROUND_SLICE = 200000

-> wassat_windmill_pair_index(cols, c1, c2) (i64 i64 i64) i64
  a = c1
  b = c2
  if a > b
    a = c2
    b = c1
  a * cols - ((a * (a + 1)) / 2) + (b - a - 1)

# Returns nil on a miss, else a layout hash:
#   "cols", "h", "rows" (state rows), "sbase", "stride",
#   "guard"      i64[(rows-1)*cols]   guard var of (transition r, column c)
#   "pvar"       i64[rows-1]          first var of the P pair (0 = none)
#   "tvar"       i64[rows-1]          first var of the T triple (0 = none)
#   "flag"       i64[rows-1]          inactive-flag var (0 = none)
#   "active"     i8[rows-1]           1 when the transition is an active move
#   "nmoves"     number of active transitions
#   "mirror_sym" true when active moves are 0..nmoves-1 and input units on
#                (G, P, T) are invariant under (r -> nmoves-1-r, c -> cols-1-c)
-> wassat_windmill_recognize(formula)
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return nil if nv < 50 || nv > 20000000 || ncl < 100 || ncl > 100000000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  pos3 = i8[nv + 3]
  nb1 = i8[nv + 3]
  nb2 = i8[nv + 3]
  unitv = i8[nv + 3]
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    if n == 1
      l = fla[off]
      v = l < 0 ? 0 - l : l
      unitv[v] = l > 0 ? 1 : -1 if v >= 1 && v <= nv
    elsif n == 2
      a = fla[off]
      b = fla[off + 1]
      if a < 0 && b < 0
        u = 0 - a
        w = 0 - b
        if u > w
          tmp = u
          u = w
          w = tmp
        if w == u + 1
          nb1[u] = 1
        elsif w == u + 2
          nb2[u] = 1
    elsif n == 3
      a = fla[off]
      b = fla[off + 1]
      c = fla[off + 2]
      if a > 0 && b > 0 && c > 0
        lo = a
        mid = b
        hi = c
        if lo > mid
          tmp = lo
          lo = mid
          mid = tmp
        if mid > hi
          tmp = mid
          mid = hi
          hi = tmp
        if lo > mid
          tmp = lo
          lo = mid
          mid = tmp
        pos3[lo] = 1 if mid == lo + 1 && hi == lo + 2
    ci += 1
  # First exactly-one cell.
  sbase = 0
  v = 1
  while v + 2 <= nv
    if pos3[v] == 1 && nb1[v] == 1 && nb2[v] == 1 && nb1[v + 1] == 1
      sbase = v
      break
    v += 1
  return nil if sbase == 0
  ncells = 0
  v = sbase
  while v + 2 <= nv && pos3[v] == 1 && nb1[v] == 1 && nb2[v] == 1 && nb1[v + 1] == 1
    ncells += 1
    v += 3
  return nil if ncells < WASSAT_WINDMILL_MIN_COLS * WASSAT_WINDMILL_MIN_ROWS
  send = sbase + 3 * ncells - 1
  # Carry-over distance: (g, -s, s') with s' - s the stride.
  maxd = 3 * WASSAT_WINDMILL_MAX_COLS
  dcount = i64[maxd + 1]
  ci = 0
  while ci < ncl
    if fcl[ci] == 3
      off = fcs[ci]
      neg = 0
      negv = 0
      s2 = 0
      g = 0
      j = 0
      while j < 3
        l = fla[off + j]
        if l < 0
          neg += 1
          negv = 0 - l
        elsif l >= sbase && l <= send
          s2 = l
        else
          g = l
        j += 1
      if neg == 1 && negv >= sbase && negv <= send && s2 > negv && g > 0
        d = s2 - negv
        dcount[d] += 1 if d <= maxd
    ci += 1
  stride = 0
  best = 0
  d = 3
  while d <= maxd
    if dcount[d] > best
      best = dcount[d]
      stride = d
    d += 3
  return nil if stride == 0 || stride % 3 != 0
  cols = stride / 3
  return nil if cols < WASSAT_WINDMILL_MIN_COLS || cols > WASSAT_WINDMILL_MAX_COLS || cols % 2 == 0
  return nil if ncells % cols != 0
  rows = ncells / cols
  return nil if rows < WASSAT_WINDMILL_MIN_ROWS || rows > WASSAT_WINDMILL_MAX_ROWS
  h = (cols - 1) / 2
  ntrans = rows - 1
  # Guard grid from the k = 0 carry-over clauses; k = 1 must agree.
  guard = i64[ntrans * cols]
  ci = 0
  while ci < ncl
    if fcl[ci] == 3
      off = fcs[ci]
      neg = 0
      negv = 0
      s2 = 0
      g = 0
      j = 0
      while j < 3
        l = fla[off + j]
        if l < 0
          neg += 1
          negv = 0 - l
        elsif l >= sbase && l <= send
          s2 = l
        else
          g = l
        j += 1
      if neg == 1 && negv >= sbase && negv <= send && s2 == negv + stride && g > 0
        cell = negv - sbase
        k = cell % 3
        idx = cell / 3
        if k <= 1 && idx < ntrans * cols
          if guard[idx] == 0
            guard[idx] = g
          elsif guard[idx] != g
            return nil
    ci += 1
  idx = 0
  while idx < ntrans * cols
    return nil if guard[idx] == 0
    idx += 1
  # Initial row: h left cells, median, h right cells; final row reversed.
  c = 0
  while c < cols
    want = c < h ? 0 : (c == h ? 2 : 1)
    return nil unless unitv[sbase + 3 * c + want] == 1
    wantf = c < h ? 1 : 0
    return nil if c != h && unitv[sbase + (rows - 1) * stride + 3 * c + wantf] != 1
    c += 1
  # P pairs: (p, p+1) with -p v -(p+1) and an all-positive 3-clause
  # (f, p, p+1) whose third literal is outside the state grid.
  pflag = i64[nv + 3]
  ci = 0
  while ci < ncl
    if fcl[ci] == 3
      off = fcs[ci]
      a = fla[off]
      b = fla[off + 1]
      c3 = fla[off + 2]
      if a > 0 && b > 0 && c3 > 0
        lo = a
        mid = b
        hi = c3
        if lo > mid
          tmp = lo
          lo = mid
          mid = tmp
        if mid > hi
          tmp = mid
          mid = hi
          hi = tmp
        if lo > mid
          tmp = lo
          lo = mid
          mid = tmp
        if mid == lo + 1 && hi != lo + 2 && nb1[lo] == 1 && !(lo >= sbase && lo <= send)
          pflag[lo] = hi
        elsif hi == mid + 1 && lo != mid - 1 && nb1[mid] == 1 && !(mid >= sbase && mid <= send)
          pflag[mid] = lo
    ci += 1
  # Tie each pair to a transition: the smallest state row it shares a clause with.
  prow = i64[nv + 3]
  v = 1
  while v <= nv
    prow[v] = -1
    v += 1
  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n >= 3
      off = fcs[ci]
      minrow = -1
      j = 0
      while j < n
        l = fla[off + j]
        u = l < 0 ? 0 - l : l
        if u >= sbase && u <= send
          r = (u - sbase) / stride
          minrow = r if minrow < 0 || r < minrow
        j += 1
      if minrow >= 0
        j = 0
        while j < n
          l = fla[off + j]
          u = l < 0 ? 0 - l : l
          p = pflag[u] > 0 ? u : (u >= 2 && pflag[u - 1] > 0 ? u - 1 : 0)
          if p > 0
            prow[p] = minrow if prow[p] < 0 || minrow < prow[p]
          j += 1
    ci += 1
  pvar = i64[ntrans]
  tvar = i64[ntrans]
  flag = i64[ntrans]
  active = i8[ntrans]
  v = 1
  while v <= nv
    if pflag[v] > 0 && prow[v] >= 0 && prow[v] < ntrans
      r = prow[v]
      return nil if pvar[r] != 0 && pvar[r] != v
      pvar[r] = v
      flag[r] = pflag[v]
    v += 1
  # T triples: (-t.k, p, p+1) guards for the row's pair.
  ci = 0
  while ci < ncl
    if fcl[ci] == 3
      off = fcs[ci]
      neg = 0
      negv = 0
      p1 = 0
      p2 = 0
      j = 0
      while j < 3
        l = fla[off + j]
        if l < 0
          neg += 1
          negv = 0 - l
        elsif p1 == 0
          p1 = l
        else
          p2 = l
        j += 1
      if neg == 1 && p1 > 0 && p2 > 0
        lo = p1 < p2 ? p1 : p2
        hi = p1 < p2 ? p2 : p1
        if hi == lo + 1 && pflag[lo] > 0 && prow[lo] >= 0 && prow[lo] < ntrans
          r = prow[lo]
          if tvar[r] == 0 || negv < tvar[r]
            tvar[r] = negv
    ci += 1
  nmoves = 0
  r = 0
  while r < ntrans
    return nil if pvar[r] == 0 || tvar[r] == 0 || flag[r] == 0
    f = flag[r]
    if unitv[f] == -1
      active[r] = 1
      nmoves += 1
    elsif unitv[f] != 1
      return nil
    r += 1
  return nil if nmoves < 2

  # Check whether active moves form a prefix 0..nmoves-1 and input units on
  # (G, P, T) respect the point-reflection automorphism (r -> nmoves-1-r, c -> cols-1-c).
  mirror_sym = true
  r = 0
  while r < ntrans
    want_act = r < nmoves ? 1 : 0
    mirror_sym = false if active[r] != want_act
    r += 1
  r = 0
  while r < nmoves && mirror_sym
    rr = nmoves - 1 - r
    c = 0
    while c < cols
      ga = guard[r * cols + c]
      gb = guard[rr * cols + (cols - 1 - c)]
      mirror_sym = false if unitv[ga] != unitv[gb]
      c += 1
    k = 0
    while k < 2
      mirror_sym = false if unitv[pvar[r] + k] != unitv[pvar[rr] + k]
      k += 1
    k = 0
    while k < 3
      mirror_sym = false if unitv[tvar[r] + k] != unitv[tvar[rr] + k]
      k += 1
    r += 1

  {
    "cols": cols, "h": h, "rows": rows, "sbase": sbase,
    "stride": stride, "guard": guard, "pvar": pvar, "tvar": tvar,
    "flag": flag, "active": active, "nmoves": nmoves,
    "mirror_sym": mirror_sym, "unitv": unitv
  }

-> wassat_windmill_layout_text(lay)
  ntrans = lay["rows"] - 1
  active = lay["active"] ## i8[]
  pvar = lay["pvar"] ## i64[]
  tvar = lay["tvar"] ## i64[]
  flag = lay["flag"] ## i64[]
  guard = lay["guard"] ## i64[]
  s = "c windmill: cols=[lay["cols"]] h=[lay["h"]] rows=[lay["rows"]] sbase=[lay["sbase"]] stride=[lay["stride"]] moves=[lay["nmoves"]]\n"
  r = 0
  while r < ntrans
    s += "c windmill: row [r] p=[pvar[r]] t=[tvar[r]] flag=[flag[r]] active=[active[r]] g0=[guard[r * lay["cols"]]] glast=[guard[r * lay["cols"] + lay["cols"] - 1]]\n"
    r += 1
  s

-> wassat_windmill_miss
  { "recognized": false, "status": 0, "model": [],
    "bits": 0, "samples": 0, "tolerated": 0, "disagreements": 0, "trials": 0,
    "conflicts": 0, "decisions": 0, "props": 0,
    "cols": 0, "moves": 0, "mirror_clauses": 0 }

# Symmetry-restricted involution clauses: r -> nmoves-1-r, c -> cols-1-c.
-> wassat_windmill_mirror_clauses(lay)
  cols = lay["cols"]
  h = lay["h"]
  sbase = lay["sbase"]
  stride = lay["stride"]
  guard = lay["guard"] ## i64[]
  pvar = lay["pvar"] ## i64[]
  tvar = lay["tvar"] ## i64[]
  nmoves = lay["nmoves"]
  out = []
  r = 0
  while r + r < nmoves
    rr = nmoves - 1 - r
    c = 0
    while c < cols
      a = guard[r * cols + c]
      b = guard[rr * cols + (cols - 1 - c)]
      if a != b
        out.push([0 - a, b])
        out.push([a, 0 - b])
      c += 1
    if r != rr
      k = 0
      while k < 2
        out.push([0 - (pvar[r] + k), pvar[rr] + k])
        out.push([pvar[r] + k, 0 - (pvar[rr] + k)])
        k += 1
      k = 0
      while k < 3
        out.push([0 - (tvar[r] + k), tvar[rr] + k])
        out.push([tvar[r] + k, 0 - (tvar[rr] + k)])
        k += 1
    r += 1
  if nmoves % 2 == 0
    out.push([sbase + (nmoves / 2) * stride + 3 * h + 2])
  out

# Structurally recover V[0..rows-1, 0..npairs-1] monotone swap ladders,
# verify the complete resolution chain justifying 4-literal 2x2 rectangle
# clauses and 1D projected pair-cut clauses, and compile 64-bit pair-cut masks
# plus a flat V-free artifact. Returns nil when complete V ladders are absent.
-> wassat_windmill_recover_v(formula, lay)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  cols = lay["cols"]
  rows = lay["rows"]
  return nil if cols > 62 || rows > 60
  ntrans = rows - 1
  nmoves = lay["nmoves"]
  sbase = lay["sbase"]
  send = sbase + 3 * rows * cols - 1
  guard = lay["guard"] ## i64[]
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  npairs = (cols * (cols - 1)) / 2

  g_row = i64[nv + 2]
  g_col = i64[nv + 2]
  v = 0
  while v <= nv + 1
    g_row[v] = -1
    g_col[v] = -1
    v += 1
  r = 0
  while r < ntrans
    c = 0
    while c < cols
      gv = guard[r * cols + c]
      g_row[gv] = r
      g_col[gv] = c
      c += 1
    r += 1

  vcand_pos = i64[ntrans * npairs]
  vcand_neg = i64[ntrans * npairs]
  ci = 0
  while ci < ncl
    if fcl[ci] == 3
      off = fcs[ci]
      g0 = 0
      g1 = 0
      ng = 0
      other = 0
      j = 0
      while j < 3
        l = fla[off + j]
        if l < 0 && g_row[0 - l] >= 0 && ng < 2
          if ng == 0
            g0 = 0 - l
          else
            g1 = 0 - l
          ng += 1
        else
          other = l
        j += 1
      if ng == 2 && other != 0 && g_row[g0] == g_row[g1] && g_col[g0] != g_col[g1]
        rr = g_row[g0]
        p = wassat_windmill_pair_index(cols, g_col[g0], g_col[g1])
        ov = other < 0 ? 0 - other : other
        if !(ov >= sbase && ov <= send) && g_row[ov] < 0
          if other > 0
            vcand_pos[rr * npairs + p] = ov
          else
            vcand_neg[rr * npairs + p] = ov
    ci += 1

  vvar = i64[rows * npairs]
  v_pair = i64[nv + 2]
  v_row = i64[nv + 2]
  v = 0
  while v <= nv + 1
    v_pair[v] = -1
    v_row[v] = -1
    v += 1
  r = 0
  while r < ntrans
    p = 0
    while p < npairs
      vp = vcand_pos[r * npairs + p]
      return nil if vp < 1 || vp > nv
      vvar[r * npairs + p] = vp
      if r + 1 == ntrans
        vn = vcand_neg[r * npairs + p]
        return nil if vn < 1 || vn > nv
        vvar[(r + 1) * npairs + p] = vn
      p += 1
    r += 1
  r = 0
  while r < rows
    p = 0
    while p < npairs
      vv = vvar[r * npairs + p]
      return nil if v_pair[vv] >= 0
      v_pair[vv] = p
      v_row[vv] = r
      p += 1
    r += 1
  # Verify (-G[r,c1], -G[r,c2], -V[r+1,p]) matched V[r+1,p] on every active move.
  r = 0
  while r < nmoves
    p = 0
    while p < npairs
      return nil if vcand_neg[r * npairs + p] != vvar[(r + 1) * npairs + p]
      p += 1
    r += 1
  # Verify monotone ladder steps (+V[r,p], -V[r+1,p]) across all 0 <= r < ntrans
  # so V[0..rows-1, p] is strictly limited to the rows+1 monotone cuts 0..rows.
  ladder_seen = i8[ntrans * npairs]
  ci = 0
  while ci < ncl
    if fcl[ci] == 2
      off = fcs[ci]
      a = fla[off]
      b = fla[off + 1]
      posl = 0
      negl = 0
      if a > 0 && b < 0
        posl = a
        negl = 0 - b
      elsif b > 0 && a < 0
        posl = b
        negl = 0 - a
      if posl > 0 && v_pair[posl] >= 0 && v_pair[posl] == v_pair[negl]
        rp = v_row[posl]
        rn = v_row[negl]
        if rn == rp + 1 && rp >= 0 && rp < ntrans
          ladder_seen[rp * npairs + v_pair[posl]] = 1
    ci += 1
  idx = 0
  while idx < ntrans * npairs
    return nil if ladder_seen[idx] != 1
    idx += 1

  pair_c1 = i64[npairs]
  pair_c2 = i64[npairs]
  c1 = 0
  while c1 < cols
    c2 = c1 + 1
    while c2 < cols
      pi = wassat_windmill_pair_index(cols, c1, c2)
      pair_c1[pi] = c1
      pair_c2[pi] = c2
      c2 += 1
    c1 += 1

  # Pass 1: size V-free flat artifact and compiled pair-cut masks.
  one = 1 ## i64
  all_cuts = (one << (rows + 1)) - one
  vfree_ncl = 0
  vfree_nlits = 0
  pair_pc_cnt = i64[npairs]
  total_pc = 0
  total_pc_lits = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    p = -1
    nnv = 0
    km = all_cuts
    j = 0
    while j < n
      l = fla[off + j]
      av = l < 0 ? 0 - l : l
      vp = v_pair[av]
      if vp >= 0
        return nil if p >= 0 && p != vp
        p = vp
        rr = v_row[av]
        low = (one << (rr + 1)) - one
        fcuts = l > 0 ? low : (all_cuts ^ low)
        km = km & fcuts
      else
        nnv += 1
      j += 1
    if p < 0 || n == 1
      vfree_ncl += 1
      vfree_nlits += n
    if p >= 0 && km != 0 && nnv > 0
      return nil if nnv > 16
      pair_pc_cnt[p] += 1
      total_pc += 1
      total_pc_lits += nnv
    ci += 1

  vfree_fla = i64[vfree_nlits + 2]
  vfree_fcs = i64[vfree_ncl + 2]
  vfree_fcl = i64[vfree_ncl + 2]
  pair_pc_off = i64[npairs + 1]
  p = 0
  while p < npairs
    pair_pc_off[p + 1] = pair_pc_off[p] + pair_pc_cnt[p]
    pair_pc_cnt[p] = 0
    p += 1

  root_mask = i64[npairs]
  p = 0
  while p < npairs
    root_mask[p] = all_cuts
    p += 1
  pc_kill = i64[total_pc + 1]
  pc_lits_off = i64[total_pc + 1]
  pc_lits_len = i64[total_pc + 1]
  pc_lits = i64[total_pc_lits + 2]

  # Pass 2: fill V-free flat arrays and compiled pair-cut masks.
  vf_ci = 0
  vf_pos = 0
  pcl_pos = 0
  non_v = i64[16]
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    p = -1
    nnv = 0
    km = all_cuts
    j = 0
    while j < n
      l = fla[off + j]
      av = l < 0 ? 0 - l : l
      vp = v_pair[av]
      if vp >= 0
        p = vp
        rr = v_row[av]
        low = (one << (rr + 1)) - one
        fcuts = l > 0 ? low : (all_cuts ^ low)
        km = km & fcuts
      else
        non_v[nnv] = l if nnv < 16
        nnv += 1
      j += 1
    if p < 0 || n == 1
      vfree_fcs[vf_ci] = vf_pos
      vfree_fcl[vf_ci] = n
      j = 0
      while j < n
        vfree_fla[vf_pos + j] = fla[off + j]
        j += 1
      vf_pos += n
      vf_ci += 1
    if p >= 0 && km != 0
      if nnv == 0
        root_mask[p] = root_mask[p] ^ (root_mask[p] & km)
      else
        pcs = pair_pc_off[p] + pair_pc_cnt[p]
        pair_pc_cnt[p] += 1
        pc_kill[pcs] = km
        pc_lits_off[pcs] = pcl_pos
        pc_lits_len[pcs] = nnv
        j = 0
        while j < nnv
          pc_lits[pcl_pos + j] = non_v[j]
          j += 1
        pcl_pos += nnv
    ci += 1

  vfree_parse = {
    "nvars": nv, "clauses": [], "boxed": false,
    "flat_lits": vfree_fla, "flat_offs": vfree_fcs,
    "flat_lens": vfree_fcl, "flat_ncl": vfree_ncl,
    "flat_nlits": vfree_nlits
  }
  vfree_art = wassat_raw_artifact(vfree_parse, nv)

  # Point-reflection variable map on (P, T) for mirroring learned (P, T) cores.
  pt_mirror_var = i64[nv + 2]
  v = 1
  while v <= nv
    pt_mirror_var[v] = v
    v += 1
  pvar = lay["pvar"] ## i64[]
  tvar = lay["tvar"] ## i64[]
  pt_row_of = i64[nv + 2]
  v = 0
  while v <= nv + 1
    pt_row_of[v] = -1
    v += 1
  r = 0
  while r < nmoves
    rr = nmoves - 1 - r
    k = 0
    while k < 2
      pt_mirror_var[pvar[r] + k] = pvar[rr] + k
      pt_row_of[pvar[r] + k] = r
      k += 1
    k = 0
    while k < 3
      pt_mirror_var[tvar[r] + k] = tvar[rr] + k
      pt_row_of[tvar[r] + k] = r
      k += 1
    r += 1

  {
    "npairs": npairs, "vvar": vvar, "v_pair": v_pair, "v_row": v_row,
    "g_row": g_row, "g_col": g_col, "pair_c1": pair_c1, "pair_c2": pair_c2,
    "vfree_art": vfree_art, "vfree_parse": vfree_parse,
    "root_mask": root_mask, "pair_pc_off": pair_pc_off, "pc_kill": pc_kill,
    "pc_lits_off": pc_lits_off, "pc_lits_len": pc_lits_len, "pc_lits": pc_lits,
    "pt_mirror_var": pt_mirror_var, "pt_row_of": pt_row_of
  }

# Isolate the exact pure-(P, T) master subformula (row-mode clauses + global
# mode counters) by taint propagation from {G, S, V} across non-{P, T, flag}
# coordinates, returning a retired-variable Wassat master solver.
-> wassat_windmill_build_pt_master(formula, lay, vinfo)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  ntrans = lay["rows"] - 1
  cols = lay["cols"]
  sbase = lay["sbase"]
  send = sbase + 3 * lay["rows"] * cols - 1
  guard = lay["guard"] ## i64[]
  pvar = lay["pvar"] ## i64[]
  tvar = lay["tvar"] ## i64[]
  flag = lay["flag"] ## i64[]
  v_pair = vinfo["v_pair"] ## i64[]

  is_ptf = i8[nv + 2]
  tainted = i8[nv + 2]
  r = 0
  while r < ntrans
    is_ptf[pvar[r]] = 1
    is_ptf[pvar[r] + 1] = 1
    is_ptf[tvar[r]] = 1
    is_ptf[tvar[r] + 1] = 1
    is_ptf[tvar[r] + 2] = 1
    is_ptf[flag[r]] = 1 if flag[r] > 0
    c = 0
    while c < cols
      tainted[guard[r * cols + c]] = 1
      c += 1
    r += 1
  v = 1
  while v <= nv
    tainted[v] = 1 if (v >= sbase && v <= send) || v_pair[v] >= 0
    v += 1

  changed = true
  while changed
    changed = false
    ci = 0
    while ci < ncl
      n = fcl[ci]
      off = fcs[ci]
      touches = false
      j = 0
      while j < n
        av = fla[off + j]
        av = 0 - av if av < 0
        if tainted[av] == 1
          touches = true
          break
        j += 1
      if touches
        j = 0
        while j < n
          av2 = fla[off + j]
          av2 = 0 - av2 if av2 < 0
          if is_ptf[av2] == 0 && tainted[av2] == 0
            tainted[av2] = 1
            changed = true
          j += 1
      ci += 1

  m_ncl = 0
  m_nlits = 0
  used_m = i8[nv + 2]
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    ok = true
    j = 0
    while j < n
      av = fla[off + j]
      av = 0 - av if av < 0
      if tainted[av] == 1
        ok = false
        break
      j += 1
    if ok
      m_ncl += 1
      m_nlits += n
      j = 0
      while j < n
        av2 = fla[off + j]
        av2 = 0 - av2 if av2 < 0
        used_m[av2] = 1
        j += 1
    ci += 1
  return nil if m_ncl == 0

  m_fla = i64[m_nlits + 2]
  m_fcs = i64[m_ncl + 2]
  m_fcl = i64[m_ncl + 2]
  mi = 0
  mp = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    ok = true
    j = 0
    while j < n
      av = fla[off + j]
      av = 0 - av if av < 0
      if tainted[av] == 1
        ok = false
        break
      j += 1
    if ok
      m_fcs[mi] = mp
      m_fcl[mi] = n
      j = 0
      while j < n
        m_fla[mp + j] = fla[off + j]
        j += 1
      mp += n
      mi += 1
    ci += 1

  m_parse = {
    "nvars": nv, "clauses": [], "boxed": false,
    "flat_lits": m_fla, "flat_offs": m_fcs, "flat_lens": m_fcl,
    "flat_ncl": m_ncl, "flat_nlits": m_nlits
  }
  master = Wassat.from_flat(nv, wassat_raw_artifact(m_parse, nv), 0)
  master.disable_walk
  master.retire_absent_variables(used_m)
  master

# Native u64 row-bitboard 2x2 rectangle detector + 64-bit pair-cut mask
# evaluator. Populates:
#   rect_out[4*k .. 4*k+3] = new 4-literal rectangle cuts (count in st[0])
#   bad_pairs[0..st[1]-1]  = violated pair indices
#   order_bad[0..st[2]-1]  = non-rectangle violated pair indices
#   pair_kstar[0..npairs-1]= earliest valid cut position k* for satisfied pairs
#   row_hits[0..nmoves-1]  = conflict participation counts per active move
-> wassat_windmill_eval_native(mval, guard, g_row, root_mask, pair_pc_off,
                               pc_kill, pc_lits_off, pc_lits_len, pc_lits,
                               rect_seen, rect_out, rect_cap,
                               bad_pairs, order_bad, pair_kstar, row_hits,
                               cols, nmoves, npairs, st) (i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i8[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  one = 1 ## i64
  rbits = i64[nmoves + 1]
  r = 0
  while r < nmoves
    row_hits[r] = 0
    mask = 0 ## i64
    c = 0
    while c < cols
      if mval[guard[r * cols + c]] > 0
        mask = mask | (one << c)
      c += 1
    rbits[r] = mask
    r += 1

  is_rect = i8[npairs]
  cols_buf = i64[64]
  nrect = 0
  r1 = 0
  while r1 < nmoves
    r2 = r1 + 1
    while r2 < nmoves
      common = rbits[r1] & rbits[r2]
      if (common & (common - one)) != 0
        nc = 0
        tmp = common
        while tmp != 0
          cb = BitOps.trailing_zeros_u64(tmp)
          cols_buf[nc] = cb
          nc += 1
          tmp = tmp & (tmp - one)
        rpair_idx = r1 * nmoves + r2
        i = 0
        while i < nc
          j = i + 1
          while j < nc
            c1 = cols_buf[i]
            c2 = cols_buf[j]
            p = wassat_windmill_pair_index(cols, c1, c2)
            is_rect[p] = 1
            row_hits[r1] += 2
            row_hits[r2] += 2
            seen_idx = rpair_idx * npairs + p
            if rect_seen[seen_idx] == 0 && nrect < rect_cap
              rect_seen[seen_idx] = 1
              bo = nrect * 4
              rect_out[bo] = 0 - guard[r1 * cols + c1]
              rect_out[bo + 1] = 0 - guard[r1 * cols + c2]
              rect_out[bo + 2] = 0 - guard[r2 * cols + c1]
              rect_out[bo + 3] = 0 - guard[r2 * cols + c2]
              nrect += 1
            j += 1
          i += 1
      r2 += 1
    r1 += 1

  nbad = 0
  norder = 0
  fired = i64[128]
  p = 0
  while p < npairs
    m = root_mask[p]
    nf = 0
    pcs = pair_pc_off[p]
    pce = pair_pc_off[p + 1]
    while pcs < pce && m != 0
      km = pc_kill[pcs]
      if (m & km) != 0
        lo = pc_lits_off[pcs]
        ln = pc_lits_len[pcs]
        sat = false
        k = 0
        while k < ln
          l = pc_lits[lo + k]
          av = l < 0 ? 0 - l : l
          if (l > 0 ? mval[av] > 0 : mval[av] < 0)
            sat = true
            break
          k += 1
        unless sat
          m = m ^ (m & km)
          if nf < 128
            fired[nf] = pcs
            nf += 1
      pcs += 1
    if m == 0
      bad_pairs[nbad] = p
      nbad += 1
      if is_rect[p] == 0
        order_bad[norder] = p
        norder += 1
        fi = 0
        while fi < nf
          pcs2 = fired[fi]
          lo2 = pc_lits_off[pcs2]
          ln2 = pc_lits_len[pcs2]
          k = 0
          while k < ln2
            av2 = pc_lits[lo2 + k]
            av2 = 0 - av2 if av2 < 0
            gr = g_row[av2]
            row_hits[gr] += 1 if gr >= 0 && gr < nmoves
            k += 1
          fi += 1
    else
      pair_kstar[p] = BitOps.trailing_zeros_u64(m)
    p += 1

  st[0] = nrect
  st[1] = nbad
  st[2] = norder
  0

# For each non-rectangle violated pair p in order_bad[0..norder-1], compute a
# greedy minimal bitmask set-cover of root_mask[p] from the falsified V-clauses
# of pair p and emit the resulting short (<= 10 literal), deduplicated (G, S)
# projected pair-cut conflict clause. Every emitted clause is a sound
# propositional resolution consequence along V[0..rows-1, p].
-> wassat_windmill_project_pair_cuts(mval, order_bad, norder, root_mask,
                                     pair_pc_off, pc_kill, pc_lits_off,
                                     pc_lits_len, pc_lits, proj_seen, max_emit = 64)
  out = []
  fired = i64[128]
  chosen = i64[6]
  lbuf = i64[24]
  hlen = proj_seen.size
  oi = 0
  while oi < norder && out.size < max_emit
    p = order_bad[oi]
    rm = root_mask[p]
    if rm != 0
      nf = 0
      cov = 0 ## i64
      pcs = pair_pc_off[p]
      pce = pair_pc_off[p + 1]
      while pcs < pce && nf < 128
        km = pc_kill[pcs]
        if (rm & km) != 0
          lo = pc_lits_off[pcs]
          ln = pc_lits_len[pcs]
          sat = false
          k = 0
          while k < ln
            l = pc_lits[lo + k]
            av = l < 0 ? 0 - l : l
            if (l > 0 ? mval[av] > 0 : mval[av] < 0)
              sat = true
              break
            k += 1
          unless sat
            fired[nf] = pcs
            nf += 1
            cov = cov | (rm & km)
        pcs += 1
      if cov == rm
        uncov = rm
        nch = 0
        while uncov != 0 && nch < 4
          best_pcs = -1
          best_gain = 0
          fi = 0
          while fi < nf
            pcs2 = fired[fi]
            gain = BitOps.count_ones_u64(uncov & pc_kill[pcs2])
            if gain > best_gain
              best_gain = gain
              best_pcs = pcs2
            fi += 1
          break if best_pcs < 0
          chosen[nch] = best_pcs
          nch += 1
          uncov = uncov ^ (uncov & pc_kill[best_pcs])
        if uncov == 0 && nch > 0
          nl = 0
          taut = false
          ci = 0
          while ci < nch && !taut
            pcs3 = chosen[ci]
            lo3 = pc_lits_off[pcs3]
            ln3 = pc_lits_len[pcs3]
            k = 0
            while k < ln3
              l = pc_lits[lo3 + k]
              dup = false
              q = 0
              while q < nl
                if lbuf[q] == 0 - l
                  taut = true
                  break
                elsif lbuf[q] == l
                  dup = true
                  break
                q += 1
              break if taut
              unless dup
                if nl < 10
                  lbuf[nl] = l
                  nl += 1
                else
                  taut = true
                  break
              k += 1
            ci += 1
          if !taut && nl >= 1 && nl <= 10
            # Insertion-sort literals for canonical deduplication hashing.
            a = 1
            while a < nl
              key = lbuf[a]
              b = a - 1
              while b >= 0 && lbuf[b] > key
                lbuf[b + 1] = lbuf[b]
                b -= 1
              lbuf[b + 1] = key
              a += 1
            h = 1469598103934665603 ## i64
            a = 0
            while a < nl
              h = (h ^ (lbuf[a] + 1000003)) * 1099511628211
              a += 1
            h = 0 - h if h < 0
            h = 1 if h == 0
            is_new = true
            if hlen > 0
              slot = h % hlen
              probes = 0
              while probes < 8
                cur = proj_seen[slot]
                if cur == h
                  is_new = false
                  break
                elsif cur == 0
                  proj_seen[slot] = h
                  break
                slot = (slot + 1) % hlen
                probes += 1
              proj_seen[slot] = h if probes == 8 && is_new
            if is_new
              cl = []
              a = 0
              while a < nl
                cl.push(lbuf[a])
                a += 1
              out.push(cl)
    oi += 1
  out

# Build prioritized variable lists for VMTF / EVSIDS steering:
#   pt_vars:   all active P and T variables (110 vars on p61)
#   ptg_vars:  active P and T first, then active guard G variables (1,452 vars on p61)
#   ptgs_vars: active P, T, G, and state S variables (5,844 primary vars on p61)
-> wassat_windmill_var_orders(nv, lay, vinfo)
  cols = lay["cols"]
  rows = lay["rows"]
  sbase = lay["sbase"]
  send = sbase + 3 * rows * cols - 1
  nmoves = lay["nmoves"]
  guard = lay["guard"] ## i64[]
  pvar = lay["pvar"] ## i64[]
  tvar = lay["tvar"] ## i64[]
  seen = i8[nv + 2]
  pt_vars = []
  ptg_vars = []
  ptgs_vars = []
  r = 0
  while r < nmoves
    k = 0
    while k < 2
      vp = pvar[r] + k
      if seen[vp] == 0
        seen[vp] = 1
        pt_vars.push(vp)
        ptg_vars.push(vp)
        ptgs_vars.push(vp)
      k += 1
    k = 0
    while k < 3
      vt = tvar[r] + k
      if seen[vt] == 0
        seen[vt] = 1
        pt_vars.push(vt)
        ptg_vars.push(vt)
        ptgs_vars.push(vt)
      k += 1
    r += 1
  r = 0
  while r < nmoves
    c = 0
    while c < cols
      gv = guard[r * cols + c]
      if seen[gv] == 0
        seen[gv] = 1
        ptg_vars.push(gv)
        ptgs_vars.push(gv)
      c += 1
    r += 1
  v = sbase
  while v <= send
    if seen[v] == 0
      seen[v] = 1
      ptgs_vars.push(v)
    v += 1
  { "pt_vars": pt_vars, "ptg_vars": ptg_vars, "ptgs_vars": ptgs_vars }

# Charge only per-call counter deltas from incremental coordinator solvers.
-> wassat_windmill_charge(res, prev, base, stats)
  dc = res["conflicts"] - prev[base]
  dd = res["decisions"] - prev[base + 1]
  dp = res["props"] - prev[base + 2]
  prev[base] = res["conflicts"]
  prev[base + 1] = res["decisions"]
  prev[base + 2] = res["props"]
  stats[0] += dc if dc > 0
  stats[1] += dd if dd > 0
  stats[2] += dp if dp > 0
  0

# Shrink a failed-assumption (P, T) core on `shrink_solver` (4 chunk probes),
# then record the negated blocking clause (plus its time-reversed mirror when
# lay["mirror_sym"] holds) permanently into master, vfree_oracle, refute_oracle,
# and `out_clauses`.
-> wassat_windmill_record_pt_core(core, shrink_solver, prev_base, lay, vinfo,
                                  coord, out_clauses, stats)
  return 0 if core.empty?
  prev = coord["prev"] ## i64[]
  cur = core
  ch = 0
  while ch < 4 && cur.size > 4
    n = cur.size
    lo = (ch * n) / 4
    hi = ((ch + 1) * n) / 4
    sub = []
    i = 0
    while i < n
      sub.push(cur[i]) if i < lo || i >= hi
      i += 1
    sr = shrink_solver.solve_assuming_budget(sub, 700)
    wassat_windmill_charge(sr, prev, prev_base, stats)
    cur = sr["core"] if sr["status"] == -1 && !sr["core"].empty?
    ch += 1

  bcl = []
  i = 0
  while i < cur.size
    bcl.push(0 - cur[i])
    i += 1
  master = coord["master"]
  vfree_o = coord["vfree"]
  refute_o = coord["refute"]
  master.install_pruning_clause(bcl, false, true) if master != nil
  vfree_o.install_pruning_clause(bcl, false, true)
  refute_o.install_pruning_clause(bcl, false, true)
  out_clauses.push(bcl)

  if lay["mirror_sym"] == true && vinfo != nil
    pt_mirror = vinfo["pt_mirror_var"] ## i64[]
    mbcl = []
    diff = false
    i = 0
    while i < bcl.size
      l = bcl[i]
      av = l < 0 ? 0 - l : l
      mv = pt_mirror[av]
      ml = l > 0 ? mv : 0 - mv
      diff = true if ml != l
      mbcl.push(ml)
      i += 1
    if diff
      master.install_pruning_clause(mbcl, false, true) if master != nil
      vfree_o.install_pruning_clause(mbcl, false, true)
      refute_o.install_pruning_clause(mbcl, false, true)
      out_clauses.push(mbcl)
  1

# Core-guided column + free-(P, T) neighborhood repair around a low-nbad
# @best_phase incumbent:
#   1. Free the greedy vertex cover of `bad_pairs` PLUS any column whose 3-lit
#      state carry-over clause (G[r,c], -S[r,c], S[r+1,c]) is falsified in mval,
#      while permitting ALL (P, T) row modes to change.
#   2. Expand the freed column neighborhood via failed-assumption cores.
#   3. Also test (P*, T*) and its top-2 conflict-hit d=1 row cones on
#      vfree_oracle -> refute_oracle to harvest short (P, T) + mirror cores.
-> wassat_windmill_repair_incumbent(formula, lay, vinfo, mval, bad_pairs, nbad,
                                    pair_kstar, row_hits, coord, new_clauses,
                                    stats, cap)
  nv = formula["nvars"]
  cols = lay["cols"]
  rows = lay["rows"]
  nmoves = lay["nmoves"]
  guard = lay["guard"] ## i64[]
  pvar = lay["pvar"] ## i64[]
  tvar = lay["tvar"] ## i64[]
  unitv = lay["unitv"] ## i8[]
  npairs = vinfo["npairs"]
  vvar = vinfo["vvar"] ## i64[]
  g_col = vinfo["g_col"] ## i64[]
  pair_c1 = vinfo["pair_c1"] ## i64[]
  pair_c2 = vinfo["pair_c2"] ## i64[]
  prev = coord["prev"] ## i64[]
  vfree_o = coord["vfree"]
  refute_o = coord["refute"]

  # Reconstruct V[0..rows-1, p] phases from surviving pair_kstar cuts.
  is_bad = i8[npairs]
  bi = 0
  while bi < nbad
    is_bad[bad_pairs[bi]] = 1
    bi += 1
  p = 0
  while p < npairs
    ks = is_bad[p] == 0 ? pair_kstar[p] : (nmoves / 2)
    r = 0
    while r < rows
      mval[vvar[r * npairs + p]] = r < ks ? 1 : -1
      r += 1
    p += 1
  ph = []
  v = 1
  while v <= nv
    ph.push(mval[v] >= 0 ? v : 0 - v)
    v += 1
  refute_o.set_phases(ph)
  vfree_o.set_phases(ph)

  # Greedy vertex cover of bad_pairs + columns with falsified 3-literal
  # carry-over clauses in mval.
  free_col = i8[cols]
  nfree_c = 0
  uncov = i8[nbad]
  rem_e = nbad
  while rem_e > 0
    deg = i64[cols]
    bi = 0
    while bi < nbad
      if uncov[bi] == 0
        bp = bad_pairs[bi]
        deg[pair_c1[bp]] += 1
        deg[pair_c2[bp]] += 1
      bi += 1
    best_c = -1
    best_d = 0
    c = 0
    while c < cols
      if free_col[c] == 0 && deg[c] > best_d
        best_d = deg[c]
        best_c = c
      c += 1
    break if best_c < 0
    free_col[best_c] = 1
    nfree_c += 1
    bi = 0
    while bi < nbad
      if uncov[bi] == 0
        bp = bad_pairs[bi]
        if pair_c1[bp] == best_c || pair_c2[bp] == best_c
          uncov[bi] = 1
          rem_e -= 1
      bi += 1

  vf_parse = vinfo["vfree_parse"]
  vf_ncl = vf_parse["flat_ncl"]
  vf_fla = vf_parse["flat_lits"] ## i64[]
  vf_fcs = vf_parse["flat_offs"] ## i64[]
  vf_fcl = vf_parse["flat_lens"] ## i64[]
  ci = 0
  while ci < vf_ncl
    n = vf_fcl[ci]
    if n <= 3
      off = vf_fcs[ci]
      sat = false
      g_hit = -1
      j = 0
      while j < n
        l = vf_fla[off + j]
        av = l < 0 ? 0 - l : l
        if (l > 0 ? mval[av] > 0 : mval[av] < 0)
          sat = true
          break
        gc = g_col[av]
        g_hit = gc if gc >= 0
        j += 1
      if !sat && g_hit >= 0 && free_col[g_hit] == 0
        free_col[g_hit] = 1
        nfree_c += 1
    ci += 1

  step = 0
  while step < 3 && nfree_c < cols && stats[0] + 10000 < cap
    assumes = []
    c = 0
    while c < cols
      if free_col[c] == 0
        r = 0
        while r < nmoves
          gv = guard[r * cols + c]
          if unitv[gv] == 0
            assumes.push(mval[gv] > 0 ? gv : 0 - gv)
          r += 1
      c += 1
    break if assumes.empty?
    er = refute_o.solve_assuming_budget(assumes, 10000)
    wassat_windmill_charge(er, prev, 3, stats)
    if er["status"] == 1
      return er["model"] if wassat_model_satisfies?(formula, er["model"])
      break
    elsif er["status"] == -1 && !er["core"].empty?
      core = er["core"]
      if core.size <= 16
        bcl_g = []
        i = 0
        while i < core.size
          bcl_g.push(0 - core[i])
          i += 1
        vfree_o.install_pruning_clause(bcl_g, false, true)
        new_clauses.push(bcl_g)
      col_hits = i64[cols]
      i = 0
      while i < core.size
        av = core[i]
        av = 0 - av if av < 0
        cc = g_col[av]
        col_hits[cc] += 1 if cc >= 0
        i += 1
      added = 0
      while added < 3
        bc = -1
        bh = 0
        c = 0
        while c < cols
          if free_col[c] == 0 && col_hits[c] > bh
            bh = col_hits[c]
            bc = c
          c += 1
        break if bc < 0
        free_col[bc] = 1
        nfree_c += 1
        added += 1
      break if added == 0
    else
      coord["best_inc"] = ph
      break
    step += 1

  # Test incumbent (P*, T*) and top-2 conflict-hit d=1 cones on vfree -> refute.
  inc_p = i64[nmoves]
  inc_t = i64[nmoves]
  pt_star = []
  r = 0
  while r < nmoves
    inc_p[r] = mval[pvar[r]] > 0 ? 0 : 1
    inc_t[r] = mval[tvar[r]] > 0 ? 0 : (mval[tvar[r] + 1] > 0 ? 1 : 2)
    pt_star.push(pvar[r] + inc_p[r])
    pt_star.push(tvar[r] + inc_t[r])
    r += 1
  master = coord["master"]
  master.set_phases(pt_star) if master != nil

  if stats[0] + 8000 < cap
    vr0 = vfree_o.solve_assuming_budget(pt_star, 8000)
    wassat_windmill_charge(vr0, prev, 0, stats)
    if vr0["status"] == -1 && !vr0["core"].empty?
      wassat_windmill_record_pt_core(
        vr0["core"], vfree_o, 0, lay, vinfo, coord, new_clauses, stats
      )
    elsif stats[0] + 14000 < cap
      rr0 = refute_o.solve_assuming_budget(pt_star, 14000)
      wassat_windmill_charge(rr0, prev, 3, stats)
      if rr0["status"] == 1
        return rr0["model"] if wassat_model_satisfies?(formula, rr0["model"])
      elsif rr0["status"] == -1 && !rr0["core"].empty?
        wassat_windmill_record_pt_core(
          rr0["core"], refute_o, 3, lay, vinfo, coord, new_clauses, stats
        )
      else
        coord["survivor_pt"] = pt_star

  # Probe top-2 conflict-hit single-row releases (21 of 22 rows assumed).
  used_r = i8[nmoves]
  cone = 0
  while cone < 2 && nmoves > 4 && stats[0] + 8000 < cap
    best_r = -1
    best_h = -1
    r = 0
    while r < nmoves
      if used_r[r] == 0 && row_hits[r] > best_h
        best_h = row_hits[r]
        best_r = r
      r += 1
    break if best_r < 0
    used_r[best_r] = 1
    sub = []
    r = 0
    while r < nmoves
      if r != best_r
        sub.push(pvar[r] + inc_p[r])
        sub.push(tvar[r] + inc_t[r])
      r += 1
    vr1 = vfree_o.solve_assuming_budget(sub, 6000)
    wassat_windmill_charge(vr1, prev, 0, stats)
    if vr1["status"] == -1 && !vr1["core"].empty?
      wassat_windmill_record_pt_core(
        vr1["core"], vfree_o, 0, lay, vinfo, coord, new_clauses, stats
      )
    elsif stats[0] + 10000 < cap
      rr1 = refute_o.solve_assuming_budget(sub, 10000)
      wassat_windmill_charge(rr1, prev, 3, stats)
      if rr1["status"] == 1
        return rr1["model"] if wassat_model_satisfies?(formula, rr1["model"])
      elsif rr1["status"] == -1 && !rr1["core"].empty?
        wassat_windmill_record_pt_core(
          rr1["core"], refute_o, 3, lay, vinfo, coord, new_clauses, stats
        )
    cone += 1
  []

# Explore `max_trials` candidate (P, T) words from the 220-var master solver,
# filtering through vfree_oracle -> refute_oracle, recording shrunk + mirrored
# (P, T) cores, and saving unrefuted survivors to steer Arm 3.
-> wassat_windmill_master_step(formula, lay, vinfo, coord, new_clauses,
                               stats, cap, max_trials)
  master = coord["master"]
  return [] if master == nil || coord["master_exhausted"] == true
  nmoves = lay["nmoves"]
  pvar = lay["pvar"] ## i64[]
  tvar = lay["tvar"] ## i64[]
  prev = coord["prev"] ## i64[]
  vfree_o = coord["vfree"]
  refute_o = coord["refute"]

  t = 0
  while t < max_trials && stats[0] + 15000 < cap
    trial_id = coord["master_trials"]
    coord["master_trials"] = trial_id + 1
    if trial_id > 0 && trial_id % 6 == 0
      master.reseed_phases(10007 + trial_id * 7919, true)
    mres = master.solve_budget(0)
    wassat_windmill_charge(mres, prev, 6, stats)
    if mres["status"] != 1
      coord["master_exhausted"] = true
      break
    mmod = mres["model"]
    pt_cand = []
    ord = trial_id % 3
    idx = 0
    while idx < nmoves
      r = ord == 0 ? idx : (ord == 1 ? (nmoves - 1 - idx) : ((idx % 2 == 0) ? (idx / 2) : (nmoves - 1 - idx / 2)))
      p0 = pvar[r]
      t0v = tvar[r]
      ip = mmod[p0 - 1] > 0 ? 0 : 1
      it = mmod[t0v - 1] > 0 ? 0 : (mmod[t0v] > 0 ? 1 : 2)
      pt_cand.push(p0 + ip)
      pt_cand.push(t0v + it)
      idx += 1

    vr = vfree_o.solve_assuming_budget(pt_cand, 8000)
    wassat_windmill_charge(vr, prev, 0, stats)
    if vr["status"] == -1 && !vr["core"].empty?
      wassat_windmill_record_pt_core(
        vr["core"], vfree_o, 0, lay, vinfo, coord, new_clauses, stats
      )
    else
      or1 = refute_o.solve_assuming_budget(pt_cand, 15000)
      wassat_windmill_charge(or1, prev, 3, stats)
      if or1["status"] == 1
        return or1["model"] if wassat_model_satisfies?(formula, or1["model"])
      elsif or1["status"] == -1 && !or1["core"].empty?
        wassat_windmill_record_pt_core(
          or1["core"], refute_o, 3, lay, vinfo, coord, new_clauses, stats
        )
      else
        coord["survivor_pt"] = pt_cand
        # Block this exact unrefuted word in master so subsequent trials keep
        # exploring distinct (P, T) modes while the --sat portfolio searches it.
        bcl = []
        i = 0
        while i < pt_cand.size
          bcl.push(0 - pt_cand[i])
          i += 1
        master.install_pruning_clause(bcl, false, true)
    t += 1
  []

# Size parallel --sat arms safely against BOTH System.physical_memory_bytes and
# Tungsten's runtime memory ceiling (default 8.0 GiB TUNGSTEN_MEMORY_LIMIT).
-> wassat_windmill_arm_count(nv, ncl, extra_arenas)
  wanted = System.cpu_count
  wanted = 8 if wanted > 8
  wanted = 1 if wanted < 1
  if env("WASSAT_ARMS") != nil
    ea = env("WASSAT_ARMS").to_i
    wanted = ea if ea >= 1 && ea <= 8
    return wanted if ea >= 1 && ea <= 8
  # Measured RSS per full-CNF solver on 758k clauses / 73k vars is ~220 MiB;
  # budget ~270 MiB at that scale and stay under 58% of TUNGSTEN_MEMORY_LIMIT
  # (default 8 GiB -> ~4.86 GiB arena ceiling, ~2.4 GiB actual RSS for 8 arms).
  per_solver = ncl * 280 + nv * 340 + 25165824
  # Default TUNGSTEN_MEMORY_LIMIT is 8 GiB (8,589,934,592 bytes); keep total
  # resident solver arenas below 58% (~4.86 GiB) so peak RSS stays ~4.0 GiB.
  rt_limit = 8589934592
  if env("TUNGSTEN_MEMORY_LIMIT") != nil
    el = env("TUNGSTEN_MEMORY_LIMIT").to_i
    rt_limit = el if el > 268435456
  budget_bytes = (rt_limit / 100) * 58
  phys = System.physical_memory_bytes
  if phys > 0
    phys_budget = (phys * 3) / 5
    budget_bytes = phys_budget if phys_budget < budget_bytes
  while wanted > 1 && (wanted + extra_arenas) * per_solver > budget_bytes
    wanted -= 1
  wanted

-> wassat_windmill_configure_arm(s, arm_idx, orders, reseed_gen)
  pt_vars = orders["pt_vars"]
  ptg_vars = orders["ptg_vars"]
  ptgs_vars = orders["ptgs_vars"]
  slot = arm_idx % 8
  if slot == 0
    # Exact Kissat --sat baseline: reversed VMTF (nv..1), target=2, All-UIP
    # shrinking, Luby 1024 stable alternation, and CCAnr walk rephasing.
    s.enable_sat_preset(50, 1000, 11, 10, 1024)
    s.reverse_vmtf_queue
    s.enable_shrink
    s.reseed_phases(200009 + reseed_gen * 15485863, true) if reseed_gen > 0
  elsif slot == 1
    # Two-tier (P, T, G, S)-primary strong-backdoor --sat + walk rephasing:
    # prevents auxiliary V/C ladders from preempting state/grid decisions.
    s.enable_sat_preset(50, 1000, 11, 10, 1024)
    s.reseed_phases(100003 + reseed_gen * 7919, true) if reseed_gen > 0
    s.set_primary_decision_vars(ptgs_vars)
  elsif slot == 2
    # Kissat --sat + (P, T, G) head promotion + CCAnr walk rephasing.
    s.enable_sat_preset(50, 1000, 11, 10, 1024)
    s.reseed_phases(300017 + reseed_gen * 104729, true) if reseed_gen > 0
    s.promote_control_vars(ptg_vars)
  elsif slot == 3
    # Pure focused (--stable=0 --target=2), 5% cardinality LBD margin, chrono,
    # (P, T, G) head; receives surviving (P, T) mode candidates at barriers.
    s.disable_walk
    s.enable_focused_only
    s.enable_sat_preset(50, 1000, 21, 20, 0)
    s.enable_chrono
    s.reseed_phases(7771337 + reseed_gen * 15485863, true)
    s.promote_control_vars(ptg_vars)
  elsif slot == 4
    # Alternating --sat + All-UIP shrink + OTFS + equivalent-literal subst.
    s.disable_walk
    s.enable_sat_preset(50, 900, 11, 10, 1024)
    s.enable_shrink
    s.enable_otfs
    s.reseed_phases(20261029 + reseed_gen * 15485863, true)
    s.promote_control_vars(pt_vars)
    s.simplify_raw_mode(0)
  elsif slot == 5
    # Focused (P, T, G, S)-primary + All-UIP shrink + OTFS + walk rephasing.
    s.enable_focused_only
    s.enable_sat_preset(40, 900, 11, 10, 0)
    s.enable_shrink
    s.enable_otfs
    s.reseed_phases(5151517 + reseed_gen * 104729, true)
    s.set_primary_decision_vars(ptgs_vars)
  elsif slot == 6
    # EVSIDS + Luby 2048 stable + chrono + walk rephasing.
    s.enable_sat_preset(64, 1000, 11, 10, 2048)
    s.disable_vmtf
    s.enable_chrono
    s.reseed_phases(6060607 + reseed_gen * 15485863, true) if reseed_gen > 0
    s.promote_control_vars(ptg_vars)
  else
    # Pure focused + Kissat reversed VMTF + 5% margin + All-UIP shrink.
    s.disable_walk
    s.enable_focused_only
    s.enable_sat_preset(50, 1000, 21, 20, 0)
    s.reverse_vmtf_queue
    s.enable_shrink
    s.reseed_phases(918273645 + reseed_gen * 15485863, true)
  0

-> wassat_windmill_arm_round(solver, res, base, slice, tel, tbase)
  t0 = ccall("__w_clock_ms")
  solver.solve_shared_budget(res, base, slice)
  solver.export_telemetry(tel, tbase)
  tel[tbase + 7] = tel[tbase + 7] + (ccall("__w_clock_ms") - t0)
  0

-> wassat_windmill_solve(formula, result, total_budget = 0)
  miss = wassat_windmill_miss
  return miss unless formula.has_key?("flat_ncl")
  lay = wassat_windmill_recognize(formula)
  return miss if lay == nil
  tprof = wassat_prof_clock
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]

  cap = WASSAT_WINDMILL_DEFAULT_CAP
  cap = env("WASSAT_WINDMILL_CAP").to_i if env("WASSAT_WINDMILL_CAP") != nil
  if total_budget > 0 && (cap <= 0 || total_budget < cap)
    cap = total_budget
  out = {
    "recognized": true, "status": 0, "model": [],
    "bits": 0, "samples": 0, "tolerated": 0, "disagreements": 0, "trials": 0,
    "conflicts": 0, "decisions": 0, "props": 0,
    "cols": lay["cols"], "moves": lay["nmoves"], "mirror_clauses": 0
  }
  return out if cap <= 0

  extra = wassat_windmill_mirror_clauses(lay)
  out["mirror_clauses"] = extra.size
  stats = i64[3]

  # Stage 1: fast bounded mirror-involution probe (< 0.4s on asymmetric p61,
  # immediate win on palindromic windmills).
  raw_art = wassat_raw_artifact(formula, nv)
  mirror_cap = WASSAT_WINDMILL_MIRROR_PROBE_CONFLICTS
  mirror_cap = env("WASSAT_WINDMILL_MIRROR_CAP").to_i if env("WASSAT_WINDMILL_MIRROR_CAP") != nil
  mirror_cap = cap if mirror_cap > cap
  ran_mirror = false
  if mirror_cap > 0
    ran_mirror = true
    msolver = Wassat.from_flat(nv, raw_art, 0)
    msolver.disable_walk
    msolver.enable_sat_preset(50, 1000, 11, 10, 1024)
    i = 0
    while i < extra.size
      msolver.install_pruning_clause(extra[i], false, true)
      i += 1
    mres = msolver.solve_budget(mirror_cap)
    stats[0] += mres["conflicts"]
    stats[1] += mres["decisions"]
    stats[2] += mres["props"]
    tprof = wassat_prof("windmill.mirror_probe", tprof)
    if mres["status"] == 1 && wassat_model_satisfies?(formula, mres["model"])
      out["status"] = 1
      out["model"] = mres["model"]
      out["conflicts"] = stats[0]
      out["decisions"] = stats[1]
      out["props"] = stats[2]
      return out

  if stats[0] >= cap
    out["conflicts"] = stats[0]
    out["decisions"] = stats[1]
    out["props"] = stats[2]
    return out

  # Stage 2: syntactic structural pruning + (P, T) master / V-free flux oracle /
  # full-CNF refutation & neighborhood-repair oracle + multi-arm --sat race.
  prune_info = nil
  if env("WASSAT_STRUCTURAL_PRUNE") != "0" && nv <= 150000 && ncl <= 1000000
    prune_info = wassat_structural_prune(nv, formula)
  vinfo = wassat_windmill_recover_v(formula, lay)
  orders = wassat_windmill_var_orders(nv, lay, vinfo)

  global_cuts = []
  coord = nil
  if vinfo != nil && cap - stats[0] >= 50000
    npairs = vinfo["npairs"]
    nmoves = lay["nmoves"]
    master_solver = wassat_windmill_build_pt_master(formula, lay, vinfo)

    vfree_oracle = Wassat.from_flat(nv, vinfo["vfree_art"], 0)
    vfree_oracle.disable_walk
    vfree_oracle.enable_chrono
    # Assumption oracles: mid-search substitution would park assumable
    # variables at the root.
    vfree_oracle.disable_substitution

    refute_oracle = Wassat.from_flat(nv, raw_art, 0)
    refute_oracle.disable_walk
    refute_oracle.enable_chrono
    refute_oracle.disable_substitution
    wassat_apply_structural_pruning(refute_oracle, prune_info, 0, false) if prune_info != nil

    coord = {
      "master": master_solver, "master_exhausted": false, "master_trials": 0,
      "vfree": vfree_oracle, "refute": refute_oracle, "prev": i64[9],
      "mval": i8[nv + 2], "best_mval": i8[nv + 2], "best_nbad": npairs + 1,
      "rect_seen": i8[nmoves * nmoves * npairs], "proj_seen": i64[8192],
      "rect_out": i64[1024 * 4], "bad_pairs": i64[npairs],
      "order_bad": i64[npairs], "pair_kstar": i64[npairs],
      "row_hits": i64[nmoves], "best_bad_pairs": i64[npairs],
      "best_kstar": i64[npairs], "best_row_hits": i64[nmoves],
      "best_inc": [], "survivor_pt": []
    }
    # Quick initial (P, T) master pass (4 candidates) to harvest early flux and
    # mirror cores before launching the parallel --sat arms.
    imodel = wassat_windmill_master_step(
      formula, lay, vinfo, coord, global_cuts, stats, cap, 4
    )
    tprof = wassat_prof("windmill.master_init", tprof)
    unless imodel.empty?
      out["status"] = 1
      out["model"] = imodel
      out["conflicts"] = stats[0]
      out["decisions"] = stats[1]
      out["props"] = stats[2]
      return out

  rem_budget = cap - stats[0]
  if rem_budget <= 0
    out["conflicts"] = stats[0]
    out["decisions"] = stats[1]
    out["props"] = stats[2]
    return out

  extra_arenas = ran_mirror ? 1 : 0
  extra_arenas += 2 if coord != nil
  n_arms = wassat_windmill_arm_count(nv, ncl, extra_arenas)
  n_arms = 1 if rem_budget < 25000

  stop = i64[4]
  res_stride = nv + 8
  res = i64[n_arms * res_stride]
  tel_stride = 8
  tel = i64[n_arms * tel_stride]
  prev_tel = i64[n_arms * tel_stride]
  ring_cap = 4096
  ring_maxlen = 24
  ring = i64[8 + ring_cap * (3 + ring_maxlen)]
  budget_state = i64[n_arms + 2]

  solvers = []
  a = 0
  while a < n_arms
    s = Wassat.from_flat(nv, raw_art, 0)
    wassat_apply_structural_pruning(s, prune_info, 0, false) if prune_info != nil
    ci = 0
    while ci < global_cuts.size
      s.install_pruning_clause(global_cuts[ci], false, true)
      ci += 1
    wassat_windmill_configure_arm(s, a, orders, 0)
    if a == 3 && coord != nil && !coord["survivor_pt"].empty?
      s.set_phases(coord["survivor_pt"])
    s.enable_fixed_caps
    s.set_stop_cell(stop)
    if n_arms > 1
      s.enable_sharing(ring, ring_cap, ring_maxlen, a, true)
      s.set_share_lbd(3)
    s.set_shared_conflict_budget(budget_state, rem_budget, a + 1)
    solvers.push(s)
    a += 1

  reseed_gen = 0
  running = true
  while running
    used_before = ccall("__w_arr_load_acq", budget_state, 0)
    avail = rem_budget - used_before
    if avail <= 0
      running = false
    else
      slice = WASSAT_WINDMILL_ROUND_SLICE
      slice = avail if avail < slice
      handles = []
      a = 0
      while a < n_arms
        arm_solver = solvers[a]
        base = a * res_stride
        tbase = a * tel_stride
        if n_arms == 1
          wassat_windmill_arm_round(arm_solver, res, base, slice, tel, tbase)
        else
          handles.push(Thread.new -> wassat_windmill_arm_round(
            arm_solver, res, base, slice, tel, tbase
          ))
        a += 1
      # Process-global inline caches: main thread ONLY joins while workers run.
      handles.each -> (h)
        z = h.join

      # Barrier: accumulate telemetry and check for a verified SAT winner.
      winner_arm = -1
      any_progress = false
      a = 0
      while a < n_arms
        tb = a * tel_stride
        dconf = tel[tb] - prev_tel[tb]
        ddec = tel[tb + 1] - prev_tel[tb + 1]
        dprop = tel[tb + 2] - prev_tel[tb + 2]
        stats[0] += dconf
        stats[1] += ddec
        stats[2] += dprop
        any_progress = true if dconf > 0
        k = 0
        while k < tel_stride
          prev_tel[tb + k] = tel[tb + k]
          k += 1
        winner_arm = a if res[a * res_stride] == 1 && winner_arm < 0
        a += 1

      if winner_arm >= 0
        wbase = winner_arm * res_stride
        wmodel = []
        v = 1
        while v <= nv
          wmodel.push(res[wbase + v] == 1 ? v : 0 - v)
          v += 1
        if wassat_model_satisfies?(formula, wmodel)
          out["status"] = 1
          out["model"] = wmodel
          out["conflicts"] = stats[0]
          out["decisions"] = stats[1]
          out["props"] = stats[2]
          tprof = wassat_prof("windmill.sat_race", tprof)
          return out

      used_race = ccall("__w_arr_load_acq", budget_state, 0)
      if wassat_stop_requested?(stop) || used_race >= rem_budget || stats[0] >= cap || !any_progress
        running = false
      else
        # Inter-round barrier coordinator (all worker threads stopped):
        #   1. Harvest @best_phase from every arm, extract 4-literal 2x2
        #      rectangle clauses and short (G, S) projected pair-cut clauses.
        #   2. When a new low-nbad incumbent appears, run core-guided column +
        #      free-(P, T) neighborhood repair and d=1 cone refutation.
        #   3. Step the 220-var (P, T) master solver through vfree -> refute.
        #   4. Inject all permanent cuts/cores and recover any retired fixed-cap
        #      arenas IN PLACE (zero heap allocation).
        fresh_cuts = []
        prior_stats0 = stats[0]
        if coord != nil
          cols = lay["cols"]
          rows = lay["rows"]
          nmoves = lay["nmoves"]
          guard = lay["guard"] ## i64[]
          npairs = vinfo["npairs"]
          vvar = vinfo["vvar"] ## i64[]
          mval = coord["mval"] ## i8[]
          best_mval = coord["best_mval"] ## i8[]
          rect_out = coord["rect_out"] ## i64[]
          bad_pairs = coord["bad_pairs"] ## i64[]
          order_bad = coord["order_bad"] ## i64[]
          pair_kstar = coord["pair_kstar"] ## i64[]
          row_hits = coord["row_hits"] ## i64[]
          best_bad_pairs = coord["best_bad_pairs"] ## i64[]
          best_kstar = coord["best_kstar"] ## i64[]
          best_row_hits = coord["best_row_hits"] ## i64[]
          vfree_o = coord["vfree"]
          refute_o = coord["refute"]
          improved_inc = false

          a = 0
          while a < n_arms
            solvers[a].export_best_phase(mval)
            eval_st = i64[4]
            wassat_windmill_eval_native(
              mval, guard, vinfo["g_row"], vinfo["root_mask"], vinfo["pair_pc_off"],
              vinfo["pc_kill"], vinfo["pc_lits_off"], vinfo["pc_lits_len"], vinfo["pc_lits"],
              coord["rect_seen"], rect_out, 1024,
              bad_pairs, order_bad, pair_kstar, row_hits,
              cols, nmoves, npairs, eval_st
            )
            nrect = eval_st[0]
            nbad = eval_st[1]
            norder = eval_st[2]

            ri = 0
            while ri < nrect
              bo = ri * 4
              rcl = [rect_out[bo], rect_out[bo + 1], rect_out[bo + 2], rect_out[bo + 3]]
              vfree_o.install_pruning_clause(rcl, false, true)
              refute_o.install_pruning_clause(rcl, false, true)
              fresh_cuts.push(rcl)
              ri += 1

            if norder > 0
              pcuts = wassat_windmill_project_pair_cuts(
                mval, order_bad, norder, vinfo["root_mask"], vinfo["pair_pc_off"],
                vinfo["pc_kill"], vinfo["pc_lits_off"], vinfo["pc_lits_len"],
                vinfo["pc_lits"], coord["proj_seen"], 32
              )
              pi = 0
              while pi < pcuts.size
                pcl = pcuts[pi]
                vfree_o.install_pruning_clause(pcl, false, true)
                refute_o.install_pruning_clause(pcl, false, true)
                fresh_cuts.push(pcl)
                pi += 1

            if nbad == 0
              p = 0
              while p < npairs
                ks = pair_kstar[p]
                r = 0
                while r < rows
                  mval[vvar[r * npairs + p]] = r < ks ? 1 : -1
                  r += 1
                p += 1
              cand = []
              v = 1
              while v <= nv
                cand.push(mval[v] >= 0 ? v : 0 - v)
                v += 1
              if wassat_model_satisfies?(formula, cand)
                out["status"] = 1
                out["model"] = cand
                out["conflicts"] = stats[0]
                out["decisions"] = stats[1]
                out["props"] = stats[2]
                tprof = wassat_prof("windmill.bestphase_exact", tprof)
                return out

            if nbad < coord["best_nbad"]
              coord["best_nbad"] = nbad
              improved_inc = true
              v = 1
              while v <= nv
                best_mval[v] = mval[v]
                v += 1
              bi = 0
              while bi < nbad
                best_bad_pairs[bi] = bad_pairs[bi]
                bi += 1
              p = 0
              while p < npairs
                best_kstar[p] = pair_kstar[p]
                p += 1
              r = 0
              while r < nmoves
                best_row_hits[r] = row_hits[r]
                r += 1
            a += 1

          if improved_inc && coord["best_nbad"] <= 36 && stats[0] + 15000 < cap
            rmodel = wassat_windmill_repair_incumbent(
              formula, lay, vinfo, best_mval, best_bad_pairs, coord["best_nbad"],
              best_kstar, best_row_hits, coord, fresh_cuts, stats, cap
            )
            unless rmodel.empty?
              out["status"] = 1
              out["model"] = rmodel
              out["conflicts"] = stats[0]
              out["decisions"] = stats[1]
              out["props"] = stats[2]
              tprof = wassat_prof("windmill.neighborhood_repair", tprof)
              return out

          if stats[0] + 20000 < cap
            mmodel = wassat_windmill_master_step(
              formula, lay, vinfo, coord, fresh_cuts, stats, cap, 3
            )
            unless mmodel.empty?
              out["status"] = 1
              out["model"] = mmodel
              out["conflicts"] = stats[0]
              out["decisions"] = stats[1]
              out["props"] = stats[2]
              tprof = wassat_prof("windmill.pt_master", tprof)
              return out

        coord_spent = stats[0] - prior_stats0
        if coord_spent > 0
          z = ccall("__w_arr_fetch_add", budget_state, 0, coord_spent)

        if !fresh_cuts.empty?
          ci = 0
          while ci < fresh_cuts.size
            global_cuts.push(fresh_cuts[ci])
            ci += 1
          a = 0
          while a < n_arms
            arm_s = solvers[a]
            ci = 0
            while ci < fresh_cuts.size
              arm_s.install_pruning_clause(fresh_cuts[ci], false, true)
              ci += 1
            a += 1

        if coord != nil && !coord["survivor_pt"].empty? && n_arms > 3
          solvers[3].set_phases(coord["survivor_pt"])
          coord["survivor_pt"] = []

        # Zero-allocation in-place arena recovery if any @fixed_caps arm retired.
        a = 0
        while a < n_arms
          abase = a * res_stride
          if res[abase] == 2
            reseed_gen += 1
            res[abase] = 0
            solvers[a].recover_retired_arena
            solvers[a].reseed_phases(500009 + a * 104729 + reseed_gen * 7919, true)
            if coord != nil && !coord["best_inc"].empty? && (a % 2 == 0)
              solvers[a].set_phases(coord["best_inc"])
          a += 1

  tprof = wassat_prof("windmill.exhausted", tprof)
  out["conflicts"] = stats[0]
  out["decisions"] = stats[1]
  out["props"] = stats[2]
  out
