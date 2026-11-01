use spec
use ../lib/mycielski

+ MycielFixture
  ro :clauses, :vertices, :variables, :edge_clauses

  -> new(layers, colors)
    @vertices = 2
    edges = [[0, 1]]
    level = 0
    while level < layers
      n = @vertices
      next_edges = []
      edges.each -> (e)
        next_edges.push(e)
        next_edges.push([e[0], n + e[1]])
        next_edges.push([e[1], n + e[0]])
      v = 0
      while v < n
        next_edges.push([n + v, 2 * n])
        v += 1
      edges = next_edges
      @vertices = 2 * n + 1
      level += 1
    @variables = 3 * @vertices
    @clauses = []
    @edge_clauses = []
    edges.each -> (e)
      out = []
      bit = 0
      while bit < 3
        a = 3 * e[0] + bit + 1
        b = 3 * e[1] + bit + 1
        @variables += 1
        o = @variables
        @clauses.push([-o, a, b])
        @clauses.push([-o, -a, -b])
        @clauses.push([o, -a, b])
        @clauses.push([o, a, -b])
        out.push(o)
        bit += 1
      @edge_clauses.push(@clauses.size)
      @clauses.push(out)
    v = 0
    while v < @vertices
      color = colors
      while color < 8
        row = []
        bit = 0
        while bit < 3
          x = 3 * v + bit + 1
          row.push(((color >> bit) & 1) == 0 ? x : -x)
          bit += 1
        @clauses.push(row)
        color += 1
      v += 1

  -> formula
    size = 0
    @clauses.each -> (c) size += c.size
    lits = i64[size]
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

-> myciel_result(fixture)
  wassat_mycielski_refute(fixture.formula, i64[1])

describe "Checked Mycielski coloring obstruction" ->
  it "derives the lower bound from an edge and each verified layer" ->
    level = 0
    while level <= 2
      m = myciel_result(MycielFixture.new(level, level + 1))
      expect(m[0]).to eq(-1)
      expect(m[4]).to eq(level + 1)
      expect(m[5]).to eq(level + 2)
      expect(m[6]).to eq(level)
      level += 1

  it "declines when the palette admits a valid coloring" ->
    expect(myciel_result(MycielFixture.new(2, 4))[0]).to eq(0)

  it "counts the common palette rather than the largest local domain" ->
    f = MycielFixture.new(1, 3)
    # Original edge 0--1; shadows 2,3; apex 4. This is a proper 3-coloring.
    colors = [0, 1, 0, 1, 2]
    v = 0
    while v < 5
      b = 0
      while b < 3
        x = 3 * v + b + 1
        f.clauses.push([((colors[v] >> b) & 1) == 0 ? -x : x])
        b += 1
      v += 1
    m = myciel_result(f)
    expect(m[0]).to eq(0)
    expect(m[4]).to eq(3)

  it "requires every XOR clause and does not count duplicates as premises" ->
    missing = 0
    while missing < 4
      f = MycielFixture.new(1, 2)
      f.clauses[missing] = f.clauses[(missing + 1) % 4]
      expect(myciel_result(f)[0]).to eq(0)
      missing += 1

  it "checks graph edges instead of vertex and clause tallies" ->
    f = MycielFixture.new(1, 2)
    f.clauses[f.edge_clauses[0]] = f.clauses[f.edge_clauses[1]]
    expect(myciel_result(f)[0]).to eq(0)

  it "declines a polarity twist that changes inequality into equality" ->
    f = MycielFixture.new(1, 2)
    c = f.clauses[f.edge_clauses[0]]
    c[0] = -c[0]
    expect(myciel_result(f)[0]).to eq(0)

  it "supports complemented variables and reordered literals" ->
    f = MycielFixture.new(2, 3)
    f.clauses.each -> (c)
      i = 0
      while i < c.size
        c[i] = -c[i] if (c[i].abs % 3) == 1
        i += 1
      t = c[0]
      c[0] = c[c.size - 1]
      c[c.size - 1] = t
    expect(myciel_result(f)[0]).to eq(-1)

  it "supports vertex renumbering without consulting a graph name" ->
    f = MycielFixture.new(2, 3)
    f.clauses.each -> (c)
      i = 0
      while i < c.size
        x = c[i].abs
        if x <= 3 * f.vertices
          vertex = (x - 1) / 3
          bit = (x - 1) % 3
          mapped = 3 * ((vertex + 4) % f.vertices) + bit + 1
          c[i] = c[i] < 0 ? -mapped : mapped
        i += 1
    expect(myciel_result(f)[0]).to eq(-1)

  it "observes cancellation, deadlines and admission bounds" ->
    f = MycielFixture.new(1, 2).formula
    stop = i64[1]
    wassat_stop_cancel(stop)
    m = wassat_mycielski_refute(f, stop)
    expect(m[0]).to eq(0)
    expect(m[8]).to eq(1)
    m = wassat_mycielski_refute(f, i64[1], clock_ms() - 1)
    expect(m[0]).to eq(0)
    expect(m[8]).to eq(2)
    f["nvars"] = 10001
    expect(wassat_mycielski_refute(f, i64[1])[0]).to eq(0)
    f = MycielFixture.new(1, 2)
    f.clauses.push([1, 2, 3, 4])
    expect(myciel_result(f)[0]).to eq(0)

  it "does not certify a partial graph fold after work exhaustion" ->
    meta = i64[13]
    meta[7] = 2000000
    result = wassat_myciel_fold(i8[262144], i32[5120], i32[5120], i8[5120], 0, 5, meta, i64[1], 0)
    expect(result).to eq(0)
    expect(meta[8]).to eq(3)
    expect(meta[0]).to eq(0)

spec_summary
