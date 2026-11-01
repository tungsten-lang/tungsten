use spec
use ../lib/resolution_cover

+ CoverFixture
  ro :clauses, :variables

  -> new(copies, omitted = 63)
    @variables = 6 * copies
    @clauses = []
    mask = 0
    while mask < 64
      if mask != omitted
        @variables += 1
        aux = @variables
        c = 0
        while c < copies
          a = []; b = [-aux]; j = 0
          while j < 6
            v = c * 6 + j + 1
            l = ((mask >> j) & 1) == 0 ? v : -v
            if j < 3
              a.push(l)
            else
              b.push(l)
            j += 1
          a.push(aux)
          @clauses.push(a); @clauses.push(b)
          c += 1
      mask += 1

  -> block
    row = []; v = 1
    while v <= 18
      row.push(-v)
      v += 1
    @clauses.push(row)

  -> formula
    n = 0
    @clauses.each -> (c) n += c.size
    lits = i64[n]; offs = i64[@clauses.size]; lens = i64[@clauses.size]
    at = 0; ci = 0
    @clauses.each -> (c)
      offs[ci] = at; lens[ci] = c.size
      c.each -> (l)
        lits[at] = l
        at += 1
      ci += 1
    {"nvars": @variables, "flat_ncl": ci, "flat_nlits": n,
     "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}

-> cover_result(f)
  wassat_resolution_cover_refute(f.formula, i64[4])

describe "Checked resolution-chain cover" ->
  it "refutes a complete cover of a discovered projection" ->
    m = cover_result(CoverFixture.new(1, -1))
    expect(m[0]).to eq(-1)
    expect(m[2]).to eq(64)

  it "combines forced projections through an original wide clause" ->
    f = CoverFixture.new(3)
    f.block
    m = cover_result(f)
    expect(m[0]).to eq(-1)
    expect(m[1]).to eq(3)
    expect(m[6]).to eq(18)
    expect(m[9]).to eq(f.clauses.size)

  it "does not call an all-but-one cover unsatisfiable" ->
    expect(cover_result(CoverFixture.new(3))[0]).to eq(0)

  it "does not replace a missing row with a duplicate" ->
    f = CoverFixture.new(1)
    f.clauses[0] = f.clauses[2]
    expect(cover_result(f)[0]).to eq(0)

  it "requires a valid opposite pivot in each resolution step" ->
    f = CoverFixture.new(1, -1)
    f.clauses[0][3] = -f.clauses[0][3]
    expect(cover_result(f)[0]).to eq(0)

  it "declines tautological and foreign-core chain premises" ->
    f = CoverFixture.new(1, -1)
    f.clauses[0][0] = -f.clauses[0][1]
    expect(cover_result(f)[0]).to eq(0)
    f = CoverFixture.new(3)
    f.clauses[0][0] = 7
    expect(cover_result(f)[0]).to eq(0)

  it "survives variable complementation and reversed clause order" ->
    f = CoverFixture.new(3)
    f.block
    f.clauses.each -> (c)
      j = 0
      while j < c.size
        c[j] = -c[j] if c[j].abs % 3 == 0
        j += 1
      j = 0
      while j < c.size / 2
        k = c.size - 1 - j
        t = c[j]; c[j] = c[k]; c[k] = t
        j += 1
    j = 0
    while j < f.clauses.size / 2
      k = f.clauses.size - 1 - j
      t = f.clauses[j]; f.clauses[j] = f.clauses[k]; f.clauses[k] = t
      j += 1
    expect(cover_result(f)[0]).to eq(-1)

  it "honors cancellation and deadlines before doing work" ->
    f = CoverFixture.new(1).formula
    stop = i64[4]
    wassat_stop_cancel(stop)
    m = wassat_resolution_cover_refute(f, stop)
    expect(m[0]).to eq(0)
    expect(m[8]).to eq(1)
    m = wassat_resolution_cover_refute(f, i64[4], clock_ms() - 1)
    expect(m[0]).to eq(0)
    expect(m[8]).to eq(2)

  it "does not certify incomplete work after its work cap" ->
    m = i64[14]
    m[10] = 400000000
    expect(wassat_cover_tick(m, i64[4], 0)).to eq(1)
    expect(m[0]).to eq(0)
    expect(m[8]).to eq(3)

spec_summary
