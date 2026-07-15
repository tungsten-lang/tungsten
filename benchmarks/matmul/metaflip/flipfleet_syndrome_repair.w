# Event-triggered exact syndrome repair for nominal FlipFleet GPU records.
#
# A preserved reject is still a structurally valid rank-one decomposition; it
# merely fails the exhaustive multiplication-tensor gate.  This module rebuilds
# its complete n^6-bit error syndrome, records its three families of coordinate
# slices, and treats every one-bit edit of one factor of one term as an exact
# GF(2) delta column.
#
# Linear repair is exact when each touched term is edited on only one of U, V,
# or W.  Modes 1--3 enforce that condition globally; striped modes 4--6 enforce
# one axis per term.  Mode 0 includes every axis and is useful as a broader
# probe, but a solution may contain nonlinear cross-axis interactions.  No
# candidate is admitted on the linear calculation alone: `ffsr_apply_exact`
# materializes the edits, canonicalizes zero/duplicate terms, and runs the
# independent exhaustive `metaflip_worker` gate in a fresh state.
#
# The solver is deliberately event-driven CPU code.  All-axis storage is small
# through 5x5; axis-safe 6x6/7x7 attempts are also practical as rare jobs but
# use progressively more memory.  Every allocation is guarded by an explicit
# word budget.  GPU integration can reuse the syndrome and edit descriptors
# for regular overlap scoring without moving the authoritative exact gate off
# the host.

use metaflip_worker
use flipfleet_gpu_reject

-> ffsr_tensor_bits(n) (i64) i64
  dim = n * n ## i64
  dim * dim * dim

-> ffsr_tensor_words(n) (i64) i64
  (ffsr_tensor_bits(n) + 63) / 64

-> ffsr_combo_words(count) (i64) i64
  (count + 63) / 64

-> ffsr_clear(values, offset, count) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    values[offset + i] = 0
    i += 1
  count

-> ffsr_copy(source, source_offset, target, target_offset, count) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    target[target_offset + i] = source[source_offset + i]
    i += 1
  count

-> ffsr_xor(source, source_offset, target, target_offset, count) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    target[target_offset + i] = target[target_offset + i] ^ source[source_offset + i]
    i += 1
  count

-> ffsr_bit(values, offset, bit) (i64[] i64 i64) i64
  (values[offset + bit / 64] >> (bit % 64)) & 1

-> ffsr_set_bit(values, offset, bit) (i64[] i64 i64) i64
  word = offset + bit / 64 ## i64
  values[word] = values[word] | (1 << (bit % 64))
  1

-> ffsr_toggle_bit(values, offset, bit) (i64[] i64 i64) i64
  word = offset + bit / 64 ## i64
  values[word] = values[word] ^ (1 << (bit % 64))
  1

-> ffsr_xor_outer(tensor, offset, u, v, w, n) (i64[] i64 i64 i64 i64 i64) i64
  dim = n * n ## i64
  ai = 0 ## i64
  while ai < dim
    if ((u >> ai) & 1) != 0
      bi = 0 ## i64
      while bi < dim
        if ((v >> bi) & 1) != 0
          ci = 0 ## i64
          while ci < dim
            if ((w >> ci) & 1) != 0
              z = ffsr_toggle_bit(tensor, offset, (ai * dim + bi) * dim + ci) ## i64
            ci += 1
        bi += 1
    ai += 1
  1

-> ffsr_xor_multiplication_tensor(tensor, offset, n) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    k = 0 ## i64
    while k < n
      j = 0 ## i64
      while j < n
        ai = i * n + k ## i64
        bi = k * n + j ## i64
        ci = i * n + j ## i64
        z = ffsr_toggle_bit(tensor, offset, (ai * n * n + bi) * n * n + ci) ## i64
        j += 1
      k += 1
    i += 1
  1

