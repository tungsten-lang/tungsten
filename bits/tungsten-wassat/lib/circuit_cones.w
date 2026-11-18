# Original-clause decoder for topological AND circuits with a one-direction
# comparison miter. Recognition supplies structure, never a SAT verdict.
# Every clause belongs to a complete gate, a comparison gadget, the reduction
# tree, or the final assertion. All identifiers are inferred from the clauses.

use cnf
use policy
use solver

WASSAT_CONE_DECODE_MAX_VARS = 2000000
WASSAT_CONE_DECODE_MAX_CLAUSES = 8000000

-> wassat_cone_enabled?
  # Private query ownership fixes the measured cumulative allocation growth.
  # TODO: qualify total portfolio memory and phase throughput before restoring
  # automatic admission; the current full fast b18 attempt still times out.
  env("WASSAT_CIRCUIT_CONES") == "1"

# Resident planning estimate, not a process limit. Include certificate copies,
# decoded/simulated graph data and allocator retention after query disposal.
# The old base-only estimate omitted cumulative query storage entirely.
-> wassat_cone_memory_bytes(nv)
  512 * (nv + 1) + 384000000

-> wassat_cone_stopped(stop, deadline)
  wassat_stop_requested?(stop) || (deadline > 0 && clock_ms() >= deadline)

# Conflict tickets belong to the surrounding race. Fresh compact solvers
# reuse this arm's slot rather than receiving independent copies of the cap.
-> wassat_cone_budget_left(workspace, cap)
  state = workspace["conflict_budget"]
  return cap if state == nil
  left = workspace["conflict_limit"] - ccall("__w_arr_load_acq", state, 0)
  left < cap ? left : cap

-> wassat_cone_abs(v) (i64) i64
  v < 0 ? 0 - v : v

# Constant-time admission only; full recognition still checks every clause.
-> wassat_cone_candidate(formula)
  return false unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return false if nv < 4 || nv > WASSAT_CONE_DECODE_MAX_VARS
  return false if nc < 9 || nc > WASSAT_CONE_DECODE_MAX_CLAUSES
  lens = formula["flat_lens"]; offs = formula["flat_offs"]; lits = formula["flat_lits"]
  return false unless lens[0] == 2 && lens[1] == 2 && lens[2] == 3
  lens[nc - 1] == 1 && lits[offs[nc - 1]] == 0 - nv

-> wassat_cone_other(lits, offs, lens, ci, wanted) (i64[] i64[] i64[] i64 i64) i64
  return 0 unless lens[ci] == 2
  o = offs[ci]
  return lits[o + 1] if lits[o] == wanted
  return lits[o] if lits[o + 1] == wanted
  0

-> wassat_cone_triple(lits, offs, lens, ci, a, b, c) (i64[] i64[] i64[] i64 i64 i64 i64) bool
  return false unless lens[ci] == 3
  o = offs[ci]
  x = lits[o]; y = lits[o + 1]; z = lits[o + 2]
  if x == a
    (y == b && z == c) || (y == c && z == b)
  elsif y == a
    (x == b && z == c) || (x == c && z == b)
  elsif z == a
    (x == b && y == c) || (x == c && y == b)
  else
    false

