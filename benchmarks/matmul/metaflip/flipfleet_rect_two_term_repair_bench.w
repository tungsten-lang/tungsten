# Exhaustive correlated two-term repair over archived unit-floor worm states.
# This is an offline admission experiment; it does not alter production pools.

use flipfleet_rect_two_term_repair
use flipfleet_block_composer

-> ffr2trb_fail(message)
  << "TWO_TERM_REPAIR_FAIL " + message
  exit(1)
  0

-> ffr2trb_load_source(path, us, vs, ws) (String i64[] i64[] i64[]) i64
  source = ffbc_load_exact(path, 2, 2, 5, 32)
  if source == nil || source.rank() != 18 || source.uw() != 1 || source.vw() != 1 || source.ww() != 1
    return 0
  term = 0 ## i64
  while term < 18
    us[term] = source.us()[term]
    vs[term] = source.vs()[term]
    ws[term] = source.ws()[term]
    term += 1
  18

-> ffr2trb_child(us, vs, ws, left, right, du, dv, dw, repair_rank) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64)
  child_rank = 15 + repair_rank ## i64
  child = FFBCScheme.new(2, 2, 5, child_rank)
  at = 0 ## i64
  term = 0 ## i64
  while term < 17
    if term != left && term != right
      child.us()[at] = us[term]
      child.vs()[at] = vs[term]
      child.ws()[at] = ws[term]
      at += 1
    term += 1
  term = 0
  while term < repair_rank
    child.us()[at] = du[term]
    child.vs()[at] = dv[term]
    child.ws()[at] = dw[term]
    at += 1
    term += 1
  child.set_rank(child_rank)
  if at != child_rank || ffbc_verify_exact(child) != 1
    return nil
  child

-> ffr2trb_terms_scheme(us, vs, ws, rank) (i64[] i64[] i64[] i64)
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

# Publish only after write, fresh parse, and a second full FFBC reconstruction.
-> ffr2trb_save_checked(output, scheme) (String FFBCScheme) i64
  if scheme == nil || scheme.rank() > 17 || ffbc_verify_exact(scheme) != 1
    return 0
  if ffbc_write(output, scheme) != scheme.rank()
    return 0
  replay = ffbc_load_exact(output, 2, 2, 5, 32)
  if replay == nil || replay.rank() != scheme.rank() || ffbc_verify_exact(replay) != 1
    return 0
  replay.rank()

-> ffr2trb_copy_archived(archive_u, archive_v, archive_w, state, us, vs, ws) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  base = state * 17 ## i64
  term = 0 ## i64
  while term < 17
    us[term] = archive_u[base + term]
    vs[term] = archive_v[base + term]
    ws[term] = archive_w[base + term]
    term += 1
  17

-> ffr2trb_residual_cell(us, vs, ws, target) (i64[] i64[] i64[] i64[]) i64
  residual = i64[target.size()]
  if ffrrw_build_residual(us, vs, ws, 17, 2, 2, 5, target, residual) != 1
    return 0 - 1
  cell = 0 ## i64
  while cell < 400
    if ffrrw_bit(residual, cell) != 0
      return cell
    cell += 1
  0 - 1

-> ffr2trb_dump_state(us, vs, ws, target, label, drop, state, manifest) (i64[] i64[] i64[] i64[] String i64 i64 Array) i64
  cell = ffr2trb_residual_cell(us, vs, ws, target) ## i64
  if cell < 0
    return 0
  path = "/tmp/flipfleet_225_floor_" + label + "_drop" + drop.to_s() + "_state" + state.to_s() + ".txt"
  body = "FLOOR225 v1 door=" + label + " drop=" + drop.to_s() + " state=" + state.to_s() + " residual_cell=" + cell.to_s() + "\n"
  term = 0 ## i64
  while term < 17
    body = body + us[term].to_s() + " " + vs[term].to_s() + " " + ws[term].to_s() + "\n"
    term += 1
  if write_file(path, body) == nil
    return 0
  manifest.push(path + "\t" + label + "\t" + drop.to_s() + "\t" + state.to_s() + "\t" + cell.to_s() + "\t" + ffrrw_terms_hash(us, vs, ws, 17).to_s())
  1

