use spec
use ../lib/wassat

-> par32_units_oracle(clauses, val, st)
  i = 0
  while i < 4
    st[i] = 0
    i += 1
  changed = true
  while changed
    changed = false
    st[0] += 1
    ci = 0
    while ci < clauses.size
      st[1] += 1
      c = clauses[ci]
      sat = false
      unset = 0
      last_l = 0
      j = 0
      while j < c.size
        st[2] += 1
        l = c[j]
        av = val[l.abs]
        if av != 0
          if (l > 0 && av == 1) || (l < 0 && av == -1)
            sat = true
            j = c.size
          else
            j += 1
        else
          unset += 1
          last_l = l
          j += 1
      unless sat
        return false if unset == 0
        if unset == 1
          val[last_l.abs] = last_l > 0 ? 1 : -1
          changed = true
          st[3] += 1
      ci += 1
  true

-> par32_units_compare(nv, clauses, preset = [])
  a = i8[nv + 1]
  b = i8[nv + 1]
  preset.each ->(l)
    a[l.abs] = l > 0 ? 1 : -1
    b[l.abs] = l > 0 ? 1 : -1
  offs = i64[clauses.size]
  lens = i64[clauses.size]
  lits = i64[3 * clauses.size + 1]
  ci = 0
  top = 0
  while ci < clauses.size
    c = clauses[ci]
    offs[ci] = top
    lens[ci] = c.size
    c.each ->(l)
      lits[top] = l
      top += 1
    ci += 1
  sa = i64[4]
  sb = i64[4]
  sa[0] = 999
  sb[0] = 999
  want = par32_units_oracle(clauses, a, sa)
  have = wassat_par32_root_units(lits, offs, lens, b, sb, clauses.size)
  raise "unit closure result differs" unless want == have
  raise "unit closure assignment differs" unless a.to_s == b.to_s
  raise "unit closure counters differ" unless sa.to_s == sb.to_s
  true

describe "Parity decoder root unit scans" ->
  it "handles empty formulas and immediate or delayed contradictions" ->
    expect(par32_units_compare(3, [])).to eq(true)
    expect(par32_units_compare(3, [[]])).to eq(true)
    expect(par32_units_compare(3, [[1], [-1]])).to eq(true)
    expect(par32_units_compare(3, [[-2], [-1, 2], [1]])).to eq(true)
  it "preserves scan order through reverse dependency chains" ->
    values = i8[4]
    stats = i64[4]
    literals = i64[5]
    literals[0] = 1; literals[1] = -2
    literals[2] = 2; literals[3] = -3; literals[4] = 3
    offsets = i64[3]
    offsets[1] = 2; offsets[2] = 4
    lengths = i64[3]
    lengths[0] = 2; lengths[1] = 2; lengths[2] = 1
    closed = wassat_par32_root_units(literals, offsets, lengths, values, stats, 3)
    expect([closed, values[1], values[2], values[3]]).to eq([true, 1, 1, 1])
    expect([stats[0], stats[1], stats[2], stats[3]]).to eq([4, 12, 17, 3])
    cs = []
    v = 1
    while v < 33
      cs.push([v, 0 - (v + 1)])
      v += 1
    cs.push([33])
    expect(par32_units_compare(33, cs)).to eq(true)
    cs.push([-1])
    expect(par32_units_compare(33, cs)).to eq(true)
  it "retains repeated and complementary literal behavior and preassigned values" ->
    expect(par32_units_compare(4, [[1, 1], [2, -2], [-1, 3], [-3, 4]], [1])).to eq(true)
    expect(par32_units_compare(4, [[-2], [2, 3]], [2])).to eq(true)
  it "matches the scalar oracle on 256 generated clause lists" ->
    seed = 73
    rep = 0
    while rep < 256
      cs = []
      ci = 0
      while ci < 24
        seed = (seed * 1103515245 + 12345) % 2147483647
        width = 1 + seed % 3
        c = []
        j = 0
        while j < width
          seed = (seed * 1103515245 + 12345) % 2147483647
          l = 1 + seed % 9
          l = 0 - l if (seed / 9) % 2 == 1
          c.push(l)
          j += 1
        if rep % 2 == 0
          v = c[0].abs
          c[0] = v % 2 == 1 ? v : 0 - v
        cs.push(c)
        ci += 1
      par32_units_compare(9, cs)
      rep += 1
    expect(rep).to eq(256)

spec_summary
