use spec
use ../lib/wassat

-> shape_probe(nelem, rows)
  total = 0
  rows.each -> (row) total += row.size
  offs = i64[rows.size + 1]
  elems = i64[total]
  pos = 0
  si = 0
  rows.each -> (row)
    offs[si] = pos
    row.each -> (e)
      elems[pos] = e
      pos += 1
    si += 1
  offs[rows.size] = pos
  wassat_arith_ramsey?(offs, elems, nelem, rows.size)

-> shape_clique(nverts, chosen)
  row = []
  e = 0
  i = 0
  while i < nverts
    j = i + 1
    while j < nverts
      row.push(e) if chosen.include?(i) && chosen.include?(j)
      e += 1
      j += 1
    i += 1
  row

describe "Ramsey scope shape verification" ->
  it "checks all 64 edge subsets of K4 against the five explicit cliques" ->
    code = 0
    while code < 64
      row = []
      e = 0
      while e < 6
        row.push(e) if (code & (1 << e)) != 0
        e += 1
      expected = [11, 21, 38, 56, 63].include?(code)
      expect(shape_probe(6, [row])).to eq(expected)
      code += 1

  it "rejects duplicate edges and incomplete cliques regardless of ordering" ->
    expect(shape_probe(6, [[3, 1, 0]])).to eq(true)
    expect(shape_probe(6, [[0, 1, 2]])).to eq(false)
    expect(shape_probe(6, [[0, 1, 3], [0, 1, 3]])).to eq(true)
    expect(shape_probe(6, [[0, 1, 2, 3, 4, 4]])).to eq(false)
    expect(shape_probe(5, [[0, 1, 3]])).to eq(false)

  it "handles the widest admitted clique and vertices above bit 31" ->
    expect(shape_probe(780, [shape_clique(40, [0, 38, 39])])).to eq(true)
    expect(shape_probe(28, [shape_clique(8, [0, 1, 2, 3, 4, 5, 6, 7])])).to eq(true)
    expect(shape_probe(36, [shape_clique(9, [0, 1, 2, 3, 4, 5, 6, 7, 8])])).to eq(false)

spec_summary
