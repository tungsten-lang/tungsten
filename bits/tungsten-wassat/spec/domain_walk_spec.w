use spec
use ../lib/wassat
use ../lib/domain_walk

-> dw_flat(nv, rows)
  total = 0
  rows.each -> (row)
    total += row.size
  lits = i64[total]
  offs = i64[rows.size]
  lens = i64[rows.size]
  pos = 0
  ci = 0
  rows.each -> (row)
    offs[ci] = pos
    lens[ci] = row.size
    row.each -> (lit)
      lits[pos] = lit
      pos += 1
    ci += 1
  { "nvars": nv, "flat_ncl": rows.size, "flat_nlits": total,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

# Direct library calls omit wall limits so interpreted parity tests exercise
# the same finite-domain semantics independently of interpreter speed.
-> dw_run(f, steps = 100, shift_mask = -1)
  nv = f["nvars"]
  nc = f["flat_ncl"]
  vb = i64[nv + 1]; vi = i64[nv + 1]
  bv = i64[128 * 32]; bl = i64[128]; dom = i64[128]
  forbid = i64[(nv + 1) * 128]; amo = i64[nv + 1]
  seen = i64[nv + 1]; ib = i8[nc]
  m = i64[24]; stop = i64[4]; sol = i64[128]
  costs = i64[128 * 32]; counts = i64[128 * 32]
  weights = i64[(nv + 1) * (nv + 1)]
  nb = wassat_domain_prepare(f["flat_lits"], f["flat_offs"], f["flat_lens"], nv, nc,
    vb, vi, bv, bl, dom, forbid, amo, seen, ib, m, stop, 0)
  res = i64[nv + 8]
  if nb > 0
    m[13] = nb * nb
    hit = wassat_domain_trial(bv, bl, forbid, dom, sol, costs, counts, weights,
      seen, m, stop, nb, nv + 1, 1, shift_mask, steps, 0)
    if hit == 1
      checked = wassat_domain_verify(f["flat_lits"], f["flat_offs"], f["flat_lens"], nc, vb, vi, sol, m, stop, 0)
      if checked == 1
        res[0] = 1
        v = 1
        while v <= nv
          res[v] = sol[vb[v] - 1] == vi[v] ? 1 : 0
          v += 1
  { "meta": m, "result": res, "sol": sol, "var_block": vb, "var_bit": vi }

-> dw_replay(rows, result)
  rows.each -> (row)
    found = false
    row.each -> (lit)
      v = lit < 0 ? 0 - lit : lit
      found = true if (result[v] == 1) == (lit > 0)
    return false unless found
  true

-> dw_base(blocks, width)
  rows = []
  b = 0
  while b < blocks
    row = []
    j = 0
    while j < width
      row.push(b * width + j + 1)
      j += 1
    rows.push(row)
    j = 0
    while j < width
      k = j + 1
      while k < width
        rows.push([0 - (b * width + j + 1), 0 - (b * width + k + 1)])
        k += 1
      j += 1
    b += 1
  rows

describe "Wassat bounded finite-domain walk" ->
  it "returns only an original-clause-verified model" ->
    rows = dw_base(4, 3)
    rows.push([-1, -4])
    f = dw_flat(12, rows)
    r = dw_run(f)
    expect(r["result"][0]).to eq(1)
    expect(r["meta"][16]).to eq(1)
    expect(r["meta"][14]).to eq(rows.size)
    expect(dw_replay(rows, r["result"])).to eq(true)
    expect(f["flat_ncl"]).to eq(rows.size)

  it "accepts permuted duplicate positive and binary clauses" ->
    rows = dw_base(4, 3)
    rows.push([3, 1, 2])
    rows.push([-1, -2])
    rows.push([-2, -1])
    r = dw_run(dw_flat(12, rows))
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "treats a repeated-literal negative binary as a unit" ->
    rows = dw_base(4, 3)
    rows.push([-1, -1])
    rows.push([-2])
    r = dw_run(dw_flat(12, rows))
    expect(r["result"][0]).to eq(1)
    expect(r["result"][1]).to eq(0)
    expect(r["result"][3]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "handles bit31 and forced 32-value domains" ->
    rows = dw_base(3, 32)
    rows.push([32])
    rows.push([64])
    rows.push([96])
    rows.push([-31, -64])
    r = dw_run(dw_flat(96, rows))
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(1)
    expect(r["result"][32]).to eq(1)
    expect(r["result"][64]).to eq(1)
    expect(r["result"][96]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "declines contradictory units without refuting" ->
    rows = dw_base(4, 3)
    rows.push([1])
    rows.push([2])
    r = dw_run(dw_flat(12, rows))
    expect(r["meta"][1]).to eq(0)
    expect(r["result"][0]).to eq(0)

  it "declines nonadjacent duplicates in a domain row" ->
    rows = dw_base(4, 3)
    rows[0] = [1, 2, 1]
    r = dw_run(dw_flat(12, rows))
    expect(r["meta"][1]).to eq(0)
    expect(r["result"][0]).to eq(0)

  it "declines partial overlap between positive rows" ->
    rows = dw_base(4, 3)
    rows.push([1, 4])
    r = dw_run(dw_flat(12, rows))
    expect(r["meta"][1]).to eq(0)

  it "requires complete original at-most-one exclusions" ->
    rows = dw_base(4, 3)
    rows[1] = [-1, -3]
    r = dw_run(dw_flat(12, rows))
    expect(r["meta"][1]).to eq(0)

  it "declines unsupported residual clauses" ->
    rows = dw_base(4, 3)
    rows.push([1, -4])
    r = dw_run(dw_flat(12, rows))
    expect(r["meta"][1]).to eq(0)

  it "declines empty clauses and uncovered variables" ->
    rows = dw_base(4, 3)
    r = dw_run(dw_flat(13, rows))
    expect(r["meta"][1]).to eq(0)
    rows.push([])
    r = dw_run(dw_flat(12, rows))
    expect(r["meta"][1]).to eq(0)

  it "validates offsets and literal ranges before indexing" ->
    rows = dw_base(4, 3)
    f = dw_flat(12, rows)
    f["flat_offs"][0] = -1
    expect(dw_run(f)["meta"][1]).to eq(0)
    f = dw_flat(12, rows)
    f["flat_offs"][0] = f["flat_nlits"]
    expect(dw_run(f)["meta"][1]).to eq(0)
    f = dw_flat(12, rows)
    f["flat_lits"][0] = 13
    expect(dw_run(f)["meta"][1]).to eq(0)

  it "never turns bounded search failure into UNSAT" ->
    rows = dw_base(3, 2)
    rows.push([-1, -3])
    rows.push([-1, -4])
    rows.push([-2, -3])
    rows.push([-2, -4])
    r = dw_run(dw_flat(6, rows), 20)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(0)
    expect(r["meta"][7]).to eq(20)

  it "honors cancellation before any preparation" ->
    rows = dw_base(4, 3)
    f = dw_flat(12, rows)
    m = i64[24]; stop = i64[4]; res = i64[20]
    stop[0] = 1
    status = wassat_domain_arm(f["flat_lits"], f["flat_offs"], f["flat_lens"], 12,
      f["flat_ncl"], m, stop, res, 0, 8, 100000, 1000)
    expect(status).to eq(0)
    expect(m[2]).to eq(1)
    expect(m[4]).to eq(0)
    expect(res[0]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)

  it "honors an expired search deadline" ->
    rows = dw_base(4, 3)
    f = dw_flat(12, rows)
    m = i64[24]; stop = i64[4]; res = i64[20]
    status = wassat_domain_search(f["flat_lits"], f["flat_offs"], f["flat_lens"], 12,
      f["flat_ncl"], m, stop, res, 0, 8, 100000, clock_ms() - 1)
    expect(status).to eq(0)
    expect(m[2]).to eq(2)
    expect(m[4]).to eq(0)
    expect(res[0]).to eq(0)

  it "rejects an incorrect model during original-clause replay" ->
    rows = dw_base(4, 3)
    rows.push([1])
    f = dw_flat(12, rows)
    r = dw_run(f)
    expect(r["result"][0]).to eq(1)
    sol = r["sol"]
    sol[0] = 1
    m = i64[24]; stop = i64[4]
    checked = wassat_domain_verify(f["flat_lits"], f["flat_offs"], f["flat_lens"],
      f["flat_ncl"], r["var_block"], r["var_bit"], sol, m, stop, 0)
    expect(checked).to eq(0)
    expect(m[16]).to eq(0)

  it "agrees with exhaustive finite-domain oracle 0" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-5],[-2,-5],[-1,-8],[-3,-7],[-3,-8],[-1,-10],[-2,-11],[-3,-11],[-4,-7],[-4,-8],[-5,-8],[-6,-7],[-6,-9],[-5,-12],[-6,-10],[-9,-10]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "agrees with exhaustive finite-domain oracle 1" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-5],[-1,-6],[-2,-4],[-2,-5],[-2,-6],[-3,-4],[-3,-5],[-1,-7],[-1,-9],[-2,-7],[-2,-8],[-3,-7],[-3,-8],[-1,-10],[-1,-11],[-1,-12],[-2,-10],[-2,-11],[-2,-12],[-3,-10],[-3,-11],[-4,-7],[-4,-8],[-4,-9],[-5,-7],[-5,-8],[-5,-9],[-6,-7],[-6,-8],[-6,-9],[-4,-12],[-5,-10],[-5,-11],[-5,-12],[-6,-10],[-6,-11],[-6,-12],[-7,-10],[-7,-11],[-8,-10],[-8,-11],[-8,-12],[-9,-10],[-9,-11],[-9,-12]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(0)

  it "agrees with exhaustive finite-domain oracle 2" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-7],[-2,-7],[-1,-10],[-2,-11],[-4,-9],[-6,-7],[-4,-10],[-7,-12]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "agrees with exhaustive finite-domain oracle 3" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-4],[-1,-5],[-1,-6],[-2,-4],[-2,-5],[-2,-6],[-3,-4],[-3,-5],[-3,-6],[-1,-7],[-1,-8],[-1,-9],[-2,-9],[-1,-10],[-1,-11],[-1,-12],[-2,-10],[-2,-11],[-3,-10],[-3,-11],[-4,-7],[-4,-8],[-5,-7],[-5,-8],[-5,-9],[-6,-7],[-6,-8],[-4,-10],[-4,-11],[-5,-10],[-7,-10],[-7,-12],[-8,-11],[-8,-12],[-9,-10]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(0)

  it "agrees with exhaustive finite-domain oracle 4" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-3,-4],[-2,-9],[-3,-9],[-1,-10],[-3,-11],[-4,-8],[-5,-8],[-5,-11],[-6,-10],[-6,-12],[-7,-10],[-7,-12],[-8,-10]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "agrees with exhaustive finite-domain oracle 5" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-4],[-1,-5],[-2,-4],[-2,-6],[-3,-4],[-3,-5],[-3,-6],[-1,-8],[-1,-9],[-2,-8],[-2,-9],[-3,-7],[-3,-8],[-3,-9],[-1,-10],[-1,-11],[-2,-10],[-2,-12],[-4,-7],[-4,-8],[-5,-7],[-5,-8],[-5,-9],[-6,-7],[-6,-9],[-4,-10],[-4,-11],[-4,-12],[-5,-10],[-5,-11],[-7,-12],[-8,-10],[-9,-10],[-9,-11],[-9,-12]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(0)

  it "agrees with exhaustive finite-domain oracle 6" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-5],[-1,-6],[-2,-4],[-2,-6],[-2,-9],[-3,-9],[-6,-8],[-6,-11],[-7,-10],[-7,-11],[-7,-12],[-8,-11],[-9,-12]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "agrees with exhaustive finite-domain oracle 7" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-4],[-1,-6],[-2,-6],[-3,-4],[-3,-5],[-1,-7],[-1,-9],[-2,-8],[-2,-9],[-3,-7],[-3,-8],[-3,-9],[-1,-10],[-1,-12],[-2,-10],[-2,-12],[-3,-10],[-3,-12],[-4,-7],[-4,-8],[-4,-9],[-5,-8],[-5,-9],[-6,-8],[-6,-9],[-4,-11],[-4,-12],[-5,-10],[-5,-12],[-6,-10],[-6,-11],[-6,-12],[-7,-11],[-7,-12],[-8,-10],[-8,-12],[-9,-11],[-9,-12]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(0)

  it "agrees with exhaustive finite-domain oracle 8" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-4],[-2,-4],[-2,-6],[-1,-7],[-2,-7],[-1,-10],[-1,-11],[-1,-12],[-3,-12],[-4,-7],[-4,-10],[-4,-12],[-5,-12],[-6,-11],[-9,-12]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "agrees with exhaustive finite-domain oracle 9" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-6],[-2,-5],[-2,-6],[-3,-4],[-1,-7],[-1,-9],[-2,-7],[-2,-8],[-2,-9],[-3,-7],[-3,-9],[-1,-10],[-1,-12],[-2,-12],[-3,-10],[-3,-11],[-3,-12],[-4,-7],[-4,-9],[-5,-7],[-5,-9],[-6,-7],[-4,-10],[-5,-10],[-5,-11],[-6,-10],[-6,-12],[-7,-11],[-8,-10],[-8,-11],[-8,-12],[-9,-10],[-9,-11],[-9,-12]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(0)

  it "agrees with exhaustive finite-domain oracle 10" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-3,-4],[-1,-8],[-2,-11],[-4,-9],[-6,-10],[-6,-11],[-8,-11],[-8,-12]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "agrees with exhaustive finite-domain oracle 11" ->
    rows = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[4,5,6],[-4,-5],[-4,-6],[-5,-6],[7,8,9],[-7,-8],[-7,-9],[-8,-9],[10,11,12],[-10,-11],[-10,-12],[-11,-12],[-1,-4],[-1,-5],[-1,-6],[-2,-4],[-2,-5],[-2,-6],[-3,-4],[-3,-5],[-3,-6],[-1,-7],[-1,-8],[-2,-8],[-2,-9],[-3,-8],[-3,-9],[-1,-11],[-1,-12],[-2,-10],[-2,-12],[-3,-11],[-4,-7],[-4,-8],[-4,-9],[-5,-8],[-6,-7],[-6,-8],[-6,-9],[-4,-10],[-4,-11],[-5,-10],[-5,-11],[-5,-12],[-6,-10],[-6,-12],[-7,-11],[-7,-12],[-8,-11],[-8,-12],[-9,-10],[-9,-11]]
    r = dw_run(dw_flat(12, rows), 100)
    expect(r["meta"][1]).to eq(1)
    expect(r["result"][0]).to eq(0)

  it "reuses preparation stamps for only the violated domain pairs" ->
    rows = dw_base(3, 2)
    rows.push([-1, -3])
    rows.push([-1, -4])
    rows.push([-2, -3])
    rows.push([-2, -4])
    r = dw_run(dw_flat(6, rows), 20)
    expect(r["result"][0]).to eq(0)
    expect(r["meta"][9] > 0).to eq(true)
    expect(r["meta"][23]).to eq(r["meta"][9])

  it "finds an original model with the logical-shift stream" ->
    rows = dw_base(4, 3)
    rows.push([-1, -4])
    rows.push([-1, -7])
    rows.push([-4, -7])
    rows.push([-2, -5])
    rows.push([-2, -8])
    rows.push([-5, -8])
    one = 1 ## i64
    mask = (one << 57) - one
    r = dw_run(dw_flat(12, rows), 100, mask)
    expect(r["result"][0]).to eq(1)
    expect(r["meta"][16]).to eq(1)
    expect(dw_replay(rows, r["result"])).to eq(true)

  it "never refutes on an exhausted logical-shift walk" ->
    rows = dw_base(3, 2)
    rows.push([-1, -3])
    rows.push([-1, -4])
    rows.push([-2, -3])
    rows.push([-2, -4])
    one = 1 ## i64
    mask = (one << 57) - one
    r = dw_run(dw_flat(6, rows), 20, mask)
    expect(r["result"][0]).to eq(0)
    expect(r["meta"][7]).to eq(20)
    expect(r["meta"][23]).to eq(r["meta"][9])

spec_summary
