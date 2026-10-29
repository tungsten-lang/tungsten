use spec
use ../lib/wassat

# Generic gate-circuit preimage lane. A gate [a, b, o, tt] forbids, for
# each input combination (a + 2*b), the output value tt does not select.

-> circuit_gate_clauses(lines, gate)
  combo = 0
  while combo < 4
    va = combo & 1
    vb = (combo >> 1) & 1
    want = (gate[3] >> combo) & 1
    la = va == 1 ? 0 - gate[0] : gate[0]
    lb = vb == 1 ? 0 - gate[1] : gate[1]
    lo = want == 1 ? gate[2] : 0 - gate[2]
    lines.push("[la] [lb] [lo] 0")
    combo += 1

-> circuit_cnf(nv, gates, units, break_first_gate = false)
  lines = []
  gates.each -> (gate)
    circuit_gate_clauses(lines, gate)
  if break_first_gate
    lines[3] = lines[0]
  units.each -> (u)
    lines.push("[u] 0")
  "p cnf [nv] [lines.size]\n" + lines.join("\n") + "\n"

CIRCUIT_XOR = 6
CIRCUIT_AND = 8
CIRCUIT_OR = 14
CIRCUIT_NOT_A = 5

describe "Wassat generic circuit preimage" ->
  it "finds a full-adder input for pinned sum and carry" ->
    gates = [
      [1, 2, 4, CIRCUIT_XOR],
      [3, 4, 5, CIRCUIT_XOR],
      [1, 2, 6, CIRCUIT_AND],
      [3, 4, 7, CIRCUIT_AND],
      [6, 7, 8, CIRCUIT_OR]
    ]
    text = circuit_cnf(8, gates, [5, 8])
    formula = wassat_parse_cnf_native(text)
    model = wassat_circuit_model(formula)
    expect(model.empty?).to eq(false)
    expect(wassat_model_satisfies?(formula, model)).to eq(true)

  it "accepts arbitrary truth tables, including projection negation" ->
    text = circuit_cnf(3, [[1, 2, 3, CIRCUIT_NOT_A]], [3])
    formula = wassat_parse_cnf_native(text)
    model = wassat_circuit_model(formula)
    expect(model.empty?).to eq(false)
    expect(model[0]).to eq(-1)
    expect(wassat_model_satisfies?(formula, model)).to eq(true)

  it "returns no model for an impossible pinning (model-only lane)" ->
    text = circuit_cnf(3, [[1, 2, 3, CIRCUIT_XOR]], [-1, -2, 3])
    formula = wassat_parse_cnf_native(text)
    expect(wassat_circuit_model(formula).empty?).to eq(true)

  it "rejects a gate group with a duplicated pattern" ->
    text = circuit_cnf(3, [[1, 2, 3, CIRCUIT_XOR]], [3], true)
    formula = wassat_parse_cnf_native(text)
    expect(wassat_circuit_model(formula).empty?).to eq(true)

spec_summary
