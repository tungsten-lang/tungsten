# spec: compiled -- builds its formulas with the native DIMACS parser
use spec
use ../lib/wassat

-> cl_formula(nvars, lines)
  wassat_parse_cnf_native("p cnf [nvars] [lines.size]\n" + lines.join("\n") + "\n")

# x + y + z = rhs (mod 2): the four clauses forbidding the other parity.
-> cl_xor3(x, y, z, rhs)
  if rhs == 1
    ["[x] [y] [z] 0", "[x] [0 - y] [0 - z] 0", "[0 - x] [y] [0 - z] 0", "[0 - x] [0 - y] [z] 0"]
  else
    ["[0 - x] [y] [z] 0", "[x] [0 - y] [z] 0", "[x] [y] [0 - z] 0", "[0 - x] [0 - y] [0 - z] 0"]

-> cl_xor2(x, y, rhs)
  if rhs == 1
    ["[x] [y] 0", "[0 - x] [0 - y] 0"]
  else
    ["[x] [0 - y] 0", "[0 - x] [y] 0"]

-> cl_join(groups)
  lines = []
  groups.each -> (group)
    group.each -> (line)
      lines.push(line)
  lines

-> cl_flip(x, flip)
  v = x < 0 ? 0 - x : x
  return 0 - x if flip == 1 && v % 2 == 1
  x

# Relativized pigeonhole: np pigeons, nr resting places, nh holes. flip = 1
# negates every odd variable; drop is the index of one conflict clause to
# leave out (-1 for none).
-> cl_rphp(np, nr, nh, flip, drop)
  lines = []
  rbase = np * nr
  qbase = rbase + nr
  u = 0
  while u < np
    parts = []
    v = 0
    while v < nr
      parts.push(cl_flip(u * nr + v + 1, flip))
      a = cl_flip(0 - (u * nr + v + 1), flip)
      b = cl_flip(rbase + v + 1, flip)
      lines.push("[a] [b] 0")
      u2 = u + 1
      while u2 < np
        b = cl_flip(0 - (u2 * nr + v + 1), flip)
        lines.push("[a] [b] 0")
        u2 += 1
      v += 1
    lines.push(parts.join(" ") + " 0")
    u += 1
  conflict = 0
  v = 0
  while v < nr
    parts = [cl_flip(0 - (rbase + v + 1), flip)]
    w = 0
    while w < nh
      parts.push(cl_flip(qbase + v * nh + w + 1, flip))
      w += 1
    lines.push(parts.join(" ") + " 0")
    v2 = v + 1
    while v2 < nr
      w = 0
      while w < nh
        if conflict != drop
          a = cl_flip(0 - (rbase + v + 1), flip)
          b = cl_flip(0 - (rbase + v2 + 1), flip)
          c = cl_flip(0 - (qbase + v * nh + w + 1), flip)
          d = cl_flip(0 - (qbase + v2 * nh + w + 1), flip)
          lines.push("[a] [b] [c] [d] 0")
        conflict += 1
        w += 1
      v2 += 1
    v += 1
  cl_formula(qbase + nr * nh, lines)

describe "Wassat parity sum" ->
  it "refutes a Tseitin triangle with an odd total charge" ->
    # Vertices a, b, c; edges 1 = ab, 2 = bc, 3 = ca. Charges 1, 0, 0.
    f = cl_formula(3, cl_join([cl_xor2(1, 3, 1), cl_xor2(1, 2, 0), cl_xor2(2, 3, 0)]))
    r = wassat_parity_sum_unsat(f)
    expect(r["status"]).to eq(0 - 1)
    expect(r["work"][5]).to eq(3)

  it "does not refute an even total charge" ->
    f = cl_formula(3, cl_join([cl_xor2(1, 3, 1), cl_xor2(1, 2, 1), cl_xor2(2, 3, 0)]))
    expect(wassat_parity_sum_unsat(f)["status"]).to eq(0)

  it "ignores a parity constraint with a clause missing" ->
    lines = cl_join([cl_xor3(1, 2, 3, 1), cl_xor3(1, 2, 3, 0)])
    # All eight clauses forbid every assignment of the three variables.
    expect(wassat_parity_sum_unsat(cl_formula(3, lines))["status"]).to eq(0 - 1)
    lines.pop
    expect(wassat_parity_sum_unsat(cl_formula(3, lines))["status"]).to eq(0)

  it "leaves out an equation whose variable occurs nowhere else" ->
    # The triangle again, with a dangling fourth edge on one vertex.
    f = cl_formula(4, cl_join([cl_xor3(1, 3, 4, 1), cl_xor2(1, 2, 0), cl_xor2(2, 3, 0)]))
    expect(wassat_parity_sum_unsat(f)["status"]).to eq(0)

  it "reads exact cardinality constraints as parity equations" ->
    # Exactly 2 of {1,2,3,4}, exactly 3 of {1,2,3,4,5}, and 5 false.
    lines = []
    [[1, 2, 3], [1, 2, 4], [1, 3, 4], [2, 3, 4]].each -> (t)
      lines.push("[t[0]] [t[1]] [t[2]] 0")
      lines.push("[0 - t[0]] [0 - t[1]] [0 - t[2]] 0")
    [[1, 2, 3], [1, 2, 4], [1, 2, 5], [1, 3, 4], [1, 3, 5], [1, 4, 5], [2, 3, 4], [2, 3, 5], [2, 4, 5], [3, 4, 5]].each -> (t)
      lines.push("[t[0]] [t[1]] [t[2]] 0")
    [[1, 2, 3, 4], [1, 2, 3, 5], [1, 2, 4, 5], [1, 3, 4, 5], [2, 3, 4, 5]].each -> (q)
      lines.push("[0 - q[0]] [0 - q[1]] [0 - q[2]] [0 - q[3]] 0")
    lines.push("-5 0")
    r = wassat_parity_sum_unsat(cl_formula(5, lines))
    expect(r["status"]).to eq(0 - 1)
    expect(r["work"][7]).to eq(2)
    lines.pop
    expect(wassat_parity_sum_unsat(cl_formula(5, lines))["status"]).to eq(0)

