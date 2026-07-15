# Exhaustive correlated two-term unit-to-unit hops for <2,2,5> residual floors.
# Offline only: retained children are full-residual gated and never enter the
# production fleet automatically.

use flipfleet_rect_two_term_repair
use flipfleet_block_composer

-> ffr2th_fail(message)
  << "TWO_TERM_HOP_FAIL " + message
  exit(1)
  0

-> ffr2th_bit_get(bits, value) (i64[] i64) i64
  (bits[value / 64] >> (value % 64)) & 1

-> ffr2th_bit_set(bits, value) (i64[] i64) i64
  bits[value / 64] = bits[value / 64] | (1 << (value % 64))
  1

-> ffr2th_find(parent, value) (i64[] i64) i64
  root = value ## i64
  while parent[root] != root
    root = parent[root]
  while parent[value] != value
    next_value = parent[value] ## i64
    parent[value] = root
    value = next_value
  root

-> ffr2th_union(parent, left, right) (i64[] i64 i64) i64
  lroot = ffr2th_find(parent, left) ## i64
  rroot = ffr2th_find(parent, right) ## i64
  if lroot != rroot
    if lroot < rroot
      parent[rroot] = lroot
    else
      parent[lroot] = rroot
    return 1
  0

-> ffr2th_load(path, us, vs, ws) (String i64[] i64[] i64[]) i64
  body = read_file(path)
  if body == nil
    return 0
  lines = body.split("\n")
  if lines.size() < 18
    return 0
  term = 0 ## i64
  while term < 17
    fields = lines[term + 1].split(" ")
    if fields.size() != 3
      return 0
    us[term] = fields[0].to_i()
    vs[term] = fields[1].to_i()
    ws[term] = fields[2].to_i()
    if us[term] < 1 || us[term] > 15 || vs[term] < 1 || vs[term] > 1023 || ws[term] < 1 || ws[term] > 1023
      return 0
    term += 1
  17

