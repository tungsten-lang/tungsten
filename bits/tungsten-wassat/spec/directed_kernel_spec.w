use spec
use wassat

# `attackers[v - 1]` is the ordered list of variables attacking v.
-> directed_kernel_text(attackers)
  lines = []
  v = 1
  attackers.each -> (row)
    row.each -> (a)
      lines.push("[0 - v] [0 - a] 0")
    positive = [v]
    row.each -> (a)
      positive.push(a)
    lines.push(positive.join(" ") + " 0")
    v += 1
  "p cnf [attackers.size] [lines.size]\n" + lines.join("\n") + "\n"

-> directed_kernel_formula(attackers)
  wassat_parse_cnf_native(directed_kernel_text(attackers))

-> directed_kernel_model_count(formula, nvars)
  count = 0
  mask = 0
  while mask < (1 << nvars) && count < 2
    model = []
    v = 1
    while v <= nvars
      model.push((mask & (1 << (v - 1))) == 0 ? 0 - v : v)
      v += 1
    count += 1 if wassat_model_satisfies?(formula, model)
    mask += 1
  count

describe "Wassat exact directed-kernel SCC prefix" ->
  it "assembles an all-unique SAT model across a DAG" ->
    # 1 is selected, forcing 2 out; 2 being out forces 3 in.
    formula = directed_kernel_formula([[], [1], [2]])
    result = wassat_directed_kernel_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["components"]).to eq(3)
    expect(result["unique"]).to eq(3)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "refutes an odd directed cycle exactly" ->
    formula = directed_kernel_formula([[3], [1], [2]])
    result = wassat_directed_kernel_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["components"]).to eq(1)
    expect(result["status"]).to eq(-1)

  it "handles an exact self-attack obstruction" ->
    formula = directed_kernel_formula([[1]])
    result = wassat_directed_kernel_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(-1)

  it "falls through on a component with multiple kernels" ->
    formula = directed_kernel_formula([[2], [1]])
    result = wassat_directed_kernel_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["multi"]).to eq(1)

  it "continues an independent sibling after a MULTI component" ->
    # One source SCC is MULTI; the independent odd cycle remains ready and
    # supplies an exact global refutation.
    formula = directed_kernel_formula([[3], [1], [2], [5], [4]])
    result = wassat_directed_kernel_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(-1)
    expect(result["multi"]).to eq(1)
    expect(result["checked"]).to eq(2)

  it "uses a unique selected ancestor to condition a child exactly" ->
    # 1 is the only source kernel. Its attack forces 2 out, after which the
    # conditioned 2->3->4->2 cycle has the unique assignment -2,3,-4.
    formula = directed_kernel_formula([[], [4, 1], [2], [3]])
    result = wassat_directed_kernel_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["unique"]).to eq(2)
    expect(result["model"]).to eq([1, -2, 3, -4])
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "does not descend through a MULTI ancestor using an arbitrary model" ->
    # The child odd cycle is inconsistent for one source model but satisfiable
    # for the other. Guessing a source model could therefore manufacture a
    # false global UNSAT result.
    formula = directed_kernel_formula([[2], [1], [5, 1], [3], [4]])
    expect(wassat_model_satisfies?(formula, [1, -2, -3, 4, -5])).to eq(true)
    result = wassat_directed_kernel_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["checked"]).to eq(1)
    expect(result["multi"]).to eq(1)

  it "returns UNKNOWN rather than guessing when its node cap expires" ->
    result = wassat_directed_kernel_solve(
      directed_kernel_formula([[2], [1]]), 1
    )
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)

  it "defers a large dense single SCC to the general SAT race" ->
    expect(wassat_directed_defer_dense_single_scc?(320, 1, 30406)).to eq(true)
    expect(wassat_directed_defer_dense_single_scc?(384, 1, 43789)).to eq(true)
    expect(wassat_directed_defer_dense_single_scc?(127, 1, 100000)).to eq(false)
    expect(wassat_directed_defer_dense_single_scc?(320, 2, 30406)).to eq(false)
    expect(wassat_directed_defer_dense_single_scc?(320, 1, 10239)).to eq(false)

  it "rejects mismatched, reordered, and extra clauses" ->
    mismatch = wassat_parse_cnf_native(
      "p cnf 2 4\n-1 -2 0\n1 2 0\n-2 -1 0\n2 2 0\n"
    )
    reordered = wassat_parse_cnf_native(
      "p cnf 2 4\n1 2 0\n-1 -2 0\n-2 -1 0\n2 1 0\n"
    )
    reversed = wassat_parse_cnf_native(
      "p cnf 2 4\n-2 -1 0\n1 2 0\n-2 -1 0\n2 1 0\n"
    )
    extra = wassat_parse_cnf_native(
      "p cnf 2 5\n-1 -2 0\n1 2 0\n-2 -1 0\n2 1 0\n1 -2 0\n"
    )
    expect(wassat_directed_kernel_solve(mismatch)["recognized"]).to eq(false)
    expect(wassat_directed_kernel_solve(reordered)["recognized"]).to eq(false)
    expect(wassat_directed_kernel_solve(reversed)["recognized"]).to eq(false)
    expect(wassat_directed_kernel_solve(extra)["recognized"]).to eq(false)

  it "never proves a false result on every directed graph through four vertices" ->
    sound = true
    nvars = 1
    while nvars <= 4
      edge_mask = 0
      while edge_mask < (1 << (nvars * nvars))
        attackers = []
        target = 1
        while target <= nvars
          row = []
          attacker = 1
          while attacker <= nvars
            bit = (attacker - 1) * nvars + target - 1
            row.push(attacker) if ((edge_mask >> bit) & 1) == 1
            attacker += 1
          attackers.push(row)
          target += 1
        formula = directed_kernel_formula(attackers)
        count = directed_kernel_model_count(formula, nvars)
        result = wassat_directed_kernel_solve(formula, 1000000)
        sound = false unless result["recognized"]
        sound = false if result["status"] == -1 && count != 0
        if result["status"] == 1
          sound = false unless count == 1
          sound = false unless wassat_model_satisfies?(
            formula, result["model"]
          )
        sound = false unless result["status"] == -1 || result["status"] == 0 || result["status"] == 1
        edge_mask += 1
      nvars += 1
    expect(sound).to eq(true)

spec_summary
