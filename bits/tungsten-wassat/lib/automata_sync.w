# Verified SAT shortcut for bounded synchronizing-automaton encodings.
#
# The supported rendering has L image-set blocks of Q variables followed by
# L pairs of letter selectors.  Binary clauses encode the image of the full
# initial state set, ternary clauses propagate images through a complete
# binary DFA, a final negative clique enforces at most one active state, and
# one positive selector pair chooses a letter at every step.
#
# Recognition recovers both transition maps from clause incidence alone.  It
# then tries the two Černý words obtained by treating either letter as the
# merge map and the other as the cycle map.  A candidate is published only
# after expansion to every Boolean variable and an original-CNF model check by
# the caller.  Malformed, unsupported, and non-synchronizing formulas return
# no model and fall through to the ordinary solver.

WASSAT_AUTOMATA_SYNC_MAX_STATES = 512
WASSAT_AUTOMATA_SYNC_MAX_STEPS = 2000000

-> wassat_automata_state_var(q, step, state) (i64 i64 i64) i64
  step * q + state + 1

-> wassat_automata_selector_var(q, steps, step, letter) (i64 i64 i64 i64) i64
  q * steps + 2 * step + letter + 1

# The header equations are an allocation-free first gate:
#
#   nvars   = L * (Q + 2)
#   clauses = 2Q(L-1) + 2Q + choose(Q,2) + L
#
# Return [Q,L], requiring a unique bounded solution.
-> wassat_automata_dimensions(nv, ncl)
  found_q = 0
  found_l = 0
  q = 2
  while q <= WASSAT_AUTOMATA_SYNC_MAX_STATES
    if nv % (q + 2) == 0
      steps = nv / (q + 2)
      if steps >= 1 && steps <= WASSAT_AUTOMATA_SYNC_MAX_STEPS
        expected = 2 * q * (steps - 1) + 2 * q
        expected += q * (q - 1) / 2 + steps
        if expected == ncl
          return [] if found_q != 0
          found_q = q
          found_l = steps
    q += 1
  return [] if found_q == 0
  [found_q, found_l]

# Construct and simulate (merge cycle^(Q-1))^(Q-2) merge, padding a found
# singleton with the cycle letter when the encoding permits a longer word.
# `trans` stores destination+1 so zero remains the uninitialized sentinel.
-> wassat_automata_try_word(q, steps, merge, trans, values) (i64 i64 i64 i64[] i8[]) i64
  minimum = (q - 1) * (q - 1)
  return 0 if steps < minimum
  cycle = 1 - merge
  word = i8[steps]
  at = 0
  round = 0
  while round < q - 2
    word[at] = merge
    at += 1
    turn = 0
    while turn < q - 1
      word[at] = cycle
      at += 1
      turn += 1
    round += 1
  word[at] = merge
  at += 1
  while at < steps
    word[at] = cycle
    at += 1

  current = i8[q]
  next_states = i8[q]
  state = 0
  while state < q
    current[state] = 1
    state += 1

  step = 0
  while step < steps
    state = 0
    while state < q
      next_states[state] = 0
      state += 1
    letter = word[step]
    state = 0
    while state < q
      if current[state] == 1
        destination = trans[letter * q + state] - 1
        return 0 if destination < 0 || destination >= q
        next_states[destination] = 1
      state += 1

    state = 0
    while state < q
      values[wassat_automata_state_var(q, step, state)] = next_states[state]
      state += 1
    values[wassat_automata_selector_var(q, steps, step, 0)] = letter == 0 ? 1 : 0
    values[wassat_automata_selector_var(q, steps, step, 1)] = letter == 1 ? 1 : 0

    swap = current
    current = next_states
    next_states = swap
    step += 1

  active = 0
  state = 0
  while state < q
    active += 1 if current[state] == 1
    state += 1
  active == 1 ? 1 : 0

