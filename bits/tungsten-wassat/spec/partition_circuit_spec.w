use spec
use ../lib/partition_circuit

+ PartitionFixture
  ro :clauses
  -> new(@weights)
    @nv = @weights.size
    @clauses = []
    first = []
    i = 1
    while i <= @nv
      first.push(-i)
      i += 1
    @clauses.push(first)
    @nv += 1
    @zero = @nv
    @clauses.push([0 - @zero])

  -> gate(inputs, table)
    @nv += 1
    z = @nv
    state = 0
    while state < (1 << inputs.size)
      row = []
      k = 0
      while k < inputs.size
        row.push(((state >> k) & 1) == 1 ? -inputs[k] : inputs[k])
        k += 1
      row.push(((table >> state) & 1) == 1 ? z : -z)
      @clauses.push(row)
      state += 1
    z

  -> add(left, right)
    carry = @zero
    out = []
    i = 0
    while i < left.size
      inputs = [left[i], right[i], carry]
      out.push(gate(inputs, 150))
      carry = gate(inputs, 232)
      i += 1
    out

  -> sum(invert)
    acc = [@zero, @zero, @zero, @zero, @zero, @zero]
    i = 0
    while i < @weights.size
      x = invert ? gate([i + 1], 1) : i + 1
      bits = []
      b = 0
      while b < 6
        bits.push(((@weights[i] >> b) & 1) == 1 ? x : @zero)
        b += 1
      acc = add(acc, bits)
      i += 1
    out = []
    acc.each -> (v) out.push(gate([v, @zero], 6))
    out

  -> formula
    a = sum(false)
    b = sum(true)
    i = 0
    while i < a.size
      @clauses.push([-a[i], b[i]])
      @clauses.push([a[i], -b[i]])
      i += 1
    flat

  -> flat
    n = 0
    @clauses.each -> (c) n += c.size
    lits = i64[n]
    offs = i64[@clauses.size]
    lens = i64[@clauses.size]
    p = 0
    ci = 0
    @clauses.each -> (c)
      offs[ci] = p
      lens[ci] = c.size
      c.each -> (l)
        lits[p] = l
        p += 1
      ci += 1
    { "nvars": @nv, "flat_ncl": ci, "flat_lits": lits,
      "flat_offs": offs, "flat_lens": lens }

-> partition_checked(formula, model)
  return false if model.size != formula["nvars"]
  ci = 0
  while ci < formula["flat_ncl"]
    sat = false
    j = 0
    while j < formula["flat_lens"][ci]
      l = formula["flat_lits"][formula["flat_offs"][ci] + j]
      v = l < 0 ? -l : l
      sat = true if model[v - 1] == l
      j += 1
    return false unless sat
    ci += 1
  true

describe "Verified equal-sum partition circuit model" ->
  it "recovers an arithmetic circuit and checks every input clause" ->
    f = PartitionFixture.new([1, 1, 2, 2]).formula
    r = wassat_partition_model(f, i64[2])
    expect(r["meta"][0]).to eq(1)
    expect(r["meta"][3]).to eq(6)
    expect(r["meta"][9]).to eq(f["flat_ncl"])
    expect(partition_checked(f, r["model"])).to eq(true)

  it "rejects additional constraints violated by a candidate model" ->
    fixture = PartitionFixture.new([1, 1, 2, 2])
    f = fixture.formula
    r = wassat_partition_model(f, i64[2])
    expect(r["meta"][0]).to eq(1)
    blocked = []
    r["model"].each -> (l) blocked.push(-l)
    fixture.clauses.push(blocked)
    r = wassat_partition_model(fixture.flat, i64[2])
    expect(r["meta"][0]).to eq(0)
    expect(r["meta"][10]).to eq(1)
    expect(r["model"].empty?).to eq(true)

  it "never refutes an impossible partition" ->
    f = PartitionFixture.new([1, 1, 1, 9]).formula
    r = wassat_partition_model(f, i64[2])
    expect(r["meta"][0]).to eq(0)
    expect(r["model"].empty?).to eq(true)

  it "honors cancellation and deadlines before allocating the circuit arena" ->
    f = PartitionFixture.new([1, 1, 2, 2]).formula
    stop = i64[2]
    z = wassat_stop_cancel(stop)
    r = wassat_partition_model(f, stop)
    expect(r["meta"][11]).to eq(1)
    expect(r["meta"][4]).to eq(0)
    r = wassat_partition_model(f, i64[2], clock_ms() - 1)
    expect(r["meta"][11]).to eq(2)
    expect(r["meta"][4]).to eq(0)

  it "declines unsupported headers and primary layouts" ->
    f = PartitionFixture.new([1, 1, 2, 2]).formula
    f["flat_lits"][0] = 1
    expect(wassat_partition_primary(f)).to eq(0)
    f["flat_lits"][0] = -1
    f["nvars"] = 200001
    expect(wassat_partition_primary(f)).to eq(0)
    expect(wassat_partition_primary(nil)).to eq(0)

  it "exchanges two selected items without changing the group sizes" ->
    # One-hot differences are twice the item weight, with a negative total.
    w = i64[9]
    raw = [3, 11, 17, 23, 29, 37, 41, 47]
    sum = 0
    raw.each -> (x) sum += x
    w[0] = -sum
    i = 0
    while i < raw.size
      w[i + 1] = 2 * raw[i] - sum
      i += 1
    selected = i8[9]
    meta = i64[12]
    hit = wassat_partition_find(w, 8, selected, meta, i64[2], 0)
    expect(hit).to eq(1)
    count = 0
    total = 0
    i = 1
    while i <= 8
      if selected[i] == 1
        count += 1
        total += raw[i - 1]
      i += 1
    expect(count).to eq(4)
    expect(2 * total).to eq(sum)

  it "evaluates three-input truth tables across the sign bit" ->
    prog = i32[20]
    prog[16] = 1
    prog[17] = 2
    prog[18] = 3
    values = i64[5]
    values[1] = -6148914691236517206
    values[2] = -3689348814741910324
    values[3] = -1085102592571150096
    tt = 0
    while tt < 256
      prog[19] = tt
      z = wassat_partition_eval(prog, values, 3, 4, i64[12], i64[2], 0)
      bit = 0
      while bit < 64
        expect((values[4] >> bit) & 1).to eq((tt >> (bit % 8)) & 1)
        bit += 1
      tt += 1

spec_summary
