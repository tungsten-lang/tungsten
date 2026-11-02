use ../lib/wassat
use ../lib/reconfiguration

-> rc_flat(nv, rows)
  total = 0
  rows.each -> (row) total += row.size
  lits = i64[total]; offs = i64[rows.size]; lens = i64[rows.size]
  at = 0
  i = 0
  rows.each -> (row)
    offs[i] = at
    lens[i] = row.size
    row.each -> (lit)
      lits[at] = lit
      at += 1
    i += 1
  { "nvars": nv, "flat_ncl": rows.size, "flat_nlits": total,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

# Ordinary token-jump encoding of a cycle graph. Two exactly-one selector
# rows encode each addition/removal, with pairwise exclusion auxiliaries.
-> rc_rows(n, start, goal, horizon = 2)
  rows = []
  t = 0
  while t < horizon
    base = 3 * n * t
    v = 0
    while v < n
      rows.push([0 - (base + v + 1), 0 - (base + (v + 1) % n + 1)])
      v += 1
    side = 0
    while side < 2
      v = 0
      while v < n
        x = base + v + 1
        a = base + (side + 1) * n + v + 1
        if t == 0
          inside = start.include?(v)
          if side == 0
            if inside
              rows.push([0 - a]); rows.push([0 - a, x])
            else
              rows.push([0 - x, a]); rows.push([0 - a, x])
          else
            if inside
              rows.push([0 - a, 0 - x]); rows.push([a, x])
            else
              rows.push([0 - a]); rows.push([0 - a, 0 - x])
        else
          old = base - 3 * n + v + 1
          if side == 0
            rows.push([0 - x, old, a]); rows.push([0 - a, x]); rows.push([0 - a, 0 - old])
          else
            rows.push([0 - old, x, a]); rows.push([0 - a, old]); rows.push([0 - a, 0 - x])
        v += 1
      a_base = base + (side + 1) * n
      u = 0
      wide = []
      while u < n
        wide.push(a_base + u + 1)
        v = u + 1
        while v < n
          rows.push([0 - (a_base + u + 1), 0 - (a_base + v + 1)])
          v += 1
        u += 1
      rows.push(wide)
      side += 1
    t += 1
  base = 3 * n * (horizon - 1)
  v = 0
  while v < n
    lit = base + v + 1
    rows.push([goal.include?(v) ? lit : 0 - lit])
    v += 1
  rows

-> rc_solve(n, rows, horizon = 2, cancelled = false)
  f = rc_flat(3 * n * horizon, rows)
  m = i64[24]; stop = i64[4]; res = i64[f["nvars"] + 8]
  wassat_stop_cancel(stop) if cancelled
  hit = wassat_reconf_run(f["flat_lits"], f["flat_offs"], f["flat_lens"], f["nvars"], f["flat_ncl"], m, stop, res, 0, 0)
  { "hit": hit, "meta": m, "result": res, "formula": f }

-> rc_replay(rows, res)
  rows.each -> (row)
    sat = false
    row.each -> (lit)
      v = lit < 0 ? 0 - lit : lit
      sat = true if (res[v] == 1) == (lit > 0)
    return false unless sat
  true
