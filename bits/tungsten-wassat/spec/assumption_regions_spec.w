use spec
use ../lib/assumption_regions

# A boundary conflict is concealed behind two free interior variables.
-> region_equality_input
  text = StringBuffer()
  text.append("p cnf 4 8\n")
  [-3, 3].each -> (z)
    [-4, 4].each -> (w)
      text.append("-1 2 [z] [w] 0\n1 -2 [z] [w] 0\n")
  wassat_parse_cnf(text.to_s)

describe "cached assumption regions" ->
  it "preserves a joint boundary relation and returns original-variable models and cores" ->
    f = region_equality_input
    cache = wassat_region_query_facts(f, [1, 2, 1])
    expect(cache.size).to eq(2)
    s = wassat_region_query_solver(f, [1, 2])
    conflict = s.solve_assuming([1, -2])
    expect(conflict["status"]).to eq(-1)
    expect(conflict["core"].sort).to eq([-2, 1])
    result = s.solve_assuming_budget([-2, 3, -4], 4)
    expect(result["status"]).to eq(1)
    expect(result["model"]).to eq([-1, -2, 3, -4])
    expect(wassat_model_satisfies?(f, result["model"])).to eq(true)
    expect(conflict["core"].sort).to eq([-2, 1])

  it "caches a forced interior literal and accepts assumptions on the interior" ->
    f = wassat_parse_cnf("p cnf 4 4\n-1 2 3 4 0\n-1 2 3 -4 0\n-1 2 -3 4 0\n-1 2 -3 -4 0\n")
    expect(wassat_region_query_facts(f, [1])).to eq([[-1, 2]])
    s = wassat_region_query_solver(f, [1])
    expect(s.solve_assuming([1, -2])["status"]).to eq(-1)
    expect(s.solve_assuming([-1, -2])["status"]).to eq(1)

  it "recovers an unconditional conflict and does not duplicate unit propagation" ->
    f = wassat_parse_cnf("p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n")
    expect(wassat_region_query_facts(f, [])).to eq([[]])
    r = wassat_region_query_solver(f, []).solve_assuming([1])
    expect(r["status"]).to eq(-1)
    expect(r["core"].empty?).to eq(true)
    easy = wassat_parse_cnf("p cnf 3 2\n-1 2 0\n-2 3 0\n")
    expect(wassat_region_query_facts(easy, [1])).to eq([])

  it "retains interior assignment 63 when it is the only witness" ->
    text = StringBuffer()
    text.append("p cnf 6 63\n")
    (0...63).each -> (row)
      (0...6).each -> (j)
        lit = j + 1
        lit = 0 - lit if ((row >> j) & 1) == 1
        text.append("[lit] ")
      text.append("0\n")
    f = wassat_parse_cnf(text.to_s)
    expect(wassat_region_query_facts(f, []).size).to eq(6)
    model = wassat_region_query_solver(f, []).solve_assuming([])["model"]
    expect(model).to eq([1, 2, 3, 4, 5, 6])

  it "ignores a component over the limit and keeps an independent small one" ->
    f = wassat_parse_cnf("p cnf 12 6\n-1 2 3 4 0\n-1 2 3 -4 0\n-1 2 -3 4 0\n-1 2 -3 -4 0\n5 6 7 8 9 10 11 12 0\n-5 6 7 8 9 10 11 12 0\n")
    expect(wassat_region_query_facts(f, [1])).to eq([[-1, 2]])

  it "finds a reason with part of the boundary unknown" ->
    f = wassat_parse_cnf("p cnf 5 4\n-1 2 3 4 0\n-1 2 3 -4 0\n5 2 -3 0\n-5 2 -3 0\n")
    expect(wassat_region_query_facts(f, [1, 5]).include?([-1, 2])).to eq(true)

  it "validates boundary IDs before accessing typed storage" ->
    f = region_equality_input
    expect(-> () wassat_region_query_solver(f, [0])).to raise_error
    expect(-> () wassat_region_query_solver(f, [5])).to raise_error
    expect(-> () wassat_region_query_solver(f, [-1])).to raise_error
    expect(-> () wassat_region_query_solver(f, [1.5])).to raise_error

spec_summary()
