use spec
use ../lib/cnf
use ../lib/path_cover

-> path_fixture(n, line = false, units = [], corrupt = 0, encoded = false)
  clauses = []
  cell = 0
  while cell < n
    row = []
    value = 0
    while value < n
      row.push(cell * n + value + 1)
      value += 1
    row[1] = row[0] if corrupt == 2 && cell == 0
    clauses.push(row) unless corrupt == 4 && cell == 0
    if encoded
      aux = n * n + cell * (n - 1)
      clauses.push([0 - (cell * n + 1), aux + 1])
      value = 1
      while value + 1 < n
        x = cell * n + value + 1
        clauses.push([0 - x, aux + value + 1])
        clauses.push([0 - (aux + value), aux + value + 1])
        clauses.push([0 - x, 0 - (aux + value)])
        value += 1
      clauses.push([0 - (cell * n + n), 0 - (aux + n - 1)])
    else
      a = 0
      while a < n
        b = a + 1
        while b < n
          unless corrupt == 3 && cell == 0 && a == 0 && b == 1
            clauses.push([0 - (cell * n + a + 1), 0 - (cell * n + b + 1)])
          b += 1
        a += 1
    value = 0
    while value < n
      direction = -1
      while direction <= 1
        target = value + direction
        if direction != 0 && target >= 0 && target < n
          unless corrupt == 1 && value == 0 && direction == 1
            support = [0 - (cell * n + value + 1)]
            dest = 0
            while dest < n
              if (line && (dest - cell).abs == 1) || (!line && dest != cell)
                support.push(dest * n + target + 1)
              dest += 1
            clauses.push(support)
        direction += 1
      value += 1
    cell += 1
  units.each -> (lit) clauses.push([lit])
  nv = n * n + (encoded ? n * (n - 1) : 0)
  lines = ["p cnf [nv] [clauses.size]"]
  clauses.each -> (c) lines.push(c.join(" ") + " 0")
  lines.join("\n") + "\n"

# Portable parser plus flat packing keeps this specification on both engines.
-> path_formula(text)
  f = wassat_parse_cnf(text)
  cs = f["clauses"]
  total = 0
  cs.each -> (c) total += c.size
  f["flat_ncl"] = cs.size
  f["flat_lits"] = i64[total]
  f["flat_offs"] = i64[cs.size]
  f["flat_lens"] = i64[cs.size]
  ci = 0
  off = 0
  while ci < cs.size
    f["flat_offs"][ci] = off
    f["flat_lens"][ci] = cs[ci].size
    j = 0
    while j < cs[ci].size
      f["flat_lits"][off] = cs[ci][j]
      off += 1
      j += 1
    ci += 1
  f

-> path_check(text, width, budget = WASSAT_PATH_COVER_WORK, cancel = false)
  f = path_formula(text)
  out = i64[8]
  stop = i64[4]
  wassat_stop_cancel(stop) if cancel
  status = wassat_path_cover_refute(f["flat_lits"], f["flat_offs"],
    f["flat_lens"], f["nvars"], f["flat_ncl"], width, budget, stop, out)
  [status, out]

-> path_model_ok(text, true_vars)
  f = wassat_parse_cnf(text)
  f["clauses"].all? -> (c)
    c.any? -> (lit)
      lit > 0 ? true_vars.include?(lit) : !true_vars.include?(0 - lit)

describe "Wassat checked complete-path domains" ->
  it "bounds speculative workers before allocating scratch" ->
    expect(wassat_path_cover_candidate?(24, 64, 4)).to eq(true)
    expect(wassat_path_cover_candidate?(1000, 1000, 4)).to eq(false)
    expect(wassat_path_cover_candidate?(9, 20, 2)).to eq(false)
    expect(wassat_path_cover_candidate?(4225, 20, 65)).to eq(false)
    expect(wassat_path_cover_candidate?(16, 65537, 4)).to eq(false)

  it "leaves a satisfiable complete graph undecided" ->
    text = path_fixture(3)
    expect(path_model_ok(text, [1, 5, 9])).to eq(true)
    r = path_check(text, 3)
    expect(r[0]).to eq(0)
    expect(r[1][7]).to eq(1)

  it "derives value uniqueness from checked cell capacity and path coverage" ->
    expect(path_check(path_fixture(3, false, [1, 4]), 3)[0]).to eq(-1)

  it "finds an intermediate value blocked by a different clue" ->
    expect(path_check(path_fixture(4, true, [1, 11, 8]), 4)[0]).to eq(-1)

  it "verifies auxiliary binary AMOs instead of requiring direct pairs" ->
    expect(path_check(path_fixture(4, true, [1, 11, 8], 0, true), 4)[0]).to eq(-1)
    text = path_fixture(4, true, [1, 16], 0, true)
    expect(path_model_ok(text, [1, 6, 11, 16, 17, 18, 19, 21, 22, 25])).to eq(true)
    expect(path_check(text, 4)[0]).to eq(0)

  it "honors negative primary units" ->
    expect(path_check(path_fixture(4, true, [1, 16, -6]), 4)[0]).to eq(-1)

  it "rejects missing path coverage even when duplicate values would refute a full path" ->
    text = path_fixture(3, false, [1, 4], 1)
    expect(path_model_ok(text, [1, 4, 7])).to eq(true)
    expect(path_check(text, 3)[0]).to eq(0)

  it "requires every cell clause and a full within-cell exclusion proof" ->
    expect(path_check(path_fixture(3, false, [1, 4], 2), 3)[0]).to eq(0)
    expect(path_check(path_fixture(3, false, [1, 4], 3), 3)[0]).to eq(0)
    expect(path_check(path_fixture(3, false, [1, 4], 4), 3)[0]).to eq(0)

  it "does not infer value uniqueness after an AMO pair is removed" ->
    # Values1 and2 share the third cell; value0 occurs in both other cells.
    # All row and support clauses hold, but the third cell is not exact-one.
    clauses = [[1,2,3],[-1,-2],[-1,-3],[-2,-3],[-1,8],[-2,7],[-2,9],[-3,8],
      [4,5,6],[-4,-5],[-4,-6],[-5,-6],[-4,8],[-5,7],[-5,9],[-6,8],
      [7,8,9],[-7,-8],[-7,-9],[-7,5,8],[-8,4,7],[-8,6,9],[-9,5,8],[1],[4]]
    lines = ["p cnf 9 [clauses.size]"]
    clauses.each -> (c) lines.push(c.join(" ") + " 0")
    text = lines.join("\n") + "\n"
    expect(path_model_ok(text, [1,4,8,9])).to eq(true)
    expect(path_check(text, 3)[0]).to eq(0)

  it "treats a work limit and cancellation as misses" ->
    text = path_fixture(3, false, [1, 4])
    bounded = path_check(text, 3, 0)
    expect(bounded[0]).to eq(0)
    expect(bounded[1][6]).to eq(2)
    cancelled = path_check(text, 3, WASSAT_PATH_COVER_WORK, true)
    expect(cancelled[0]).to eq(0)
    expect(cancelled[1][6]).to eq(1)

  it "publishes only a complete refutation through the shared stop cell" ->
    f = path_formula(path_fixture(3, false, [1, 4]))
    out = i64[12]
    stop = i64[4]
    expect(wassat_path_cover_arm_body(f, 3, out, stop)).to eq(-1)
    expect(out[0]).to eq(-1)
    expect(wassat_stop_status(stop)).to eq(-1)
    expect(out[10] >= out[9]).to eq(true)

spec_summary
