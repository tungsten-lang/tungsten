use spec
use ../lib/monochrome_watch

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

-> watch_run_problem(p, m, cap = 100000, deadline = 0, symmetric = 0, stop = nil)
  cell = stop == nil ? i64[4] : stop
  wassat_mwatch_run(p["asg"], p["offs"], p["elems"], p["forbid"],
    p["order"], p["trail"], p["nv"], p["ns"], cap, deadline, symmetric, m, cell)

describe "Watched monochromatic constraints" ->
  it "matches exhaustive search and count trees on asymmetric generated scopes" ->
    seed = 39
    shards = (env("WASSAT_TEST_SHARDS") || "1").to_i
    shard = (env("WASSAT_TEST_SHARD") || "0").to_i
    trial = 0
    while trial < 200
      nv = 3 + trial % 7
      rows = []
      c = 0
      while c < 5 * nv
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
      if trial % shards == shard
        p = mono_problem(rows, nv); m = i64[32]
        got = watch_run_problem(p, m)
        expect(got).to eq(mono_brute(rows, nv))
        expect(mono_accepts(rows, p["asg"])).to eq(true) if got == 1
        q = mono_problem(rows, nv); old = i64[32]
        expect(got).to eq(mono_run_problem(q, old))
        expect(m[2]).to eq(old[2])
        expect(m[12]).to eq(old[12])
      trial += 1

  it "returns unknown and unwinds at each limited search depth" ->
    rows = [[0, 0, 1, 2], [1, 0, 1, 2], [0, 1, 2, 3], [1, 1, 2, 3]]
    cap = 0
    while cap < 4
      p = mono_problem(rows, 5); m = i64[32]
      expect(watch_run_problem(p, m, cap)).to eq(0)
      expect(m[5]).to eq(1)
      expect(m[0]).to eq(0)
      i = 0
      while i < 5
        expect(p["asg"][i]).to eq(-1)
        i += 1
      cap += 1

  it "checks cancellation and expiry before allocating watches" ->
    p = mono_problem([[0, 0, 1]], 2); m = i64[32]; stop = i64[4]
    wassat_stop_cancel(stop)
    expect(watch_run_problem(p, m, 100, 0, 0, stop)).to eq(0)
    expect([m[2], m[5], m[14]]).to eq([0, 3, 0])
    m = i64[32]
    expect(watch_run_problem(p, m, 100, clock_ms() - 1)).to eq(0)
    expect([m[2], m[5], m[14]]).to eq([0, 2, 0])

  it "retains caller-verified color symmetry and handles duplicate scopes" ->
    rows = [[0, 0, 1], [1, 0, 1], [0, 0, 1], [0, 1, 2], [1, 1, 2]]
    p = mono_problem(rows, 3); m = i64[32]
    expect(watch_run_problem(p, m, 100, 0, 1)).to eq(1)
    expect(p["asg"][0]).to eq(0)
    expect(mono_accepts(rows, p["asg"])).to eq(true)

  it "detects conflicts after moving watches and fully rolls back" ->
    rows = [[0, 0, 1, 2], [0, 0, 1, 3], [1, 2, 3], [0, 2, 3], [1, 0, 1]]
    p = mono_problem(rows, 4); m = i64[32]
    got = watch_run_problem(p, m)
    expect(got).to eq(mono_brute(rows, 4))
    expect(mono_accepts(rows, p["asg"])).to eq(true) if got == 1

  it "preserves each scope across watch swaps and repeated bounded searches" ->
    rows = [[0, 0, 1, 2, 3, 4], [1, 0, 1, 2, 3, 4],
            [0, 1, 2, 5], [1, 1, 2, 5], [0, 0, 5], [1, 0, 5]]
    p = mono_problem(rows, 6)
    cap = 1
    moves = 0
    while cap <= 8
      m = i64[32]
      got = watch_run_problem(p, m, cap)
      moves += m[20]
      expect(got).to eq(mono_brute(rows, 6)) if got != 0
      expect(mono_accepts(rows, p["asg"])).to eq(true) if got == 1
      si = 0
      rows.each -> (r)
        before = []; after = []
        j = 1
        while j < r.size
          before.push(r[j])
          after.push(p["elems"][p["offs"][si] + j - 1])
          j += 1
        expect(after.sort).to eq(before.sort)
        si += 1
      i = 0
      while i < 6
        p["asg"][i] = -1
        i += 1
      cap += 1
    expect(moves > 0).to eq(true)
    m = i64[32]
    expect(watch_run_problem(p, m)).to eq(mono_brute(rows, 6))

spec_summary