-> wassat_cone_decode(formula, deadline = 0, stop = nil)
  miss = { "recognized": false, "stopped": false }
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return miss if nv < 4 || nv > WASSAT_CONE_DECODE_MAX_VARS
  return miss if nc < 9 || nc > WASSAT_CONE_DECODE_MAX_CLAUSES
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  return miss unless lens[0] == 2 && lens[1] == 2 && lens[2] == 3
  return miss unless lens[nc - 1] == 1 && lits[offs[nc - 1]] == 0 - nv
  if wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
    return miss
  ga = i64[nv + 1]
  gb = i64[nv + 1]
  ci = 0
  first = 0
  last = 0
  while ci + 2 < nc && lens[ci] == 2 && lens[ci + 1] == 2 && lens[ci + 2] == 3
    o = offs[ci]
    g = 0
    j = 0
    while j < 2
      candidate = 0 - lits[o + j]
      if candidate > g && wassat_cone_other(lits, offs, lens, ci + 1, 0 - candidate) != 0
        g = candidate
      j += 1
    return miss if g <= 1 || g > nv
    a = wassat_cone_other(lits, offs, lens, ci, 0 - g)
    b = wassat_cone_other(lits, offs, lens, ci + 1, 0 - g)
    return miss if a == 0 || b == 0
    return miss if wassat_cone_abs(a) >= g || wassat_cone_abs(b) >= g
    return miss unless wassat_cone_triple(lits, offs, lens, ci + 2, g, 0 - a, 0 - b)
    if first == 0
      first = g
    else
      return miss unless g == last + 1
    ga[g] = a; gb[g] = b
    last = g
    ci += 3
    if (g & 1023) == 0 && wassat_cone_stopped(stop, deadline)
      miss["stopped"] = true
      return miss
  return miss if first == 0
  gate_end = ci
  comps = []
  seen = i8[nv + 1]
  used = i8[nv + 1]
  next_var = last + 1
  while ci + 4 < nc && lens[ci] == 2 && lens[ci + 1] == 2 && lens[ci + 2] == 2 && lens[ci + 3] == 2
    a = next_var
    b = a + 1
    c = b + 1
    return miss if c > nv
    p = wassat_cone_other(lits, offs, lens, ci, 0 - a)
    q = 0 - wassat_cone_other(lits, offs, lens, ci + 1, 0 - a)
    return miss if p == 0 || q == 0
    return miss if wassat_cone_abs(p) > last || wassat_cone_abs(q) > last
    u = wassat_cone_other(lits, offs, lens, ci + 2, 0 - b)
    v = wassat_cone_other(lits, offs, lens, ci + 3, 0 - b)
    return miss unless (u == 0 - p && v == q) || (v == 0 - p && u == q)
    return miss unless wassat_cone_triple(lits, offs, lens, ci + 4, c, a, b)
    comps.push([c, a, b, p, q])
    seen[c] = 1
    next_var += 3
    ci += 5
    if (comps.size & 1023) == 0 && wassat_cone_stopped(stop, deadline)
      miss["stopped"] = true
      return miss
  return miss if comps.empty?
  tree_start = ci
  tree_count = 0
  while ci < nc - 1
    return miss unless lens[ci] == 3
    o = offs[ci]
    y = 0; a = 0; b = 0
    j = 0
    while j < 3
      lit = lits[o + j]
      if lit > 0
        return miss if y != 0
        y = lit
      elsif a == 0
        a = 0 - lit
      elsif b == 0
        b = 0 - lit
      else
        return miss
      j += 1
    return miss unless y == next_var && y <= nv
    return miss if a <= 0 || b <= 0 || a >= y || b >= y || a == b
    return miss unless seen[a] == 1 && seen[b] == 1 && used[a] == 0 && used[b] == 0
    used[a] = 1; used[b] = 1; seen[y] = 1
    next_var += 1
    tree_count += 1
    ci += 1
    if (tree_count & 1023) == 0 && wassat_cone_stopped(stop, deadline)
      miss["stopped"] = true
      return miss
  return miss unless next_var == nv + 1 && seen[nv] == 1
  return miss unless tree_count == comps.size - 1
  # A binary tree with n leaves and n-1 distinct internal nodes, where every
  # child has one parent and all edges point backward, has exactly one root.
  # Check that root explicitly and rule out disconnected unused outputs.
  j = 0
  while j < comps.size
    if (j & 1023) == 0 && wassat_cone_stopped(stop, deadline)
      miss["stopped"] = true
      return miss
    cmp = comps[j]
    return miss if cmp[0] != nv && used[cmp[0]] != 1
    j += 1
  y = last + 1 + 3 * comps.size
  while y < nv
    if (y & 1023) == 0 && wassat_cone_stopped(stop, deadline)
      miss["stopped"] = true
      return miss
    return miss unless used[y] == 1
    y += 1
  { "recognized": true, "stopped": false, "nvars": nv,
    "inputs": first - 1, "gates": last - first + 1,
    "last_gate": last, "ga": ga, "gb": gb,
    "comparisons": comps, "gate_end": gate_end, "tree_start": tree_start }

# Reused dense membership/map arrays avoid an O(nvars) clear for every local
# query. The extracted nodes, clauses and solver state are bounded by cap.
-> wassat_cone_workspace(decoded, cap = 8192)
  nv = decoded["nvars"]
  { "marks": i64[nv + 1], "map": i64[nv + 1], "epoch": i64[1],
    "stack": i64[cap + 2], "cap": cap }