# GF(2) multiset compaction: a repeated rank-one term cancels in pairs.
-> ffr2th_compact(us, vs, ws, rank, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  term = 0 ## i64
  while term < rank
    found = 0 - 1 ## i64
    at = 0 ## i64
    while at < count && found < 0
      if out_u[at] == us[term] && out_v[at] == vs[term] && out_w[at] == ws[term]
        found = at
      at += 1
    if found >= 0
      count -= 1
      if found < count
        out_u[found] = out_u[count]
        out_v[found] = out_v[count]
        out_w[found] = out_w[count]
    else
      out_u[count] = us[term]
      out_v[count] = vs[term]
      out_w[count] = ws[term]
      count += 1
    term += 1
  count

-> ffr2th_replace(us, vs, ws, left, right, du, dv, dw, repair_rank, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  at = 0 ## i64
  term = 0 ## i64
  while term < 17
    if term != left && term != right
      out_u[at] = us[term]
      out_v[at] = vs[term]
      out_w[at] = ws[term]
      at += 1
    term += 1
  term = 0
  while term < repair_rank
    out_u[at] = du[term]
    out_v[at] = dv[term]
    out_w[at] = dw[term]
    at += 1
    term += 1
  at

-> ffr2th_residual_cell(us, vs, ws, rank, target) (i64[] i64[] i64[] i64 i64[]) i64
  residual = i64[target.size()]
  if ffrrw_build_residual(us, vs, ws, rank, 2, 2, 5, target, residual) != 1
    return 0 - 1
  cell = 0 ## i64
  while cell < 400
    if ffrrw_bit(residual, cell) != 0
      return cell
    cell += 1
  0 - 1

-> ffr2th_scheme(us, vs, ws, rank) (i64[] i64[] i64[] i64)
  scheme = FFBCScheme.new(2, 2, 5, rank)
  term = 0 ## i64
  while term < rank
    scheme.us()[term] = us[term]
    scheme.vs()[term] = vs[term]
    scheme.ws()[term] = ws[term]
    term += 1
  scheme.set_rank(rank)
  if ffbc_verify_exact(scheme) != 1
    return nil
  scheme

-> ffr2th_save_exact(path, scheme) (String FFBCScheme) i64
  if scheme == nil || scheme.rank() > 17 || ffbc_write(path, scheme) != scheme.rank()
    return 0
  replay = ffbc_load_exact(path, 2, 2, 5, 32)
  if replay == nil || replay.rank() != scheme.rank() || ffbc_verify_exact(replay) != 1
    return 0
  replay.rank()

-> ffr2th_save_hop(us, vs, ws, label, source_cell, target_cell, source_index, left, right, manifest) (i64[] i64[] i64[] String i64 i64 i64 i64 i64 Array) i64
  path = "/tmp/flipfleet_225_hop_cell" + target_cell.to_s() + ".txt"
  body = "HOP225 v1 door=" + label + " source_cell=" + source_cell.to_s() + " target_cell=" + target_cell.to_s() + " source_state=" + source_index.to_s() + " pair=" + left.to_s() + "," + right.to_s() + "\n"
  term = 0 ## i64
  while term < 17
    body = body + us[term].to_s() + " " + vs[term].to_s() + " " + ws[term].to_s() + "\n"
    term += 1
  if write_file(path, body) == nil
    return 0
  manifest.push(path + "\t" + label + "\t" + source_cell.to_s() + "\t" + target_cell.to_s() + "\t" + source_index.to_s() + "\t" + left.to_s() + "\t" + right.to_s() + "\t" + ffrrw_terms_hash(us, vs, ws, 17).to_s())
  1

av = argv()
input_manifest = "/tmp/flipfleet_225_floor_manifest.tsv"
limit = 0 ## i64
if av.size() > 2
  << "usage: two-term-hop-bench [FLOOR_MANIFEST] [MAX_STATES]"
  exit(2)
if av.size() >= 1
  input_manifest = av[0]
if av.size() == 2
  limit = av[1].to_i()
if limit < 0
  << "MAX_STATES must be nonnegative"
  exit(2)

manifest_body = read_file(input_manifest)
if manifest_body == nil
  ffr2th_fail("manifest read")
lines = manifest_body.split("\n")
if lines.size() < 2
  ffr2th_fail("manifest empty")
manifest_state_count = lines.size() - 2 ## i64
state_count = manifest_state_count ## i64
if limit > 0 && limit < state_count
  state_count = limit

target = i64[ffrrw_tensor_words(2, 2, 5)]
if ffrrw_build_mmt_target(target, 2, 2, 5) != target.size()
  ffr2th_fail("target")
original_all = i64[7]
original_84 = i64[7]
original_88 = i64[7]
active_cells = i64[7]
state = 0 ## i64
while state < manifest_state_count
  fields = lines[state + 1].split("\t")
  if fields.size() < 6
    ffr2th_fail("manifest row " + state.to_s())
  cell = fields[4].to_i() ## i64
  if cell < 0 || cell >= 400
    ffr2th_fail("manifest cell")
  z = ffr2th_bit_set(original_all, cell) ## i64
  z = ffr2th_bit_set(active_cells, cell)
  if fields[1] == "d84"
    z = ffr2th_bit_set(original_84, cell)
  elsif fields[1] == "d88"
    z = ffr2th_bit_set(original_88, cell)
  else
    ffr2th_fail("manifest door")
  state += 1

parent = i64[400]
cell = 0 ## i64
while cell < 400
  parent[cell] = cell
  cell += 1
edge_bits = i64[2500]
saved_cells = i64[7]
expanded_cells = i64[7]
hop_manifest = []
candidates = 0 ## i64
uflat1 = 0 ## i64
uflat2 = 0 ## i64
decomposable = 0 ## i64
rank1_repairs = 0 ## i64
rank2_repairs = 0 ## i64
gated_hops = 0 ## i64
unique_edges = 0 ## i64
new_global_cells = 0 ## i64
expanded_door_cells = 0 ## i64
exact_rank = 0 ## i64
exact_path = "/tmp/flipfleet_2x2x5_rank17_two_term_hop_exact.txt"
start_ms = ccall("__w_clock_ms") ## i64
state = 0
while state < state_count && exact_rank == 0
  fields = lines[state + 1].split("\t")
  path = fields[0]
  label = fields[1]
  current_cell = fields[4].to_i() ## i64
  us = i64[17]
  vs = i64[17]
  ws = i64[17]
  if ffr2th_load(path, us, vs, ws) != 17 || ffr2th_residual_cell(us, vs, ws, 17, target) != current_cell
    ffr2th_fail("state replay " + state.to_s())
  residual = i64[target.size()]
  z = ffrrw_build_residual(us, vs, ws, 17, 2, 2, 5, target, residual) ## i64
  left = 0 ## i64
  while left < 17 && exact_rank == 0
    right = left + 1 ## i64
    while right < 17 && exact_rank == 0
      carrier = i64[residual.size()]
      z = ffrrw_copy(residual, carrier, residual.size())
      weight = 1 ## i64
      weight = ffrrw_xor_outer_weight(carrier, us[left], vs[left], ws[left], 4, 10, 10, weight)
      weight = ffrrw_xor_outer_weight(carrier, us[right], vs[right], ws[right], 4, 10, 10, weight)
      target_cell = 0 ## i64
      while target_cell < 400 && exact_rank == 0
        if target_cell != current_cell
          candidates += 1
          carrier[target_cell / 64] = carrier[target_cell / 64] ^ (1 << (target_cell % 64))
          du = i64[2]
          dv = i64[2]
          dw = i64[2]
          meta = i64[3]
          repair_rank = ffr2tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta) ## i64
          if meta[0] == 1
            uflat1 += 1
          if meta[0] == 2
            uflat2 += 1
          if repair_rank > 0
            decomposable += 1
            if repair_rank == 1
              rank1_repairs += 1
            if repair_rank == 2
              rank2_repairs += 1
            if ffr2tr_rebuild(du, dv, dw, repair_rank, 2, 2, 5, carrier) != 1
              ffr2th_fail("decomposition rebuild")
            raw_u = i64[17]
            raw_v = i64[17]
            raw_w = i64[17]
            raw_rank = ffr2th_replace(us, vs, ws, left, right, du, dv, dw, repair_rank, raw_u, raw_v, raw_w) ## i64
            compact_u = i64[18]
            compact_v = i64[18]
            compact_w = i64[18]
            compact_rank = ffr2th_compact(raw_u, raw_v, raw_w, raw_rank, compact_u, compact_v, compact_w) ## i64
            if ffr2th_residual_cell(compact_u, compact_v, compact_w, compact_rank, target) != target_cell
              ffr2th_fail("full hop residual gate")
            gated_hops += 1
            if compact_rank <= 16
              exact_in_u = i64[18]
              exact_in_v = i64[18]
              exact_in_w = i64[18]
              term = 0 ## i64
              while term < compact_rank
                exact_in_u[term] = compact_u[term]
                exact_in_v[term] = compact_v[term]
                exact_in_w[term] = compact_w[term]
                term += 1
              a = target_cell / 100 ## i64
              b = (target_cell / 10) % 10 ## i64
              c = target_cell % 10 ## i64
              exact_in_u[compact_rank] = 1 << a
              exact_in_v[compact_rank] = 1 << b
              exact_in_w[compact_rank] = 1 << c
              exact_u = i64[18]
              exact_v = i64[18]
              exact_w = i64[18]
              candidate_rank = ffr2th_compact(exact_in_u, exact_in_v, exact_in_w, compact_rank + 1, exact_u, exact_v, exact_w) ## i64
              exact_scheme = ffr2th_scheme(exact_u, exact_v, exact_w, candidate_rank)
              exact_rank = ffr2th_save_exact(exact_path, exact_scheme)
              if exact_rank < 1 || exact_rank > 17
                ffr2th_fail("exact completion")
            elsif compact_rank == 17
              edge = current_cell * 400 + target_cell ## i64
              if ffr2th_bit_get(edge_bits, edge) == 0
                z = ffr2th_bit_set(edge_bits, edge)
                unique_edges += 1
              z = ffr2th_union(parent, current_cell, target_cell)
              if ffr2th_bit_get(active_cells, target_cell) == 0
                z = ffr2th_bit_set(active_cells, target_cell)
                new_global_cells += 1
              door_original = original_84
              if label == "d88"
                door_original = original_88
              if ffr2th_bit_get(door_original, target_cell) == 0 && ffr2th_bit_get(expanded_cells, target_cell) == 0
                z = ffr2th_bit_set(expanded_cells, target_cell)
                expanded_door_cells += 1
              if ffr2th_bit_get(door_original, target_cell) == 0 && ffr2th_bit_get(saved_cells, target_cell) == 0
                if ffr2th_save_hop(compact_u, compact_v, compact_w, label, current_cell, target_cell, state, left, right, hop_manifest) != 1
                  ffr2th_fail("hop write")
                z = ffr2th_bit_set(saved_cells, target_cell)
          carrier[target_cell / 64] = carrier[target_cell / 64] ^ (1 << (target_cell % 64))
        target_cell += 1
      right += 1
    left += 1
  if state % 25 == 24 || state + 1 == state_count
    elapsed = ccall("__w_clock_ms") - start_ms ## i64
    << "TWO_TERM_HOP_PROGRESS states=" + (state + 1).to_s() + "/" + state_count.to_s() + " candidates=" + candidates.to_s() + " decomposable=" + decomposable.to_s() + " gated=" + gated_hops.to_s() + " new_cells=" + new_global_cells.to_s() + " saved=" + hop_manifest.size().to_s() + " elapsed_ms=" + elapsed.to_s()
  state += 1

components = 0 ## i64
cell = 0
while cell < 400
  if ffr2th_bit_get(active_cells, cell) != 0 && ffr2th_find(parent, cell) == cell
    components += 1
  cell += 1
output_manifest = "/tmp/flipfleet_225_hop_manifest.tsv"
output_body = "path\tdoor\tsource_cell\ttarget_cell\tsource_state\tleft\tright\tterm_hash\n" + hop_manifest.join("\n") + "\n"
if write_file(output_manifest, output_body) == nil
  ffr2th_fail("output manifest")
elapsed_ms = ccall("__w_clock_ms") - start_ms ## i64
<< "TWO_TERM_HOP_RESULT states=" + state_count.to_s() + " candidates=" + candidates.to_s() + " expected_candidates=" + (state_count * 136 * 399).to_s() + " uflat1=" + uflat1.to_s() + " uflat2=" + uflat2.to_s() + " decomposable=" + decomposable.to_s() + " rank1=" + rank1_repairs.to_s() + " rank2=" + rank2_repairs.to_s() + " gated_hops=" + gated_hops.to_s() + " unique_edges=" + unique_edges.to_s() + " new_global_cells=" + new_global_cells.to_s() + " expanded_door_cells=" + expanded_door_cells.to_s() + " active_components=" + components.to_s() + " saved_seeds=" + hop_manifest.size().to_s() + " exact_rank=" + exact_rank.to_s() + " elapsed_ms=" + elapsed_ms.to_s() + " manifest=" + output_manifest + " exact_path=" + exact_path
