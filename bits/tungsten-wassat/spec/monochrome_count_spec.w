use spec
use ../lib/wassat

# Each row is [forbidden color, distinct element indices...]. These builders
# and the exhaustive oracle are independent of the production clause decoder.
-> mono_problem(rows, nv)
  ns = rows.size
  total = 0
  rows.each -> (r) total += r.size - 1
  offs = i64[ns + 1]; elems = i64[total]; forbid = i8[ns]
  heads = i64[nv + 1]; inc = i64[total]; fill = i64[nv]
  asg = i8[nv]; order = i64[nv]; trail = i64[nv]
  pos = 0; si = 0
  rows.each -> (r)
    offs[si] = pos
    forbid[si] = r[0]
    j = 1
    while j < r.size
      v = r[j]
      elems[pos] = v
      heads[v + 1] += 1
      pos += 1
      j += 1
    si += 1
  offs[ns] = pos
  i = 0
  while i < nv
    heads[i + 1] += heads[i]
    asg[i] = -1
    order[i] = i
    i += 1
  si = 0
  while si < ns
    j = offs[si]
    while j < offs[si + 1]
      v = elems[j]
      inc[heads[v] + fill[v]] = si
      fill[v] += 1
      j += 1
    si += 1
  {"offs": offs, "elems": elems, "forbid": forbid, "heads": heads,
   "inc": inc, "asg": asg, "order": order, "trail": trail, "nv": nv, "ns": ns}

-> mono_run_problem(p, m, cap = 100000, deadline = 0, symmetric = 0, stop = nil)
  cell = stop == nil ? i64[4] : stop
  wassat_mono_run(p["asg"], p["offs"], p["elems"], p["forbid"],
    p["heads"], p["inc"], p["order"], p["trail"], p["nv"], p["ns"],
    cap, deadline, symmetric, m, cell)

-> mono_accepts(rows, asg)
  rows.each -> (r)
    safe = false
    j = 1
    while j < r.size
      safe = true if asg[r[j]] != r[0]
      j += 1
    return false unless safe
  true

-> mono_brute(rows, nv)
  bits = 0
  asg = i8[nv]
  while bits < (1 << nv)
    i = 0
    while i < nv
      asg[i] = (bits >> i) & 1
      i += 1
    return 1 if mono_accepts(rows, asg)
    bits += 1
  -1

describe "Incremental monochromatic constraints" ->
  it "handles independent forbidden colors without assuming NAE symmetry" ->
    rows = [[0, 0, 1], [1, 0, 1, 2]]
    p = mono_problem(rows, 3); m = i64[32]
    expect(mono_run_problem(p, m)).to eq(1)
    expect(mono_accepts(rows, p["asg"])).to eq(true)
    expect(m[6] > 0).to eq(true)

  it "refutes an odd cycle with both forbidden colors" ->
    rows = [[0, 0, 1], [1, 0, 1], [0, 1, 2], [1, 1, 2], [0, 0, 2], [1, 0, 2]]
    expect(mono_brute(rows, 3)).to eq(-1)
    p = mono_problem(rows, 3); m = i64[32]
    expect(mono_run_problem(p, m)).to eq(-1)
    expect(m[5]).to eq(0)
    expect(m[0]).to eq(0)
    expect([p["asg"][0], p["asg"][1], p["asg"][2]]).to eq([-1, -1, -1])

  it "rolls back queued conflicts and every processed incidence" ->
    p = mono_problem([[0, 0, 1], [0, 0, 2], [1, 1, 2]], 3)
    width = i8[3]; counts = i8[6]; remain = i64[3]
    width[0] = 2; width[1] = 2; width[2] = 2
    remain[0] = 1; remain[1] = 2; remain[2] = 3
    m = i64[32]; stop = i64[4]
    got = wassat_mono_propagate(p["asg"], p["trail"], p["heads"], p["inc"],
      width, p["forbid"], counts, remain, m, stop, 0, 0)
    expect(got).to eq(0)
    expect(m[0] > m[1]).to eq(true)
    wassat_mono_undo(p["asg"], p["trail"], p["heads"], p["inc"], counts, remain, m, 0)
    i = 0
    while i < 6
      expect(counts[i]).to eq(0)
      i += 1
    expect([remain[0], remain[1], remain[2]]).to eq([1, 2, 3])
    expect([m[0], m[1]]).to eq([0, 0])

  it "keeps an exhausted node budget nondecisive and unwinds the trail" ->
    p = mono_problem([[0, 0, 1], [1, 1, 2]], 3); m = i64[32]
    expect(mono_run_problem(p, m, 1)).to eq(0)
    expect(m[5]).to eq(1)
    expect(m[0]).to eq(0)
    expect(m[2]).to eq(2)

  it "checks cancellation before allocating or preparing scope scratch" ->
    p = mono_problem([[0, 0, 1]], 2); m = i64[32]; stop = i64[4]
    wassat_stop_cancel(stop)
    expect(mono_run_problem(p, m, 100, 0, 0, stop)).to eq(0)
    expect([m[2], m[5], m[14], m[15]]).to eq([0, 3, 0, 0])

  it "checks an expired deadline before search" ->
    p = mono_problem([[0, 0, 1]], 2); m = i64[32]
    expect(mono_run_problem(p, m, 100, clock_ms() - 1)).to eq(0)
    expect([m[2], m[5], m[14], m[15]]).to eq([0, 2, 0, 0])

  it "preserves a caller-verified complemented-root symmetry" ->
    rows = [[0, 0, 1], [1, 0, 1], [0, 1, 2], [1, 1, 2]]
    p = mono_problem(rows, 3); m = i64[32]
    expect(mono_run_problem(p, m, 100, 0, 1)).to eq(1)
    expect(p["asg"][0]).to eq(0)
    expect(mono_accepts(rows, p["asg"])).to eq(true)

  it "matches exhaustive models and the scan backend on generated scopes" ->
    seed = 37
    trial = 0
    while trial < 64
      nv = 3 + trial % 5
      rows = []
      c = 0
      while c < 3 * nv
        seed = (seed * 48271) % 2147483647
        row = [seed & 1]
        v = 0
        while v < nv
          seed = (seed * 48271) % 2147483647
          row.push(v) if (seed & 3) == 0
          v += 1
        rows.push(row) if row.size >= 3
        c += 1
      rows.push([0, 0, 1])
      p = mono_problem(rows, nv); m = i64[32]
      got = mono_run_problem(p, m)
      expect(got).to eq(mono_brute(rows, nv))
      expect(mono_accepts(rows, p["asg"])).to eq(true) if got == 1
      q = mono_problem(rows, nv); old = i64[15]; old[2] = 100000
      scan = wassat_arith_dfs(q["asg"], q["offs"], q["elems"], q["forbid"],
        q["heads"], q["inc"], q["order"], q["trail"],
        i64[q["elems"].size + q["ns"] + 1], i64[q["ns"]], old, nv, q["ns"])
      expect(got).to eq(scan)
      expect(m[2]).to eq(old[1])
      expect(m[18]).to eq(old[5])
      trial += 1

spec_summary