# stats: states, pairs, U-flat rank1/rank2, decomposable, exact admissions,
# repair rank1/rank2, decomposition rebuilds, independent admission rejects.
-> ffr2trb_sweep_state(us, vs, ws, target, output, stats) (i64[] i64[] i64[] i64[] String i64[]) i64
  residual = i64[target.size()]
  residual_weight = ffrrw_build_residual(us, vs, ws, 17, 2, 2, 5, target, residual) ## i64
  if residual_weight != 1
    return 0 - 1
  stats[0] += 1
  left = 0 ## i64
  while left < 17
    right = left + 1 ## i64
    while right < 17
      stats[1] += 1
      carrier = i64[residual.size()]
      z = ffrrw_copy(residual, carrier, residual.size()) ## i64
      weight = 1 ## i64
      weight = ffrrw_xor_outer_weight(carrier, us[left], vs[left], ws[left], 4, 10, 10, weight)
      weight = ffrrw_xor_outer_weight(carrier, us[right], vs[right], ws[right], 4, 10, 10, weight)
      du = i64[2]
      dv = i64[2]
      dw = i64[2]
      meta = i64[3]
      repair_rank = ffr2tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta) ## i64
      if meta[0] == 1
        stats[2] += 1
      if meta[0] == 2
        stats[3] += 1
      if repair_rank > 0
        stats[4] += 1
        if repair_rank == 1
          stats[6] += 1
        if repair_rank == 2
          stats[7] += 1
        if ffr2tr_rebuild(du, dv, dw, repair_rank, 2, 2, 5, carrier) != 1
          return 0 - 2
        stats[8] += 1
        child = ffr2trb_child(us, vs, ws, left, right, du, dv, dw, repair_rank)
        if child != nil
          stats[5] += 1
          if ffr2trb_save_checked(output, child) != child.rank()
            return 0 - 3
          return child.rank()
        stats[9] += 1
      right += 1
    left += 1
  0

-> ffr2trb_run(path, attempts, seed, label, archive_capacity, manifest) (String i64 i64 String i64 Array) i64
  source_u = i64[18]
  source_v = i64[18]
  source_w = i64[18]
  if ffr2trb_load_source(path, source_u, source_v, source_w) != 18
    ffr2trb_fail("source load " + label)
  target = i64[ffrrw_tensor_words(2, 2, 5)]
  if ffrrw_build_mmt_target(target, 2, 2, 5) != target.size()
    ffr2trb_fail("target " + label)
  output = "/tmp/flipfleet_2x2x5_rank17_two_term_repair_" + label + ".txt"
  per = attempts / 18 ## i64
  remainder = attempts % 18 ## i64
  stats = i64[10]
  worm_ms = 0 ## i64
  repair_ms = 0 ## i64
  floor_moves = 0 ## i64
  floor_deletions = 0 ## i64
  saturated_deletions = 0 ## i64
  min_states = 65 ## i64
  max_states = 0 ## i64
  global_floor = i64[target.size()]
  hit_rank = 0 ## i64
  drop = 0 ## i64
  while drop < 18 && hit_rank == 0
    start_u = i64[17]
    start_v = i64[17]
    start_w = i64[17]
    at = 0 ## i64
    term = 0 ## i64
    while term < 18
      if term != drop
        start_u[at] = source_u[term]
        start_v[at] = source_v[term]
        start_w[at] = source_w[term]
        at += 1
      term += 1
    budget = per ## i64
    if drop < remainder
      budget += 1
    out_u = i64[17]
    out_v = i64[17]
    out_w = i64[17]
    floor_cells = i64[target.size()]
    archive_u = i64[archive_capacity * 17]
    archive_v = i64[archive_capacity * 17]
    archive_w = i64[archive_capacity * 17]
    archive_count = i64[1]
    local = i64[21]
    t0 = ccall("__w_clock_ms") ## i64
    best_weight = ffrrw_walk_target_floor_states(start_u, start_v, start_w, 17, 2, 2, 5, target, budget, seed + drop * 104729, out_u, out_v, out_w, floor_cells, archive_u, archive_v, archive_w, archive_capacity, archive_count, local) ## i64
    worm_ms += ccall("__w_clock_ms") - t0
    if best_weight < 0
      ffr2trb_fail("worm " + label + " drop=" + drop.to_s() + " code=" + best_weight.to_s())
    word = 0 ## i64
    while word < global_floor.size()
      global_floor[word] = global_floor[word] | floor_cells[word]
      word += 1
    floor_moves += local[6]
    if archive_count[0] > 0
      floor_deletions += 1
    if archive_count[0] == archive_capacity
      saturated_deletions += 1
    if archive_count[0] < min_states
      min_states = archive_count[0]
    if archive_count[0] > max_states
      max_states = archive_count[0]
    << "TWO_TERM_REPAIR_DROP door=" + label + " drop=" + drop.to_s() + " attempts=" + budget.to_s() + " initial_weight=" + local[1].to_s() + " best_weight=" + best_weight.to_s() + " floor_moves=" + local[6].to_s() + " floor_states=" + archive_count[0].to_s() + " floor_hashes=" + local[20].to_s()

    if best_weight == 0
      direct = ffr2trb_terms_scheme(out_u, out_v, out_w, 17)
      hit_rank = ffr2trb_save_checked(output, direct)
      if hit_rank != 17
        ffr2trb_fail("direct exact admission " + label)
    state = 0 ## i64
    t0 = ccall("__w_clock_ms")
    while state < archive_count[0] && hit_rank == 0
      us = i64[17]
      vs = i64[17]
      ws = i64[17]
      z = ffr2trb_copy_archived(archive_u, archive_v, archive_w, state, us, vs, ws) ## i64
      if ffr2trb_dump_state(us, vs, ws, target, label, drop, state, manifest) != 1
        ffr2trb_fail("state dump " + label + " drop=" + drop.to_s() + " state=" + state.to_s())
      hit_rank = ffr2trb_sweep_state(us, vs, ws, target, output, stats)
      if hit_rank < 0
        ffr2trb_fail("state sweep " + label + " drop=" + drop.to_s() + " state=" + state.to_s() + " code=" + hit_rank.to_s())
      state += 1
    repair_ms += ccall("__w_clock_ms") - t0
    drop += 1
  if min_states == 65
    min_states = 0
  floor_cells_count = ffrrw_weight(global_floor, global_floor.size()) ## i64
  << "TWO_TERM_REPAIR_RESULT door=" + label + " attempts=" + attempts.to_s() + " deletions=" + drop.to_s() + " archive_capacity=" + archive_capacity.to_s() + " floor_deletions=" + floor_deletions.to_s() + " floor_states=" + stats[0].to_s() + " states_per_deletion=" + min_states.to_s() + ".." + max_states.to_s() + " saturated_deletions=" + saturated_deletions.to_s() + " floor_moves=" + floor_moves.to_s() + " distinct_floor_cells=" + floor_cells_count.to_s() + " pairs=" + stats[1].to_s() + " uflat1=" + stats[2].to_s() + " uflat2=" + stats[3].to_s() + " decomposable=" + stats[4].to_s() + " repair_rank1=" + stats[6].to_s() + " repair_rank2=" + stats[7].to_s() + " rebuilds=" + stats[8].to_s() + " admission_rejects=" + stats[9].to_s() + " exact=" + stats[5].to_s() + " hit_rank=" + hit_rank.to_s() + " worm_ms=" + worm_ms.to_s() + " repair_ms=" + repair_ms.to_s() + " output=" + output
  hit_rank

