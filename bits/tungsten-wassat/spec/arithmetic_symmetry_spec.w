use spec
use ../lib/solver
use ../lib/arithmetic_coloring

-> guard_scopes(rows)
  offsets = i64[rows.size + 1]
  elems = i64[3 * rows.size]
  colors = i8[rows.size]
  i = 0
  rows.each -> (row)
    offsets[i] = 3 * i
    colors[i] = row[0]
    j = 0
    while j < 3
      elems[3 * i + j] = row[j + 1]
      j += 1
    i += 1
  offsets[rows.size] = 3 * rows.size
  wassat_arith_color_symmetric?(offsets, elems, colors, rows.size)

describe "Wassat exact color-complement symmetry guard" ->
  it "accepts complementary copies of every actual scope" ->
    expect(guard_scopes([[0, 0, 1, 2], [1, 0, 1, 2], [1, 1, 3, 5], [0, 1, 3, 5]])).to eq(true)

  it "rejects equal color counts with different scopes" ->
    expect(guard_scopes([[0, 0, 1, 2], [1, 0, 2, 4]])).to eq(false)

  it "treats repeated clauses as logically redundant" ->
    expect(guard_scopes([[0, 0, 1, 2], [0, 0, 1, 2], [1, 0, 1, 2]])).to eq(true)

  it "rejects a scope lacking its complementary color" ->
    expect(guard_scopes([[0, 0, 1, 2], [1, 0, 1, 2], [1, 1, 3, 5]])).to eq(false)

describe "Arithmetic color width filter" ->
  it "rejects unequal color width sets before exact scope matching" ->
    offsets = i64[3]
    offsets[1] = 3
    offsets[2] = 7
    colors = i8[2]
    colors[1] = 1
    expect(wassat_arith_widths_match(offsets, colors, 2, 0)).to eq(0)

  it "does not confuse duplicate multiplicity with missing complementary scopes" ->
    offsets = i64[4]
    offsets[1] = 3
    offsets[2] = 6
    offsets[3] = 9
    colors = i8[3]
    colors[2] = 1
    elems = i64[9]
    i = 0
    while i < 9
      elems[i] = i % 3
      i += 1
    expect(wassat_arith_widths_match(offsets, colors, 3, 0)).to eq(1)
    expect(wassat_arith_color_symmetric?(offsets, elems, colors, 3)).to eq(true)
    elems[8] = 4
    expect(wassat_arith_color_symmetric?(offsets, elems, colors, 3)).to eq(false)

  it "leaves unsupported widths to the exact checker without a masked shift" ->
    offsets = i64[2]
    offsets[1] = 63
    colors = i8[1]
    expect(wassat_arith_widths_match(offsets, colors, 1, 0)).to eq(1)

spec_summary
