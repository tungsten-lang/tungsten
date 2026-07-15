# Exact bounded SAT destroy-and-repair for FlipFleet.
#
# A caller selects k live rank-one terms.  Their three joint coordinate
# supports define a lossless local window: every selected term is zero outside
# that Cartesian cube.  This module emits the complete Brent equations for
# asking whether the selected partial tensor has rank at most `want < k`
# inside that window.  DIMACS uses Tseitin variables for every trilinear
# product and an exact XOR chain for every tensor coefficient; there are no
# projected fingerprints or random checks.
#
# An optional external solver is run as one alarm-bounded process.  Its model
# is parsed in Tungsten, reconstructed in the ambient factor coordinates, and
# checked against the exact selected tensor.  `ffsdr_apply_current` then
# performs an independent full n^6 scheme gate and rolls back every rejected
# splice.  Zero SAT slots are allowed, so the query really is rank <= want.

use flipfleet_span_refactor

-> ffsdr_tensor_words(bits) (i64) i64
  (bits + 63) / 64

-> ffsdr_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

-> ffsdr_bit(values, bit) (i64[] i64) i64
  (values[bit / 64] >> (bit % 64)) & 1

-> ffsdr_toggle_bit(values, bit) (i64[] i64) i64
  word = bit / 64 ## i64
  values[word] = values[word] ^ (1 << (bit % 64))
  1

-> ffsdr_rows_equal(left, right, words) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < words
    if left[i] != right[i]
      return 0
    i += 1
  1

-> ffsdr_xor_outer(tensor, u, v, w, uwidth, vwidth, wwidth) (i64[] i64 i64 i64 i64 i64 i64) i64
  ui = 0 ## i64
  while ui < uwidth
    if ((u >> ui) & 1) != 0
      vi = 0 ## i64
      while vi < vwidth
        if ((v >> vi) & 1) != 0
          wi = 0 ## i64
          while wi < wwidth
            if ((w >> wi) & 1) != 0
              z = ffsdr_toggle_bit(tensor, (ui * vwidth + vi) * wwidth + wi) ## i64
            wi += 1
        vi += 1
    ui += 1
  1

-> ffsdr_collect_support(values, count, width, coordinates) (i64[] i64 i64 i64[]) i64
  union = 0 ## i64
  i = 0 ## i64
  while i < count
    if values[i] <= 0 || (values[i] >> width) != 0
      return 0
    union = union | values[i]
    i += 1
  support = 0 ## i64
  bit = 0 ## i64
  while bit < width
    if ((union >> bit) & 1) != 0
      coordinates[support] = bit
      support += 1
    bit += 1
  support

-> ffsdr_compress_factor(value, coordinates, count) (i64 i64[] i64) i64
  result = 0 ## i64
  i = 0 ## i64
  while i < count
    if ((value >> coordinates[i]) & 1) != 0
      result = result | (1 << i)
    i += 1
  result

-> ffsdr_expand_factor(value, coordinates, count) (i64 i64[] i64) i64
  result = 0 ## i64
  i = 0 ## i64
  while i < count
    if ((value >> i) & 1) != 0
      result = result | (1 << coordinates[i])
    i += 1
  result

