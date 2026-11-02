use spec
use ../lib/wassat
use ../lib/count_cover

-> count_cover_test(text, cap = 100000, bdd_cap = 512, stop = nil, deadline = 0)
  f = wassat_parse_cnf(text)
  nc = f["clauses"].size
  lits = i64[4 * nc]
  offs = i64[nc]
  lens = i64[nc]
  ci = 0
  pos = 0
  f["clauses"].each -> (c)
    offs[ci] = pos
    lens[ci] = c.size
    c.each -> (l)
      lits[pos] = l
      pos += 1
    ci += 1
  stop = i64[4] if stop == nil
  m = i64[28]
  r = wassat_count_cover_run(lits, offs, lens, f["nvars"], nc, m, stop, deadline, cap, bdd_cap)
  [r, m]

describe "Clause-checked counting cover" ->
  it "derives a count bound and exhausts a covering partition" ->
    r = count_cover_test("p cnf 3 6\n1 2 0\n1 3 0\n2 3 0\n-1 -2 0\n-1 -3 0\n-2 -3 0\n")
    expect(r[0]).to eq(1)
    expect(r[1][10]).to eq(1)
    expect(r[1][7]).to eq(3)
    expect(r[1][22]).to eq(-1)

  it "counts free variables skipped by the decision diagram" ->
    r = count_cover_test("p cnf 5 5\n2 0\n3 0\n4 0\n-1 0\n-5 0\n")
    expect(r[0]).to eq(0)
    expect(r[1][10]).to eq(3)
    expect(r[1][22]).to eq(1)

  it "recognizes complete AND and OR definitions in arbitrary variable order" ->
    r = count_cover_test("p cnf 3 6\n1 -2 -3 0\n-1 2 0\n-1 3 0\n-1 0\n2 0\n3 0\n")
    expect(r[0]).to eq(1)
    expect(r[1][9]).to eq(1)
    expect(r[1][10]).to eq(1)
    r = count_cover_test("p cnf 3 5\n-1 2 3 0\n1 -2 0\n1 -3 0\n-1 0\n2 3 0\n")
    expect(r[0]).to eq(1)
    expect(r[1][10]).to eq(0)

  it "recognizes majority and three-input conjunctions" ->
    r = count_cover_test("p cnf 4 8\n4 -1 -2 0\n4 -1 -3 0\n4 -2 -3 0\n-4 1 2 0\n-4 1 3 0\n-4 2 3 0\n-4 0\n1 2 3 0\n")
    expect(r[0]).to eq(0)
    expect(r[1][9]).to eq(1)
    expect(r[1][10]).to eq(1)
    r = count_cover_test("p cnf 4 8\n4 -1 -2 -3 0\n-4 1 0\n-4 2 0\n-4 3 0\n-4 0\n1 0\n2 0\n3 0\n")
    expect(r[0]).to eq(1)
    expect(r[1][10]).to eq(2)

  it "does not invent an incomplete gate or publish a relaxed cover" ->
    r = count_cover_test("p cnf 3 5\n1 -2 -3 0\n-1 2 0\n-1 0\n2 0\n3 0\n")
    expect(r[0]).to eq(0)
    expect(r[1][9]).to eq(0)
    # The count bound forgets which two variables are forbidden together.
    # A surviving cover is not a model of these original clauses.
    r = count_cover_test("p cnf 3 3\n1 0\n2 0\n-1 -2 0\n")
    expect(r[0]).to eq(0)
    expect(r[1][22]).to eq(1)

  it "handles repeated literals without treating them as distinct points" ->
    r = count_cover_test("p cnf 2 3\n1 1 0\n2 2 0\n-1 -2 0\n")
    expect(r[0]).to eq(1)

  it "returns unknown on cancellation, deadline, or search limits" ->
    text = "p cnf 3 6\n1 2 0\n1 3 0\n2 3 0\n-1 -2 0\n-1 -3 0\n-2 -3 0\n"
    stop = i64[4]
    wassat_stop_cancel(stop)
    r = count_cover_test(text, 10000, 512, stop)
    expect(r[0]).to eq(0)
    expect(r[1][2]).to eq(1)
    r = count_cover_test(text, 10000, 512, nil, 1)
    expect(r[0]).to eq(0)
    expect(r[1][2]).to eq(2)
    r = count_cover_test(text, 0)
    expect(r[0]).to eq(0)
    expect(r[1][2]).to eq(4)

  it "fails closed when the BDD node budget is exhausted" ->
    body = "1 0\n2 0\n3 0\n4 0\n"
    n = 4
    a = 1
    while a <= 8
      b = a + 1
      while b <= 8
        c = b + 1
        while c <= 8
          d = c + 1
          while d <= 8
            body += "[0-a] [0-b] [0-c] [0-d] 0\n"
            n += 1
            d += 1
          c += 1
        b += 1
      a += 1
    r = count_cover_test("p cnf 8 [n]\n[body]", 100000, 128)
    expect(r[0]).to eq(0)
    expect(r[1][2]).to eq(3)

  it "publishes a refutation and preserves an earlier winning verdict" ->
    values = [1, 2, 1, 3, 2, 3, -1, -2, -1, -3, -2, -3]
    lits = i64[12]
    offs = i64[6]
    lens = i64[6]
    i = 0
    while i < 12
      lits[i] = values[i]
      i += 1
    i = 0
    while i < 6
      offs[i] = 2 * i
      lens[i] = 2
      i += 1
    m = i64[28]
    stop = i64[4]
    res = i64[11]
    expect(wassat_count_cover_arm(lits, offs, lens, m, stop, res, 0, 3, 6)).to eq(1)
    expect(res[0]).to eq(-1)
    expect(wassat_stop_status(stop)).to eq(-1)
    stop2 = i64[4]
    res2 = i64[11]
    wassat_stop_publish(stop2, 1)
    expect(wassat_count_cover_arm(lits, offs, lens, m, stop2, res2, 0, 3, 6)).to eq(0)
    expect(res2[0]).to eq(0)
    expect(wassat_stop_status(stop2)).to eq(1)

  it "rejects unsupported capacities and too many free inputs" ->
    expect(count_cover_test("p cnf 2 2\n1 2 0\n-1 -2 0\n", 1000, 300)[0]).to eq(0)
    expect(count_cover_test("p cnf 64 2\n1 2 0\n-1 -2 0\n")[0]).to eq(0)

spec_summary
