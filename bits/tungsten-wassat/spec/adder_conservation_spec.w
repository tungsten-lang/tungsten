use spec
use ../lib/cnf
use ../lib/adder_conservation

+ ConservationFixture
  ro :clauses, :variables

  -> new
    @clauses = []
    @variables = 0

  -> variable
    @variables += 1
    @variables

  -> conjunction(a, b)
    o = variable
    @clauses.push([o, -a, -b])
    @clauses.push([-o, a])
    @clauses.push([-o, b])
    o

  -> xor(a, b)
    x = conjunction(a, -b)
    y = conjunction(-a, b)
    -conjunction(-x, -y)

  -> half(a, b)
    [xor(a, b), conjunction(a, b)]

  -> full(a, b, c)
    sum = xor(xor(a, b), c)
    ab = conjunction(a, b)
    ac = conjunction(a, c)
    bc = conjunction(b, c)
    carry = -conjunction(conjunction(-ab, -ac), -bc)
    [sum, carry]

  -> circuit(style, duplicate)
    inputs = []
    i = 0
    while i < 8
      inputs.push(variable)
      i += 1
    products = []
    i = 0
    while i < 4
      products.push(conjunction(inputs[2 * i], inputs[2 * i + 1]))
      i += 1
    products[1] = products[0] if duplicate
    if style == 0
      a = half(products[0], products[1])
      b = half(products[2], products[3])
      c = half(a[0], b[0])
      result = full(a[1], b[1], c[1])
    else
      a = full(products[0], products[1], products[2])
      b = half(a[0], products[3])
      result = half(a[1], b[1])
    [inputs, result[0]]

  -> miter(same = false, duplicate = false)
    a = circuit(0, duplicate)
    b = circuit(1, duplicate)
    i = 0
    while i < 8
      @clauses.push([-a[0][i], b[0][i]])
      @clauses.push([a[0][i], -b[0][i]])
      i += 1
    @clauses.push([a[1]])
    @clauses.push([same ? b[1] : -b[1]])
    self

  -> wide_miter
    outputs = []
    side = 0
    while side < 2
      inputs = []
      i = 0
      while i < 12
        inputs.push(variable)
        i += 1
      sum = 0
      i = 0
      while i < 12
        j = i + 1
        while j < 12
          product = conjunction(inputs[i], inputs[j])
          sum = sum == 0 ? product : xor(sum, product)
          j += 1
        i += 1
      outputs.push(sum)
      side += 1
    @clauses.push([outputs[0]])
    @clauses.push([-outputs[1]])
    self

  -> formula
    count = 0
    @clauses.each -> (c) count += c.size
    lits = i64[count]
    offs = i64[@clauses.size]
    lens = i64[@clauses.size]
    at = 0
    ci = 0
    @clauses.each -> (c)
      offs[ci] = at
      lens[ci] = c.size
      c.each -> (l)
        lits[at] = l
        at += 1
      ci += 1
    {"nvars": @variables, "flat_ncl": ci, "flat_lits": lits,
      "flat_offs": offs, "flat_lens": lens}

-> conservation_result(fixture)
  wassat_adder_conservation_refute(fixture.formula, i64[1])

describe "Checked adder conservation" ->
  it "equates different half/full-adder trees by a common weighted sum" ->
    r = conservation_result(ConservationFixture.new.miter)
    expect(r[0]).to eq(-1)
    expect(r[6] > 0).to eq(true)
    expect(r[9]).to eq(4)
    expect(r[10]).to eq(1)

  it "does not refute satisfiable equal output requirements" ->
    expect(conservation_result(ConservationFixture.new.miter(true))[0]).to eq(0)

  it "checks every gate premise instead of relying on gate counts" ->
    omitted = 0
    while omitted < 3
      f = ConservationFixture.new.miter
      f.clauses[omitted] = f.clauses[3]
      expect(conservation_result(f)[0]).to eq(0)
      omitted += 1

  it "requires both clauses of each input equality" ->
    f = ConservationFixture.new.miter
    f.clauses[f.clauses.size - 18] = f.clauses[0]
    expect(conservation_result(f)[0]).to eq(0)

  it "preserves semantics under complemented variables and clause order" ->
    f = ConservationFixture.new.miter
    f.clauses.each -> (c)
      i = 0
      while i < c.size
        c[i] = -c[i] if (c[i].abs % 3) == 0
        i += 1
    # Literal order is irrelevant to exact binary membership and gate checks.
    f.clauses.each -> (c)
      first = c[0]
      c[0] = c[c.size - 1]
      c[c.size - 1] = first
    expect(conservation_result(f)[0]).to eq(-1)

  it "does not drop multiplicities when an input product is reused" ->
    expect(conservation_result(ConservationFixture.new.miter(true, true))[0]).to eq(0)

  it "declines unsupported widths, extra units and variable bounds" ->
    f = ConservationFixture.new.miter
    f.clauses.push([1, 2, 3, 4])
    expect(conservation_result(f)[0]).to eq(0)
    f = ConservationFixture.new.miter
    f.clauses.push([1])
    expect(conservation_result(f)[0]).to eq(0)
    formula = ConservationFixture.new.miter.formula
    formula["nvars"] = 10001
    expect(wassat_adder_conservation_refute(formula, i64[1])[0]).to eq(0)

  it "stops without a refutation on cancellation or deadline" ->
    f = ConservationFixture.new.miter.formula
    stop = i64[1]
    wassat_stop_cancel(stop)
    r = wassat_adder_conservation_refute(f, stop)
    expect(r[0]).to eq(0)
    expect(r[8]).to eq(1)
    r = wassat_adder_conservation_refute(f, i64[1], clock_ms() - 1)
    expect(r[0]).to eq(0)
    expect(r[8]).to eq(2)

  it "declines XORs wider than the scratch capacity" ->
    r = conservation_result(ConservationFixture.new.wide_miter)
    expect(r[0]).to eq(0)
    expect(r[8]).to eq(3)

spec_summary