-> wassat_cone_representative(lit, aliases) (i64 i64[]) i64
  v = wassat_cone_abs(lit)
  raise "invalid cone alias literal" if v == 0 || v >= aliases.size
  sign = lit < 0 ? -1 : 1
  while aliases[v] != 0
    r = aliases[v]
    next_v = wassat_cone_abs(r)
    raise "cone aliases must point backward" if next_v == 0 || next_v >= v
    sign = 0 - sign if r < 0
    v = next_v
  sign * v

-> wassat_cone_compact(decoded, aliases, workspace, y, rhs, deadline = 0, stop = nil, owner = nil)
  miss = { "recognized": false, "stopped": false, "capacity": false, "nodes": [], "clauses": [] }
  return miss unless decoded["recognized"]
  nv = decoded["last_gate"]
  return miss if y <= 0 || y > nv || rhs == 0 || wassat_cone_abs(rhs) > nv
  return miss if aliases.size <= nv
  if wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
    return miss
  marks = workspace["marks"] ## i64[]
  mapping = workspace["map"] ## i64[]
  epoch = workspace["epoch"] ## i64[]
  stack = workspace["stack"] ## i64[]
  cap = workspace["cap"]
  if cap < 2 || stack.size < cap + 2
    miss["capacity"] = true
    return miss
  epoch[0] += 1
  stamp = epoch[0]
  ga = decoded["ga"] ## i64[]
  gb = decoded["gb"] ## i64[]
  inputs = decoded["inputs"]
  constants = workspace["constants"]
  return miss if constants != nil && constants.size <= nv
  nodes = wassat_query_box(owner)
  sp = 0
  root = 0
  while root < 2
    v = root == 0 ? y : wassat_cone_abs(rhs)
    unless marks[v] == stamp
      marks[v] = stamp
      stack[sp] = v
      sp += 1
    root += 1
  scheduled = sp
  while sp > 0
    sp -= 1
    v = stack[sp]
    nodes.push(v)
    first = 0; second = 0; count = 0
    if constants != nil && constants[v] != 0
      return miss unless constants[v] == 1 || constants[v] == -1
    elsif aliases[v] != 0
      first = wassat_cone_abs(aliases[v])
      # A previously proved alias points backward. Reject untrusted cyclic
      # input instead of allowing a malformed table to create a false cone.
      return miss if first <= 0 || first >= v
      count = 1
    elsif v > inputs
      first = wassat_cone_abs(ga[v]); second = wassat_cone_abs(gb[v])
      count = 2
    j = 0
    while j < count
      a = j == 0 ? first : second
      return miss if a <= 0 || a >= v
      unless marks[a] == stamp
        if scheduled >= cap
          miss["stopped"] = true
          miss["capacity"] = true
          return miss
        marks[a] = stamp
        stack[sp] = a
        sp += 1
        scheduled += 1
      j += 1
    if (nodes.size & 255) == 0 && wassat_cone_stopped(stop, deadline)
      miss["stopped"] = true
      return miss
  nodes = nodes.sort
  wassat_query_keep(owner, nodes, 0) if owner != nil
  i = 0
  while i < nodes.size
    mapping[nodes[i]] = i + 1
    i += 1
  clauses = wassat_query_box(owner)
  i = 0
  while i < nodes.size
    if (i & 255) == 0 && wassat_cone_stopped(stop, deadline)
      miss["stopped"] = true
      return miss
    v = nodes[i]
    local = mapping[v]
    if constants != nil && constants[v] != 0
      wassat_cone_owned_clause(clauses, [constants[v] * local], owner)
    elsif aliases[v] != 0
      other = aliases[v]
      a = mapping[wassat_cone_abs(other)]
      a = 0 - a if other < 0
      wassat_cone_owned_clause(clauses, [0 - local, a], owner)
      wassat_cone_owned_clause(clauses, [local, 0 - a], owner)
    elsif v > inputs
      left = ga[v]; right = gb[v]
      a = mapping[wassat_cone_abs(left)]
      b = mapping[wassat_cone_abs(right)]
      a = 0 - a if left < 0
      b = 0 - b if right < 0
      wassat_cone_owned_clause(clauses, [0 - local, a], owner)
      wassat_cone_owned_clause(clauses, [0 - local, b], owner)
      wassat_cone_owned_clause(clauses, [local, 0 - a, 0 - b], owner)
    i += 1
  local_rhs = mapping[wassat_cone_abs(rhs)]
  local_rhs = 0 - local_rhs if rhs < 0
  { "recognized": true, "stopped": false, "nodes": nodes,
    "clauses": clauses, "left": mapping[y], "right": local_rhs }

