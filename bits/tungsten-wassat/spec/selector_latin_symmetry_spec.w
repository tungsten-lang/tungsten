use spec
use ../lib/selector_latin_symmetry

-> wassat_qg_assert_eq(a, b)
  expect(a).to eq(b)

-> wassat_qg_sym_fixture(mode = 0)
  state = i64[2176 * 8]; tables = i64[140]; tuples = i64[98]
  offs = i64[64]; lens = i64[64]; lits = i64[128]; leaves = i64[64]; groups = i64[12]
  m = i64[64]; stop = i64[4]
  c = 0
  while c < 49
    state[c] = c / 7 == c % 7 ? 127 ^ (1 << (c % 7)) : 127
    c += 1
  ci = 0
  while ci < 14
    tables[ci * 10 + 7] = 1
    tables[ci * 10 + 8] = 1
    tables[ci * 10 + 9] = ci * 7
    state[49 + ci * 66] = 1
    p = 0
    while p < 7
      tables[ci * 10 + p] = ci < 7 ? ci * 7 + p : p * 7 + ci - 7
      tuples[ci * 7 + p] = p
      p += 1
    ci += 1
  if mode == 1
    m[13] = 1
    lens[0] = 1
    lits[0] = 10
  if mode == 2 || mode == 3
    m[14] = 1
    groups[1] = mode == 2 ? 7 : 6
    i = 0
    while i < 7
      leaves[2 * i] = i
      leaves[2 * i + 1] = 1
      offs[i] = i
      lens[i] = 1
      lits[i] = 57 * i + 1
      i += 1
  if mode == 4
    tuples[7] = 1
    tuples[8] = 0
  wassat_stop_cancel(stop) if mode == 5
  result = wassat_qg_symmetry(state, tables, tuples, offs, lens, lits, leaves, groups, m, stop)
  [result, m, state]

describe "input-derived selector symmetry certificate" ->
  it "accepts a fully invariant finite relation" ->
    result = wassat_qg_sym_fixture()
    wassat_qg_assert_eq(result[0], 1)
    wassat_qg_assert_eq(result[1][45], 1)
    wassat_qg_assert_eq(result[1][46], 1)
  it "rejects an asymmetric primary clause without changing search state" ->
    result = wassat_qg_sym_fixture(1)
    wassat_qg_assert_eq(result[0], 0)
    wassat_qg_assert_eq(result[2][49], 1)
  it "checks every global alternative after normalization" ->
    wassat_qg_assert_eq(wassat_qg_sym_fixture(2)[0], 1)
    wassat_qg_assert_eq(wassat_qg_sym_fixture(3)[0], 0)
  it "rejects a table whose image is missing" ->
    wassat_qg_assert_eq(wassat_qg_sym_fixture(4)[0], 0)
  it "honors cancellation before changing root choices" ->
    result = wassat_qg_sym_fixture(5)
    wassat_qg_assert_eq(result[0], 0)
    wassat_qg_assert_eq(result[2][49], 1)
  it "interns colliding sets using exact equality" ->
    keys = i64[2]; data = i64[16]; starts = i64[4]; sizes = i64[4]; meta = i64[2]; a = i64[2]
    a[0] = 1
    x = wassat_qg_intern(a, 1, 1, 1, keys, data, starts, sizes, meta)
    a[0] = 3
    y = wassat_qg_intern(a, 1, 1, 1, keys, data, starts, sizes, meta)
    expect(x != y).to eq(true)
    wassat_qg_assert_eq(wassat_qg_intern(a, 1, 1, 0, keys, data, starts, sizes, meta), y)
    a[0] = 5
    wassat_qg_assert_eq(wassat_qg_intern(a, 1, 1, 0, keys, data, starts, sizes, meta), 0)
  it "distributes a leaf and removes inconsistent same-cell terms" ->
    keys = i64[64]; data = i64[128]; starts = i64[32]; sizes = i64[32]; meta = i64[2]
    a = i64[2]; ids = i64[2]
    a[0] = 1; a[1] = 9
    ids[0] = wassat_qg_intern(a, 2, 1, 1, keys, data, starts, sizes, meta)
    a[0] = 2; a[1] = 9
    ids[1] = wassat_qg_intern(a, 2, 1, 1, keys, data, starts, sizes, meta)
    terms = i64[2048]; pending = i64[2048]; counts = i64[1]; tmp = i64[128]; m = i64[64]
    wassat_qg_assert_eq(wassat_qg_expand_leaf(ids, 2, data, starts, sizes, terms, pending, counts, tmp, m), 1)
    wassat_qg_assert_eq(counts[0], 1)
    wassat_qg_assert_eq(terms[0], 1)
    wassat_qg_assert_eq(terms[1], 9)
