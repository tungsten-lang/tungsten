# Exhaustive correlated three-term repair over archived <2,2,5> unit-floor
# states.  This is an offline exact experiment; it does not alter FlipFleet's
# production pools or TUI.

use flipfleet_rect_three_term_repair
use flipfleet_block_composer

-> ffr3trb_fail(message)
  << "THREE_TERM_REPAIR_FAIL " + message
  exit(1)
  0

-> ffr3trb_header_value(field, name) (String String)
  parts = field.split("=")
  if parts.size() != 2 || parts[0] != name
    return ""
  parts[1]

# Load one selector dump and independently reconstruct its unit residual.
# meta: residual cell, drop, state, door number.
-> ffr3trb_load_state(path, target, us, vs, ws, meta) (String i64[] i64[] i64[] i64[] i64[]) i64
  content = read_file(path)
  if content == nil
    return 0
  lines = content.split("\n")
  if lines.size() < 18
    return 0
  header = lines[0].split(" ")
  if header.size() != 6 || header[0] != "FLOOR225" || header[1] != "v1"
    return 0
  door_text = ffr3trb_header_value(header[2], "door")
  drop_text = ffr3trb_header_value(header[3], "drop")
  state_text = ffr3trb_header_value(header[4], "state")
  cell_text = ffr3trb_header_value(header[5], "residual_cell")
  if door_text == "" || drop_text == "" || state_text == "" || cell_text == ""
    return 0
  door = 0 ## i64
  if door_text == "d84"
    door = 84
  if door_text == "d88"
    door = 88
  if door == 0
    return 0
  term = 0 ## i64
  while term < 17
    fields = lines[term + 1].split(" ")
    if fields.size() != 3
      return 0
    us[term] = fields[0].to_i()
    vs[term] = fields[1].to_i()
    ws[term] = fields[2].to_i()
    if us[term] < 1 || us[term] >= 16 || vs[term] < 1 || vs[term] >= 1024 || ws[term] < 1 || ws[term] >= 1024
      return 0
    term += 1
  residual = i64[target.size()]
  if ffrrw_build_residual(us, vs, ws, 17, 2, 2, 5, target, residual) != 1
    return 0
  actual_cell = 0 - 1 ## i64
  cell = 0 ## i64
  while cell < 400
    if ffrrw_bit(residual, cell) != 0
      actual_cell = cell
    cell += 1
  meta[0] = cell_text.to_i()
  meta[1] = drop_text.to_i()
  meta[2] = state_text.to_i()
  meta[3] = door
  if actual_cell != meta[0]
    return 0
  17

-> ffr3trb_same_term(us, vs, ws, left, right) (i64[] i64[] i64[] i64 i64) i64
  if us[left] == us[right] && vs[left] == vs[right] && ws[left] == ws[right]
    return 1
  0