# Return a complete SAT model, or [] on every recognition/search miss.
-> wassat_automata_sync_model(formula)
  return [] unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  dims = wassat_automata_dimensions(nv, ncl)
  return [] if dims.empty?
  q = dims[0]
  steps = dims[1]
  state_limit = q * steps

  trans = i64[2 * q]
  transition_seen = i8[2 * q * (steps - 1)]
  initial_counts = i64[2 * q]
  selector_seen = i8[steps]
  final_seen = i8[q * q]

  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  ci = 0
  while ci < ncl
    n = lens[ci]
    off = offs[ci]
    if n == 3
      previous = 0
      destination = 0
      selector = 0
      j = 0
      while j < 3
        literal = lits[off + j]
        variable = literal < 0 ? 0 - literal : literal
        return [] if variable < 1 || variable > nv
        if variable <= state_limit
          if literal > 0
            return [] if destination != 0
            destination = variable
          else
            return [] if previous != 0
            previous = variable
        else
          return [] if literal > 0 || selector != 0
          selector = variable
        j += 1
      return [] if previous == 0 || destination == 0 || selector == 0

      selector_index = selector - state_limit - 1
      step = selector_index / 2
      letter = selector_index % 2
      return [] if step < 1 || step >= steps
      previous_index = previous - 1
      destination_index = destination - 1
      previous_step = previous_index / q
      destination_step = destination_index / q
      source_state = previous_index % q
      destination_state = destination_index % q
      return [] unless previous_step == step - 1 && destination_step == step

      slot = ((step - 1) * 2 + letter) * q + source_state
      return [] if transition_seen[slot] != 0
      transition_seen[slot] = 1
      map_slot = letter * q + source_state
      encoded = destination_state + 1
      if trans[map_slot] == 0
        trans[map_slot] = encoded
      else
        return [] unless trans[map_slot] == encoded
    elsif n == 2
      a = lits[off]
      b = lits[off + 1]
      av = a < 0 ? 0 - a : a
      bv = b < 0 ? 0 - b : b
      return [] if av < 1 || av > nv || bv < 1 || bv > nv || av == bv

      if a > 0 && b > 0 && av > state_limit && bv > state_limit
        ai = av - state_limit - 1
        bi = bv - state_limit - 1
        return [] unless ai / 2 == bi / 2 && ai % 2 != bi % 2
        step = ai / 2
        return [] if step < 0 || step >= steps || selector_seen[step] != 0
        selector_seen[step] = 1
      elsif a < 0 && b < 0 && av <= state_limit && bv <= state_limit
        ai = av - 1
        bi = bv - 1
        return [] unless ai / q == steps - 1 && bi / q == steps - 1
        as = ai % q
        bs = bi % q
        if as > bs
          swap = as
          as = bs
          bs = swap
        return [] if final_seen[as * q + bs] != 0
        final_seen[as * q + bs] = 1
      else
        positive = 0
        negative = 0
        if a > 0 && av <= state_limit && b < 0 && bv > state_limit
          positive = av
          negative = bv
        elsif b > 0 && bv <= state_limit && a < 0 && av > state_limit
          positive = bv
          negative = av
        else
          return []
        positive_index = positive - 1
        selector_index = negative - state_limit - 1
        return [] unless positive_index / q == 0 && selector_index / 2 == 0
        destination_state = positive_index % q
        letter = selector_index % 2
        initial_counts[letter * q + destination_state] += 1
    else
      return []
    ci += 1

  letter = 0
  while letter < 2
    state = 0
    expected_initial = i64[q]
    while state < q
      return [] if trans[letter * q + state] == 0
      expected_initial[trans[letter * q + state] - 1] += 1
      state += 1
    state = 0
    while state < q
      return [] unless initial_counts[letter * q + state] == expected_initial[state]
      state += 1
    letter += 1

  step = 0
  while step < steps
    return [] if selector_seen[step] == 0
    step += 1
  a = 0
  while a < q
    b = a + 1
    while b < q
      return [] if final_seen[a * q + b] == 0
      b += 1
    a += 1

  merge = 0
  while merge < 2
    values = i8[nv + 1]
    if wassat_automata_try_word(q, steps, merge, trans, values) == 1
      model = []
      v = 1
      while v <= nv
        model.push(values[v] == 1 ? v : 0 - v)
        v += 1
      return model
    merge += 1
  []
