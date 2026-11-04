+ AffineCircuitFixture
  ro :clauses, :nv
  -> new(np)
    @nv = np; @clauses = []; first = []; i = 1
    while i <= np
      first.push(-i); i += 1
    @clauses.push(first)

  -> gate(inputs, table)
    @nv += 1; z = @nv; state = 0
    while state < (1 << inputs.size)
      row = []; k = 0
      while k < inputs.size
        row.push(((state >> k) & 1) == 1 ? -inputs[k] : inputs[k]); k += 1
      row.push(((table >> state) & 1) == 1 ? z : -z)
      @clauses.push(row); state += 1
    z

  -> parity(a, b, odd)
    @clauses.push([a, odd ? b : -b])
    @clauses.push([-a, odd ? -b : b])

  -> flat
    n = 0
    @clauses.each -> (c) n += c.size
    lits = i64[n]; offs = i64[@clauses.size]; lens = i64[@clauses.size]
    p = 0; ci = 0
    @clauses.each -> (c)
      offs[ci] = p; lens[ci] = c.size
      c.each -> (l)
        lits[p] = l; p += 1
      ci += 1
    { "nvars": @nv, "flat_ncl": ci, "flat_nlits": n,
      "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

-> affine_fixture_checked(f, model)
  return false if model.size != f["nvars"]
  ci = 0
  while ci < f["flat_ncl"]
    hit = false; j = 0
    while j < f["flat_lens"][ci]
      l = f["flat_lits"][f["flat_offs"][ci] + j]; v = l < 0 ? -l : l
      hit = true if model[v - 1] == l
      j += 1
    return false unless hit
    ci += 1
  true
