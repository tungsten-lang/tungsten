use spec
use ../lib/wassat

-> nae_test_text(n, k)
  body = ""
  nc = 0
  d = 1
  while 1 + (k - 1) * d <= n
    a = 1
    while a + (k - 1) * d <= n
      positive = ""
      negative = ""
      j = 0
      while j < k
        v = a + j * d
        positive += "[v] "
        negative += "[-v] "
        j += 1
      body += positive + "0\n" + negative + "0\n"
      nc += 2
      a += 1
    d += 1
  "p cnf [n] [nc]\n" + body

# Build the native flat view from the portable parser for both spec engines.
-> nae_test_flat(text)
  f = wassat_parse_cnf(text)
  nc = f["clauses"].size
  nl = 0
  f["clauses"].each -> (clause) nl += clause.size
  lits = i64[nl]; offs = i64[nc]; lens = i64[nc]
  ci = 0; pos = 0
  f["clauses"].each -> (clause)
    offs[ci] = pos; lens[ci] = clause.size
    clause.each -> (lit)
      lits[pos] = lit
      pos += 1
    ci += 1
  f["flat_ncl"] = nc; f["flat_nlits"] = nl
  f["flat_lits"] = lits; f["flat_offs"] = offs; f["flat_lens"] = lens
  f

-> nae_test_solve(text, stopped = false)
  f = nae_test_flat(text)
  plan = { "meta": i64[32], "scratch": 0 }
  stop = i64[4]
  wassat_stop_cancel(stop) if stopped
  res = i64[f["nvars"] + 8]
  wassat_nae_search(f, plan, stop, res, 0)
  { "formula": f, "result": res, "meta": plan["meta"], "stop": stop }

describe "Exact arithmetic scope decoding" ->
  it "replays a recovered model against every original clause" ->
    r = nae_test_solve(nae_test_text(8, 3))
    expect(r["result"][0]).to eq(1)
    model = []
    v = 1
    while v <= 8
      model.push(r["result"][v] == 1 ? v : -v)
      v += 1
    expect(wassat_model_satisfies?(r["formula"], model)).to eq(true)
    expect(r["meta"][16]).to eq(r["formula"]["flat_ncl"])
    expect(r["meta"][21]).to eq(1)

  it "exhausts the original complementary constraints before refuting" ->
    r = nae_test_solve(nae_test_text(9, 3))
    expect(r["result"][0]).to eq(-1)
    expect(r["meta"][16]).to eq(r["formula"]["flat_ncl"])
    expect(r["meta"][5]).to eq(0)
    expect(r["meta"][2] > 0).to eq(true)

  it "accepts duplicate pairs and reordered literals without assuming multiplicity" ->
    r = nae_test_solve("p cnf 3 4\n3 1 2 0\n-2 -3 -1 0\n2 1 3 0\n-1 -2 -3 0\n")
    expect(r["result"][0]).to eq(1)
    expect(r["meta"][14]).to eq(1)
    expect(r["meta"][16]).to eq(4)

  it "rejects equal color totals with mismatched actual scopes" ->
    r = nae_test_solve("p cnf 5 2\n1 2 3 0\n-1 -3 -5 0\n")
    expect(r["result"][0]).to eq(0)
    expect(r["meta"][2]).to eq(0)

  it "rejects duplicate elements, mixed signs, units, and non-arithmetic scopes" ->
    ["1 1 2 0\n-1 -1 -2 0\n", "1 -2 3 0\n-1 2 -3 0\n",
     "1 0\n-1 0\n", "1 2 4 0\n-1 -2 -4 0\n"].each -> (body)
      r = nae_test_solve("p cnf 4 2\n" + body)
      expect(r["result"][0]).to eq(0)
      expect(r["meta"][2]).to eq(0)

  it "does not publish a verdict after cancellation" ->
    r = nae_test_solve(nae_test_text(9, 3), true)
    expect(r["result"][0]).to eq(0)
    expect(r["meta"][5]).to eq(3)
    expect(wassat_stop_status(r["stop"])).to eq(0)

spec_summary