-> wassat_cone_owned_clause(clauses, row, owner)
  wassat_query_keep(owner, row, 0) if owner != nil
  clauses.push(row)

# A query owns only allocations explicitly registered by its factories. A
# retained UNKNOWN keeps its owner; a retired/single-use query releases after
# its original-variable proof and primary counterexample have been detached.
-> wassat_cone_lifetime_finish(scope, completed)
  entry = scope["entry"]
  if !completed && entry != nil
    wassat_cone_retry_retire(scope["cache"], scope["key"])
  if completed && entry != nil && entry["retired"] != true
    cache = scope["cache"]
    charge = scope["owner"].retention_bytes
    total = cache["bytes"] - entry["bytes"] + charge
    if cache["max_bytes"] != nil && total > cache["max_bytes"]
      cache["declined"] += 1
      wassat_cone_retry_retire(cache, scope["key"])
    else
      entry["bytes"] = charge
      cache["bytes"] = total
      cache["peak_bytes"] = total if total > cache["peak_bytes"]
  keep = completed && entry != nil && entry["retired"] != true
  unless keep
    owner = scope["owner"]
    if owner != nil
      z = wassat_query_destroy(owner)
  z = ccall("w_value_free_w", scope)
  0

# Optional, already-proved constants are compact-cone axioms just like aliases.
# A simulated constant is only a proposal: refute its opposite before the
# caller may record it. The returned original-variable unit is RUP, and this
# local result never supplies a verdict for the original comparison miter.
-> wassat_cone_prove_constant(decoded, aliases, workspace, y, value, cap, deadline = 0, stop = nil)
  scope = { "owner": wassat_query_storage(), "entry": nil }
  begin
    wassat_cone_prove_constant_inner(decoded, aliases, workspace, y, value, cap, deadline, stop, scope)
  ensure
    wassat_cone_lifetime_finish(scope, true)

-> wassat_cone_prove_constant_inner(decoded, aliases, workspace, y, value, cap, deadline, stop, scope)
  miss = { "equivalent": false, "stopped": false, "conflicts": 0,
    "decisions": 0, "props": 0, "drat": [], "variables": 0,
    "separated": false, "capacity": false }
  return miss unless value == -1 || value == 1
  cap = wassat_cone_budget_left(workspace, cap)
  return miss if cap <= 0
  owner = scope["owner"]
  cone = wassat_cone_compact(decoded, aliases, workspace, y, y, deadline, stop, owner)
  wassat_query_keep(owner, cone, 0)
  unless cone["recognized"]
    miss["stopped"] = cone["stopped"]
    miss["capacity"] = cone["capacity"]
    return miss
  miss["variables"] = cone["nodes"].size
  solver = Wassat.new(cone["nodes"].size, cone["clauses"], WASSAT_PROOF_DRAT, 0, false, owner)
  wassat_query_keep(owner, solver, 0)
  solver.set_stop_cell(stop)
  if workspace["conflict_budget"] != nil
    solver.set_shared_conflict_budget(workspace["conflict_budget"], workspace["conflict_limit"], workspace["conflict_slot"])
  if wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
    return miss
  result = solver.solve_assuming_budget([0 - value * cone["left"]], cap)
  miss["conflicts"] = result["conflicts"]
  miss["decisions"] = result["decisions"]
  miss["props"] = result["props"]
  if wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
    return miss
  unless result["status"] == -1
    miss["separated"] = result["status"] == 1
    return miss
  lifted = wassat_cone_lift_drat(result["drat"], cone["nodes"], deadline, stop, workspace["decimal_lift"] != false)
  if lifted == nil
    miss["stopped"] = true
    return miss
  lifted.push("[value * y] 0")
  miss["drat"] = lifted
  miss["equivalent"] = true
  miss

