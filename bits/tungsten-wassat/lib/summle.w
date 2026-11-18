# Recover a bounded arithmetic-expression puzzle from CBMC word comparisons.
# The decoder supplies SAT assumptions only. Even a structurally identical
# formula can have extra constraints, so every model is checked on the CNF.
use solver
use preprocess

WASSAT_SUMMLE_MAX_INPUTS = 10
WASSAT_SUMMLE_MAX_STEPS = 8
WASSAT_SUMMLE_CONFLICT_CAP = 2000

# The encoder begins with a bank of two-input ANDs sharing an enable.
# Inspect only these twelve clauses before allocating or scanning anything.
-> wassat_summle_prefix(lits, offs, lens, nc) (i64[] i64[] i64[] i64) bool
  return false if nc < 12 || lens[0] != 2
  enable = lits[offs[0]]
  return false if enable <= 0
  ci = 0
  while ci < 12
    return false unless lens[ci] == 2 && lens[ci+1] == 2 && lens[ci+2] == 3
    a = offs[ci]; b = offs[ci+1]; c = offs[ci+2]
    gate = 0 - lits[a+1]; input = lits[b]
    return false unless gate > 0 && input > 0 && input != enable
    return false unless lits[a] == enable && lits[b+1] == 0 - gate
    return false unless lits[c] == 0 - enable && lits[c+1] == 0 - input && lits[c+2] == gate
    ci += 3
  true

# A long converse clause and all sixteen binary implications define
# gate <=> word == constant. Store the word start and decoded constant.
-> wassat_summle_equalities(lits, offs, lens, nc, word, code, count) (i64[] i64[] i64[] i64 i32[] i32[] i8[]) i64
  ci = 16; found = 0
  while ci < nc
    if lens[ci] == 17
      off = offs[ci]; gate = lits[off+16]; start = lits[off]
      start = 0 - start if start < 0
      bit = 0; value = 0
      while gate > 0 && bit < 16
        lit = lits[off+bit]; var = start + bit; before = ci - 16 + bit
        break unless (lit == var || lit == 0 - var) && lens[before] == 2
        pos = offs[before]
        break unless lits[pos] == 0 - lit && lits[pos+1] == 0 - gate
        value = value | (1 << bit) if lit < 0
        bit += 1
      if bit == 16
        return 0 if word[gate] != 0
        word[gate] = start; code[gate] = value
        count[start] += 1 if count[start] < 2
        found += 1
    ci += 1
  found

