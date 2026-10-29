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

spec_summary