# Only additions are lifted. Wassat's assumption queries log ordinary RUP
# consequences of their input, including the negated failed-assumption core.
# Keeping deleted clauses is sound because RUP is monotone under extra axioms.
-> wassat_cone_lift_drat(lines, nodes, deadline = 0, stop = nil, decimal = true)
  return wassat_cone_lift_tokenized(lines, nodes, deadline, stop) unless decimal
  owner = wassat_query_storage()
  begin
    wassat_cone_lift_drat_owned(lines, nodes, deadline, stop, owner)
  ensure
    wassat_query_destroy(owner)

-> wassat_cone_lift_drat_owned(lines, nodes, deadline, stop, owner)
  lifted = []
  # Parse and remap without allocating a string token or boxed clause entry
  # per literal. Only completed output strings transfer to the caller.
  capacity = nodes.size + 8
  capacity = 64 if capacity > 64
  mapped = wassat_query_i64(owner, capacity)
  bytes = wassat_query_u8(owner, 12 * mapped.size + 6)
  scanned = 0
  lines.each -> (line)
    return nil if (scanned & 255) == 0 && wassat_cone_stopped(stop, deadline)
    scanned += 1
    i = 0 ## i64
    length = line.size ## i64
    while i < length && line.byte_at(i) <= 32
      i += 1
    unless i == length || (line.byte_at(i) == 100 && (i + 1 == length || line.byte_at(i + 1) <= 32))
      count = 0 ## i64
      terminated = false
      while i < length
        return nil if (i & 1023) == 0 && wassat_cone_stopped(stop, deadline)
        while i < length && line.byte_at(i) <= 32
          i += 1
        break if i == length
        start = i ## i64
        negative = line.byte_at(i) == 45
        i += 1 if negative || line.byte_at(i) == 43
        digits = 0 ## i64
        value = 0 ## i64
        while i < length && line.byte_at(i) > 32
          c = line.byte_at(i) ## i64
          raise "invalid cone proof literal" if c < 48 || c > 57
          value = value * 10 + c - 48
          raise "cone proof literal outside compact mapping" if value > nodes.size
          digits += 1
          i += 1
        raise "invalid cone proof literal" if digits == 0
        if value == 0
          raise "unterminated cone proof clause" unless i == start + 1 && !negative
          while i < length && line.byte_at(i) <= 32
            i += 1
          raise "unterminated cone proof clause" unless i == length
          terminated = true
          break
        if count >= mapped.size
          grown = wassat_query_i64(owner, 2 * mapped.size)
          j = 0
          while j < count
            grown[j] = mapped[j]
            j += 1
          mapped = grown
          bytes = wassat_query_u8(owner, 12 * mapped.size + 6)
        original = nodes[value - 1]
        mapped[count] = negative ? 0 - original : original
        count += 1
      raise "unterminated cone proof clause" unless terminated
      used = wassat_drat_put(bytes, 0, bytes.size, mapped, 0, count, 0)
      raise "cone proof formatter overflow" if used < 0
      output = wassat_query_u8(owner, used - 1)
      wassat_query_copy_bytes(bytes, output, used - 1)
      lifted.push(ccall("w_string_from_byte_array", output))
  lifted

-> wassat_cone_lift_tokenized(lines, nodes, deadline = 0, stop = nil)
  lifted = []
  scanned = 0
  lines.each -> (line)
    return nil if (scanned & 255) == 0 && wassat_cone_stopped(stop, deadline)
    scanned += 1
    tokens = wassat_tokenize(line)
    unless tokens.empty? || tokens[0] == "d"
      clause = []
      i = 0
      while i < tokens.size
        lit = tokens[i].to_i
        if lit == 0
          raise "unterminated cone proof clause: [line.inspect]" unless i == tokens.size - 1
          break
        v = wassat_cone_abs(lit)
        raise "cone proof literal outside compact mapping" if v > nodes.size
        original = nodes[v - 1]
        clause.push(lit > 0 ? original : 0 - original)
        i += 1
      raise "unterminated cone proof clause: [line.inspect]" unless tokens[tokens.size - 1] == "0"
      lifted.push(clause.join(" ") + (clause.empty? ? "0" : " 0"))
  lifted


