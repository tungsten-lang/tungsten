use spec
use ../lib/wassat

+ LuckyCapacityFixture < Wassat
  ro :wp_state, :ccap, :acap, :ncl, :asize

-> lucky_capacity_formula(nv, rows)
  count = 0
  rows.each -> (row) count += row.size
  lits = i64[count]
  offs = i64[rows.size]
  lens = i64[rows.size]
  ci = 0
  pos = 0
  rows.each -> (row)
    offs[ci] = pos
    lens[ci] = row.size
    row.each -> (lit)
      lits[pos] = lit
      pos += 1
    ci += 1
  { "nvars": nv, "nclauses": rows.size, "clauses": [], "boxed": false,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens,
    "flat_ncl": rows.size, "flat_nlits": count }

-> lucky_capacity_solver(f, lean)
  a = wassat_raw_artifact(f, f["nvars"])
  s = LuckyCapacityFixture.new(f["nvars"], [], WASSAT_PROOF_NONE, 0, true)
  s.load_flat(a, lean)
  s

-> capacity_model_holds(rows, model)
  i = 0
  while i < rows.size
    hit = false
    j = 0
    while j < rows[i].size
      hit = true if model.include?(rows[i][j])
      j += 1
    return false unless hit
    i += 1
  true

-> capacity_meta(widths)
  cm = i64[2 * widths.size]
  i = 0
  while i < widths.size
    cm[2 * i + 1] = widths[i]
    i += 1
  cm

describe "Lean lucky watch relocation space" ->
  it "does not repeatedly rebuild a dense database for single watch moves" ->
    rows = [[-1], [-2]]
    i = 0
    while i < 1536
      rows.push([1, 2, 3])
      i += 1
    f = lucky_capacity_formula(3, rows)
    s = lucky_capacity_solver(f, true)
    before = s.wp_state[3]
    result = s.lucky_probe
    expect(result).to eq(1)
    expect(capacity_model_holds(rows, s.result_for(result)["model"])).to eq(true)
    expect(capacity_model_holds(rows, [1, 2, 3])).to eq(false)
    expect(capacity_model_holds(rows, [])).to eq(false)
    expect(s.wp_state[3] - before < 192).to eq(true)
    # Only the watcher arena gets relocation headroom. Learning remains lean.
    expect(s.ccap).to eq(s.ncl + 2)
    expect(s.acap).to eq(s.asize + 2)

  it "preserves a dense root contradiction" ->
    rows = [[-1], [-2], [-3]]
    i = 0
    while i < 512
      rows.push([1, 2, 3])
      i += 1
    f = lucky_capacity_formula(3, rows)
    s = lucky_capacity_solver(f, true)
    expect(s.lucky_probe).to eq(-1)

  it "does not enlarge binary-only or already spacious pools" ->
    cm = i64[2048]
    i = 0
    while i < 1024
      cm[2 * i + 1] = 2
      i += 1
    expect(wassat_lucky_watch_capacity(cm, 1024, 3, 2136)).to eq(2136)
    i = 0
    while i < 1024
      cm[2 * i + 1] = 3
      i += 1
    expect(wassat_lucky_watch_capacity(cm, 1024, 4096, 18504)).to eq(18504)
    expect(wassat_lucky_watch_capacity(cm, 1024, 3, 4096)).to eq(4096)
    expect(wassat_lucky_watch_capacity(i64[0], 0, 0, 72)).to eq(72)

  it "reserves relocation space for long clauses without charging binaries or units" ->
    widths = []
    i = 0
    while i < 2048
      widths.push(i < 1536 ? 3 : (i % 2 == 0 ? 2 : 1))
      i += 1
    cm = capacity_meta(widths)
    capacity = wassat_lucky_watch_capacity(cm, widths.size, 3, 3200)
    expect(capacity >= 2 * 1536 + 10 + 1536 / 2).to eq(true)
    expect(capacity < 2 * 2048 + 10 + 2048 / 2).to eq(true)

  it "keeps ordinary CDCL loading independent of the lucky-only capacity floor" ->
    rows = []
    i = 0
    while i < 512
      rows.push([1, 2, 3])
      i += 1
    f = lucky_capacity_formula(3, rows)
    ordinary = lucky_capacity_solver(f, false)
    expect(ordinary.wp_state[1]).to eq(2 * ordinary.ccap + 4 * 3 + 72)
    result = ordinary.solve
    expect(result["status"]).to eq(1)
    expect(capacity_model_holds(rows, result["model"])).to eq(true)

spec_summary
