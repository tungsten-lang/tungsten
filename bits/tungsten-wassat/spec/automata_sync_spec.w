use spec
use wassat

-> automata_sync_cnf(q, steps, transition0, transition1)
  lines = []
  transitions = [transition0, transition1]

  step = 1
  while step < steps
    state = 0
    while state < q
      letter = 0
      while letter < 2
        previous = wassat_automata_state_var(q, step - 1, state)
        destination = wassat_automata_state_var(
          q, step, transitions[letter][state]
        )
        selector = wassat_automata_selector_var(q, steps, step, letter)
        lines.push("-[previous] [destination] -[selector] 0")
        letter += 1
      state += 1
    step += 1

  state = 0
  while state < q
    letter = 0
    while letter < 2
      destination = wassat_automata_state_var(
        q, 0, transitions[letter][state]
      )
      selector = wassat_automata_selector_var(q, steps, 0, letter)
      lines.push("[destination] -[selector] 0")
      letter += 1
    state += 1

  a = 0
  while a < q
    b = a + 1
    while b < q
      av = wassat_automata_state_var(q, steps - 1, a)
      bv = wassat_automata_state_var(q, steps - 1, b)
      lines.push("-[av] -[bv] 0")
      b += 1
    a += 1

  step = 0
  while step < steps
    s0 = wassat_automata_selector_var(q, steps, step, 0)
    s1 = wassat_automata_selector_var(q, steps, step, 1)
    lines.push("[s0] [s1] 0")
    step += 1

  nv = steps * (q + 2)
  "p cnf [nv] [lines.size]\n" + lines.join("\n") + "\n"

describe "Wassat synchronizing-automaton shortcut" ->
  it "constructs a checked Černý model from clause structure" ->
    q = 4
    steps = 9
    merge = [1, 1, 2, 3]
    cycle = [1, 2, 3, 0]
    formula = wassat_parse_cnf_native(
      automata_sync_cnf(q, steps, merge, cycle)
    )
    model = wassat_automata_sync_model(formula)
    expect(model.empty?).to eq(false)
    expect(wassat_model_satisfies?(formula, model)).to eq(true)

  it "accepts a longer bound by padding the synchronized singleton" ->
    q = 4
    merge = [1, 1, 2, 3]
    cycle = [1, 2, 3, 0]
    formula = wassat_parse_cnf_native(
      automata_sync_cnf(q, 12, merge, cycle)
    )
    model = wassat_automata_sync_model(formula)
    expect(model.empty?).to eq(false)
    expect(wassat_model_satisfies?(formula, model)).to eq(true)

  it "rejects a transition clause inconsistent across time slices" ->
    text = automata_sync_cnf(4, 9, [1, 1, 2, 3], [1, 2, 3, 0])
    text = text.replace("-1 6 -39 0", "-1 7 -39 0")
    formula = wassat_parse_cnf_native(text)
    expect(wassat_automata_sync_model(formula).empty?).to eq(true)

  it "falls through when neither recovered letter synchronizes" ->
    identity = [0, 1, 2, 3]
    formula = wassat_parse_cnf_native(
      automata_sync_cnf(4, 9, identity, identity)
    )
    expect(wassat_automata_sync_model(formula).empty?).to eq(true)

spec_summary