# Prepare the exact partial tensor in compressed joint-support coordinates.
# meta: support U/V/W, cells, words, selected count.
-> ffsdr_prepare_window(su, sv, sw, k, uwidth, vwidth, wwidth, ucoords, vcoords, wcoords, local_u, local_v, local_w, target, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if k < 1 || uwidth < 1 || vwidth < 1 || wwidth < 1
    return 0
  au = ffsdr_collect_support(su, k, uwidth, ucoords) ## i64
  av = ffsdr_collect_support(sv, k, vwidth, vcoords) ## i64
  aw = ffsdr_collect_support(sw, k, wwidth, wcoords) ## i64
  if au < 1 || av < 1 || aw < 1
    return 0
  cells = au * av * aw ## i64
  words = ffsdr_tensor_words(cells) ## i64
  if target.size() < words || local_u.size() < k || local_v.size() < k || local_w.size() < k
    return 0
  z = ffsdr_clear(target, words) ## i64
  i = 0 ## i64
  while i < k
    local_u[i] = ffsdr_compress_factor(su[i], ucoords, au)
    local_v[i] = ffsdr_compress_factor(sv[i], vcoords, av)
    local_w[i] = ffsdr_compress_factor(sw[i], wcoords, aw)
    z = ffsdr_xor_outer(target, local_u[i], local_v[i], local_w[i], au, av, aw)
    i += 1
  meta[0] = au
  meta[1] = av
  meta[2] = aw
  meta[3] = cells
  meta[4] = words
  meta[5] = k
  1

-> ffsdr_primary_u(term, bit, au, av, aw) (i64 i64 i64 i64 i64) i64
  1 + term * (au + av + aw) + bit

-> ffsdr_primary_v(term, bit, au, av, aw) (i64 i64 i64 i64 i64) i64
  1 + term * (au + av + aw) + au + bit

-> ffsdr_primary_w(term, bit, au, av, aw) (i64 i64 i64 i64 i64) i64
  1 + term * (au + av + aw) + au + av + bit

-> ffsdr_product_var(cell, term, want, primary) (i64 i64 i64 i64) i64
  primary + 1 + cell * want + term

-> ffsdr_parity_var(cell, stage, cells, want, primary) (i64 i64 i64 i64 i64) i64
  primary + cells * want + 1 + cell * (want - 1) + stage

# Emit exact DIMACS Brent equations.  The target is an arbitrary multiword
# bitset in (U,V,W) lexicographic cell order.  meta[4]/[5] receive vars/clauses.
-> ffsdr_emit_cnf(target, au, av, aw, want, max_cells, meta) (i64[] i64 i64 i64 i64 i64 i64[])
  cells = au * av * aw ## i64
  if au < 1 || av < 1 || aw < 1 || want < 1 || cells < 1 || cells > max_cells
    return nil
  if target.size() < ffsdr_tensor_words(cells)
    return nil
  primary = want * (au + av + aw) ## i64
  parity_variables = 0 ## i64
  if want > 1
    parity_variables = cells * (want - 1)
  variables = primary + cells * want + parity_variables ## i64
  clauses_per_cell = want * 4 + 1 ## i64
  if want > 1
    clauses_per_cell += (want - 1) * 4
  clauses = cells * clauses_per_cell ## i64
  body = ""
  cell = 0 ## i64
  while cell < cells
    wi = cell % aw ## i64
    rest = cell / aw ## i64
    vi = rest % av ## i64
    ui = rest / av ## i64
    term = 0 ## i64
    while term < want
      uvar = ffsdr_primary_u(term, ui, au, av, aw) ## i64
      vvar = ffsdr_primary_v(term, vi, au, av, aw) ## i64
      wvar = ffsdr_primary_w(term, wi, au, av, aw) ## i64
      product = ffsdr_product_var(cell, term, want, primary) ## i64
      body = body + (0 - product).to_s() + " " + uvar.to_s() + " 0\n"
      body = body + (0 - product).to_s() + " " + vvar.to_s() + " 0\n"
      body = body + (0 - product).to_s() + " " + wvar.to_s() + " 0\n"
      body = body + product.to_s() + " " + (0 - uvar).to_s() + " " + (0 - vvar).to_s() + " " + (0 - wvar).to_s() + " 0\n"
      term += 1
    if want == 1
      product = ffsdr_product_var(cell, 0, want, primary) ## i64
      if ffsdr_bit(target, cell) == 1
        body = body + product.to_s() + " 0\n"
      else
        body = body + (0 - product).to_s() + " 0\n"
    else
      left = ffsdr_product_var(cell, 0, want, primary) ## i64
      right = ffsdr_product_var(cell, 1, want, primary) ## i64
      stage = 0 ## i64
      while stage < want - 1
        parity = ffsdr_parity_var(cell, stage, cells, want, primary) ## i64
        if stage > 0
          left = ffsdr_parity_var(cell, stage - 1, cells, want, primary)
          right = ffsdr_product_var(cell, stage + 1, want, primary)
        body = body + left.to_s() + " " + right.to_s() + " " + (0 - parity).to_s() + " 0\n"
        body = body + (0 - left).to_s() + " " + (0 - right).to_s() + " " + (0 - parity).to_s() + " 0\n"
        body = body + left.to_s() + " " + (0 - right).to_s() + " " + parity.to_s() + " 0\n"
        body = body + (0 - left).to_s() + " " + right.to_s() + " " + parity.to_s() + " 0\n"
        stage += 1
      final_parity = ffsdr_parity_var(cell, want - 2, cells, want, primary) ## i64
      if ffsdr_bit(target, cell) == 1
        body = body + final_parity.to_s() + " 0\n"
      else
        body = body + (0 - final_parity).to_s() + " 0\n"
    cell += 1
  meta[4] = variables
  meta[5] = clauses
  "p cnf " + variables.to_s() + " " + clauses.to_s() + "\n" + body

-> ffsdr_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

# Return model text.  meta[6]: 1=solver reported SAT, -1=UNSAT,
# -2=timeout/process failure, -3=malformed/unknown response.
-> ffsdr_run_solver(cnf, solver_command, timeout_s, stem, meta) (String String i64 String i64[])
  meta[6] = 0 - 3
  if cnf == nil || solver_command.size() < 1 || timeout_s < 1
    return nil
  input_path = stem + ".cnf"
  model_path = stem + ".model"
  if write_file(input_path, cnf) == false || write_file(model_path, "") == false
    return nil
  command = "/usr/bin/perl -e 'alarm shift; exec @ARGV' " + timeout_s.to_s() + " " + solver_command + " " + ffsdr_shell_quote(input_path)
  command = command + " > " + ffsdr_shell_quote(model_path) + " 2>&1"
  ok = system(command)
  model = read_file(model_path)
  if model != nil && model.include?("UNSAT")
    meta[6] = 0 - 1
    return model
  if model != nil && model.include?("SAT")
    meta[6] = 1
    return model
  if ok == false
    meta[6] = 0 - 2
  model

# Decode only complete primary-variable assignments.  Partial and conflicting
# SAT models are malformed rather than silently treating missing bits as false.
-> ffsdr_decode_dimacs(model, want, au, av, aw, local_u, local_v, local_w) (String i64 i64 i64 i64 i64[] i64[] i64[]) i64
  if model == nil || !model.include?("SAT") || model.include?("UNSAT")
    return 0
  primary = want * (au + av + aw) ## i64
  assignments = i64[primary + 1]
  normalized = model.replace("\n", " ").replace("\r", " ").replace("\t", " ")
  tokens = normalized.split(" ")
  valid = 1 ## i64
  i = 0 ## i64
  while i < tokens.size()
    value = tokens[i].to_i() ## i64
    variable = value ## i64
    truth = 2 ## i64
    if value < 0
      variable = 0 - value
      truth = 1
    if variable > 0 && variable <= primary
      if assignments[variable] != 0 && assignments[variable] != truth
        valid = 0
      assignments[variable] = truth
    i += 1
  variable = 1
  while variable <= primary
    if assignments[variable] == 0
      valid = 0
    variable += 1
  if valid == 0
    return 0
  term = 0 ## i64
  while term < want
    local_u[term] = 0
    local_v[term] = 0
    local_w[term] = 0
    bit = 0 ## i64
    while bit < au
      if assignments[ffsdr_primary_u(term, bit, au, av, aw)] == 2
        local_u[term] = local_u[term] | (1 << bit)
      bit += 1
    bit = 0
    while bit < av
      if assignments[ffsdr_primary_v(term, bit, au, av, aw)] == 2
        local_v[term] = local_v[term] | (1 << bit)
      bit += 1
    bit = 0
    while bit < aw
      if assignments[ffsdr_primary_w(term, bit, au, av, aw)] == 2
        local_w[term] = local_w[term] | (1 << bit)
      bit += 1
    term += 1
  want

-> ffsdr_toggle_term(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return rank
  i = 0 ## i64
  while i < rank
    if us[i] == u && vs[i] == v && ws[i] == w
      us[i] = us[rank - 1]
      vs[i] = vs[rank - 1]
      ws[i] = ws[rank - 1]
      return rank - 1
    i += 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

-> ffsdr_local_terms_match(target, au, av, aw, us, vs, ws, count) (i64[] i64 i64 i64 i64[] i64[] i64[] i64) i64
  words = ffsdr_tensor_words(au * av * aw) ## i64
  made = i64[words]
  i = 0 ## i64
  while i < count
    z = ffsdr_xor_outer(made, us[i], vs[i], ws[i], au, av, aw) ## i64
    i += 1
  ffsdr_rows_equal(target, made, words)

# Deterministic exact fallback for tiny rank-one queries.  This is deliberately
# bounded rather than masquerading as a general SAT solver.
-> ffsdr_internal_rank1(su, sv, sw, k, uwidth, vwidth, wwidth, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  ucoords = i64[uwidth]
  vcoords = i64[vwidth]
  wcoords = i64[wwidth]
  local_u = i64[k]
  local_v = i64[k]
  local_w = i64[k]
  max_words = ffsdr_tensor_words(uwidth * vwidth * wwidth) ## i64
  target = i64[max_words]
  if ffsdr_prepare_window(su, sv, sw, k, uwidth, vwidth, wwidth, ucoords, vcoords, wcoords, local_u, local_v, local_w, target, meta) != 1
    return 0
  au = meta[0] ## i64
  av = meta[1] ## i64
  aw = meta[2] ## i64
  if au + av + aw > 18
    return 0
  u = 1 ## i64
  while u < (1 << au)
    v = 1 ## i64
    while v < (1 << av)
      w = 1 ## i64
      while w < (1 << aw)
        made = i64[meta[4]]
        z = ffsdr_xor_outer(made, u, v, w, au, av, aw) ## i64
        if ffsdr_rows_equal(target, made, meta[4]) == 1
          out_u[0] = ffsdr_expand_factor(u, ucoords, au)
          out_v[0] = ffsdr_expand_factor(v, vcoords, av)
          out_w[0] = ffsdr_expand_factor(w, wcoords, aw)
          meta[8] = 1
          meta[9] = 1
          meta[11] = 1
          return 1
        w += 1
      v += 1
    u += 1
  meta[11] = 0
  0

# End-to-end external query for selected raw terms.
-> ffsdr_solve_selected_external(su, sv, sw, k, want, uwidth, vwidth, wwidth, solver_command, timeout_s, stem, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 String i64 String i64[] i64[] i64[] i64[]) i64
  # The earlier experimental cap of eight replacement terms excluded the
  # intended 4x4 frozen-fringe query (16 -> 15).  The actual safety bounds are
  # the 4,096-cell CNF limit below and the caller's process deadline.
  if want < 1 || want >= k || want > 31
    return 0
  ucoords = i64[uwidth]
  vcoords = i64[vwidth]
  wcoords = i64[wwidth]
  selected_u = i64[k]
  selected_v = i64[k]
  selected_w = i64[k]
  max_words = ffsdr_tensor_words(uwidth * vwidth * wwidth) ## i64
  target = i64[max_words]
  if ffsdr_prepare_window(su, sv, sw, k, uwidth, vwidth, wwidth, ucoords, vcoords, wcoords, selected_u, selected_v, selected_w, target, meta) != 1
    return 0
  cnf = ffsdr_emit_cnf(target, meta[0], meta[1], meta[2], want, 4096, meta)
  if cnf == nil
    return 0
  model = ffsdr_run_solver(cnf, solver_command, timeout_s, stem, meta)
  if meta[6] != 1
    return 0
  model_u = i64[want]
  model_v = i64[want]
  model_w = i64[want]
  decoded = ffsdr_decode_dimacs(model, want, meta[0], meta[1], meta[2], model_u, model_v, model_w) ## i64
  meta[7] = decoded
  if decoded != want
    return 0
  rank = 0 ## i64
  i = 0 ## i64
  while i < want
    rank = ffsdr_toggle_term(out_u, out_v, out_w, rank,
      ffsdr_expand_factor(model_u[i], ucoords, meta[0]),
      ffsdr_expand_factor(model_v[i], vcoords, meta[1]),
      ffsdr_expand_factor(model_w[i], wcoords, meta[2]))
    i += 1
  meta[8] = rank
  # Verify in local coordinates after re-compressing canonical outputs.
  check_u = i64[want]
  check_v = i64[want]
  check_w = i64[want]
  i = 0
  while i < rank
    check_u[i] = ffsdr_compress_factor(out_u[i], ucoords, meta[0])
    check_v[i] = ffsdr_compress_factor(out_v[i], vcoords, meta[1])
    check_w[i] = ffsdr_compress_factor(out_w[i], wcoords, meta[2])
    i += 1
  if rank < 1 || rank > want || ffsdr_local_terms_match(target, meta[0], meta[1], meta[2], check_u, check_v, check_w, rank) != 1
    meta[9] = 0
    return 0
  meta[9] = 1
  meta[11] = rank
  rank

# Full worker-state splice gate for arbitrary bounded k -> fewer replacements.
-> ffsdr_apply_current(st, selected, k, out_u, out_v, out_w, out_count) (i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if ffw_valid(st) != 1 || out_count < 1 || out_count >= k
    return 0 - 1
  old_rank = st[6] ## i64
  if ffsr_selected_positions_valid(selected, k, old_rank) != 1 || ffsr_output_well_formed(out_u, out_v, out_w, out_count) != 1
    return 0 - 1
  source_u = i64[k]
  source_v = i64[k]
  source_w = i64[k]
  if ffsr_capture_current(st, selected, k, source_u, source_v, source_w) != 1
    return 0 - 1
  if ffw_verify_current_exact(st, st[2]) != 1
    return 0 - 1
  rank = old_rank ## i64
  i = 0 ## i64
  while i < k
    rank = ffw_toggle(st, source_u[i], source_v[i], source_w[i], rank)
    i += 1
  collision = i64[out_count]
  collisions = 0 ## i64
  i = 0
  while i < out_count
    if ffw_find_term(st,out_u[i],out_v[i],out_w[i]) >= 0
      collision[i] = 1
      collisions += 1
    i += 1
  final_rank = rank + out_count - 2*collisions ## i64
  if final_rank < 1 || final_rank > st[4]
    # No output has been toggled yet; restoring the selected source is safe.
    i = 0
    while i < k
      rank = ffw_toggle(st,source_u[i],source_v[i],source_w[i],rank)
      i += 1
    st[6] = rank
    return 0 - 1
  i = 0
  while i < out_count
    if collision[i] == 1
      rank = ffw_toggle(st,out_u[i],out_v[i],out_w[i],rank)
    i += 1
  i = 0
  while i < out_count
    if collision[i] == 0
      rank = ffw_toggle(st,out_u[i],out_v[i],out_w[i],rank)
    i += 1
  st[6] = rank
  if rank == final_rank && ffw_verify_current_exact(st, st[2]) == 1
    return rank
  # Exact involutive rollback.
  i = 0
  while i < out_count
    if collision[i] == 0 && ffw_find_term(st,out_u[i],out_v[i],out_w[i]) >= 0
      rank = ffw_toggle(st,out_u[i],out_v[i],out_w[i],rank)
    i += 1
  i = 0
  while i < out_count
    if collision[i] == 1 && ffw_find_term(st,out_u[i],out_v[i],out_w[i]) < 0
      rank = ffw_toggle(st,out_u[i],out_v[i],out_w[i],rank)
    i += 1
  i = 0
  while i < k
    rank = ffw_toggle(st, source_u[i], source_v[i], source_w[i], rank)
    i += 1
  st[6] = rank
  z = ffw_verify_current_exact(st, st[2]) ## i64
  0 - 1