av = argv()
attempts = 180000 ## i64
archive_capacity = 64 ## i64
if av.size() > 2
  << "usage: two-term-repair-bench [attempts-per-door] [archive-capacity]"
  exit(2)
if av.size() >= 1
  attempts = av[0].to_i()
if av.size() == 2
  archive_capacity = av[1].to_i()
if attempts < 18 || archive_capacity < 1 || archive_capacity > 64
  << "attempts must be at least 18 and archive capacity must be 1..64"
  exit(2)

root = "benchmarks/matmul/metaflip/"
manifest = []
hit84 = ffr2trb_run(root + "matmul_2x2x5_rank18_d84_gf2.txt", attempts, 2258401, "d84", archive_capacity, manifest) ## i64
hit88 = ffr2trb_run(root + "matmul_2x2x5_rank18_d88_gf2.txt", attempts, 2258801, "d88", archive_capacity, manifest) ## i64
manifest_path = "/tmp/flipfleet_225_floor_manifest.tsv"
manifest_body = "path\tdoor\tdrop\tstate\tresidual_cell\tterm_hash\n" + manifest.join("\n") + "\n"
if write_file(manifest_path, manifest_body) == nil
  ffr2trb_fail("manifest write")
exact_hits = 0 ## i64
if hit84 > 0
  exact_hits += 1
if hit88 > 0
  exact_hits += 1
<< "TWO_TERM_REPAIR_SUMMARY attempts_per_door=" + attempts.to_s() + " archive_capacity=" + archive_capacity.to_s() + " hit84=" + hit84.to_s() + " hit88=" + hit88.to_s() + " exact_hits=" + exact_hits.to_s() + " dumped_states=" + manifest.size().to_s() + " manifest=" + manifest_path