# aliases must contain only equalities already proved from this formula.
# The return value concerns equivalence, never the original formula's verdict.
# The two mismatch queries share one conflict allowance. A SAT or UNKNOWN
# result leaves the proposed equality unused and does not alter aliases.
-> wassat_cone_primary_model(decoded, cone, result)
  return nil unless result["status"] == 1
  nodes = cone["nodes"]
  model = result["model"]
  return nil unless model.size == nodes.size
  positive = []
  i = 0
  while i < nodes.size
    return nil unless wassat_cone_abs(model[i]) == i + 1
    positive.push(nodes[i]) if nodes[i] <= decoded["inputs"] && model[i] > 0
    i += 1
  positive

# Research opt-in: private compact solvers may survive UNKNOWN output queries.
# Their old cone remains a sound subset of the original formula even if later
# aliases shrink other queries. Cumulative counters are charged only once;
# the eventual lifted proof includes the retained solver's complete RUP prefix.
-> wassat_cone_retry_cache(limit, max_bytes = nil)
  raise "negative cone retry cache limit" if limit < 0
  raise "negative cone retry byte reservation" if max_bytes != nil && max_bytes < 0
  { "entries": {}, "limit": limit, "resident": 0,
    "hits": 0, "created": 0, "peak": 0, "first_skipped": 0,
    "max_bytes": max_bytes, "bytes": 0, "peak_bytes": 0, "declined": 0 }

-> wassat_cone_retry_retire(cache, key)
  if cache != nil && cache["entries"][key] != nil
    cache["bytes"] -= cache["entries"][key]["bytes"]
    cache["entries"][key]["retired"] = true
    cache["entries"][key] = nil
    cache["resident"] -= 1
  0

-> wassat_cone_prove_inner(decoded, aliases, workspace, y, rhs, cap, deadline, capture, stop, profile, scope)
  miss = { "equivalent": false, "stopped": false, "conflicts": 0,
    "decisions": 0, "props": 0, "drat": [], "variables": 0,
    "counterexample": nil, "separated": false, "capacity": false }
  cap = wassat_cone_budget_left(workspace, cap)
  return miss if cap <= 0
  cache = workspace["retry_active"] == true ? workspace["retry_cache"] : nil
  key = cache == nil ? "" : "[y]:[rhs]"
  entry = cache == nil ? nil : cache["entries"][key]
  scope["cache"] = cache; scope["key"] = key
  before = entry == nil ? nil : entry["counters"].dup
  first_proved = entry != nil && entry["first_proved"]
  if entry != nil
    cone = entry["cone"]; solver = entry["solver"]
    scope["owner"] = entry["owner"]; scope["entry"] = entry
    cache["hits"] += 1
  else
    owner = wassat_query_storage()
    scope["owner"] = owner
    started = profile == nil ? 0 : clock_ms()
    cone = wassat_cone_compact(decoded, aliases, workspace, y, rhs, deadline, stop, owner)
    wassat_query_keep(owner, cone, 0)
    profile[6] += clock_ms() - started if profile != nil
    unless cone["recognized"]
      miss["stopped"] = cone["stopped"]
      miss["capacity"] = cone["capacity"]
      return miss
    started = profile == nil ? 0 : clock_ms()
    solver = Wassat.new(cone["nodes"].size, cone["clauses"], WASSAT_PROOF_DRAT, 0, false, owner)
    wassat_query_keep(owner, solver, 0)
    profile[7] += clock_ms() - started if profile != nil
    if cache != nil && cache["resident"] < cache["limit"]
      entry = { "cone": cone, "solver": solver, "owner": owner,
        "first_proved": false, "counters": wassat_query_i64(owner, 3), "retired": false,
        "bytes": 0 }
      wassat_query_keep(owner, entry, 0)
      scope["entry"] = entry
      cache["entries"][key] = entry
      cache["resident"] += 1
      cache["created"] += 1
      cache["peak"] = cache["resident"] if cache["resident"] > cache["peak"]
  miss["variables"] = cone["nodes"].size
  # Assumption queries do not publish their local SAT/UNSAT status. This cell
  # is only read for cooperative cancellation by the private cone solver.
  solver.set_stop_cell(stop)
  if workspace["conflict_budget"] != nil
    solver.set_shared_conflict_budget(workspace["conflict_budget"], workspace["conflict_limit"], workspace["conflict_slot"])
  if wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
    return miss
  unless first_proved
    started = profile == nil ? 0 : clock_ms()
    first = solver.solve_assuming_budget([cone["left"], 0 - cone["right"]], cap)
    profile[8] += clock_ms() - started if profile != nil
    wassat_cone_query_charge(miss, first, before, entry)
    if wassat_cone_stopped(stop, deadline)
      miss["stopped"] = true
      return miss
    unless first["status"] == -1
      miss["separated"] = first["status"] == 1
      miss["counterexample"] = wassat_cone_primary_model(decoded, cone, first) if capture
      wassat_cone_retry_retire(cache, key) if miss["separated"]
      return miss
    entry["first_proved"] = true if entry != nil
    return miss if miss["conflicts"] >= cap
  else
    cache["first_skipped"] += 1
  started = profile == nil ? 0 : clock_ms()
  second = solver.solve_assuming_budget(
    [0 - cone["left"], cone["right"]], cap - miss["conflicts"]
  )
  profile[9] += clock_ms() - started if profile != nil
  # Solver counters and proof prefix are cumulative over incremental queries.
  wassat_cone_query_charge(miss, second, before, entry)
  if wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
    return miss
  unless second["status"] == -1
    miss["separated"] = second["status"] == 1
    miss["counterexample"] = wassat_cone_primary_model(decoded, cone, second) if capture
    wassat_cone_retry_retire(cache, key) if miss["separated"]
    return miss
  started = profile == nil ? 0 : clock_ms()
  lifted = wassat_cone_lift_drat(second["drat"], cone["nodes"], deadline, stop, workspace["decimal_lift"] != false)
  profile[10] += clock_ms() - started if profile != nil
  if lifted == nil
    miss["stopped"] = true
    return miss
  miss["drat"] = lifted
  miss["drat"].push("[0 - y] [rhs] 0")
  miss["drat"].push("[y] [0 - rhs] 0")
  miss["equivalent"] = true
  wassat_cone_retry_retire(cache, key)
  miss

