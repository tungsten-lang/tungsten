# Exact GPU enumeration for rank-neutral q=2 low-rank shear absorption.
#
# One GPU thread owns a regular tuple
#
#   (rotated source pair, ordered logical-axis pair, rotated first carrier).
#
# The complementary two-factor matrix has rank at most two.  The thread
# derives its exact rank-1/rank-2 factorization and, for rank two, scans for a
# second compatible carrier.  A shared match array preserves every structural
# hit; the host scans it in deterministic tuple order, rejects ordinary
# one-flip endpoints, materializes the shear, and admits it only after local
# and full n^6 verification.  Atomic-min records the deterministic first
# structural winner for diagnostics but is not trusted as the admission gate.

## i64[]: us, vs, ws
## i32[]: pair_first, pair_second, matches, control, params
@gpu fn fflrsp_probe(us, vs, ws, pair_first, pair_second, matches, control, params)
  tid = gpu.thread_position_in_grid.x ## i32
  scheme_rank = params[0] ## i32
  pair_count = params[1] ## i32
  nonce = params[2] ## i32
  work = pair_count * 6 * scheme_rank ## i32
  if tid < work
    carrier_step = tid % scheme_rank ## i32
    axis_code = (tid / scheme_rank) % 6 ## i32
    pair_slot = tid / (scheme_rank * 6) ## i32
    first = pair_first[pair_slot] ## i32
    second = pair_second[pair_slot] ## i32
    carrier0 = (carrier_step + nonce) % scheme_rank ## i32

    shift_axis = 0 ## i32
    factor_axis = 1 ## i32
    right_axis = 2 ## i32
    if axis_code == 1
      shift_axis = 0
      factor_axis = 2
      right_axis = 1
    if axis_code == 2
      shift_axis = 1
      factor_axis = 0
      right_axis = 2
    if axis_code == 3
      shift_axis = 1
      factor_axis = 2
      right_axis = 0
    if axis_code == 4
      shift_axis = 2
      factor_axis = 0
      right_axis = 1
    if axis_code == 5
      shift_axis = 2
      factor_axis = 1
      right_axis = 0

    first_left = us[first] ## i64
    first_right = us[first] ## i64
    second_left = us[second] ## i64
    second_right = us[second] ## i64
    carrier_shift = us[carrier0] ## i64
    carrier_left = us[carrier0] ## i64
    carrier_right = us[carrier0] ## i64
    if factor_axis == 1
      first_left = vs[first]
      second_left = vs[second]
      carrier_left = vs[carrier0]
    if factor_axis == 2
      first_left = ws[first]
      second_left = ws[second]
      carrier_left = ws[carrier0]
    if right_axis == 1
      first_right = vs[first]
      second_right = vs[second]
      carrier_right = vs[carrier0]
    if right_axis == 2
      first_right = ws[first]
      second_right = ws[second]
      carrier_right = ws[carrier0]
    if shift_axis == 1
      carrier_shift = vs[carrier0]
    if shift_axis == 2
      carrier_shift = ws[carrier0]

    correction_rank = 2 ## i32
    correction_left0 = first_left ## i64
    correction_right0 = first_right ## i64
    correction_left1 = second_left ## i64
    correction_right1 = second_right ## i64
    if first_left == second_left
      correction_rank = 1
      correction_right0 = first_right ^ second_right
    else
      if first_right == second_right
        correction_rank = 1
        correction_left0 = first_left ^ second_left

    valid = 1 ## i32
    if first == second
      valid = 0
    if carrier0 == first
      valid = 0
    if carrier0 == second
      valid = 0
    if correction_left0 == 0
      valid = 0
    if correction_right0 == 0
      valid = 0
    if carrier_shift == 0
      valid = 0
    if carrier_left != correction_left0
      valid = 0
    if (carrier_right ^ correction_right0) == 0
      valid = 0

    carrier1 = 0 - 1 ## i32
    if valid != 0
      if correction_rank == 2
        scan = 0 ## i32
        while scan < scheme_rank
          candidate = (scan + nonce) % scheme_rank ## i32
          candidate_shift = us[candidate] ## i64
          candidate_left = us[candidate] ## i64
          candidate_right = us[candidate] ## i64
          if shift_axis == 1
            candidate_shift = vs[candidate]
          if shift_axis == 2
            candidate_shift = ws[candidate]
          if factor_axis == 1
            candidate_left = vs[candidate]
          if factor_axis == 2
            candidate_left = ws[candidate]
          if right_axis == 1
            candidate_right = vs[candidate]
          if right_axis == 2
            candidate_right = ws[candidate]
          if carrier1 < 0
            distinct = 1 ## i32
            if candidate == first
              distinct = 0
            if candidate == second
              distinct = 0
            if candidate == carrier0
              distinct = 0
            if distinct != 0
              if candidate_shift == carrier_shift
                if candidate_left == correction_left1
                  if (candidate_right ^ correction_right1) != 0
                    carrier1 = candidate
          scan = scan + 1
        if carrier1 < 0
          valid = 0

    if valid != 0
      code = 1 ## i32
      if correction_rank == 2
        code = carrier1 + 2
      matches[tid] = code
      old = gpu.atomic_min_i32(control, 0, tid) ## i32

