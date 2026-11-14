# spec: compiled -- builds its formulas with the native DIMACS parser
use spec
use ../lib/wassat

-> gc_and(o, a, b)
  ["[o] [0 - a] [0 - b] 0", "[0 - o] [a] 0", "[0 - o] [b] 0"]

-> gc_xor(o, a, b)
  ["[0 - o] [a] [b] 0", "[0 - o] [0 - a] [0 - b] 0", "[o] [0 - a] [b] 0", "[o] [a] [0 - b] 0"]

-> gc_ite(o, c, t, e)
  ["[0 - c] [0 - t] [o] 0", "[0 - c] [t] [0 - o] 0", "[c] [0 - e] [o] 0", "[c] [e] [0 - o] 0"]

-> gc_formula(nvars, groups)
  lines = []
  groups.each -> (group)
    group.each -> (line)
      lines.push(line)
  wassat_parse_cnf_native("p cnf [nvars] [lines.size]\n" + lines.join("\n") + "\n")

# Does the clause list hold under the assignment in `mask` (bit v-1)?
-> gc_holds?(f, from, upto, mask)
  lits = f["flat_lits"]
  offs = f["flat_offs"]
  lens = f["flat_lens"]
  ok = true
  ci = from
  while ci < upto
    hit = false
    j = 0
    while j < lens[ci]
      lit = lits[offs[ci] + j]
      v = lit > 0 ? lit : 0 - lit
      bit = (mask >> (v - 1)) & 1
      hit = true if (lit > 0 && bit == 1) || (lit < 0 && bit == 0)
      j += 1
    ok = false unless hit
    ci += 1
  ok

# Every appended clause must hold in every model of the input, and the two
# formulas must have the same models.
-> gc_added_implied?(f, lifted, nvars)
  ok = true
  models = 0
  mask = 0
  while mask < (1 << nvars)
    if gc_holds?(f, 0, f["flat_ncl"], mask)
      models += 1
      ok = false unless gc_holds?(lifted, f["flat_ncl"], lifted["flat_ncl"], mask)
    mask += 1
  ok && models > 0

# Exactly the same assignments satisfy both formulas.
-> gc_same_models?(f, g, nvars)
  same = true
  mask = 0
  while mask < (1 << nvars)
    a = gc_holds?(f, 0, f["flat_ncl"], mask)
    b = gc_holds?(g, 0, g["flat_ncl"], mask)
    same = false if a != b
    mask += 1
  same

-> gc_has_binary?(lifted, from, a, b)
  lits = lifted["flat_lits"]
  offs = lifted["flat_offs"]
  lens = lifted["flat_lens"]
  found = false
  ci = from
  while ci < lifted["flat_ncl"]
    if lens[ci] == 2
      x = lits[offs[ci]]
      y = lits[offs[ci] + 1]
      found = true if (x == a && y == b) || (x == b && y == a)
    ci += 1
  found

describe "Wassat gate congruence closure" ->
  it "merges equal AND gates and walks the merge up a layer" ->
    f = gc_formula(8, [gc_and(5, 1, 2), gc_and(6, 2, 1), gc_and(7, 5, 3), gc_and(8, 3, 6)])
    r = wassat_gate_closure_lift(f)
    expect(r != nil).to eq(true)
    expect(r["work"][16]).to eq(0)
    expect(r["work"][17]).to eq(2)
    expect(r["work"][1]).to eq(0)
    lifted = r["formula"]
    expect(lifted["flat_ncl"]).to eq(f["flat_ncl"] + 4)
    expect(gc_has_binary?(lifted, f["flat_ncl"], 0 - 6, 5)).to eq(true)
    expect(gc_has_binary?(lifted, f["flat_ncl"], 6, 0 - 5)).to eq(true)
    expect(gc_has_binary?(lifted, f["flat_ncl"], 0 - 8, 7)).to eq(true)
    expect(gc_added_implied?(f, lifted, 8)).to eq(true)

  it "reads XOR and if-then-else gates" ->
    f = gc_formula(8, [gc_ite(5, 1, 2, 3), gc_ite(6, 1, 2, 3), gc_xor(7, 5, 4), gc_xor(8, 4, 6)])
    r = wassat_gate_closure_lift(f)
    expect(r != nil).to eq(true)
    expect(r["work"][10] > 0).to eq(true)
    expect(r["work"][9] > 0).to eq(true)
    expect(r["work"][17]).to eq(2)
    expect(gc_has_binary?(r["formula"], f["flat_ncl"], 0 - 8, 7)).to eq(true)
    expect(gc_added_implied?(f, r["formula"], 8)).to eq(true)

  it "simplifies gates through constants and negated outputs" ->
    # 5 = 1 & 2 with 1 true leaves 5 = 2; 6 = 1 ? 3 : 4 leaves 6 = 3;
    # 7 = 6 ^ 3 is then false, and -8 = 2 & 1 makes 8 the negation of 5.
    f = gc_formula(8, [["1 0"], gc_and(5, 1, 2), gc_ite(6, 1, 3, 4), gc_xor(7, 6, 3), gc_and(0 - 8, 2, 1)])
    r = wassat_gate_closure_lift(f)
    expect(r != nil).to eq(true)
    expect(r["work"][1]).to eq(0)
    lifted = r["formula"]
    expect(gc_has_binary?(lifted, f["flat_ncl"], 0 - 5, 2)).to eq(true)
    expect(gc_has_binary?(lifted, f["flat_ncl"], 0 - 6, 3)).to eq(true)
    expect(gc_has_binary?(lifted, f["flat_ncl"], 0 - 8, 0 - 2)).to eq(true)
    expect(gc_added_implied?(f, lifted, 8)).to eq(true)

  it "turns a clash into clauses instead of a verdict" ->
    # 5 and 6 are the same AND, and the last two clauses make them differ.
    f = gc_formula(8, [gc_and(5, 1, 2), gc_and(6, 1, 2), ["5 6 0", "-5 -6 0", "7 8 0", "7 -8 0"]])
    r = wassat_gate_closure_lift(f)
    expect(r != nil).to eq(true)
    expect(r["work"][1]).to eq(1)
    lifted = r["formula"]
    expect(lifted["flat_ncl"] > f["flat_ncl"]).to eq(true)
    # No assignment satisfies the extended formula, and none satisfies the input.
    sat_in = 0
    sat_out = 0
    mask = 0
    while mask < 256
      sat_in += 1 if gc_holds?(f, 0, f["flat_ncl"], mask)
      sat_out += 1 if gc_holds?(lifted, 0, lifted["flat_ncl"], mask)
      mask += 1
    expect(sat_in).to eq(0)
    expect(sat_out).to eq(0)

  it "declines formulas without gates" ->
    f = wassat_parse_cnf_native("p cnf 8 8\n1 2 3 0\n-1 4 5 0\n2 -6 7 0\n-3 -7 8 0\n4 6 -8 0\n-2 5 -7 0\n1 -4 8 0\n-5 6 7 0\n")
    expect(wassat_gate_closure_lift(f) == nil).to eq(true)
    small = wassat_parse_cnf_native("p cnf 3 3\n1 -2 -3 0\n-1 2 0\n-1 3 0\n")
    expect(wassat_gate_closure_lift(small) == nil).to eq(true)

