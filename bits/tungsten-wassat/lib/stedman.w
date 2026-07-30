# Exact model-only solver for the compact Stedman/Erin triples encoding.
#
# Clean-room provenance: the variable partition, guarded transition table, and
# sequence-bit relations below were derived independently from the public
# DIMACS instance and the published description of the encoding. No competing
# solver source, generated model, or private benchmark metadata is incorporated
# here.
#
# A recognized formula has one call bit and three type bits per node. Types six
# and seven are excluded directly. Every legal (node, type, call) selector then
# guards either one forbidden transition or a complete deterministic transition:
# three destination-type bits plus a boundary, copy, or two-input-XOR relation
# over the compact sequence label. Unit clauses may fix individual calls.
#
# Recognition accounts for every clause and checks every guarded relation. A
# bounded Hamiltonian-cycle search chooses only call/type bits; ordinary Wassat
# propagation completes the sequence bits. This lane returns SAT only after a
# full replay of every original clause. Shape misses, capped search, failed
# completion, and failed replay all fall through; this lane never reports UNSAT.

use solver
use preprocess

WASSAT_STEDMAN_MIN_NODES = 5
WASSAT_STEDMAN_MAX_NODES = 4096
WASSAT_STEDMAN_MIN_BITS = 2
WASSAT_STEDMAN_MAX_BITS = 16
WASSAT_STEDMAN_NODE_CAP = 1000000
WASSAT_STEDMAN_COMPLETION_CONFLICTS = 100

-> wassat_stedman_miss
  {
    "recognized": false, "status": 0, "model": [],
    "nodes": 0, "transitions": 0,
    "conflicts": 0, "decisions": 0, "props": 0
  }

-> wassat_stedman_search(depth, nnodes, start_type, node, type,
                         target_node, target_type, fixed_call,
                         used, calls, types, meta, node_cap) (i64 i64 i64 i64 i8 i64[] i8[] i8[]
                          i8[] i8[] i8[] i64[] i64) i64
  meta[0] += 1
  if meta[0] > node_cap
    meta[1] = 1
    return 0
  if depth == nnodes
    return (node == 0 && type == start_type) ? 1 : 0

  first_call = 0
  stop_call = 2
  if fixed_call[node] >= 0
    first_call = fixed_call[node]
    stop_call = first_call + 1

  call = first_call
  while call < stop_call
    group = (node * 6 + type) * 2 + call
    to = target_node[group]
    if to >= 0
      to_type = target_type[group]
      final_step = depth + 1 == nnodes
      available = false
      if final_step
        available = to == 0 && to_type == start_type
      else
        available = to > 0 && used[to] == 0
      if available
        calls[node] = call
        types[node] = type
        used[to] = 1 unless final_step
        if wassat_stedman_search(
          depth + 1, nnodes, start_type, to, to_type,
          target_node, target_type, fixed_call,
          used, calls, types, meta, node_cap
        ) == 1
          return 1
        used[to] = 0 unless final_step
        return 0 if meta[1] == 1
    call += 1
  0

-> wassat_stedman_assumptions(nnodes, calls, types) (i64 i8[] i8[])
  assumptions = []
  node = 0
  while node < nnodes
    call_var = node + 1
    assumptions.push(calls[node] == 1 ? call_var : 0 - call_var)
    bit = 0
    while bit < 3
      type_var = nnodes + 1 + node * 3 + bit
      assumptions.push(
        (types[node] & (1 << bit)) != 0 ? type_var : 0 - type_var
      )
      bit += 1
    node += 1
  assumptions