use core/metal
use flipfleet_low_rank_shear_search

-> fflrsp_pair_at(index, scheme_rank, out_pair) (i64 i64 i64[]) i64
  if index < 0 || scheme_rank < 2
    return 0
  cursor = 0 ## i64
  first = 0 ## i64
  while first < scheme_rank - 1
    count = scheme_rank - first - 1 ## i64
    if index < cursor + count
      out_pair[0] = first
      out_pair[1] = first + 1 + (index - cursor)
      return 1
    cursor += count
    first += 1
  0

-> fflrsp_build_pairs(scheme_rank, nonce, pair_limit, pair_first, pair_second) (i64 i64 i64 i32[] i32[]) i64
  total = (scheme_rank * (scheme_rank - 1)) / 2 ## i64
  count = pair_limit ## i64
  if count > total
    count = total
  if count > pair_first.size()
    count = pair_first.size()
  if count > pair_second.size()
    count = pair_second.size()
  slot = 0 ## i64
  while slot < count
    pair = i64[2]
    wanted = (slot + nonce) % total ## i64
    if fflrsp_pair_at(wanted, scheme_rank, pair) == 0
      return 0
    pair_first[slot] = pair[0]
    pair_second[slot] = pair[1]
    slot += 1
  count

-> fflrsp_has_global_collision(us, vs, ws, scheme_rank, selected, selected_count, out_u, out_v, out_w, out_count) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64) i64
  collisions = 0 ## i64
  out_index = 0 ## i64
  while out_index < out_count
    scan = 0 ## i64
    while scan < scheme_rank
      if ffsr_contains(selected, selected_count, scan) == 0
        if ffsm_same_term(us[scan], vs[scan], ws[scan], out_u[out_index], out_v[out_index], out_w[out_index]) == 1
          collisions += 1
      scan += 1
    out_index += 1
  collisions