# Fill exact syndrome statistics and all three coordinate-slice histograms.
# meta: bits, words, weight, active-A/B/C slices, max-A/B/C slice, first error.
-> ffsr_measure(syndrome, n, a_slices, b_slices, c_slices, meta) (i64[] i64 i64[] i64[] i64[] i64[]) i64
  dim = n * n ## i64
  tensor_bits = ffsr_tensor_bits(n) ## i64
  i = 0 ## i64
  while i < dim
    a_slices[i] = 0
    b_slices[i] = 0
    c_slices[i] = 0
    i += 1
  weight = 0 ## i64
  first = 0 ## i64
  bit = 0 ## i64
  while bit < tensor_bits
    if ffsr_bit(syndrome, 0, bit) != 0
      if first == 0
        first = bit + 1
      ai = bit / (dim * dim) ## i64
      bi = (bit / dim) % dim ## i64
      ci = bit % dim ## i64
      a_slices[ai] += 1
      b_slices[bi] += 1
      c_slices[ci] += 1
      weight += 1
    bit += 1
  active_a = 0 ## i64
  active_b = 0 ## i64
  active_c = 0 ## i64
  max_a = 0 ## i64
  max_b = 0 ## i64
  max_c = 0 ## i64
  i = 0
  while i < dim
    if a_slices[i] > 0
      active_a += 1
    if b_slices[i] > 0
      active_b += 1
    if c_slices[i] > 0
      active_c += 1
    if a_slices[i] > max_a
      max_a = a_slices[i]
    if b_slices[i] > max_b
      max_b = b_slices[i]
    if c_slices[i] > max_c
      max_c = c_slices[i]
    i += 1
  meta[0] = tensor_bits
  meta[1] = ffsr_tensor_words(n)
  meta[2] = weight
  meta[3] = active_a
  meta[4] = active_b
  meta[5] = active_c
  meta[6] = max_a
  meta[7] = max_b
  meta[8] = max_c
  meta[9] = first
  weight