# Hashes are only a prefilter.  Equal hashes are followed by all 51 factor
# comparisons before a serialized entry is treated as a duplicate.
-> ffr3trb_seen_state(hash, us, vs, ws, seen_hashes, seen_u, seen_v, seen_w, seen_count) (i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  state = 0 ## i64
  while state < seen_count
    if seen_hashes[state] == hash
      same = 1 ## i64
      term = 0 ## i64
      base = state * 17 ## i64
      while term < 17 && same == 1
        if seen_u[base + term] != us[term] || seen_v[base + term] != vs[term] || seen_w[base + term] != ws[term]
          same = 0
        term += 1
      if same == 1
        return 1
    state += 1
  seen_hashes[seen_count] = hash
  base = seen_count * 17
  term = 0
  while term < 17
    seen_u[base + term] = us[term]
    seen_v[base + term] = vs[term]
    seen_w[base + term] = ws[term]
    term += 1
  0

# Retain fourteen live terms, append the recognized carrier decomposition,
# parity-compact exact duplicate triples, and independently FFBC-gate it.
# meta: nominal rank, compact rank, duplicate cancellations, FFBC exact.
-> ffr3trb_materialize(us, vs, ws, i0, i1, i2, du, dv, dw, repair_rank, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64 i64[])
  raw_u = i64[17]
  raw_v = i64[17]
  raw_w = i64[17]
  raw_count = 0 ## i64
  term = 0 ## i64
  while term < 17
    if term != i0 && term != i1 && term != i2
      raw_u[raw_count] = us[term]
      raw_v[raw_count] = vs[term]
      raw_w[raw_count] = ws[term]
      raw_count += 1
    term += 1
  term = 0
  while term < repair_rank
    raw_u[raw_count] = du[term]
    raw_v[raw_count] = dv[term]
    raw_w[raw_count] = dw[term]
    raw_count += 1
    term += 1
  meta[0] = raw_count

  used = i64[17]
  compact_u = i64[17]
  compact_v = i64[17]
  compact_w = i64[17]
  compact_count = 0 ## i64
  term = 0
  while term < raw_count
    if used[term] == 0
      parity = 1 ## i64
      other = term + 1 ## i64
      while other < raw_count
        if used[other] == 0 && ffr3trb_same_term(raw_u, raw_v, raw_w, term, other) == 1
          used[other] = 1
          parity = parity ^ 1
        other += 1
      if parity != 0
        compact_u[compact_count] = raw_u[term]
        compact_v[compact_count] = raw_v[term]
        compact_w[compact_count] = raw_w[term]
        compact_count += 1
    term += 1
  meta[1] = compact_count
  meta[2] = raw_count - compact_count
  if compact_count < 1 || compact_count > 17
    return nil
  child = FFBCScheme.new(2, 2, 5, compact_count)
  term = 0
  while term < compact_count
    child.us()[term] = compact_u[term]
    child.vs()[term] = compact_v[term]
    child.ws()[term] = compact_w[term]
    term += 1
  child.set_rank(compact_count)
  meta[3] = ffbc_verify_exact(child)
  if meta[3] != 1
    return nil
  child

-> ffr3trb_save_checked(path, child) (String FFBCScheme) i64
  if child == nil || child.rank() > 17 || ffbc_verify_exact(child) != 1
    return 0
  if ffbc_write(path, child) != child.rank()
    return 0
  replay = ffbc_load_exact(path, 2, 2, 5, 32)
  if replay == nil || replay.rank() != child.rank() || ffbc_verify_exact(replay) != 1
    return 0
  replay.rank()

# stats: states, triples, d0/d1/d2/d3/d4+, recognized, repair r0/r1/r2/r3,
# d1/weight2/weight3/d3 cases, rebuilds, materialized, exact, failures,
# basis choices, Z candidates, duplicate cancellations; serialized duplicate
# entries, raw entries, d2 basis choices, d3 GL(3,2) basis choices.
-> ffr3trb_scan_state(us, vs, ws, target, state_meta, output_prefix, stats) (i64[] i64[] i64[] i64[] i64[] String i64[]) i64
  residual = i64[target.size()]
  if ffrrw_build_residual(us, vs, ws, 17, 2, 2, 5, target, residual) != 1
    return 0 - 1
  stats[0] += 1
  i0 = 0 ## i64
  while i0 < 15
    i1 = i0 + 1 ## i64
    while i1 < 16
      i2 = i1 + 1 ## i64
      while i2 < 17
        stats[1] += 1
        carrier = i64[target.size()]
        z = ffrrw_copy(residual, carrier, residual.size()) ## i64
        weight = 1 ## i64
        weight = ffrrw_xor_outer_weight(carrier, us[i0], vs[i0], ws[i0], 4, 10, 10, weight)
        weight = ffrrw_xor_outer_weight(carrier, us[i1], vs[i1], ws[i1], 4, 10, 10, weight)
        weight = ffrrw_xor_outer_weight(carrier, us[i2], vs[i2], ws[i2], 4, 10, 10, weight)
        du = i64[3]
        dv = i64[3]
        dw = i64[3]
        meta = i64[6]
        repair_rank = ffr3tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta) ## i64
        dimension = meta[0] ## i64
        if dimension >= 0 && dimension <= 3
          stats[2 + dimension] += 1
        else
          stats[6] += 1
        stats[20] += meta[3]
        stats[21] += meta[4]
        if dimension == 2
          stats[25] += meta[3]
        if dimension == 3
          stats[26] += meta[3]
        if repair_rank >= 0
          stats[7] += 1
          stats[8 + repair_rank] += 1
          if meta[1] == 10
            stats[12] += 1
          if meta[1] >= 20 && meta[1] <= 22
            stats[13] += 1
          if meta[1] == 29
            stats[14] += 1
          if meta[1] == 30
            stats[15] += 1
          if ffr3tr_rebuild(du, dv, dw, repair_rank, 2, 2, 5, carrier) != 1
            stats[19] += 1
            return 0 - 2
          stats[16] += 1
          child_meta = i64[4]
          child = ffr3trb_materialize(us, vs, ws, i0, i1, i2, du, dv, dw, repair_rank, child_meta)
          stats[17] += 1
          stats[22] += child_meta[2]
          if child == nil || child_meta[3] != 1
            stats[19] += 1
            return 0 - 3
          stats[18] += 1
          output = output_prefix + "_r" + child.rank().to_s() + "_d" + state_meta[3].to_s() + "_drop" + state_meta[1].to_s() + "_state" + state_meta[2].to_s() + "_t" + i0.to_s() + "-" + i1.to_s() + "-" + i2.to_s() + ".txt"
          if ffr3trb_save_checked(output, child) != child.rank()
            stats[19] += 1
            return 0 - 4
          << "THREE_TERM_REPAIR_HIT rank=" + child.rank().to_s() + " door=d" + state_meta[3].to_s() + " drop=" + state_meta[1].to_s() + " state=" + state_meta[2].to_s() + " triple=" + i0.to_s() + "/" + i1.to_s() + "/" + i2.to_s() + " carrier_weight=" + weight.to_s() + " dimension=" + dimension.to_s() + " case=" + meta[1].to_s() + " output=" + output
          return child.rank()
        i2 += 1
      i1 += 1
    i0 += 1
  0