describe "Wassat demand against room" ->
  it "refutes a conjunction that needs more leaves than there are groups" ->
    f = cl_formula(4, ["4 0", "-4 1 0", "-4 2 0", "-4 3 0", "-1 -2 0"])
    r = wassat_threshold_cover_unsat(f)
    expect(r["status"]).to eq(0 - 1)
    expect(r["work"][2]).to eq(3)
    expect(r["work"][3]).to eq(2)

  it "keeps quiet when the groups leave room" ->
    f = cl_formula(4, ["4 0", "-4 1 0", "-4 2 0", "-4 3 0"])
    expect(wassat_threshold_cover_unsat(f)["status"]).to eq(0)

  it "counts through an if-then-else node" ->
    # 5 -> (1 ? 7 : 6), 6 -> 2 & 3, 7 -> 2: two leaves either way, one group.
    f = cl_formula(7, ["5 0", "-5 1 6 0", "-5 -1 7 0", "-6 2 0", "-6 3 0", "-7 2 0", "-1 -2 0", "-2 -3 0", "-1 -3 0"])
    r = wassat_threshold_cover_unsat(f)
    expect(r["status"]).to eq(0 - 1)
    expect(r["work"][2]).to eq(2)
    expect(r["work"][3]).to eq(1)

  it "does not add one for a variable read again below" ->
    # 5 -> (1 ? 6 : 7), 6 -> (1 | 2), 7 -> 2 and 3. The true branch already
    # counts leaf 1, so one true leaf suffices (1, 5 and 6 true is a model);
    # adding one for the test variable would make it two against one group.
    f = cl_formula(7, ["5 0", "-5 1 7 0", "-5 -1 6 0", "-6 1 2 0", "-7 2 0", "-7 3 0", "-1 -2 0", "-1 -3 0", "-2 -3 0"])
    r = wassat_threshold_cover_unsat(f)
    expect(r["status"]).to eq(0)
    expect(r["work"][2]).to eq(1)
    expect(r["work"][3]).to eq(1)

describe "Wassat covering bound" ->
  it "counts pigeons against holes" ->
    # Pigeon i sits in hole A (2i - 1) or B (2i); a hole takes one pigeon.
    f = cl_formula(6, ["1 2 0", "3 4 0", "5 6 0", "-1 -3 0", "-1 -5 0", "-3 -5 0", "-2 -4 0", "-2 -6 0", "-4 -6 0"])
    r = wassat_cover_bound_unsat(f)
    expect(r["status"]).to eq(0 - 1)
    expect(r["work"][3]).to eq(2)
    expect(r["work"][2]).to eq(2)

  it "accepts two pigeons" ->
    f = cl_formula(4, ["1 2 0", "3 4 0", "-1 -3 0", "-2 -4 0"])
    expect(wassat_cover_bound_unsat(f)["status"]).to eq(0)

describe "Wassat relayed pigeonhole count" ->
  it "sends three pigeons through four resting places into two holes" ->
    r = wassat_relay_count_unsat(cl_rphp(3, 4, 2, 0, 0 - 1))
    expect(r["status"]).to eq(0 - 1)
    expect(r["work"][1]).to eq(3)
    expect(r["work"][2]).to eq(2)
    expect(r["work"][3]).to eq(4)
    expect(r["work"][4]).to eq(8)

  it "reads literals, not variables, so scrambled signs change nothing" ->
    r = wassat_relay_count_unsat(cl_rphp(3, 4, 2, 1, 0 - 1))
    expect(r["status"]).to eq(0 - 1)
    expect(r["work"][1]).to eq(3)
    expect(r["work"][2]).to eq(2)

  it "keeps quiet when one conflict clause is missing" ->
    # Two resting places may then share a hole, which leaves room.
    r = wassat_relay_count_unsat(cl_rphp(3, 4, 2, 0, 0))
    expect(r["status"]).to eq(0)
    expect(r["work"][1]).to eq(3)
    expect(r["work"][2]).to eq(3)

  it "keeps quiet with a hole for every pigeon" ->
    expect(wassat_relay_count_unsat(cl_rphp(3, 4, 3, 1, 0 - 1))["status"]).to eq(0)

describe "Wassat bounded variable addition" ->
  it "factors a product of binary clauses with one fresh variable" ->
    lines = []
    [1, 2, 3, 4].each -> (m)
      [5, 6, 7, 8, 9].each -> (r)
        lines.push("[r] [m] 0")
    f = cl_formula(9, lines)
    r = wassat_bva_lift(f, 0, 2, 8, 0)
    expect(r != nil).to eq(true)
    expect(r["formula"] != nil).to eq(true)
    expect(r["formula"]["nvars"]).to eq(10)
    expect(r["formula"]["flat_ncl"]).to eq(9)

  it "declines a formula that is not dense enough" ->
    lines = []
    [1, 2, 3, 4].each -> (m)
      [5, 6, 7, 8, 9].each -> (r)
        lines.push("[r] [m] 0")
    expect(wassat_bva_lift(cl_formula(9, lines), 0, 2, 8, 24)).to eq(nil)
