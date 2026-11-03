use spec
use ../lib/wassat

-> wide_fixture(clauses, nv)
  nl = 0
  clauses.each -> (c) nl += c.size
  lits = i64[nl]; offs = i64[clauses.size]; lens = i64[clauses.size]
  at = 0; ci = 0
  clauses.each -> (c)
    offs[ci] = at; lens[ci] = c.size
    c.each -> (l)
      lits[at] = l; at += 1
    ci += 1
  { "nvars": nv, "flat_ncl": ci, "flat_nlits": nl, "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

-> wide_parity(n, rhs)
  cs = []; bits = 0
  while bits < (1 << n)
    parity = 0; j = 0; c = []
    while j < n
      b = (bits >> j) & 1
      parity = parity ^ b
      c.push(b == 0 ? j + 1 : -1 - j)
      j += 1
    cs.push(c) unless parity == rhs
    bits += 1
  cs

-> wide_test_run(f, stop, deadline)
  nv = f["nvars"]; nc = f["flat_ncl"]
  program = i64[10 * nv]; check = i64[10 * nc]; free = i64[24]; values = i64[nv + 1]; m = i64[20]; e = i64[8]
  built = wassat_wide_build(f["flat_lits"], f["flat_offs"], f["flat_lens"], nv, nc, program, check, free, values, m, stop, deadline)
  hit = 0
  hit = wassat_wide_enumerate(program, check, free, values, m[7], m[4], m[5], e, stop, deadline) if built == 1
  [built, hit, m, e]

describe "Wide original-clause circuits" ->
  it "refutes a fully defined seven-variable parity contradiction" ->
    cs = wide_parity(7, 1)
    v = 1
    while v <= 7
      cs.push([-v]); v += 1
    r = wide_test_run(wide_fixture(cs, 7), i64[4], 0)
    expect(r[0]).to eq(1)
    expect(r[1]).to eq(1)
    expect(r[2][7]).to eq(0)

  it "keeps a satisfying assignment among fewer than six free bits" ->
    r = wide_test_run(wide_fixture(wide_parity(7, 1), 7), i64[4], 0)
    expect(r[0]).to eq(1)
    expect(r[1]).to eq(0)
    expect(r[3][3] != 0).to eq(true)

  it "checks signed multi-input AND definitions" ->
    cs = [[-4, -1, 2, -3], [4, 1], [4, -2], [4, 3], [1], [-2], [3], [4]]
    r = wide_test_run(wide_fixture(cs, 4), i64[4], 0)
    expect(r[0]).to eq(1)
    expect(r[1]).to eq(1)

  it "declines an incomplete parity definition" ->
    cs = wide_parity(7, 1)
    cs.pop
    r = wide_test_run(wide_fixture(cs, 7), i64[4], 0)
    expect(r[0]).to eq(0)
    expect(r[1]).to eq(0)

  it "declines more than twenty-four free components" ->
    cs = []; v = 1
    while v <= 50
      cs.push([-v, v + 1]); cs.push([v, -v - 1]); v += 2
    r = wide_test_run(wide_fixture(cs, 50), i64[4], 0)
    expect(r[0]).to eq(0)
    expect(r[1]).to eq(0)

  it "rejects contradictory units and unsupported clause widths" ->
    expect(wide_test_run(wide_fixture([[1], [-1]], 1), i64[4], 0)[0]).to eq(0)
    expect(wide_test_run(wide_fixture([[1, 2, 3, 4, 5, 6, 7, 8]], 8), i64[4], 0)[0]).to eq(0)

  it "honors cancellation and deadlines before building" ->
    f = wide_fixture(wide_parity(7, 1), 7)
    stop = i64[4]; wassat_stop_cancel(stop)
    r = wide_test_run(f, stop, 0)
    expect(r[0]).to eq(0)
    expect(r[2][9]).to eq(1)
    r = wide_test_run(f, i64[4], clock_ms() - 1)
    expect(r[0]).to eq(0)
    expect(r[2][9]).to eq(3)

  it "returns refutation metadata without publishing a winner and resets reused plans" ->
    cs = wide_parity(7, 1)
    v = 1
    while v <= 7
      cs.push([-v]); v += 1
    f = wide_fixture(cs, 7)
    p = wassat_wide_plan(f); stop = i64[4]
    expect(wassat_wide_run(f, p, stop)).to eq(1)
    expect(p["meta"][10]).to eq(-1)
    expect(p["meta"][6]).to eq(p["meta"][5])
    expect(wassat_stop_load(stop)).to eq(0)
    wassat_stop_cancel(stop)
    expect(wassat_wide_run(f, p, stop)).to eq(0)
    expect(p["meta"][9]).to eq(1)
    expect(p["meta"][10]).to eq(0)
    expect(p["meta"][6]).to eq(0)

  it "reserves returned buffers and every temporary hash and relation array" ->
    nv = WASSAT_WIDE_MAX_VARS
    [1, 32769, WASSAT_WIDE_MAX_CLAUSES].each -> (nc)
      cap = 1
      while cap < 2 * nc
        cap *= 2
      bytes = 80 * nv + 80 * nc + 8 * (nv + 1) + 192 + 256
      bytes += 56 * nc + 8 * cap + 2 * nc + 2 * (nv + 1) + 80 * nc + 56 + 512 + 160 + 64 + 48
      expect(wassat_wide_bytes(nv, nc) >= bytes + 65536).to eq(true)
    f = wide_fixture([[1]], WASSAT_WIDE_MAX_VARS + 1)
    expect(wassat_wide_plan(f)).to eq(nil)

  it "preserves a first recognizer's refutation without running the fallback" ->
    f = wide_fixture([[1], [-1]], 1)
    first = wassat_dependency_circuit_plan(f)
    fallback = wassat_wide_plan(f)
    stop = i64[4]; res = i64[9]
    wassat_circuit_fallback_arm(f, first, fallback, stop, res, 0, 1)
    expect(res[0]).to eq(-1)
    expect(wassat_stop_status(stop)).to eq(-1)
    expect(fallback["meta"][25]).to eq(0)

  it "tries the wider circuit after an earlier shape recognizer declines" ->
    cs = wide_parity(7, 1)
    v = 1
    while v <= 7
      cs.push([-v]); v += 1
    f = wide_fixture(cs, 7)
    first = { "affine_design": true, "meta": i64[64] }
    fallback = wassat_wide_plan(f)
    stop = i64[4]; res = i64[15]
    wassat_circuit_fallback_arm(f, first, fallback, stop, res, 0, 7)
    expect(first["meta"][18]).to eq(0)
    expect(fallback["meta"][10]).to eq(-1)
    expect(res[0]).to eq(-1)
    expect(wassat_stop_status(stop)).to eq(-1)

  it "does not start the fallback after cancellation or another winner" ->
    f = wide_fixture(wide_parity(7, 1), 7)
    [-1, 0, 1].each -> (outcome)
      first = { "affine_design": true, "meta": i64[64] }
      fallback = wassat_wide_plan(f)
      stop = i64[4]; res = i64[15]
      if outcome == 0
        wassat_stop_cancel(stop)
      else
        wassat_stop_publish(stop, outcome)
      wassat_circuit_fallback_arm(f, first, fallback, stop, res, 0, 7)
      expect(res[0]).to eq(0)
      expect(wassat_stop_status(stop)).to eq(outcome)
      expect(fallback["meta"][25]).to eq(0)

spec_summary