av = argv()
manifest_path = "/tmp/flipfleet_225_floor_manifest.tsv"
max_states = 0 ## i64
if av.size() > 2
  << "usage: three-term-repair-bench [manifest.tsv] [max-states]"
  exit(2)
if av.size() >= 1
  manifest_path = av[0]
if av.size() == 2
  max_states = av[1].to_i()
if max_states < 0
  << "max-states must be nonnegative"
  exit(2)

manifest = read_file(manifest_path)
if manifest == nil
  ffr3trb_fail("missing manifest " + manifest_path)
lines = manifest.split("\n")
target = i64[ffrrw_tensor_words(2, 2, 5)]
if ffrrw_build_mmt_target(target, 2, 2, 5) != target.size()
  ffr3trb_fail("target")
stats = i64[27]
seen_hashes = i64[lines.size()]
seen_u = i64[lines.size() * 17]
seen_v = i64[lines.size() * 17]
seen_w = i64[lines.size() * 17]
seen_count = 0 ## i64
output_prefix = "/tmp/flipfleet_2x2x5_three_term_repair"
started = ccall("__w_clock_ms") ## i64
hit_rank = 0 ## i64
line = 1 ## i64
while line < lines.size() && hit_rank == 0
  if lines[line].size() > 0
    stats[24] += 1
    fields = lines[line].split("\t")
    if fields.size() < 6
      ffr3trb_fail("malformed manifest row " + line.to_s())
    us = i64[17]
    vs = i64[17]
    ws = i64[17]
    state_meta = i64[4]
    if ffr3trb_load_state(fields[0], target, us, vs, ws, state_meta) != 17
      ffr3trb_fail("state load " + fields[0])
    if state_meta[0] != fields[4].to_i()
      ffr3trb_fail("manifest residual mismatch " + fields[0])
    hash = fields[5].to_i() ## i64
    if hash != ffrrw_terms_hash(us, vs, ws, 17)
      ffr3trb_fail("manifest hash mismatch " + fields[0])
    if ffr3trb_seen_state(hash, us, vs, ws, seen_hashes, seen_u, seen_v, seen_w, seen_count) == 1
      stats[23] += 1
    else
      seen_count += 1
      hit_rank = ffr3trb_scan_state(us, vs, ws, target, state_meta, output_prefix, stats)
      if hit_rank < 0
        ffr3trb_fail("scan state " + fields[0] + " code=" + hit_rank.to_s())
    if stats[24] % 50 == 0
      elapsed = ccall("__w_clock_ms") - started ## i64
      << "THREE_TERM_REPAIR_PROGRESS raw_entries=" + stats[24].to_s() + " unique_states=" + stats[0].to_s() + " duplicates=" + stats[23].to_s() + " triples=" + stats[1].to_s() + " recognized=" + stats[7].to_s() + " elapsed_ms=" + elapsed.to_s()
    if max_states > 0 && stats[0] >= max_states
      line = lines.size()
  line += 1
elapsed = ccall("__w_clock_ms") - started ## i64
<< "THREE_TERM_REPAIR_SUMMARY manifest=" + manifest_path + " raw_entries=" + stats[24].to_s() + " duplicate_entries=" + stats[23].to_s() + " unique_states=" + stats[0].to_s() + " triples=" + stats[1].to_s() + " d0=" + stats[2].to_s() + " d1=" + stats[3].to_s() + " d2=" + stats[4].to_s() + " d3=" + stats[5].to_s() + " d4plus=" + stats[6].to_s() + " recognized=" + stats[7].to_s() + " repair_r0=" + stats[8].to_s() + " repair_r1=" + stats[9].to_s() + " repair_r2=" + stats[10].to_s() + " repair_r3=" + stats[11].to_s() + " case_d1=" + stats[12].to_s() + " case_weight2=" + stats[13].to_s() + " case_weight3=" + stats[14].to_s() + " case_d3=" + stats[15].to_s() + " rebuilds=" + stats[16].to_s() + " materialized=" + stats[17].to_s() + " exact=" + stats[18].to_s() + " failures=" + stats[19].to_s() + " basis_choices=" + stats[20].to_s() + " d2_basis_choices=" + stats[25].to_s() + " gl3_basis_choices=" + stats[26].to_s() + " z_candidates=" + stats[21].to_s() + " duplicate_cancellations=" + stats[22].to_s() + " hit_rank=" + hit_rank.to_s() + " elapsed_ms=" + elapsed.to_s()