describe "Wassat gate closure rewriting" ->
  it "rewrites the clauses through the merged gates and drops the copies" ->
    f = gc_formula(8, [gc_and(5, 1, 2), gc_and(6, 2, 1), gc_and(7, 5, 3), gc_and(8, 3, 6)])
    r = wassat_gate_closure_reduce(f)
    expect(r != nil).to eq(true)
    expect(r["refuted"]).to eq(false)
    # Two of the four gates are copies: 6 clauses stay, and 6 and 8 keep two
    # binaries each that tie them to 5 and 7.
    expect(r["clauses_in"]).to eq(12)
    expect(r["clauses_out"]).to eq(10)
    expect(r["units"]).to eq(0)
    expect(gc_same_models?(f, r["formula"], 8)).to eq(true)

  it "follows a unit that the rewriting uncovers" ->
    # 5 and 6 are one gate, so (5 | 6) says 5, and 5 says 1 and 2.
    f = gc_formula(8, [gc_and(5, 1, 2), gc_and(6, 1, 2), ["5 6 0"], gc_xor(7, 3, 4), gc_xor(8, 4, 3)])
    r = wassat_gate_closure_reduce(f)
    expect(r != nil).to eq(true)
    expect(r["refuted"]).to eq(false)
    expect(r["units"]).to eq(4)
    expect(gc_same_models?(f, r["formula"], 8)).to eq(true)

  it "writes two clashing units when a clause becomes empty" ->
    f = gc_formula(8, [gc_and(5, 1, 2), gc_and(6, 1, 2), ["5 6 0", "-5 0"], gc_xor(7, 3, 4), gc_xor(8, 4, 3)])
    r = wassat_gate_closure_reduce(f)
    expect(r != nil).to eq(true)
    expect(r["refuted"]).to eq(true)
    expect(r["formula"]["flat_ncl"]).to eq(2)
    expect(gc_same_models?(f, r["formula"], 8)).to eq(true)

  it "returns the appended form for a clash inside the closure" ->
    f = gc_formula(8, [gc_and(5, 1, 2), gc_and(6, 1, 2), ["5 6 0", "-5 -6 0", "7 8 0", "7 -8 0"]])
    r = wassat_gate_closure_reduce(f)
    expect(r != nil).to eq(true)
    expect(r["rewritten"]).to eq(false)
    expect(r["work"][1]).to eq(1)
    expect(r["added_from"]).to eq(f["flat_ncl"])
    expect(gc_same_models?(f, r["formula"], 8)).to eq(true)

  it "appends instead of rewriting when few variables merge" ->
    # One merged pair among 20,001 variables is under one in 200.
    f = gc_formula(20001, [gc_and(5, 1, 2), gc_and(6, 2, 1), ["7 8 20001 0", "9 10 11 0", "-9 12 13 0"]])
    r = wassat_gate_closure_reduce(f)
    expect(r != nil).to eq(true)
    expect(r["rewritten"]).to eq(false)
    expect(r["formula"]["flat_ncl"]).to eq(f["flat_ncl"] + 2)

  it "appends when the rewritten formula is not a tenth shorter" ->
    # One merged pair saves one clause of 46. (Binary clauses, because the
    # gate scan is skipped when binaries are under an eighth of the clauses.)
    extra = []
    i = 0
    while i < 40
      extra.push("[7 + i] [8 + i] 0")
      i += 1
    f = gc_formula(50, [gc_and(5, 1, 2), gc_and(6, 2, 1), extra])
    r = wassat_gate_closure_reduce(f)
    expect(r != nil).to eq(true)
    expect(r["rewritten"]).to eq(false)
    expect(r["formula"]["flat_ncl"]).to eq(f["flat_ncl"] + 2)

  it "declines formulas without gates" ->
    f = wassat_parse_cnf_native("p cnf 8 8\n1 2 3 0\n-1 4 5 0\n2 -6 7 0\n-3 -7 8 0\n4 6 -8 0\n-2 5 -7 0\n1 -4 8 0\n-5 6 7 0\n")
    expect(wassat_gate_closure_reduce(f) == nil).to eq(true)

spec_summary

