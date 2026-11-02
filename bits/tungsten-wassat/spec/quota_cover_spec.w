use spec
use ../lib/wassat

-> quota_test_counter(rows, xs, k, top)
  root = top[0] + 1
  rows.push([0 - xs[0], root])
  j = 1
  while j < k
    rows.push([0 - (root + j)])
    j += 1
  i = 1
  while i + 1 < xs.size
    head = root + i * k
    rows.push([0 - xs[i], head])
    rows.push([0 - (head - k), head])
    j = 1
    while j < k
      rows.push([0 - xs[i], 0 - (head - k + j - 1), head + j])
      rows.push([0 - (head - k + j), head + j])
      j += 1
    rows.push([0 - xs[i], 0 - (head - 1)])
    i += 1
  top[0] = root + (xs.size - 1) * k - 1
  rows.push([0 - xs[xs.size - 1], 0 - top[0]])

-> quota_test_fixture(mode = "")
  rows = []
  # Choose two of four items, covering each of two features once.
  masks = [1, 2, 3, 0]
  masks = [0, 0, 0, 0] if mode == "impossible"
  x = 1
  while x <= 4
    f = 0
    while f < 2
      y = 5 + 2 * (x - 1) + f
      rows.push([0 - x, (masks[x - 1] & (1 << f)) != 0 ? y : 0 - y])
      rows.push([x, 0 - y])
      f += 1
    x += 1
  top = [12]
  quota_test_counter(rows, [-1, -2, -3, -4], 2, top)
  quota_test_counter(rows, [1, 2, 3, 4], 2, top)
  quota_test_counter(rows, [-5, -7, -9, -11], 3, top)
  quota_test_counter(rows, [-6, -8, -10, -12], 3, top)
  # The weaker duplicate must not create a second independently weighted row.
  quota_test_counter(rows, [-5, -7, -9, -11], 3, top) if mode == "duplicate"
  if mode == "corrupt"
    rows[25] = [1, -1]
  if mode == "extra"
    rows.push([1]); rows.push([-1])
  words = 0
  rows.each -> (row) words += row.size
  lits = i64[words]; offs = i64[rows.size]; lens = i64[rows.size]
  ci = 0; at = 0
  rows.each -> (row)
    row = row.reverse if mode == "reverse" && ci >= 16
    offs[ci] = at; lens[ci] = row.size
    row.each -> (lit)
      lits[at] = lit; at += 1
    ci += 1
  { "nvars": top[0], "flat_ncl": rows.size, "flat_nlits": words,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

-> quota_test_run(formula, cancel = false)
  m = i64[24]; stop = i64[4]; res = i64[formula["nvars"] + 8]
  wassat_stop_cancel(stop) if cancel
  status = wassat_quota_run(formula, m, stop, res)
  { "status": status, "meta": m, "stop": stop, "res": res }

-> quota_test_valid(formula, r)
  model = i64[formula["nvars"]]
  v = 1
  while v <= model.size
    model[v - 1] = r["res"][v] == 1 ? v : 0 - v
    v += 1
  wassat_model_satisfies?(formula, model)

describe "Checked quota selection" ->
  it "lifts a compact selection through every original counter" ->
    f = quota_test_fixture
    r = quota_test_run(f)
    expect(r["status"]).to eq(1)
    expect(r["meta"][0]).to eq(4)
    expect(r["meta"][2]).to eq(4)
    expect(r["meta"][3]).to eq(2)
    expect(r["meta"][4]).to eq(2)
    expect(r["meta"][13]).to eq(f["flat_ncl"])
    expect(quota_test_valid(f, r)).to eq(true)
    expect(wassat_stop_status(r["stop"])).to eq(1)

  it "checks counters regardless of their literal order" ->
    f = quota_test_fixture("reverse")
    r = quota_test_run(f)
    expect(r["status"]).to eq(1)
    expect(quota_test_valid(f, r)).to eq(true)

  it "merges duplicate coverage supports" ->
    f = quota_test_fixture("duplicate")
    r = quota_test_run(f)
    expect(r["status"]).to eq(1)
    expect(r["meta"][2]).to eq(5)
    expect(r["meta"][3]).to eq(2)
    expect(quota_test_valid(f, r)).to eq(true)

  it "declines malformed transitions without publishing" ->
    r = quota_test_run(quota_test_fixture("corrupt"))
    expect(r["status"]).to eq(0)
    expect(wassat_stop_status(r["stop"])).to eq(0)

  it "cannot ignore extra constraints after the counters" ->
    r = quota_test_run(quota_test_fixture("extra"))
    expect(r["status"]).to eq(0)
    expect(r["res"][0]).to eq(0)

  it "treats impossible quotas as UNKNOWN" ->
    r = quota_test_run(quota_test_fixture("impossible"))
    expect(r["status"]).to eq(0)
    expect(wassat_stop_status(r["stop"])).to eq(0)

  it "cancels before decode without publishing a model" ->
    r = quota_test_run(quota_test_fixture, true)
    expect(r["status"]).to eq(0)
    expect(r["meta"][10]).to eq(2)
    expect(r["meta"][5]).to eq(0)
    expect(r["res"][0]).to eq(0)

  it "enforces the deadline at a safe point" ->
    m = i64[24]
    m[11] = clock_ms() - 1
    expect(wassat_quota_poll(m, i64[4])).to eq(1)
    expect(m[12]).to eq(1)

  it "rejects a corrupted full model on original-clause replay" ->
    f = quota_test_fixture
    r = quota_test_run(f)
    r["res"][1] = 1 - r["res"][1]
    m = i64[24]
    expect(wassat_quota_replay(f["flat_lits"], f["flat_offs"], f["flat_lens"], r["res"], f["nvars"], f["flat_ncl"], m, i64[4])).to eq(0)

spec_summary
