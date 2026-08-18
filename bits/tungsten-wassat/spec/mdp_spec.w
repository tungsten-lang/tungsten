use spec
use wassat

# Small synthetic instance of Bryant's public MIT-licensed MDP encoding.
-> mdp_fixture_clause(lines, values)
  lines.push(values.join(" ") + " 0")

-> mdp_fixture_parity(lines, variables, phase)
  pattern = 0
  count = 1 << variables.size
  while pattern < count
    zero_parity = (
      variables.size - BitOps.count_ones_u64(pattern)
    ) & 1
    if zero_parity != phase
      clause = []
      j = 0
      while j < variables.size
        variable = variables[j]
        clause.push(
          ((pattern >> j) & 1) == 1 ? variable : 0 - variable
        )
        j += 1
      mdp_fixture_clause(lines, clause)
    pattern += 1

-> mdp_fixture_parity_chain(lines, variables, phase, state)
  current = variables
  while current.size > 4
    fresh = state[0]
    state[0] += 1
    mdp_fixture_parity(
      lines, [current[0], current[1], current[2], fresh], 0
    )
    next_variables = []
    j = 3
    while j < current.size
      next_variables.push(current[j])
      j += 1
    next_variables.push(fresh)
    current = next_variables
  mdp_fixture_parity(lines, current, phase)

-> mdp_fixture_counter(lines, n, tolerated, state)
  m = 2 * n
  stride = tolerated + 1
  counter = i64[m * stride]
  counter[0] = 0 - (n + 1)

  i = 1
  while i < m - tolerated
    here = state[0]
    state[0] += 1
    counter[i * stride] = here
    local = n + 1 + i
    previous = counter[(i - 1) * stride]
    mdp_fixture_clause(lines, [0 - local, 0 - here])
    mdp_fixture_clause(lines, [previous, 0 - here])
    mdp_fixture_clause(lines, [local, 0 - previous, here])
    i += 1

  bound = 1
  while bound <= tolerated
    i = bound
    here = state[0]
    state[0] += 1
    counter[(i * stride) + bound] = here
    local = n + 1 + i
    previous_lower = counter[((i - 1) * stride) + bound - 1]
    mdp_fixture_clause(
      lines, [0 - local, previous_lower, 0 - here]
    )
    mdp_fixture_clause(lines, [local, here])
    mdp_fixture_clause(lines, [0 - previous_lower, here])

    i = bound + 1
    while i < m + bound - tolerated
      here = state[0]
      state[0] += 1
      counter[(i * stride) + bound] = here
      local = n + 1 + i
      previous = counter[((i - 1) * stride) + bound]
      previous_lower = counter[((i - 1) * stride) + bound - 1]
      mdp_fixture_clause(lines, [previous, 0 - here])
      mdp_fixture_clause(
        lines, [0 - local, previous_lower, 0 - here]
      )
      mdp_fixture_clause(
        lines, [0 - previous_lower, 0 - previous, here]
      )
      mdp_fixture_clause(lines, [local, 0 - previous, here])
      i += 1
    bound += 1

  mdp_fixture_clause(
    lines, [counter[((m - 1) * stride) + tolerated]]
  )

-> mdp_fixture_cnf
  n = 8
  tolerated = 2
  masks = [
    254, 253, 251, 247, 239, 223, 191, 127,
    15, 30, 60, 120, 240, 225, 195, 135
  ]
  planted = 181
  lines = []
  state = i64[1]
  state[0] = 3 * n + 1

  sample = 0
  while sample < 2 * n
    variables = [n + 1 + sample]
    bit = 0
    while bit < n
      variables.push(bit + 1) if ((masks[sample] >> bit) & 1) == 1
      bit += 1
    phase = BitOps.count_ones_u64(
      masks[sample] & planted
    ) & 1
    phase = phase ^ 1 if sample == 8 || sample == 13
    mdp_fixture_parity_chain(lines, variables, phase, state)
    sample += 1

  mdp_fixture_counter(lines, n, tolerated, state)
  "p cnf [state[0] - 1] [lines.size]\n" + lines.join("\n") + "\n"

describe "Wassat Minimum Disagreement Parity shortcut" ->
  it "reconstructs every noisy parity sample and the exact counter bound" ->
    formula = wassat_parse_cnf_native(mdp_fixture_cnf)
    sample_masks = i64[2 * WASSAT_MDP_MAX_BITS]
    sample_rhs = i8[2 * WASSAT_MDP_MAX_BITS]
    meta = i64[5]
    expect(wassat_mdp_recognize(
      formula, sample_masks, sample_rhs, meta
    )).to eq(true)
    expect(meta[0]).to eq(8)
    expect(meta[1]).to eq(2)
    expect(meta[2] > 16).to eq(true)

  it "decodes, completes, and verifies a full SAT model" ->
    formula = wassat_parse_cnf_native(mdp_fixture_cnf)
    result = wassat_mdp_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["disagreements"] <= 2).to eq(true)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "falls through when an XOR truth table is incomplete" ->
    text = mdp_fixture_cnf.replace(
      "9 -2 -3 -25 0", "9 -2 -3 25 0"
    )
    formula = wassat_parse_cnf_native(text)
    expect(wassat_mdp_solve(formula)["recognized"]).to eq(false)

  it "rejects an XOR-only task at the constant-time final-unit gate" ->
    text = "p cnf 3 4\n"
    text += "-1 2 3 0\n1 -2 3 0\n"
    text += "1 2 -3 0\n-1 -2 -3 0\n"
    formula = wassat_parse_cnf_native(text)
    expect(wassat_mdp_solve(formula)["recognized"]).to eq(false)

  it "falls through when the unary counter assertion is inverted" ->
    text = mdp_fixture_cnf
    original = wassat_parse_cnf_native(text)
    nv = original["nvars"]
    text = text.replace("\n[nv] 0\n", "\n-[nv] 0\n")
    formula = wassat_parse_cnf_native(text)
    expect(wassat_mdp_solve(formula)["recognized"]).to eq(false)

  it "returns a verified SAT model in proof mode without an artifact" ->
    bin = env("WASSAT_TEST_BIN")
    expect(bin == nil).to eq(false)
    input = "/tmp/wassat-mdp-proof-mode.cnf"
    proof = "/tmp/wassat-mdp-proof-mode.drat"
    output = "/tmp/wassat-mdp-proof-mode.out"
    expect(write_file(input, mdp_fixture_cnf)).to eq(true)
    File.unlink(proof) if File.exist?(proof)
    cmd = "(" + bin + " " + input + " --drat " + proof
    cmd += " > " + output + " 2>&1); test $? -eq 10"
    expect(system(cmd)).to eq(true)
    text = read_file(output)
    expect(text.include?("s SATISFIABLE")).to eq(true)
    expect(text.include?(
      "c mode: proof (verified MDP model)"
    )).to eq(true)
    expect(file?(proof)).to eq(false)

spec_summary
