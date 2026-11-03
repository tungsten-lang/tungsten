use spec
use ../lib/wassat

-> roster_test_add(rows, row, tag, drop)
  rows.push(row) if tag != drop

-> roster_test_lower(rows, starts, lengths, bound, tag, drop)
  a = 0
  while a <= lengths[0]
    b = 0
    while b <= lengths[1]
      c = bound - 1 - a - b
      if c >= 0 && c <= lengths[2]
        row = []
        row.push(-starts[0] - a) if a < lengths[0]
        row.push(-starts[1] - b) if b < lengths[1]
        row.push(-starts[2] - c) if c < lengths[2]
        roster_test_add(rows, row, tag, drop)
      b += 1
    a += 1

# Six days, with numeric hour choices [0,8,9,10,12]. This small independent
# encoding is satisfiable at 44 hours / cost 6 and contradictory at 45 hours.
# Removing any one tested rule admits a SAT model (checked with CaDiCaL).
-> roster_test_formula(required = 45, budget = 6, drop = "", mode = "")
  rows = []; domains = []; i = 0
  while i < 6
    domains.push([1 + 4 * i, 4]); i += 1
  i = 0
  while i < 6
    domains.push([25 + 2 * i, 2]); i += 1
  i = 0
  while i < 3
    domains.push([37 + 24 * i, 24]); i += 1
  domains.push([118, 7]); domains.push([125, 7]); domains.push([132, 8])
  domains.each -> (d)
    i = 0
    while i + 1 < d[1]
      rows.push([-d[0] - i, d[0] + i + 1]); i += 1
  i = 0
  while i < 6
    roster_test_add(rows, [26 + 2 * i, 1 + 4 * i], "off", drop)
    if i < 5
      roster_test_add(rows, [4 + 4 * i, 8 + 4 * i], "maximum", drop)
      roster_test_add(rows, [-109 - i, -26 - 2 * i, -28 - 2 * i], "pair", drop)
    if i < 4
      roster_test_add(rows, [-114 - i, -26 - 2 * i, 28 + 2 * i, -30 - 2 * i], "gap", drop)
      roster_test_add(rows, [-26 - 2 * i, -28 - 2 * i, -30 - 2 * i], "triple", drop)
    i += 1
  values = [0, 8, 9, 10, 12]; i = 0
  while i < 3
    x = 1 + 8 * i; y = x + 4; out = 37 + 24 * i; a = 0
    while a < 5
      b = 0
      while b < 5
        total = values[a] + values[b]
        if total < 24
          row = []; row.push(-x - a) if a < 4; row.push(-y - b) if b < 4; row.push(out + total)
          roster_test_add(rows, row, "hour_upper", drop)
        if total > 0
          row = []; row.push(x + a - 1) if a > 0; row.push(y + b - 1) if b > 0; row.push(-out - total + 1)
          rows.push(row)
        b += 1
      a += 1
    i += 1
  roster_test_lower(rows, [37, 61, 85], [24, 24, 24], required, "required", drop)
  starts = [118, 125, 132]; lengths = [7, 7, 8]; i = 0
  while i < 3
    mask = 0
    while mask < 8
      row = []; total = 0; j = 0
      while j < 3
        index = i + 3 * j; v = 109 + index; weight = index < 5 ? 2 : 3; bit = (mask >> j) & 1
        row.push(bit == 1 ? -v : v); total += weight * bit; j += 1
      roster_test_add(rows, row + [starts[i] + total], "pref_upper", drop) if total < lengths[i]
      rows.push(row + [-starts[i] - total + 1]) if total > 0
      mask += 1
    i += 1
  roster_test_lower(rows, starts, lengths, 22 - budget, "budget", drop)
  rows = rows.reverse if mode == "shuffle"
  if mode == "rename"
    rows = rows.map -> (row)
      row.map -> (x)
        x > 0 ? 140 - x : -140 - x
  if mode == "reverse"
    rows = rows.map -> (row) row.reverse
  nl = 0; rows.each -> (row) nl += row.size
  lits = i64[nl]; offs = i64[rows.size]; lens = i64[rows.size]; at = 0; ci = 0
  rows.each -> (row)
    offs[ci] = at; lens[ci] = row.size
    row.each -> (x)
      lits[at] = x; at += 1
    ci += 1
  {"nvars": 139, "flat_ncl": rows.size, "flat_nlits": nl, "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}

describe "Original-clause roster bounds" ->
  it "infers nonuniform hours and checks the counting contradiction" ->
    m = i64[64]
    expect(wassat_roster_refute(roster_test_formula(), m, i64[2])).to eq(-1)
    expect(m[13]).to eq(6)
    expect(m[14]).to eq(45)
    expect(m[15]).to eq(6)
    expect(m[16]).to eq(44)
  it "does not refute the tight satisfiable hour boundary" ->
    expect(wassat_roster_refute(roster_test_formula(44), i64[64], i64[2])).to eq(0)
  it "does not refute a relaxed penalty budget" ->
    expect(wassat_roster_refute(roster_test_formula(45, 12), i64[64], i64[2])).to eq(0)
  ["off", "maximum", "pair", "gap", "triple", "hour_upper", "pref_upper"].each -> (rule)
    it "requires the original [rule] implications" ->
      expect(wassat_roster_refute(roster_test_formula(45, 6, rule), i64[64], i64[2])).to eq(0)
  it "accepts reversed literal order" ->
    expect(wassat_roster_refute(roster_test_formula(45, 6, "", "reverse"), i64[64], i64[2])).to eq(-1)
  it "declines unsupported clause and variable permutations" ->
    expect(wassat_roster_refute(roster_test_formula(45, 6, "", "shuffle"), i64[64], i64[2])).to eq(0)
    expect(wassat_roster_refute(roster_test_formula(45, 6, "", "rename"), i64[64], i64[2])).to eq(0)
  it "honors cancellation before allocation" ->
    m = i64[64]; stop = i64[2]; wassat_stop_cancel(stop)
    expect(wassat_roster_refute(roster_test_formula(), m, stop)).to eq(0)
    expect(m[0]).to eq(1)
    expect(m[30]).to eq(0)
  it "honors an expired deadline before allocation" ->
    m = i64[64]
    expect(wassat_roster_refute(roster_test_formula(), m, i64[2], clock_ms() - 1)).to eq(0)
    expect(m[0]).to eq(2)
    expect(m[30]).to eq(0)
  it "rejects invalid literal and flat-buffer boundaries" ->
    f = roster_test_formula(); f["flat_lits"][0] = -140
    expect(wassat_roster_refute(f, i64[64], i64[2])).to eq(0)
    f = roster_test_formula(); f["flat_offs"][0] = -1
    expect(wassat_roster_refute(f, i64[64], i64[2])).to eq(0)
    f = roster_test_formula(); f["flat_nlits"] -= 1
    expect(wassat_roster_refute(f, i64[64], i64[2])).to eq(0)
  it "requires correctly sized cancellation and metric buffers" ->
    f = roster_test_formula()
    expect(wassat_roster_refute(f, i64[2], i64[2])).to eq(0)
    expect(wassat_roster_refute(f, i64[64], i64[1])).to eq(0)