# Keep DIMACS arrays typed throughout recognition. Reading a signed literal
# through an untyped local boxes the raw i64 as an unsigned value in compiled
# code; typed parameters preserve its sign and keep this scan allocation-free.
-> wassat_stedman_scan(nv, ncl, lits, offs, lens, node_cap) (i64 i64 i64[] i64[] i64[] i64)
  miss = wassat_stedman_miss
  return miss if node_cap < 1
  return miss if nv < 1 || ncl < 1

  # The public encoding uses
  #   N call + 3N type + (N - 1)B sequence variables.
  # Require a unique plausible decomposition rather than a benchmark filename.
  nnodes = 0
  nbits = 0
  decompositions = 0
  candidate_bits = WASSAT_STEDMAN_MIN_BITS
  while candidate_bits <= WASSAT_STEDMAN_MAX_BITS
    numerator = nv + candidate_bits
    denominator = 4 + candidate_bits
    if numerator % denominator == 0
      candidate_nodes = numerator / denominator
      if candidate_nodes >= WASSAT_STEDMAN_MIN_NODES && candidate_nodes <= WASSAT_STEDMAN_MAX_NODES
        nnodes = candidate_nodes
        nbits = candidate_bits
        decompositions += 1
    candidate_bits += 1
  return miss unless decompositions == 1

  ngroups = nnodes * 12
  type_base = nnodes + 1
  seq_base = 4 * nnodes + 1
  full_seq_mask = (1 << nbits) - 1
  fixed_call = i8[nnodes]
  invalid_seen = i8[nnodes]
  group_count = i64[ngroups]
  bare_count = i8[ngroups]
  type_count = i8[ngroups]
  dest_mask = i8[ngroups]
  target_node = i64[ngroups]
  target_type = i8[ngroups]
  peer_node = i64[ngroups]
  seq1_count = i8[ngroups]
  seq2_count = i8[ngroups]
  seq3_count = i8[ngroups]
  source_mask = i64[ngroups]
  peer_mask = i64[ngroups]
  source_signs = i64[ngroups]
  peer_signs = i64[ngroups]
  relation_kind = i8[ngroups * nbits]
  relation_count = i8[ngroups * nbits]
  relation_source_a = i8[ngroups * nbits]
  relation_source_b = i8[ngroups * nbits]
  relation_signs = i64[ngroups * nbits]
  stamp = i64[nv + 1]

  node = 0
  while node < nnodes
    fixed_call[node] = -1
    target_node[(node * 6) * 2] = -2
    group = node * 12
    while group < node * 12 + 12
      target_node[group] = -2
      peer_node[group] = -1
      group += 1
    node += 1

  clause_index = 0
  while clause_index < ncl
    n = lens[clause_index]
    return miss if n < 1
    off = offs[clause_index]

    # Duplicate literals (including opposite signs) are outside the emitted
    # schema and would make the selector/payload split ambiguous.
    j = 0
    while j < n
      v = lits[off + j].abs
      return miss if v < 1 || v > nv
      return miss if stamp[v] == clause_index + 1
      stamp[v] = clause_index + 1
      j += 1

    if n == 1
      lit = lits[off]
      v = lit.abs
      return miss if v > nnodes
      call_node = v - 1
      return miss unless fixed_call[call_node] == -1
      fixed_call[call_node] = lit > 0 ? 1 : 0
      clause_index += 1
      next

    if n == 2
      a = lits[off]
      b = lits[off + 1]
      return miss if a >= 0 || b >= 0
      av = a.abs
      bv = b.abs
      valid_node = -1
      node = 0
      while node < nnodes && valid_node < 0
        second_bit = type_base + node * 3 + 1
        third_bit = second_bit + 1
        if (av == second_bit && bv == third_bit) || (av == third_bit && bv == second_bit)
          valid_node = node
        node += 1
      return miss if valid_node < 0 || invalid_seen[valid_node] != 0
      invalid_seen[valid_node] = 1
      clause_index += 1
      next

    # Every remaining clause contains exactly one call literal. It names the
    # source node; the minimal legal-type gate then names one of six types.
    call_lit = 0
    call_literals = 0
    j = 0
    while j < n
      lit = lits[off + j]
      if lit.abs <= nnodes
        call_lit = lit
        call_literals += 1
      j += 1
    return miss unless call_literals == 1
    source = call_lit.abs - 1
    source_type_base = type_base + source * 3
    gate_present = 0
    gate_true = 0
    payload_lits = i64[3]
    payload_count = 0
    j = 0
    while j < n
      lit = lits[off + j]
      v = lit.abs
      if v == call_lit.abs
        # already accounted above
        z = 0
      elsif v >= source_type_base && v < source_type_base + 3
        bit = v - source_type_base
        gate_present = gate_present | (1 << bit)
        gate_true = gate_true | (1 << bit) if lit < 0
      else
        return miss if payload_count >= 3
        payload_lits[payload_count] = lit
        payload_count += 1
      j += 1

    source_type = -1
    candidates = 0
    candidate_type = 0
    while candidate_type < 6
      if (candidate_type & gate_present) == gate_true
        source_type = candidate_type
        candidates += 1
      candidate_type += 1
    return miss unless candidates == 1
    expected_present = source_type < 4 ? 7 : 5
    return miss unless gate_present == expected_present
    return miss unless gate_true == (source_type & expected_present)
    call = call_lit < 0 ? 1 : 0
    group = (source * 6 + source_type) * 2 + call
    group_count[group] += 1

    if payload_count == 0
      bare_count[group] += 1
      clause_index += 1
      next

    payload_var = payload_lits[0].abs
    if payload_count == 1 && payload_var >= type_base && payload_var < seq_base
      destination = (payload_var - type_base) / 3
      destination_bit = (payload_var - type_base) % 3
      return miss if destination == source
      if target_node[group] == -2
        target_node[group] = destination
      else
        return miss unless target_node[group] == destination
      type_count[group] += 1
      dest_mask[group] = dest_mask[group] | (1 << destination_bit)
      if payload_lits[0] > 0
        target_type[group] = target_type[group] | (1 << destination_bit)
      clause_index += 1
      next

    # All other payloads are boundary or transition relations over sequence
    # bits. A sequence block belongs to node 1..N-1; node zero is the fixed
    # boundary whose label is omitted from the variable array.
    pnodes = i64[3]
    pbits = i64[3]
    source_items = 0
    peer_items = 0
    j = 0
    while j < payload_count
      lit = payload_lits[j]
      v = lit.abs
      return miss if v < seq_base || v > nv
      seq_delta = v - seq_base
      seq_node = 1 + seq_delta / nbits
      seq_bit = seq_delta % nbits
      return miss if seq_node >= nnodes
      pnodes[j] = seq_node
      pbits[j] = seq_bit
      if seq_node == source
        source_items += 1
        source_mask[group] = source_mask[group] | (1 << seq_bit)
        source_signs[group] = source_signs[group] | (1 << seq_bit) if lit > 0
      else
        peer_items += 1
        if peer_node[group] < 0
          peer_node[group] = seq_node
        else
          return miss unless peer_node[group] == seq_node
        peer_mask[group] = peer_mask[group] | (1 << seq_bit)
        peer_signs[group] = peer_signs[group] | (1 << seq_bit) if lit > 0
      j += 1

    if payload_count == 1
      return miss unless source_items == 1 || peer_items == 1
      seq1_count[group] += 1
    elsif payload_count == 2
      return miss unless source_items == 1 && peer_items == 1
      source_slot = pnodes[0] == source ? 0 : 1
      dest_slot = 1 - source_slot
      dest_bit = pbits[dest_slot]
      relation = group * nbits + dest_bit
      if relation_kind[relation] == 0
        relation_kind[relation] = 1
        relation_source_a[relation] = pbits[source_slot]
      else
        return miss unless relation_kind[relation] == 1
        return miss unless relation_source_a[relation] == pbits[source_slot]
      relation_count[relation] += 1
      signature = 0
      signature = signature | 1 if payload_lits[source_slot] > 0
      signature = signature | 2 if payload_lits[dest_slot] > 0
      relation_signs[relation] = relation_signs[relation] | (1 << signature)
      seq2_count[group] += 1
    else
      return miss unless payload_count == 3
      return miss unless source_items == 2 && peer_items == 1
      dest_slot = 0
      dest_slot += 1 while dest_slot < 3 && pnodes[dest_slot] == source
      return miss if dest_slot == 3
      source_slot_a = 0
      source_slot_a += 1 if source_slot_a == dest_slot
      source_slot_b = source_slot_a + 1
      source_slot_b += 1 if source_slot_b == dest_slot
      return miss if pbits[source_slot_a] == pbits[source_slot_b]
      if pbits[source_slot_a] > pbits[source_slot_b]
        swap = source_slot_a
        source_slot_a = source_slot_b
        source_slot_b = swap
      dest_bit = pbits[dest_slot]
      relation = group * nbits + dest_bit
      if relation_kind[relation] == 0
        relation_kind[relation] = 2
        relation_source_a[relation] = pbits[source_slot_a]
        relation_source_b[relation] = pbits[source_slot_b]
      else
        return miss unless relation_kind[relation] == 2
        return miss unless relation_source_a[relation] == pbits[source_slot_a]
        return miss unless relation_source_b[relation] == pbits[source_slot_b]
      relation_count[relation] += 1
      signature = 0
      signature = signature | 1 if payload_lits[source_slot_a] > 0
      signature = signature | 2 if payload_lits[source_slot_b] > 0
      signature = signature | 4 if payload_lits[dest_slot] > 0
      relation_signs[relation] = relation_signs[relation] | (1 << signature)
      seq3_count[group] += 1
    clause_index += 1

  node = 0
  while node < nnodes
    return miss unless invalid_seen[node] == 1
    node += 1

  initial_pattern = -1
  final_pattern = -1
  initial_groups = 0
  final_groups = 0
  group = 0
  while group < ngroups
    return miss if group_count[group] == 0
    source = group / 12
    if bare_count[group] == 1
      return miss unless group_count[group] == 1
      return miss unless type_count[group] == 0
      return miss unless seq1_count[group] == 0 && seq2_count[group] == 0 && seq3_count[group] == 0
      return miss unless target_node[group] == -2
      target_node[group] = -1
      group += 1
      next

    return miss unless bare_count[group] == 0
    return miss unless type_count[group] == 3 && dest_mask[group] == 7
    return miss if target_node[group] < 0 || target_type[group] >= 6
    destination = target_node[group]

    if source == 0
      return miss if destination == 0
      return miss unless peer_node[group] == destination
      return miss unless seq1_count[group] == nbits
      return miss unless seq2_count[group] == 0 && seq3_count[group] == 0
      return miss unless source_mask[group] == 0 && peer_mask[group] == full_seq_mask
      return miss unless group_count[group] == 3 + nbits
      if initial_pattern < 0
        initial_pattern = peer_signs[group]
      else
        return miss unless initial_pattern == peer_signs[group]
      initial_groups += 1
    elsif destination == 0
      return miss unless peer_node[group] == -1
      return miss unless seq1_count[group] == nbits
      return miss unless seq2_count[group] == 0 && seq3_count[group] == 0
      return miss unless source_mask[group] == full_seq_mask && peer_mask[group] == 0
      return miss unless group_count[group] == 3 + nbits
      if final_pattern < 0
        final_pattern = source_signs[group]
      else
        return miss unless final_pattern == source_signs[group]
      final_groups += 1
    else
      return miss unless peer_node[group] == destination
      return miss unless seq1_count[group] == 0
      return miss unless source_mask[group] == full_seq_mask
      return miss unless peer_mask[group] == full_seq_mask
      pair_relations = 0
      xor_relations = 0
      bit = 0
      while bit < nbits
        relation = group * nbits + bit
        if relation_kind[relation] == 1
          return miss unless relation_count[relation] == 2
          signs = relation_signs[relation]
          return miss unless signs == 6 || signs == 9
          pair_relations += 1
        elsif relation_kind[relation] == 2
          return miss unless relation_count[relation] == 4
          signs = relation_signs[relation]
          return miss unless signs == 105 || signs == 150
          xor_relations += 1
        else
          return miss
        bit += 1
      if xor_relations == 0
        return miss unless pair_relations == nbits
        return miss unless seq2_count[group] == 2 * nbits && seq3_count[group] == 0
        return miss unless group_count[group] == 3 + 2 * nbits
      else
        return miss unless xor_relations == 1 && pair_relations == nbits - 1
        return miss unless seq2_count[group] == 2 * (nbits - 1) && seq3_count[group] == 4
        return miss unless group_count[group] == 5 + 2 * nbits
    group += 1
  return miss if initial_groups == 0 || final_groups == 0

  recognized = {
    "recognized": true, "status": 0, "model": [],
    "nodes": 0, "transitions": nnodes,
    "conflicts": 0, "decisions": 0, "props": 0
  }
  calls = i8[nnodes]
  types = i8[nnodes]
  used = i8[nnodes]
  meta = i64[2]
  start_types = i8[6]
  found = 0
  start_type = 0
  while start_type < 6 && found == 0 && meta[1] == 0
    start_types[start_type] = start_type
    node = 0
    while node < nnodes
      used[node] = 0
      calls[node] = -1
      types[node] = -1
      node += 1
    used[0] = 1
    found = wassat_stedman_search(
      0, nnodes, start_type, 0, start_types[start_type],
      target_node, target_type, fixed_call,
      used, calls, types, meta, node_cap
    )
    start_type += 1
  recognized["nodes"] = meta[0]
  recognized["found"] = found == 1
  recognized["assumptions"] = []
  return recognized unless found == 1

  recognized["assumptions"] = wassat_stedman_assumptions(nnodes, calls, types)
  recognized

# Return status one only with a complete replay-checked Boolean model.
-> wassat_stedman_solve(formula, node_cap = WASSAT_STEDMAN_NODE_CAP)
  wassat_stedman_solve_budget(
    formula, node_cap, WASSAT_STEDMAN_COMPLETION_CONFLICTS
  )

-> wassat_stedman_solve_budget(formula, node_cap, conflict_cap)
  miss = wassat_stedman_miss
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  scan = wassat_stedman_scan(
    nv, formula["flat_ncl"], lits, offs, lens, node_cap
  )
  return scan unless scan["recognized"] && scan["found"]

  art = wassat_raw_artifact(formula, nv)
  solver = Wassat.from_flat(nv, art, 0)
  result = solver.solve_assuming_budget(
    scan["assumptions"], conflict_cap
  )
  scan["conflicts"] = result["conflicts"]
  scan["decisions"] = result["decisions"]
  scan["props"] = result["props"]
  return scan unless result["status"] == 1
  return scan unless result["model"].size == nv
  return scan unless wassat_model_satisfies?(formula, result["model"])
  scan["status"] = 1
  scan["model"] = result["model"]
  scan
