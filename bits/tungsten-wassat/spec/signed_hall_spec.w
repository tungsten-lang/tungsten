use spec
use ../lib/signed_hall

# Each of four disjoint demand rows chooses one of three shared resources.
# The reversed alias and the root guard exercise both parts of the decoding.
-> hall_fixture(remove_exclusion)
  rows = []
  i = 0
  while i < 4
    a = 3 * i + 1
    row = [a, a + 1, a + 2]
    row[0] = 0 - 13 if i == 0
    row.push(0 - 14)
    rows.push(row)
    j = 0
    while j < 3
      k = j + 1
      while k < 3
        rows.push([0 - a - j, 0 - a - k])
        k += 1
      j += 1
    i += 1
  i = 0
  while i < 4
    j = i + 1
    while j < 4
      c = 1
      while c <= 3
        unless remove_exclusion && i == 0 && j == 1 && c == 1
          rows.push([0 - 3 * i - c, 0 - 3 * j - c])
        c += 1
      j += 1
    i += 1
  rows.push([-1, -13])
  rows.push([1, 13])
  rows.push([14])
  flat = i64[4 * rows.size]
  offs = i64[rows.size]
  lens = i64[rows.size]
  pos = 0
  k = 0
  rows.each -> (r)
    offs[k] = pos
    lens[k] = r.size
    r.each -> (lit)
      flat[pos] = lit
      pos += 1
    k += 1
  { "nvars": 14, "clauses": rows, "flat_ncl": rows.size, "flat_nlits": pos, "flat_lits": flat, "flat_offs": offs, "flat_lens": lens }

describe "signed Hall capacity" ->
  it "certifies four required rows with three exclusive resources through a reversed alias" ->
    f = hall_fixture(false)
    proof = wassat_signed_hall(f, true, 0)
    expect(proof != nil).to eq(true)
    expect(proof.ends_with?("conclusion UNSAT : -1 ;\nend pseudo-Boolean proof ;\n")).to eq(true)
    expect(wassat_signed_hall(f, false, 0)).to eq("")

  it "declines when one missing exclusion lets two rows share a resource" ->
    expect(wassat_signed_hall(hall_fixture(true), true, 0)).to eq(nil)

  it "rejects a proposed count that omits one demand choice" ->
    s = Wassat.new(4, [[1, 2], [3, 4], [-1, -3]], 0, 0)
    witness = { "rows": [[2, 4], [6, 8]], "caps": [[2, 6]] }
    expect(wassat_hall_certificate(s, witness, 3, false, 0)).to eq(nil)

  it "requires each proposed pair exclusion to propagate on the input" ->
    s = Wassat.new(4, [[1, 2], [3, 4]], 0, 0)
    witness = { "rows": [[2, 4], [6, 8]], "caps": [[2, 4, 6, 8]] }
    expect(wassat_hall_certificate(s, witness, 2, false, 0)).to eq(nil)

  it "respects an expired search budget" ->
    expect(wassat_signed_hall(hall_fixture(false), true, clock_ms() - 1)).to eq(nil)

spec_summary