# A positive unit on (value_equality OR NOT index_equality) specifies an
# entry of the operand lookup table. Both arguments of each expression step
# have the same initial slots. Previous results occupy progressively more of
# the tail and consequently disappear from the constant table.
-> wassat_summle_decode(lits, offs, lens, nv, nc, selects, values, results, numbers, meta) (i64[] i64[] i64[] i64 i64 i32[] i32[] i32[] i32[] i64[]) bool
  word = i32[nv+1]; code = i32[nv+1]; count = i8[nv+1]
  return false if wassat_summle_equalities(lits, offs, lens, nc, word, code, count) == 0
  slot_rows = i32[nv+1]; table_word = i8[nv+1]
  stride = WASSAT_SUMMLE_MAX_INPUTS + WASSAT_SUMMLE_MAX_STEPS + 1
  entries = i32[2*WASSAT_SUMMLE_MAX_STEPS*stride]
  filled = i64[2*WASSAT_SUMMLE_MAX_STEPS]
  rows = 0; ci = 1; last = 0
  while ci < nc
    if lens[ci] == 1 && lens[ci-1] == 3
      gate = lits[offs[ci]]; off = offs[ci-1]
      vg = lits[off]; sg = 0 - lits[off+1]
      if gate > 0 && lits[off+2] == 0 - gate && vg > 0 && sg > 0 && word[vg] != 0 && word[sg] != 0
        selector = word[sg]; operand = word[vg]
        idx = code[sg]; value = code[vg]
        table_word[selector] = 1; table_word[operand] = 1
        row = slot_rows[selector]
        if row == 0 && idx == 0 && value == 0
          return false if rows == 2*WASSAT_SUMMLE_MAX_STEPS
          selects[rows] = selector; values[rows] = operand
          rows += 1; row = rows; slot_rows[selector] = row
        if row != 0 && values[row-1] == operand
          return false if idx >= stride
          at = (row-1)*stride+idx
          return false if (filled[row-1] & (1 << idx)) != 0 && entries[at] != value
          entries[at] = value; filled[row-1] = filled[row-1] | (1 << idx)
          last = idx if idx > last
    ci += 1
  return false if rows < 2 || (rows & 1) != 0
  steps = rows >> 1; inputs = last - steps
  return false if inputs < 2 || inputs > WASSAT_SUMMLE_MAX_INPUTS
  row = 0
  while row < rows
    idx = 0
    while idx <= last
      constant = idx <= inputs || idx > inputs + (row >> 1)
      present = (filled[row] & (1 << idx)) != 0
      return false if constant != present
      if present
        value = entries[row*stride+idx]
        if idx == 0 || idx > inputs
          return false if value != 0
        elsif row == 0
          numbers[idx-1] = value
        else
          return false if value != numbers[idx-1]
      idx += 1
    row += 1

  # Each result word has one final equality to the same nonzero target.
  # Ignore words already explained by an operand table and reject ambiguity.
  freq = i32[65536]; gate = 1
  while gate <= nv
    base = word[gate]
    if base > 0 && count[base] == 1 && table_word[base] == 0
      freq[code[gate]] += 1
    gate += 1
  target = 0; candidate = 1
  while candidate < 65536
    if freq[candidate] == steps
      return false if target != 0
      target = candidate
    candidate += 1
  return false if target == 0
  gate = 1; step = 0
  while gate <= nv
    base = word[gate]
    if base > 0 && code[gate] == target && count[base] == 1 && table_word[base] == 0
      results[step] = base
      step += 1
    gate += 1
  meta[0] = inputs; meta[1] = steps; meta[2] = target
  true

# Each DP state has an occurrence mask and a 16-bit value. The states for
# each mask occupy one contiguous range. A stamp per value deduplicates a
# whole mask without allocating a mask-by-value matrix or hashing in the loop.
# Negative child IDs denote original number slots. A postorder traversal
# allocates result slots exactly when the corresponding operation is emitted.
-> wassat_summle_emit(node, inputs, left, right, vals, slots, operands, outputs, stats) (i64 i64 i32[] i32[] i32[] i32[] i32[] i32[] i64[]) i64
  return 0 - left[node] if left[node] < 0
  a = left[node] ## i64
  b = right[node] ## i64
  aslot = wassat_summle_emit(a, inputs, left, right, vals, slots, operands, outputs, stats)
  bslot = wassat_summle_emit(b, inputs, left, right, vals, slots, operands, outputs, stats)
  step = stats[5]
  slots[2*step] = aslot; slots[2*step+1] = bslot
  operands[2*step] = vals[a]; operands[2*step+1] = vals[b]
  outputs[step] = vals[node]; stats[5] += 1
  inputs + step + 1