# Reconstruct candidate XOR target exactly.  Returns -1 for malformed factors.
-> ffsr_build_syndrome(us, vs, ws, rank, n, syndrome, a_slices, b_slices, c_slices, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if n < 3 || n > 7 || rank < 1
    return 0 - 1
  words = ffsr_tensor_words(n) ## i64
  dim = n * n ## i64
  if syndrome.size() < words || a_slices.size() < dim || b_slices.size() < dim || c_slices.size() < dim
    return 0 - 1
  z = ffsr_clear(syndrome, 0, words) ## i64
  factor_mask = (1 << dim) - 1 ## i64
  t = 0 ## i64
  while t < rank
    if us[t] <= 0 || vs[t] <= 0 || ws[t] <= 0
      return 0 - 1
    if (us[t] & factor_mask) != us[t] || (vs[t] & factor_mask) != vs[t] || (ws[t] & factor_mask) != ws[t]
      return 0 - 1
    ai = 0 ## i64
    while ai < dim
      if ((us[t] >> ai) & 1) != 0
        bi = 0 ## i64
        while bi < dim
          if ((vs[t] >> bi) & 1) != 0
            ci = 0 ## i64
            while ci < dim
              if ((ws[t] >> ci) & 1) != 0
                tensor_bit = (ai * dim + bi) * dim + ci ## i64
                tensor_word = tensor_bit / 64 ## i64
                syndrome[tensor_word] = syndrome[tensor_word] ^ (1 << (tensor_bit % 64))
              ci += 1
          bi += 1
      ai += 1
    t += 1
  i = 0 ## i64
  while i < n
    k = 0 ## i64
    while k < n
      j = 0 ## i64
      while j < n
        ai = i * n + k
        bi = k * n + j
        ci = i * n + j
        tensor_bit = (ai * dim + bi) * dim + ci
        tensor_word = tensor_bit / 64
        syndrome[tensor_word] = syndrome[tensor_word] ^ (1 << (tensor_bit % 64))
        j += 1
      k += 1
    i += 1
  ffsr_measure(syndrome, n, a_slices, b_slices, c_slices, meta)

-> ffsr_current_syndrome(st, n, syndrome, a_slices, b_slices, c_slices, meta) (i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if ffw_valid(st) != 1 || ffw_n(st) != n || ffw_current_rank(st) < 1
    return 0 - 1
  rank = ffw_current_rank(st) ## i64
  us = i64[rank]
  vs = i64[rank]
  ws = i64[rank]
  if ffw_export_current(st, us, vs, ws) != rank
    return 0 - 1
  ffsr_build_syndrome(us, vs, ws, rank, n, syndrome, a_slices, b_slices, c_slices, meta)

# Load a coordinator-preserved replay bundle.  Exact-invalid candidates make
# `ffw_load_scheme_cap` return -1 but deliberately remain in its current view.
# info: nominal rank, first exact error, worker error, coordinator error,
# parser result.  A positive return is a replayable exact-invalid candidate.
-> ffsr_load_preserved(st, metadata_path, n, capacity, seed, info) (i64[] String i64 i64 i64 i64[]) i64
  metadata = read_file(metadata_path)
  if metadata == nil
    return 0
  candidate_path = ffgr_meta_value(metadata, "candidate_path")
  nominal = ffgr_meta_i64(metadata, "nominal_rank", 0 - 1) ## i64
  tensor_name = ffgr_meta_value(metadata, "tensor")
  if tensor_name != "" && tensor_name != n.to_s() + "x" + n.to_s()
    return 0
  if candidate_path == "" || nominal < 1 || nominal > capacity
    return 0
  loaded = ffw_load_scheme_cap(st, candidate_path, n, capacity, seed, 4, 2, 1000, 250) ## i64
  error = ffgr_candidate_exact_error(st, n, nominal) ## i64
  info[0] = nominal
  info[1] = error
  info[2] = ffgr_meta_i64(metadata, "worker_exact_error", 0)
  info[3] = ffgr_meta_i64(metadata, "coordinator_exact_error", 0)
  info[4] = loaded
  if ffw_valid(st) != 1 || ffw_current_rank(st) != nominal || error <= 0
    return 0
  nominal

# Modes: 0 all edits; 1 U; 2 V; 3 W; 4--6 one deterministic striped axis per
# term.  The latter five modes cannot select more than one axis on any term.
-> ffsr_edit_count(rank, n, mode) (i64 i64 i64) i64
  if rank < 1 || n < 3 || n > 7 || mode < 0 || mode > 6
    return 0
  multiplier = 1 ## i64
  if mode == 0
    multiplier = 3
  rank * n * n * multiplier

-> ffsr_build_edits(rank, n, mode, edit_terms, edit_axes, edit_bits) (i64 i64 i64 i64[] i64[] i64[]) i64
  count = ffsr_edit_count(rank, n, mode) ## i64
  if count < 1 || edit_terms.size() < count || edit_axes.size() < count || edit_bits.size() < count
    return 0
  dim = n * n ## i64
  at = 0 ## i64
  term = 0 ## i64
  while term < rank
    axis_first = 0 ## i64
    axis_last = 3 ## i64
    if mode >= 1 && mode <= 3
      axis_first = mode - 1
      axis_last = axis_first + 1
    if mode >= 4
      axis_first = (term + mode - 4) % 3
      axis_last = axis_first + 1
    axis = axis_first ## i64
    while axis < axis_last
      bit = 0 ## i64
      while bit < dim
        edit_terms[at] = term
        edit_axes[at] = axis
        edit_bits[at] = bit
        at += 1
        bit += 1
      axis += 1
    term += 1
  at

-> ffsr_work_words(rank, n, mode) (i64 i64 i64) i64
  edits = ffsr_edit_count(rank, n, mode) ## i64
  if edits < 1
    return 0
  tensor_words = ffsr_tensor_words(n) ## i64
  combo_words = ffsr_combo_words(edits) ## i64
  # Pivot indices are i32 in the implementation; count them conservatively as
  # full words so this estimate remains an upper bound for scheduler policy.
  edits * (tensor_words + combo_words) + ffsr_tensor_bits(n) + 2 * tensor_words + 3 * combo_words + 3 * edits

-> ffsr_first_set_from(values, offset, words, start_bit) (i64[] i64 i64 i64) i64
  word = start_bit / 64 ## i64
  first_shift = start_bit % 64 ## i64
  while word < words
    value = values[offset + word] ## i64
    bit = 0 ## i64
    if word == start_bit / 64
      bit = first_shift
    while bit < 64
      if ((value >> bit) & 1) != 0
        return word * 64 + bit
      bit += 1
    word += 1
  0 - 1

-> ffsr_fill_delta(work, words, us, vs, ws, edit_term, edit_axis, edit_bit, n) (i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64) i64
  z = ffsr_clear(work, 0, words) ## i64
  one = 1 << edit_bit ## i64
  u = us[edit_term] ## i64
  v = vs[edit_term] ## i64
  w = ws[edit_term] ## i64
  if edit_axis == 0
    u = one
  if edit_axis == 1
    v = one
  if edit_axis == 2
    w = one
  ffsr_xor_outer(work, 0, u, v, w, n)

-> ffsr_solution_matches(us, vs, ws, n, syndrome, edit_terms, edit_axes, edit_bits, edit_count, solution) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[]) i64
  words = ffsr_tensor_words(n) ## i64
  residual = i64[words]
  delta = i64[words]
  z = ffsr_copy(syndrome, 0, residual, 0, words) ## i64
  edit = 0 ## i64
  while edit < edit_count
    if ffsr_bit(solution, 0, edit) != 0
      z = ffsr_fill_delta(delta, words, us, vs, ws, edit_terms[edit], edit_axes[edit], edit_bits[edit], n)
      z = ffsr_xor(delta, 0, residual, 0, words)
    edit += 1
  word = 0 ## i64
  while word < words
    if residual[word] != 0
      return 0
    word += 1
  1

# Solve A*x=syndrome by exact bit-packed column elimination.  meta: edit
# columns, tensor words, combination words, basis rank, row XORs, selected
# edits, estimated work words, status (1 hit, 0 miss, -1 malformed, -2 cap,
# -3 internal solution-replay disagreement).
-> ffsr_solve_delta(us, vs, ws, rank, n, syndrome, edit_terms, edit_axes, edit_bits, edit_count, max_work_words, solution, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64 i64 i64[] i64[]) i64
  tensor_bits = ffsr_tensor_bits(n) ## i64
  tensor_words = ffsr_tensor_words(n) ## i64
  combo_words = ffsr_combo_words(edit_count) ## i64
  work_words = edit_count * (tensor_words + combo_words) + tensor_bits + 2 * tensor_words + 3 * combo_words + 3 * edit_count ## i64
  meta[0] = edit_count
  meta[1] = tensor_words
  meta[2] = combo_words
  meta[3] = 0
  meta[4] = 0
  meta[5] = 0
  meta[6] = work_words
  meta[7] = 0 - 1
  if n < 3 || n > 7 || rank < 1 || edit_count < 1 || syndrome.size() < tensor_words || solution.size() < combo_words
    return 0 - 1
  if max_work_words > 0 && work_words > max_work_words
    meta[7] = 0 - 2
    return 0 - 2
  z = ffsr_clear(solution, 0, combo_words) ## i64
  pivots = i32[tensor_bits]
  pivot_bit = 0 ## i64
  while pivot_bit < tensor_bits
    pivots[pivot_bit] = 0
    pivot_bit += 1
  basis_tensors = i64[edit_count * tensor_words]
  basis_combos = i64[edit_count * combo_words]
  work_tensor = i64[tensor_words]
  work_combo = i64[combo_words]
  basis_count = 0 ## i64
  reductions = 0 ## i64
  column = 0 ## i64
  while column < edit_count
    term = edit_terms[column] ## i64
    axis = edit_axes[column] ## i64
    bit = edit_bits[column] ## i64
    if term < 0 || term >= rank || axis < 0 || axis > 2 || bit < 0 || bit >= n * n
      meta[7] = 0 - 1
      return 0 - 1
    z = ffsr_fill_delta(work_tensor, tensor_words, us, vs, ws, term, axis, bit, n)
    z = ffsr_clear(work_combo, 0, combo_words)
    z = ffsr_set_bit(work_combo, 0, column)
    pivot = ffsr_first_set_from(work_tensor, 0, tensor_words, 0) ## i64
    settled = 0 ## i64
    while pivot >= 0 && settled == 0
      prior = pivots[pivot] - 1 ## i64
      if prior < 0
        z = ffsr_copy(work_tensor, 0, basis_tensors, basis_count * tensor_words, tensor_words)
        z = ffsr_copy(work_combo, 0, basis_combos, basis_count * combo_words, combo_words)
        pivots[pivot] = basis_count + 1
        basis_count += 1
        settled = 1
      if prior >= 0
        z = ffsr_xor(basis_tensors, prior * tensor_words, work_tensor, 0, tensor_words)
        z = ffsr_xor(basis_combos, prior * combo_words, work_combo, 0, combo_words)
        reductions += 1
        pivot = ffsr_first_set_from(work_tensor, 0, tensor_words, pivot + 1)
    column += 1
  target = i64[tensor_words]
  z = ffsr_copy(syndrome, 0, target, 0, tensor_words)
  pivot = ffsr_first_set_from(target, 0, tensor_words, 0) ## i64
  solved = 1 ## i64
  while pivot >= 0 && solved == 1
    prior = pivots[pivot] - 1 ## i64
    if prior < 0
      solved = 0
    if prior >= 0
      z = ffsr_xor(basis_tensors, prior * tensor_words, target, 0, tensor_words)
      z = ffsr_xor(basis_combos, prior * combo_words, solution, 0, combo_words)
      reductions += 1
      pivot = ffsr_first_set_from(target, 0, tensor_words, pivot + 1)
  selected = 0 ## i64
  if solved == 1
    i = 0 ## i64
    while i < edit_count
      if ffsr_bit(solution, 0, i) != 0
        selected += 1
      i += 1
    if selected == 0
      solved = 0
    if solved == 1 && ffsr_solution_matches(us, vs, ws, n, syndrome, edit_terms, edit_axes, edit_bits, edit_count, solution) != 1
      solved = 0 - 3
  meta[3] = basis_count
  meta[4] = reductions
  meta[5] = selected
  meta[7] = solved
  solved

-> ffsr_toggle_term(us, vs, ws, rank, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < rank && found < 0
    if us[i] == u && vs[i] == v && ws[i] == w
      found = i
    i += 1
  if found >= 0
    rank -= 1
    us[found] = us[rank]
    vs[found] = vs[rank]
    ws[found] = ws[rank]
    return rank
  if rank >= capacity
    return 0 - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

# Apply a solved edit mask and independently exact-gate the materialized
# scheme.  meta: selected edits, touched terms, multi-axis terms, zero terms,
# duplicate cancellations, materialized rank, exact gate, reserved.
-> ffsr_apply_exact(us, vs, ws, rank, n, edit_terms, edit_axes, edit_bits, edit_count, solution, out_u, out_v, out_w, capacity, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < 8
    meta[i] = 0
    i += 1
  if rank < 1 || rank > capacity || n < 3 || n > 7
    return 0
  edited_u = i64[rank]
  edited_v = i64[rank]
  edited_w = i64[rank]
  axis_masks = i64[rank]
  i = 0
  while i < rank
    edited_u[i] = us[i]
    edited_v[i] = vs[i]
    edited_w[i] = ws[i]
    axis_masks[i] = 0
    i += 1
  selected = 0 ## i64
  edit = 0 ## i64
  while edit < edit_count
    if ffsr_bit(solution, 0, edit) != 0
      term = edit_terms[edit] ## i64
      axis = edit_axes[edit] ## i64
      bit = edit_bits[edit] ## i64
      if term < 0 || term >= rank || axis < 0 || axis > 2 || bit < 0 || bit >= n * n
        return 0
      if axis == 0
        edited_u[term] = edited_u[term] ^ (1 << bit)
      if axis == 1
        edited_v[term] = edited_v[term] ^ (1 << bit)
      if axis == 2
        edited_w[term] = edited_w[term] ^ (1 << bit)
      axis_masks[term] = axis_masks[term] | (1 << axis)
      selected += 1
    edit += 1
  touched = 0 ## i64
  conflicts = 0 ## i64
  zero_terms = 0 ## i64
  i = 0
  while i < rank
    if axis_masks[i] != 0
      touched += 1
      if ffw_popcount(axis_masks[i]) > 1
        conflicts += 1
    if edited_u[i] == 0 || edited_v[i] == 0 || edited_w[i] == 0
      zero_terms += 1
    i += 1
  out_rank = 0 ## i64
  i = 0
  while i < rank
    if edited_u[i] != 0 && edited_v[i] != 0 && edited_w[i] != 0
      out_rank = ffsr_toggle_term(out_u, out_v, out_w, out_rank, capacity, edited_u[i], edited_v[i], edited_w[i])
      if out_rank < 0
        return 0
    i += 1
  duplicate_cancellations = rank - zero_terms - out_rank ## i64
  fresh = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(fresh, out_u, out_v, out_w, out_rank, n, capacity, 880301, 4, 2, 1000, 250) ## i64
  exact = 0 ## i64
  if loaded == out_rank && ffw_verify_current_exact(fresh, n) == 1
    exact = 1
  meta[0] = selected
  meta[1] = touched
  meta[2] = conflicts
  meta[3] = zero_terms
  meta[4] = duplicate_cancellations
  meta[5] = out_rank
  meta[6] = exact
  if exact == 1
    return out_rank
  0

# One complete event-triggered attempt.  meta: syndrome weight, edit columns,
# basis rank, reductions, selected edits, touched terms, multi-axis conflicts,
# result rank, exact gate, mode, work words, solve status, active A/B/C slices,
# first mismatch.
-> ffsr_try_repair(us, vs, ws, rank, n, mode, max_work_words, out_u, out_v, out_w, capacity, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  words = ffsr_tensor_words(n) ## i64
  dim = n * n ## i64
  syndrome = i64[words]
  a_slices = i64[dim]
  b_slices = i64[dim]
  c_slices = i64[dim]
  syndrome_meta = i64[10]
  weight = ffsr_build_syndrome(us, vs, ws, rank, n, syndrome, a_slices, b_slices, c_slices, syndrome_meta) ## i64
  meta[0] = weight
  meta[9] = mode
  if weight <= 0
    return 0
  edit_count = ffsr_edit_count(rank, n, mode) ## i64
  edit_terms = i64[edit_count]
  edit_axes = i64[edit_count]
  edit_bits = i64[edit_count]
  if ffsr_build_edits(rank, n, mode, edit_terms, edit_axes, edit_bits) != edit_count
    meta[11] = 0 - 1
    return 0
  solution = i64[ffsr_combo_words(edit_count)]
  solve_meta = i64[8]
  solved = ffsr_solve_delta(us, vs, ws, rank, n, syndrome, edit_terms, edit_axes, edit_bits, edit_count, max_work_words, solution, solve_meta) ## i64
  meta[1] = edit_count
  meta[2] = solve_meta[3]
  meta[3] = solve_meta[4]
  meta[4] = solve_meta[5]
  meta[10] = solve_meta[6]
  meta[11] = solved
  meta[12] = syndrome_meta[3]
  meta[13] = syndrome_meta[4]
  meta[14] = syndrome_meta[5]
  meta[15] = syndrome_meta[9]
  if solved != 1
    return 0
  apply_meta = i64[8]
  repaired = ffsr_apply_exact(us, vs, ws, rank, n, edit_terms, edit_axes, edit_bits, edit_count, solution, out_u, out_v, out_w, capacity, apply_meta) ## i64
  meta[5] = apply_meta[1]
  meta[6] = apply_meta[2]
  meta[7] = apply_meta[5]
  meta[8] = apply_meta[6]
  repaired

-> ffsr_try_repair_current(st, n, mode, max_work_words, out_u, out_v, out_w, capacity, meta) (i64[] i64 i64 i64 i64[] i64[] i64[] i64 i64[]) i64
  if ffw_valid(st) != 1 || ffw_n(st) != n
    return 0
  rank = ffw_current_rank(st) ## i64
  if rank < 1 || rank > capacity
    return 0
  us = i64[rank]
  vs = i64[rank]
  ws = i64[rank]
  if ffw_export_current(st, us, vs, ws) != rank
    return 0
  ffsr_try_repair(us, vs, ws, rank, n, mode, max_work_words, out_u, out_v, out_w, capacity, meta)
