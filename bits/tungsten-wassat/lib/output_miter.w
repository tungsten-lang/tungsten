# A disjunction of output differences over two grouped lookup-table circuits.
# Authenticate each definition, then hash its exact function on earlier wires.
# A signed representative denotes a function or its complement.
-> wassat_om_decode(f, first, width)
  lits = f["flat_lits"] ## i64[]
  offs = f["flat_offs"] ## i64[]
  lens = f["flat_lens"] ## i64[]
  nv = f["nvars"]
  last = f["flat_ncl"] - 1
  gates = {}
  constant = nv + 1
  reps = i64[nv + 1]
  queue = []
  users = {}
  needed = i64[nv + 1]
  v = 1
  while v < first
    reps[v] = v
    queue.push(v)
    v += 1
  ci = 0
  while v <= nv
    return nil if ci >= last
    if lens[ci] == 1
      unit = lits[offs[ci]]
      return nil if unit.abs != v || v < first + width
      reps[v] = unit > 0 ? constant : 0 - constant
      queue.push(v)
      ci += 1
    else
      args = []
      allow0 = 65535
      allow1 = 65535
      start = ci
      while (allow0 ^ allow1) != 65535
        return nil if ci >= last || ci - start >= 16 || lens[ci] < 2 || lens[ci] > 5
        bad = 65535
        head = 0
        j = 0
        while j < lens[ci]
          lit = lits[offs[ci] + j]
          if lit.abs == v
            return nil if head != 0
            head = lit
          else
            k = 0
            while k < args.size && args[k] != lit.abs
              k += 1
            if k == args.size
              return nil if k == 4
              args.push(lit.abs)
            # Bit m is input k in assignment m, for all 16 assignments.
            pattern = 43690
            pattern = 52428 if k == 1
            pattern = 61680 if k == 2
            pattern = 65280 if k == 3
            bad &= lit > 0 ? (65535 ^ pattern) : pattern
          j += 1
        return nil if head == 0
        if head > 0
          allow0 &= 65535 ^ bad
        else
          allow1 &= 65535 ^ bad
        ci += 1
      table = allow1 & ((1 << (1 << args.size)) - 1)
      if v < first + width
        return nil unless args.size == 2 && (table == 6 || table == 9)
      gates[v] = [args, table]
      needed[v] = args.size
      args.each -> (a)
        users[a] = [] unless users.has_key?(a)
        users[a].push(v)
    v += 1
  return nil if ci != last
  at = 0
  while at < queue.size
    v = queue[at]
    if users.has_key?(v)
      users[v].each -> (u)
        needed[u] -= 1
        queue.push(u) if needed[u] == 0
    at += 1
  return nil unless queue.size == nv
  [gates, reps, queue]

# Enumerate the gate after substituting its signed representatives. Partition
# the input variables into essential support and variables it ignores.
-> wassat_om_function(gate, reps, constant)
  inputs = []
  wires = []
  gate[0].each -> (a)
    r = reps[a]
    wires.push(r)
    inputs.push(r.abs) unless r.abs == constant || inputs.include?(r.abs)
  inputs = inputs.sort
  table = 0
  m = 0
  while m < (1 << inputs.size)
    raw = 0
    j = 0
    while j < wires.size
      r = wires[j]
      bit = 1
      if r.abs != constant
        k = 0
        while inputs[k] != r.abs
          k += 1
        bit = (m >> k) & 1
      bit ^= 1 if r < 0
      raw |= bit << j
      j += 1
    table |= ((gate[1] >> raw) & 1) << m
    m += 1
  ignored = []
  support = inputs
  j = support.size - 1
  while j >= 0
    compact = 0
    same = true
    bit = 1 << j
    k = 0
    while k < (1 << (support.size - 1))
      m = (k & (bit - 1)) | ((k & (0 - bit)) << 1)
      same = false if ((table >> m) & 1) != ((table >> (m + bit)) & 1)
      compact |= ((table >> m) & 1) << k
      k += 1
    if same
      ignored.push(support[j])
      rest = []
      support.each -> (a)
        rest.push(a) if a != inputs[j]
      support = rest
      table = compact
    j -= 1
  [support, table, ignored]

# For each assignment to the split variables, propagation establishes the
# leaf. Resolve complementary leaves in postorder to establish the parent.
-> wassat_om_project(out, row, split, at)
  if at < split.size
    v = split[at]
    unless row.include?(v) || row.include?(0 - v)
      row.push(v)
      wassat_om_project(out, row, split, at + 1)
      row.pop
      row.push(0 - v)
      wassat_om_project(out, row, split, at + 1)
      row.pop
    else
      wassat_om_project(out, row, split, at + 1)
      return
  out.append(row.join(" "))
  out.append(" 0\n")

-> wassat_om_proof(order, facts, reps, constant)
  out = StringBuffer()
  order.each -> (v)
    if facts.has_key?(v)
      data = facts[v]
      support = data[0]
      m = 0
      while m < (1 << support.size)
        row = [((data[1] >> m) & 1) == 1 ? v : 0 - v]
        j = 0
        while j < support.size
          row.push((m & (1 << j)) == 0 ? support[j] : 0 - support[j])
          j += 1
        wassat_om_project(out, row, data[2], 0)
        m += 1
      r = reps[v]
      if r != v && r.abs != constant
        wassat_om_project(out, [0 - v, r], support, 0)
        wassat_om_project(out, [v, 0 - r], support, 0)
  out.append("0\n")
  out.to_s

-> wassat_om_refute(f, emit)
  nv = f["nvars"]
  nc = f["flat_ncl"]
  return nil if nc < 9 || nc > 262144 || nv > 32768
  lens = f["flat_lens"] ## i64[]
  offs = f["flat_offs"] ## i64[]
  lits = f["flat_lits"] ## i64[]
  width = lens[nc - 1]
  return nil if width < 2 || width > 256 || lens[0] != 3
  first = lits[offs[nc - 1]]
  return nil if first < 1 || first + width - 1 > nv || lits[0].abs != first
  i = 0
  while i < width
    return nil unless lits[offs[nc - 1] + i] == first + i
    i += 1
  circuit = wassat_om_decode(f, first, width)
  return nil if circuit == nil
  gates = circuit[0]
  reps = circuit[1] ## i64[]
  order = circuit[2]
  constant = nv + 1
  classes = {}
  facts = {}
  order.each -> (v)
    if gates.has_key?(v)
      data = wassat_om_function(gates[v], reps, constant)
      support = data[0]
      table = data[1]
      if support.empty?
        reps[v] = table == 1 ? constant : 0 - constant
      elsif support.size == 1
        reps[v] = table == 2 ? support[0] : 0 - support[0]
      else
        flip = (table & 1) != 0
        mask = (1 << (1 << support.size)) - 1
        norm = flip ? (mask ^ table) : table
        key = support.join(",") + ":[norm]"
        classes[key] = flip ? 0 - v : v unless classes.has_key?(key)
        reps[v] = flip ? 0 - classes[key] : classes[key]
      facts[v] = data if emit
  i = 0
  while i < width
    return nil unless reps[first + i] == 0 - constant
    i += 1
  emit ? wassat_om_proof(order, facts, reps, constant) : ""