-> wassat_summle_search(numbers, slots, operands, outputs, stats) (i32[] i32[] i32[] i32[] i64[]) bool
  inputs = stats[0]; steps = stats[1]; target = stats[2]
  cap = 262144
  vals = i32[cap]; left = i32[cap]; right = i32[cap]
  limit = 1 << inputs; starts = i32[limit+1]; seen = i32[65536]
  used = 0; pairs = 0; mask = 1
  while mask < limit
    starts[mask] = used
    width = 0; scan = mask
    while scan != 0
      width += 1; scan = scan & (scan-1)
    if width == 1
      slot = 0
      while (1 << slot) != mask
        slot += 1
      return false if used >= cap
      vals[used] = numbers[slot]; left[used] = 0 - (slot+1); used += 1
    elsif width <= steps + 1
      part = (mask-1) & mask
      while part > 0
        other = mask ^ part
        if part < other
          i = starts[part]
          while i < starts[part+1]
            j = starts[other]
            while j < starts[other+1]
              pairs += 1
              return false if pairs > 4000000
              a = vals[i]; b = vals[j]; op = 0
              while op < 4
                x = i; y = j; value = 65536
                if op == 0
                  value = a+b
                elsif op == 1
                  # CBMC uses the low word and rejects a product smaller
                  # than either operand. Overflow can still pass that guard.
                  product = (a*b) & 65535
                  value = product if product >= a && product >= b
                else
                  if b > a
                    x = j; y = i
                  hi = vals[x]; lo = vals[y]
                  if op == 2
                    value = hi-lo
                  elsif lo > 0 && hi % lo == 0
                    value = hi / lo
                if value <= 65535 && seen[value] != mask
                  return false if used >= cap
                  seen[value] = mask; vals[used] = value
                  left[used] = x; right[used] = y; used += 1
                  if value == target
                    stats[3] = used; stats[4] = pairs
                    z = wassat_summle_emit(used-1, inputs, left, right, vals, slots, operands, outputs, stats)
                    return true
                op += 1
              j += 1
            i += 1
        part = (part-1) & mask
    mask += 1
    starts[mask] = used
  stats[3] = used; stats[4] = pairs
  false

-> wassat_summle_pin(bits, base, value)
  bit = 0
  while bit < 16
    lit = base + bit
    bits.push((value & (1 << bit)) != 0 ? lit : 0 - lit)
    bit += 1

-> wassat_summle_solve(formula, conflict_cap)
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv > 1000000 || nc > 3000000
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  return nil unless wassat_summle_prefix(lits, offs, lens, nc)
  return nil if env("WASSAT_SUMMLE") == "0"
  stats = i64[6]; numbers = i32[WASSAT_SUMMLE_MAX_INPUTS]
  selects = i32[2*WASSAT_SUMMLE_MAX_STEPS]; values = i32[2*WASSAT_SUMMLE_MAX_STEPS]
  results = i32[WASSAT_SUMMLE_MAX_STEPS]
  t = wassat_prof_clock()
  return nil unless wassat_summle_decode(lits, offs, lens, nv, nc, selects, values, results, numbers, stats)
  t = wassat_prof("summle.decode", t)
  slots = i32[2*WASSAT_SUMMLE_MAX_STEPS]; operands = i32[2*WASSAT_SUMMLE_MAX_STEPS]
  outputs = i32[WASSAT_SUMMLE_MAX_STEPS]
  return nil unless wassat_summle_search(numbers, slots, operands, outputs, stats)
  t = wassat_prof("summle.search", t)
  assumptions = []
  step = 0
  while step < stats[1]
    side = 0
    while side < 2
      at = 2*step+side
      wassat_summle_pin(assumptions, selects[at], slots[at])
      wassat_summle_pin(assumptions, values[at], operands[at])
      side += 1
    wassat_summle_pin(assumptions, results[step], outputs[step]) if step < stats[5]
    step += 1
  art = wassat_raw_artifact(formula, nv)
  solver = Wassat.from_flat(nv, art, 0)
  answer = solver.solve_assuming_budget(assumptions, conflict_cap)
  t = wassat_prof("summle.complete", t)
  if answer["status"] == 1
    unless answer["model"].size == nv && wassat_model_satisfies?(formula, answer["model"])
      raise "internal error: Summle model failed original clause replay"
  else
    # An inconsistent expression refutes only the proposed assumptions.
    answer["status"] = 0
  z = wassat_prof("summle.verify", t)
  answer["summle"] = stats
  answer
