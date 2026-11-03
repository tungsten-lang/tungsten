use spec
use ../lib/wassat

-> counter_cover_test_flat(rows, nv)
  nl = 0; rows.each -> (c) nl += c.size
  lits = i64[nl]; offs = i64[rows.size]; lens = i64[rows.size]; at = 0; ci = 0
  rows.each -> (c)
    offs[ci] = at; lens[ci] = c.size
    c.each -> (x)
      lits[at] = x; at += 1
    ci += 1
  {"nvars": nv, "flat_ncl": rows.size, "flat_nlits": nl, "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}

-> counter_cover_test_formula(k = 3, mode = "base")
  n = mode == "disjoint" ? 10 : 8; nv = n; rows = []; bucket = []; i = 1
  while i <= n
    nv += 1; rows.push([-i, nv]); rows.push([i, -nv]); bucket.push(nv); i += 1
  weight = 1; bits = []; bitweights = []
  while bucket.size > 0
    carries = []
    while bucket.size > 1
      count = bucket.size >= 3 ? 3 : 2
      ins = []; j = 0
      while j < count
        ins.push(bucket.pop); j += 1
      s = nv + 1; c = nv + 2; nv += 2; vars = ins.dup; vars.push(s); pat = 0
      while pat < (1 << (count + 1))
        parity = 0; j = 0
        while j <= count
          parity ^= (pat >> j) & 1; j += 1
        if parity == 1
          row = []; j = 0
          while j <= count
            row.push(((pat >> j) & 1) == 1 ? -vars[j] : vars[j]); j += 1
          rows.push(row)
        pat += 1
      a = ins[0]; b = ins[1]
      if count == 2
        rows.push([a, -c]); rows.push([b, -c]); rows.push([-a, -b, c])
      else
        j = 0
        while j < 3
          t = j + 1
          while t < 3
            rows.push([-ins[j], -ins[t], c]); rows.push([ins[j], ins[t], -c]); t += 1
          j += 1
      bucket.push(s); carries.push(c)
    bits.push(bucket[0]); bitweights.push(weight); bucket = carries; weight *= 2
  i = 0
  while i < bits.size
    rows.push([(k & bitweights[i]) != 0 ? bits[i] : -bits[i]]); i += 1
  all = []; i = 1
  while i <= n
    all.push(i); i += 1
  all.push(1) if mode == "duplicate"
  rows.push(all)
  rows.push([1, 2, 3, 4, 5]); rows.push([4, 5, 6, 7, 8]) unless mode == "disjoint"
  if mode == "disjoint"
    rows.push([1, 2, 3, 4, 5]); rows.push([6, 7, 8, 9, 10])
  if mode == "unreplayed"
    i = 1
    while i <= n
      rows.push([-i]); i += 1
  if mode == "missing"
    rows.delete_at(2 * n)
  if mode == "contradiction"
    rows.push([1]); rows.push([-1])
  if mode == "rename"
    rows = rows.map -> (row)
      row.reverse.map -> (x)
        a = x < 0 ? -x : x; b = nv + 18 - a
        ((x > 0) == (a % 3 != 0)) ? b : -b
    nv += 17
  counter_cover_test_flat(rows, nv)

-> counter_cover_test_valid(f, model)
  return false if model == nil || model.size != f["nvars"] + 1
  ci = 0
  while ci < f["flat_ncl"]
    j = 0; ok = false
    while j < f["flat_lens"][ci]
      x = f["flat_lits"][f["flat_offs"][ci] + j]; v = x < 0 ? -x : x
      ok = true if (model[v] > 0) == (x > 0); j += 1
    return false unless ok
    ci += 1
  true

describe "Cover choices behind binary counters" ->
  it "derives the count and input choices from checked adders" ->
    m = i64[64]; d = wassat_counter_cover_decode(counter_cover_test_formula, m, i64[2])
    expect(d != nil).to eq(true)
    expect(m[5]).to eq(8)
    expect(m[10]).to eq(3)

  it "lifts a covering assignment and checks every original clause" ->
    f = counter_cover_test_formula; m = i64[64]; model = wassat_counter_cover_run(f, m, i64[2])
    expect(counter_cover_test_valid(f, model)).to eq(true)
    expect(m[16]).to eq(f["flat_ncl"])

  it "accepts renamed, polarity-flipped inputs with unused variable gaps" ->
    f = counter_cover_test_formula(3, "rename")
    expect(counter_cover_test_valid(f, wassat_counter_cover_run(f, i64[64], i64[2]))).to eq(true)

  it "deduplicates repeated choices in a covering clause" ->
    f = counter_cover_test_formula(3, "duplicate")
    expect(counter_cover_test_valid(f, wassat_counter_cover_run(f, i64[64], i64[2]))).to eq(true)

  it "does not treat an uncovered selection as a refutation" ->
    expect(wassat_counter_cover_run(counter_cover_test_formula(1, "disjoint"), i64[64], i64[2], clock_ms() + 10)).to eq(nil)

  it "rejects incomplete gate definitions" ->
    expect(wassat_counter_cover_decode(counter_cover_test_formula(3, "missing"), i64[64], i64[2])).to eq(nil)

  it "replays additional assertions outside the decoded covering rows" ->
    expect(wassat_counter_cover_run(counter_cover_test_formula(3, "unreplayed"), i64[64], i64[2])).to eq(nil)

  it "rejects contradictory original units" ->
    expect(wassat_counter_cover_run(counter_cover_test_formula(3, "contradiction"), i64[64], i64[2])).to eq(nil)

  it "validates literal ranges before indexed accesses" ->
    f = counter_cover_test_formula; f["flat_lits"][0] = f["nvars"] + 1
    expect(wassat_counter_cover_run(f, i64[64], i64[2])).to eq(nil)

  it "validates the logical flat length" ->
    f = counter_cover_test_formula; f["flat_nlits"] = f["flat_nlits"] - 1
    expect(wassat_counter_cover_run(f, i64[64], i64[2])).to eq(nil)

  it "validates offsets before indexed accesses" ->
    f = counter_cover_test_formula; f["flat_offs"][0] = -1
    expect(wassat_counter_cover_run(f, i64[64], i64[2])).to eq(nil)

  it "honors cancellation before decoding" ->
    stop = i64[2]; wassat_stop_cancel(stop); m = i64[64]
    expect(wassat_counter_cover_run(counter_cover_test_formula, m, stop)).to eq(nil)
    expect(m[0]).to eq(1)

  it "honors an expired deadline" ->
    m = i64[64]
    expect(wassat_counter_cover_run(counter_cover_test_formula, m, i64[2], clock_ms() - 1)).to eq(nil)
    expect(m[0]).to eq(2)

  it "rejects invalid PRNG seeds" ->
    expect(wassat_counter_cover_run(counter_cover_test_formula, i64[64], i64[2], 0, 0)).to eq(nil)

  it "resets reused metrics before a new run" ->
    m = i64[64]; f = counter_cover_test_formula
    expect(wassat_counter_cover_run(f, m, i64[2]) != nil).to eq(true)
    expect(m[17]).to eq(1)
    expect(wassat_counter_cover_run(f, m, i64[2], 0, 0)).to eq(nil)
    expect(m[17]).to eq(0)

  it "checks metadata and cancellation buffer sizes" ->
    expect(wassat_counter_cover_run(counter_cover_test_formula, i64[3], i64[2])).to eq(nil)
    expect(wassat_counter_cover_run(counter_cover_test_formula, i64[64], i64[1])).to eq(nil)

  it "keeps incremental cover counts and scores equal to direct recomputation" ->
    row_offs = i64[3]; row_offs[1] = 2; row_offs[2] = 4
    rv = i64[4]; rv[1] = 1; rv[2] = 1; rv[3] = 2
    co = i64[4]; co[1] = 1; co[2] = 3; co[3] = 4
    cr = i64[4]; cr[2] = 1; cr[3] = 1
    counts = i64[2]; owners = i64[2]; weights = i64[2]; weights[0] = 1; weights[1] = 1
    gain = i64[3]; gain[0] = 1; gain[1] = 2; gain[2] = 1
    loss = i64[3]; bad = i64[2]; bad[1] = 1; bpos = i64[2]; bpos[1] = 1
    selected = i64[3]; spos = i64[3]; spos[0] = -1; spos[1] = -1; spos[2] = -1
    age = i64[3]; removed = i64[3]; state = i64[4]; state[1] = 2
    m = i64[64]; stop = i64[2]; operations = [[1, 1], [0, 1], [1, 0], [2, 1], [0, 0], [2, 0]]
    operations.each -> (op)
      z = wassat_counter_cover_move(op[0], op[1], co, cr, row_offs, rv, counts, owners, weights, gain, loss, bad, bpos, selected, spos, age, removed, state, m, stop)
      expected_gain = i64[3]; expected_loss = i64[3]; nb = 0; r = 0
      while r < 2
        count = 0; owner = 0; j = row_offs[r]
        while j < row_offs[r + 1]
          v = rv[j]
          if spos[v] >= 0
            count += 1; owner = v
          j += 1
        expect(counts[r]).to eq(count)
        if count == 0
          nb += 1; j = row_offs[r]
          while j < row_offs[r + 1]
            expected_gain[rv[j]] += weights[r]; j += 1
        elsif count == 1
          expected_loss[owner] += weights[r]
        r += 1
      expect(state[1]).to eq(nb); v = 0
      while v < 3
        expect(gain[v]).to eq(expected_gain[v]); expect(loss[v]).to eq(expected_loss[v]); v += 1


  it "publishes only a completely replayed cover model to the shared scout stop" ->
    f = counter_cover_test_formula; nv = f["nvars"]; m = i64[64]; stop = i64[4]; res = i64[nv + 8]
    wassat_counter_cover_arm(f, m, stop, res, 0, nv)
    expect(res[0]).to eq(1)
    expect(wassat_stop_status(stop)).to eq(1)
    expect(m[26]).to eq(1)
    expect(m[16]).to eq(f["flat_ncl"])
    model = i64[nv + 1]; v = 1
    while v <= nv
      model[v] = res[v]; v += 1
    expect(counter_cover_test_valid(f, model)).to eq(true)

  it "does not publish a model after another scout arm requests cancellation" ->
    f = counter_cover_test_formula; nv = f["nvars"]; m = i64[64]; stop = i64[4]; res = i64[nv + 8]
    wassat_stop_cancel(stop)
    wassat_counter_cover_arm(f, m, stop, res, 0, nv)
    expect(res[0]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)
    expect(m[26]).to eq(0)
    expect(m[0]).to eq(1)
