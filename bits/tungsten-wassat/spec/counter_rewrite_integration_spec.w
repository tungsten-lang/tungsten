use spec
use ../lib/wassat

describe "Compact preprocessing arm telemetry" ->
  it "copies all counters and clocks with an overlapping tail" ->
    res = i64[32]
    i = 1
    while i <= 7
      res[10 + i] = 100 + i; i += 1
    wassat_pre_arm_copy_telemetry(res, 0, 10, 11)
    i = 1
    while i <= 7
      expect(res[11 + i]).to eq(100 + i); i += 1

  it "leaves ordinary arm metadata unchanged" ->
    res = i64[32]; res[16] = 917
    wassat_pre_arm_copy_telemetry(res, 0, 10, 10)
    expect(res[16]).to eq(917)

  it "lifts original gate values after later substitutions" ->
    m = i64[32]; m[3] = 2
    gates = i64[10]
    gates[0] = 1; gates[1] = 4; gates[2] = 1; gates[3] = 2
    gates[5] = 2; gates[6] = 5; gates[7] = 4; gates[8] = 3
    stack = [{ "kind": "counter_rewrite", "gates": gates, "meta": m }, { "kind": "subst", "var": 2, "rep": -3 }]
    model = wassat_reconstruct_model(stack, [-1, -2, -3, -4, 5], 5)
    expect(model).to eq([-1, 2, -3, 4, -5])


-> counter_fixture_merge(rows, a, b, k, top)
  cap = a.size + b.size
  cap = k if cap > k
  z = []
  j = 0
  while j < cap
    top[0] += 1; z.push(top[0]); j += 1
  j = 1
  while j < cap
    rows.push([0 - z[j], z[j - 1]]); j += 1
  prev = i64[k + 2]
  j = 0
  while j < a.size
    prev[j + 1] = a[j]; j += 1
  bi = 1
  while bi <= b.size
    x = b[bi - 1]
    cur = i64[k + 2]
    hi = a.size + bi
    hi = cap if hi > cap
    j = bi
    while j <= hi
      out = 0
      if j == bi || bi == b.size
        out = z[j - 1]
      else
        top[0] += 1; out = top[0]
      cur[j] = out
      if j == bi
        rows.push([0 - prev[j], out]); rows.push([0 - x, out]); rows.push([0 - out, prev[j], x])
      elsif prev[j] != 0
        rows.push([0 - prev[j], out]); rows.push([0 - x, 0 - prev[j - 1], out])
        rows.push([0 - out, prev[j - 1]]); rows.push([0 - out, prev[j], x])
      else
        rows.push([0 - x, 0 - prev[j - 1], out]); rows.push([0 - out, prev[j - 1]]); rows.push([0 - out, x])
      j += 1
    rows.push([0 - x, 0 - prev[cap]]) if prev[cap] != 0
    prev = cur; bi += 1
  z

-> counter_fixture_tree(rows, leaves, k, top)
  return leaves if leaves.size == 1
  half = leaves.size / 2
  a = counter_fixture_tree(rows, leaves.slice(0, half), k, top)
  b = counter_fixture_tree(rows, leaves.slice(half, leaves.size - half), k, top)
  counter_fixture_merge(rows, a, b, k, top)

-> counter_fixture_formula(overflow = false)
  rows = []; roots = []; top = [315]; count = 0
  # Three regular groups; their union is not one arithmetic progression.
  g = 0
  while g < 3
    j = 0
    while j < 32
      v = 10 * j + 2 * g + 1
      rows.push([count < (overflow ? 13 : 12) ? v : 0 - v])
      count += 1; j += 1
    g += 1
  g = 0
  while g < 3
    leaves = []; j = 0
    while j < 32
      leaves.push(10 * j + 2 * g + 1); j += 1
    roots.push(counter_fixture_tree(rows, leaves, 12, top)); g += 1
  a = counter_fixture_merge(rows, roots[0], roots[1], 12, top)
  root = counter_fixture_merge(rows, a, roots[2], 12, top)
  rows.push([root[11]])
  words = 0
  rows.each -> (c) words += c.size
  l = i64[words]; o = i64[rows.size]; n = i64[rows.size]
  ci = 0; at = 0
  rows.each -> (c)
    o[ci] = at; n[ci] = c.size
    c.each -> (lit)
      l[at] = lit; at += 1
    ci += 1
  { "nvars": top[0], "clauses": [], "boxed": false, "flat_lits": l, "flat_offs": o, "flat_lens": n, "flat_ncl": ci, "flat_nlits": at }

describe "Counter rewriting in an existing preprocessing arm" ->
  it "reduces the logical variable range and reconstructs the original model" ->
    f = counter_fixture_formula
    p = WassatPreprocess.new(f["nvars"], [], WASSAT_PROOF_NONE, f)
    art = p.run_light_flat(f, true)
    expect(art["nvars"] < f["nvars"]).to eq(true)
    expect(art["stack"][0]["kind"]).to eq("counter_rewrite")
    solver = Wassat.from_flat(art["nvars"], art, 0)
    r = solver.solve_budget(0)
    expect(r["status"]).to eq(1)
    model = wassat_reconstruct_model(art["stack"], r["model"], f["nvars"])
    expect(model.size).to eq(f["nvars"])
    expect(wassat_model_satisfies?(f, model)).to eq(true)
    expect(-> () wassat_check_assumptions(art, [art["counter_base"]])).to raise_error

  it "preserves a refutation from the checked exact-count relation" ->
    f = counter_fixture_formula(true)
    p = WassatPreprocess.new(f["nvars"], [], WASSAT_PROOF_NONE, f)
    art = p.run_light_flat(f, true)
    expect(art["nvars"] < f["nvars"]).to eq(true)
    expect(art["status"]).to eq(-1)

  it "keeps the original encoding when a proof is requested" ->
    f = counter_fixture_formula
    p = WassatPreprocess.new(f["nvars"], [], WASSAT_PROOF_DRAT, f)
    art = p.run_light_flat(f, true)
    expect(art["nvars"]).to eq(f["nvars"])
    art["stack"].each -> (entry)
      expect(entry["kind"] == "counter_rewrite").to eq(false)

describe "Counter rewrite assumptions" ->
  it "preserves a frozen original coordinate by declining the rewrite" ->
    f = counter_fixture_formula
    p = WassatPreprocess.new(f["nvars"], [], WASSAT_PROOF_NONE, f)
    p.freeze(316)
    art = p.run_light_flat(f, true)
    expect(art["nvars"]).to eq(f["nvars"])
    expect(art["counter_base"]).to eq(0)

spec_summary