-> wassat_cone_retry_release(workspace)
  cache = workspace["retry_cache"]
  return 0 if cache == nil
  cache["entries"].keys.each -> (key)
    entry = cache["entries"][key]
    if entry != nil
      owner = entry["owner"]
      wassat_cone_retry_retire(cache, key)
      z = wassat_query_destroy(owner)
  0

-> wassat_cone_query_charge(miss, query, before, entry)
  miss["conflicts"] = query["conflicts"] - (before == nil ? 0 : before[0])
  miss["decisions"] = query["decisions"] - (before == nil ? 0 : before[1])
  miss["props"] = query["props"] - (before == nil ? 0 : before[2])
  if entry != nil
    counters = entry["counters"]
    counters[0] = query["conflicts"]; counters[1] = query["decisions"]; counters[2] = query["props"]
  0

# Optional aggregate diagnostics. No query logs or timers are allocated when
# the workspace has no profile. See the profile harness for the column names.
-> wassat_cone_prove(decoded, aliases, workspace, y, rhs, cap, deadline = 0, capture = false, stop = nil)
  profile = workspace["query_profile"]
  scope = { "owner": nil, "entry": nil }
  completed = false
  begin
    result = wassat_cone_prove_inner(decoded, aliases, workspace, y, rhs, cap, deadline, capture, stop, profile, scope)
    completed = true
  ensure
    wassat_cone_lifetime_finish(scope, completed)
  if profile != nil
    profile[0] += 1
    nv = result["variables"]
    profile[4] = nv if nv > profile[4]
    profile[5] += nv
    if nv > 0
      bucket = nv <= 32 ? 19 : (nv <= 128 ? 20 : (nv <= 512 ? 21 : (nv <= 2048 ? 22 : 23)))
      profile[bucket] += 1
    if result["capacity"]
      profile[1] += 1
    elsif result["stopped"]
      profile[2] += 1
    elsif nv == 0
      profile[3] += 1
    elsif result["equivalent"]
      profile[11] += 1
      profile[14] += 1 if result["decisions"] == 0
      profile[15] += 1 if result["conflicts"] == 0
      profile[16] += result["conflicts"]
    elsif result["separated"]
      profile[12] += 1
      profile[17] += result["conflicts"]
    else
      profile[13] += 1
      profile[18] += result["conflicts"]
  result