-> fflrsp_materialize_hit(us, vs, ws, scheme_rank, pair_first, pair_second, tid, nonce, code, selected, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i32[] i32[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if scheme_rank < 3 || tid < 0 || code < 1
    return 0
  carrier_step = tid % scheme_rank ## i64
  axis_code = (tid / scheme_rank) % 6 ## i64
  pair_slot = tid / (scheme_rank * 6) ## i64
  if pair_slot < 0 || pair_slot >= pair_first.size() || pair_slot >= pair_second.size()
    return 0
  first = pair_first[pair_slot] ## i64
  second = pair_second[pair_slot] ## i64
  carrier0 = (carrier_step + nonce) % scheme_rank ## i64
  axes = i64[3]
  if ffsm_axis_code(axis_code, axes) == 0
    return 0
  shift_axis = axes[0] ## i64
  factor_axis = axes[1] ## i64
  correction_rank = 1 ## i64
  carrier1 = 0 - 1 ## i64
  if code >= 2
    correction_rank = 2
    carrier1 = code - 2
  if fflrs_distinct4(first, second, carrier0, carrier1, scheme_rank) == 0
    return 0

  source_u = i64[2]
  source_v = i64[2]
  source_w = i64[2]
  source_u[0] = us[first]
  source_v[0] = vs[first]
  source_w[0] = ws[first]
  source_u[1] = us[second]
  source_v[1] = vs[second]
  source_w[1] = ws[second]
  correction_left = i64[2]
  correction_right = i64[2]
  derived_rank = fflrs_factor_pair(source_u, source_v, source_w, shift_axis, factor_axis, correction_left, correction_right) ## i64
  if derived_rank != correction_rank
    return 0
  total = 2 + correction_rank ## i64
  local_u = i64[4]
  local_v = i64[4]
  local_w = i64[4]
  local_u[0] = us[first]
  local_v[0] = vs[first]
  local_w[0] = ws[first]
  local_u[1] = us[second]
  local_v[1] = vs[second]
  local_w[1] = ws[second]
  local_u[2] = us[carrier0]
  local_v[2] = vs[carrier0]
  local_w[2] = ws[carrier0]
  if correction_rank == 2
    local_u[3] = us[carrier1]
    local_v[3] = vs[carrier1]
    local_w[3] = ws[carrier1]
  shift = ffsm_axis_get(us, vs, ws, carrier0, shift_axis) ## i64
  made = ffsm_low_rank_shear_absorb(local_u, local_v, local_w, 2, correction_rank, shift_axis, factor_axis, shift, correction_left, correction_right, out_u, out_v, out_w) ## i64
  if made != total
    return 0
  if fftc_local_exact(local_u, local_v, local_w, total, out_u, out_v, out_w, total) == 0
    return 0
  if fflrs_is_one_flip(local_u, local_v, local_w, total, out_u, out_v, out_w) != 0
    meta[5] = meta[5] + 1
    return 0
  selected[0] = first
  selected[1] = second
  selected[2] = carrier0
  if correction_rank == 2
    selected[3] = carrier1
  # Untouched global matches are valuable, not invalid: each one parity-
  # cancels and lowers the actual scheme rank by two beyond the nominal
  # rank-neutral absorbed shear.
  meta[6] = fflrsp_has_global_collision(us,vs,ws,scheme_rank,selected,total,out_u,out_v,out_w,total)
  meta[0] = correction_rank
  meta[1] = shift_axis
  meta[2] = factor_axis
  meta[3] = pair_slot + 1
  meta[4] = carrier_step + 1
  total

# stats: pair count, tuple work, structural hits, first structural winner,
# host candidates checked, admitted local size, one-flip skips.
-> fflrsp_find_gpu(device, library, queue, us, vs, ws, scheme_rank, nonce, pair_limit, selected, out_u, out_v, out_w, meta, stats) i64
  if scheme_rank < 3 || pair_limit < 1
    return 0
  pair_total = (scheme_rank * (scheme_rank - 1)) / 2 ## i64
  pair_count = pair_limit ## i64
  if pair_count > pair_total
    pair_count = pair_total
  pair_first = metal_array(32, pair_count) ## i32[]
  pair_second = metal_array(32, pair_count) ## i32[]
  built = fflrsp_build_pairs(scheme_rank, nonce, pair_count, pair_first, pair_second) ## i64
  if built != pair_count
    return 0
  work = pair_count * 6 * scheme_rank ## i64
  gpu_us = metal_array(64, scheme_rank)
  gpu_vs = metal_array(64, scheme_rank)
  gpu_ws = metal_array(64, scheme_rank)
  i = 0 ## i64
  while i < scheme_rank
    gpu_us[i] = us[i]
    gpu_vs[i] = vs[i]
    gpu_ws[i] = ws[i]
    i += 1
  matches = metal_array(32, work)
  control = metal_array(32, 1)
  control[0] = work
  params = metal_array(32, 3)
  params[0] = scheme_rank
  params[1] = pair_count
  params[2] = nonce % scheme_rank
  pipeline = metal_pipeline(library, "fflrsp_probe")
  metal_dispatch_n(queue, pipeline, [metal_buffer_for(device, gpu_us), metal_buffer_for(device, gpu_vs), metal_buffer_for(device, gpu_ws), metal_buffer_for(device, pair_first), metal_buffer_for(device, pair_second), metal_buffer_for(device, matches), metal_buffer_for(device, control), metal_buffer_for(device, params)], work)
  structural = 0 ## i64
  result = 0 ## i64
  tid = 0 ## i64
  while tid < work && result == 0
    code = matches[tid] ## i64
    if code != 0
      structural += 1
      stats[4] = stats[4] + 1
      result = fflrsp_materialize_hit(us, vs, ws, scheme_rank, pair_first, pair_second, tid, nonce % scheme_rank, code, selected, out_u, out_v, out_w, meta)
    tid += 1
  # Finish counting only when diagnostics request a complete hit count.  This
  # is host shared memory already produced by the single GPU dispatch.
  while tid < work
    if matches[tid] != 0
      structural += 1
    tid += 1
  stats[0] = pair_count
  stats[1] = work
  stats[2] = structural
  stats[3] = control[0]
  stats[5] = result
  stats[6] = meta[5]
  result

-> fflrsp_search(seed_path, output_path, n, pair_limit, nonce, metal_path, metallib_path = "") i64
  if n < 5 || n > 7 || pair_limit < 1 || pair_limit > 2048 || nonce < 0
    return 0 - 1
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  scheme_rank = ffw_load_scheme_cap(state, seed_path, n, capacity, 93199 + nonce, 0, 1, 1, 1) ## i64
  if scheme_rank < 3 || ffw_verify_current_exact(state, n) == 0
    return 0 - 2
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  exported = ffw_export_current(state, us, vs, ws) ## i64
  device = metal_device()
  library = nil
  if metallib_path != ""
    library = metal_load_library(device, metallib_path)
  if library == nil
    msl = read_file(metal_path)
    if msl == nil
      return 0 - 3
    library = metal_compile_source(device, msl)
  queue = metal_queue(device)
  cleared = write_file(output_path, "")
  if cleared == false
    return 0 - 4
  selected = i64[4]
  out_u = i64[4]
  out_v = i64[4]
  out_w = i64[4]
  meta = i64[8]
  stats = i64[8]
  made = fflrsp_find_gpu(device, library, queue, us, vs, ws, exported, nonce, pair_limit, selected, out_u, out_v, out_w, meta, stats) ## i64
  if made > 0
    admitted = ffsr_apply_current_compact(state, selected, made, out_u, out_v, out_w, made) ## i64
    if admitted > 0 && admitted <= scheme_rank && ffw_verify_current_exact(state, n) == 1
      written = ffw_dump_current(state, output_path) ## i64
      if written == admitted
        << "GPU_POOL_LOW_RANK_SHEAR n=" + n.to_s() + " pairs=" + stats[0].to_s() + " work=" + stats[1].to_s() + " structural=" + stats[2].to_s() + " checked=" + stats[4].to_s() + " correction=" + meta[0].to_s() + " collisions=" + meta[6].to_s() + " oneflip=" + meta[5].to_s() + " hit=1 rank=" + admitted.to_s()
        return admitted
  << "GPU_POOL_LOW_RANK_SHEAR n=" + n.to_s() + " pairs=" + stats[0].to_s() + " work=" + stats[1].to_s() + " structural=" + stats[2].to_s() + " checked=" + stats[4].to_s() + " oneflip=" + meta[5].to_s() + " hit=0"
  0
