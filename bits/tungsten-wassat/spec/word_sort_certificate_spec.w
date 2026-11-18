use spec
use ../lib/word_sort_certificate

-> word_sort_group_fixture(rows)
  lits = i64[rows.reduce(0) -> (sum, row) sum + row.size]
  offs = i64[rows.size]; lens = i64[rows.size]; clauses = i64[rows.size]
  pos = 0; i = 0
  rows.each -> (row)
    offs[i] = pos; lens[i] = row.size; clauses[i] = i
    row.each -> (lit)
      lits[pos] = lit; pos += 1
    i += 1
  [lits, offs, lens, clauses]

# Independent reference: enumerate two ordinary three-bit integer values,
# rather than encoding the ripple recurrence used by the verifier.
-> word_sort_integer_comparator_rows(force_positive = false)
  rows = []
  a = 0
  while a < 8
    b = 0
    while b < 8
      row = []
      bit = 0
      while bit < 3
        row.push(((a >> bit) & 1) == 1 ? 0 - (bit + 1) : bit + 1)
        row.push(((b >> bit) & 1) == 1 ? 0 - (bit + 4) : bit + 4)
        bit += 1
      row.push(force_positive || a > b ? 7 : -7)
      rows.push(row)
      b += 1
    a += 1
  rows

-> word_sort_comparator_check(rows, cap = 4096)
  f = word_sort_group_fixture(rows)
  starts = i64[9]; counts = i64[9]; counts[7] = rows.size
  wassat_word_sort_comparator?(f[0], f[1], f[2], f[3], starts, counts, 1, 4, 7, 3, 1, cap)

describe "Word-sort abstraction certificates" ->
  it "checks complete XOR semantics independent of clause and literal order" ->
    f = word_sort_group_fixture([[3, -1, 2], [-3, 2, 1], [-2, 3, 1], [-3, -1, -2]])
    expect(wassat_word_sort_xor_group?(f[0], f[1], f[2], f[3], 0, 4, 1, 2, 3)).to eq(true)
    f = word_sort_group_fixture([[3, -1, 2], [3, 2, 1], [-2, 3, 1], [3, -1, -2]])
    expect(wassat_word_sort_xor_group?(f[0], f[1], f[2], f[3], 0, 4, 1, 2, 3)).to eq(false)

  it "rejects duplicate XOR rows despite unchanged counts" ->
    f = word_sort_group_fixture([[3, -1, 2], [-3, 2, 1], [-2, 3, 1], [-3, 2, 1]])
    expect(wassat_word_sort_xor_group?(f[0], f[1], f[2], f[3], 0, 4, 1, 2, 3)).to eq(false)

  it "checks both directions and exact coverage of wide OR relations" ->
    f = word_sort_group_fixture([[-2, 4], [3, -4, 1, 2], [4, -3], [-1, 4]])
    expect(wassat_word_sort_or_group?(f[0], f[1], f[2], f[3], 0, 4, 1, 3, 4)).to eq(true)
    f = word_sort_group_fixture([[-2, 4], [3, 4, 1, 2], [4, -3], [-1, 4]])
    expect(wassat_word_sort_or_group?(f[0], f[1], f[2], f[3], 0, 4, 1, 3, 4)).to eq(false)
    f = word_sort_group_fixture([[-2, 4], [3, -4, 1, 2], [4, -3], [-2, 4]])
    expect(wassat_word_sort_or_group?(f[0], f[1], f[2], f[3], 0, 4, 1, 3, 4)).to eq(false)

  it "proves unsigned comparison against independent integer truth tables" ->
    expect(word_sort_comparator_check(word_sort_integer_comparator_rows)).to eq(true)
    expect(word_sort_comparator_check(word_sort_integer_comparator_rows(true))).to eq(false)

  it "declines an exhausted comparison proof and references outside the macro" ->
    expect(word_sort_comparator_check(word_sort_integer_comparator_rows, 1)).to eq(false)
    expect(word_sort_comparator_check([[7, 8], [-7, -8]])).to eq(false)

spec_summary
