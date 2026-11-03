use spec
use ../lib/wassat

-> tt_test_flat(rows, nv)
  nl = 0; rows.each -> (c) nl += c.size
  lits = i64[nl]; offs = i64[rows.size]; lens = i64[rows.size]; at = 0; ci = 0
  rows.each -> (c)
    offs[ci] = at; lens[ci] = c.size
    c.each -> (l)
      lits[at] = l; at += 1
    ci += 1
  {"nvars": nv, "flat_ncl": rows.size, "flat_nlits": nl, "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}

-> tt_test_formula(courses = 3, slots = 3, resources = 2, minimum = 3, mode = "base")
  nv = courses * slots; rows = []; c = 0
  while c < courses
    base = nv + 1; nv += slots * minimum
    rows.push([-base, c * slots + 1]); j = 1
    while j < minimum
      rows.push([-base - j]); j += 1
    i = 1
    while i < slots
      j = 1
      while j < minimum
        rows.push([-base - i * minimum - j, base + (i - 1) * minimum + j - 1]); j += 1
      j = 0
      while j < minimum
        unless mode == "break_chain" && c == 0 && i == 1 && j == 0
          rows.push([-base - i * minimum - j, base + (i - 1) * minimum + j, c * slots + i + 1])
        j += 1
      i += 1
    rows.push([nv]) unless mode == "drop_assertion" && c == 0
    c += 1
  choices = []; c = 0
  while c < courses
    xs = []; j = 0
    while j < resources
      nv += 1; xs.push(nv); j += 1
    choices.push(xs); d = xs.dup
    if mode == "extra_choice" && c == 0
      nv += 1; d.push(nv)
    rows.push(d) unless mode == "drop_domain" && c == 0
    c += 1
  teacher = 0; first_head = 0; other_head = 0
  while teacher < resources
    slot = 0
    while slot < slots
      heads = []; c = 0
      while c < courses
        a = nv + 1; b = nv + 2; nv += 2
        first_head = a if teacher == 0 && slot == 0 && c == 0
        other_head = a if teacher == 1 && slot == 0 && c == 0
        x = c * slots + slot + 1; y = choices[c][teacher]
        rows.push([-x, -y, a]); rows.push([-x, -y, b]); heads.push(a); c += 1
      i = 0
      while i < courses
        j = i + 1
        while j < courses
          rows.push([-heads[i], -heads[j]]) unless mode == "drop_conflicts"
          j += 1
        i += 1
      slot += 1
    teacher += 1
  rows.push([-first_head, other_head]) if mode == "bridge"
  rows = rows.map(-> (c) c.reverse) if mode == "reverse"
  tt_test_flat(rows, nv)

describe "Original-clause resource capacity refutation" ->
  it "checks minimum demand against available resource-slot cells" ->
    m = i64[64]
    expect(wassat_resource_refute(tt_test_formula, m, i64[2])).to eq(-1)
    expect(m[8]).to eq(9)
    expect(m[9]).to eq(6)
    expect(m[14]).to eq(18)

  it "accepts reversed literal order" ->
    expect(wassat_resource_refute(tt_test_formula(3, 3, 2, 3, "reverse"), i64[64], i64[2])).to eq(-1)

  it "does not refute a feasible capacity assignment" ->
    expect(wassat_resource_refute(tt_test_formula(2, 3, 2, 2), i64[64], i64[2])).to eq(0)

  it "does not trust auxiliary connectivity as a capacity proof" ->
    m = i64[64]
    expect(wassat_resource_refute(tt_test_formula(2, 3, 2, 2, "bridge"), m, i64[2])).to eq(0)
    expect(m[8] > m[9]).to eq(true)

  it "requires every original lower-counter recurrence" ->
    expect(wassat_resource_refute(tt_test_formula(3, 3, 2, 3, "break_chain"), i64[64], i64[2])).to eq(0)

  it "requires the asserted minimum" ->
    expect(wassat_resource_refute(tt_test_formula(3, 3, 2, 3, "drop_assertion"), i64[64], i64[2])).to eq(0)

  it "requires a complete original resource-choice clause" ->
    expect(wassat_resource_refute(tt_test_formula(3, 3, 2, 3, "drop_domain"), i64[64], i64[2])).to eq(0)

  it "checks every choice including an unsupported extra option" ->
    expect(wassat_resource_refute(tt_test_formula(3, 3, 2, 3, "extra_choice"), i64[64], i64[2])).to eq(0)

  it "requires original pairwise resource conflicts" ->
    expect(wassat_resource_refute(tt_test_formula(3, 3, 2, 3, "drop_conflicts"), i64[64], i64[2])).to eq(0)

  it "rejects undersized metadata and stop buffers" ->
    f = tt_test_formula
    expect(wassat_resource_refute(f, i64[63], i64[2])).to eq(0)
    expect(wassat_resource_refute(f, i64[64], i64[1])).to eq(0)

  it "resets reused counters" ->
    f = tt_test_formula; m = i64[64]
    expect(wassat_resource_refute(f, m, i64[2])).to eq(-1)
    first = m[14]
    expect(wassat_resource_refute(f, m, i64[2])).to eq(-1)
    expect(m[14]).to eq(first)

  it "honors cancellation before allocating scratch" ->
    stop = i64[2]; wassat_stop_cancel(stop); m = i64[64]
    expect(wassat_resource_refute(tt_test_formula, m, stop)).to eq(0)
    expect(m[0]).to eq(0)
    expect(m[11]).to eq(1)

  it "honors an expired deadline" ->
    m = i64[64]
    expect(wassat_resource_refute(tt_test_formula, m, i64[2], clock_ms() - 1)).to eq(0)
    expect(m[11]).to eq(2)

  it "validates original literal and clause spans" ->
    f = tt_test_formula; f["flat_lits"][0] = f["nvars"] + 1
    expect(wassat_resource_refute(f, i64[64], i64[2])).to eq(0)
    f = tt_test_formula; f["flat_offs"][0] = f["flat_nlits"]
    expect(wassat_resource_refute(f, i64[64], i64[2])).to eq(0)

  it "uses the logical literal length in overallocated buffers" ->
    f = tt_test_formula; original = f["flat_lits"]; padded = i64[original.size + 1]; i = 0
    while i < original.size
      padded[i] = original[i]; i += 1
    padded[i] = 9999999; f["flat_lits"] = padded
    expect(wassat_resource_refute(f, i64[64], i64[2])).to eq(-1)
    f["flat_nlits"] -= 1
    expect(wassat_resource_refute(f, i64[64], i64[2])).to eq(0)
