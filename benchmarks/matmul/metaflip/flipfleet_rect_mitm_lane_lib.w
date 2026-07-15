# Pure-Tungsten/Metal exact 5 -> 4 surgery for rectangular FlipFleet profiles.
#
# The square lane owns the GPU pair-enumeration and fingerprint-probe kernels.
# This module reuses those kernels and the bounded candidate construction while
# supplying unequal U/V/W widths and the rectangular worker's independent full
# tensor gate. A candidate is published only after both its five-term local
# identity and the complete n*m*p multiplication tensor reconstruct exactly.

use flipfleet_mitm_lane_lib
use metaflip_rect_worker

-> ffrm_plan_valid(n, m, p, subsets, pool, nearby, offset) (i64 i64 i64 i64 i64 i64 i64) i64
  ok = ffr_supported(n, m, p) ## i64
  if n * m > 63 || m * p > 63 || n * p > 63
    ok = 0
  if subsets < 1 || subsets > 16
    ok = 0
  if pool < 4 || pool > 700
    ok = 0
  if nearby < 0 || nearby > 8
    ok = 0
  if offset < 0
    ok = 0
  ok

-> ffrm_accept_and_dump(us, vs, ws, rank, selected, cu, cv, cw, indices, n, m, p, output_path) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64 i64 i64 String) i64
  cap = ffr_default_capacity(n, m, p) ## i64
  outu = i64[cap]
  outv = i64[cap]
  outw = i64[cap]
  out_rank = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffm_selected_index(selected, 5, i) == 0
      outu[out_rank] = us[i]
      outv[out_rank] = vs[i]
      outw[out_rank] = ws[i]
      out_rank += 1
    i += 1
  i = 0
  while i < 4 && out_rank >= 0
    source = indices[i] ## i64
    out_rank = ffm_toggle_plain(outu, outv, outw, out_rank, cap, cu[source], cv[source], cw[source])
    i += 1
  if out_rank < 1 || out_rank >= rank
    return 0
  candidate = i64[ffr_state_size(cap)]
  loaded = ffr_init_terms_cap(candidate, outu, outv, outw, out_rank, n, m, p, cap, 8777, 0, 1, 1, 1) ## i64
  if loaded != out_rank
    return 0
  # ffr_init_terms_cap and ffr_dump_best independently reconstruct all tensor
  # coefficients. This intentionally remains stronger than the fingerprint.
  dumped = ffr_dump_best(candidate, output_path) ## i64
  if dumped != out_rank
    return 0
  out_rank

# One rectangular subset dispatch. metrics layout matches ffm_gpu_subset:
# [candidates,pairs,table,enum_ms,table_ms,probe_ms,fingerprint_hits,exact_checks]
-> ffrm_gpu_subset(device, enum_pipeline, probe_pipeline, queue, us, vs, ws, rank, selected, cu, cv, cw, count, n, m, p, output_path, metrics)
  square = count * count ## i64
  udim = n * m ## i64
  vdim = m * p ## i64
  wdim = n * p ## i64
  host_fps0 = metal_array(32, count)
  host_fps1 = metal_array(32, count)
  host_fps2 = metal_array(32, count)
  host_fps3 = metal_array(32, count)
  words = i64[4]
  i = 0 ## i64
  while i < count
    z = ffm_fingerprint_shape(cu[i], cv[i], cw[i], udim, vdim, wdim, words) ## i64
    host_fps0[i] = words[0]
    host_fps1[i] = words[1]
    host_fps2[i] = words[2]
    host_fps3[i] = words[3]
    i += 1
  target_words = i64[4]
  z = ffm_target_fingerprint_shape(us, vs, ws, selected, udim, vdim, wdim, target_words) ## i64

  host_pair0 = metal_array(32, square)
  host_pair1 = metal_array(32, square)
  host_pair2 = metal_array(32, square)
  host_pair3 = metal_array(32, square)
  host_enum_params = metal_array(32, 1)
  host_enum_params[0] = count
  fps0_buf = metal_buffer_for(device, host_fps0)
  fps1_buf = metal_buffer_for(device, host_fps1)
  fps2_buf = metal_buffer_for(device, host_fps2)
  fps3_buf = metal_buffer_for(device, host_fps3)
  pair0_buf = metal_buffer_for(device, host_pair0)
  pair1_buf = metal_buffer_for(device, host_pair1)
  pair2_buf = metal_buffer_for(device, host_pair2)
  pair3_buf = metal_buffer_for(device, host_pair3)
  enum_params_buf = metal_buffer_for(device, host_enum_params)
  t0 = ccall("__w_clock_ms") ## i64
  metal_dispatch_n(queue, enum_pipeline, [fps0_buf, fps1_buf, fps2_buf, fps3_buf, pair0_buf, pair1_buf, pair2_buf, pair3_buf, enum_params_buf], square)
  t1 = ccall("__w_clock_ms") ## i64

  pairs = count * (count - 1) / 2 ## i64
  active_cap = 1 ## i64
  while active_cap < pairs * 2
    active_cap *= 2
  host_used = metal_array(32, active_cap)
  host_table0 = metal_array(32, active_cap)
  host_table1 = metal_array(32, active_cap)
  host_table2 = metal_array(32, active_cap)
  host_table3 = metal_array(32, active_cap)
  host_table_pair = metal_array(32, active_cap)
  z = ffm_build_table(host_pair0, host_pair1, host_pair2, host_pair3, host_used, host_table0, host_table1, host_table2, host_table3, host_table_pair, count, active_cap) ## i64
  t2 = ccall("__w_clock_ms") ## i64

  host_target = metal_array(32, 4)
  i = 0
  while i < 4
    host_target[i] = target_words[i]
    i += 1
  host_matches = metal_array(32, square * 16)
  host_probe_params = metal_array(32, 3)
  host_probe_params[0] = count
  host_probe_params[1] = active_cap - 1
  host_probe_params[2] = active_cap
  table0_buf = metal_buffer_for(device, host_table0)
  table1_buf = metal_buffer_for(device, host_table1)
  table2_buf = metal_buffer_for(device, host_table2)
  table3_buf = metal_buffer_for(device, host_table3)
  table_used_buf = metal_buffer_for(device, host_used)
  table_pair_buf = metal_buffer_for(device, host_table_pair)
  target_buf = metal_buffer_for(device, host_target)
  matches_buf = metal_buffer_for(device, host_matches)
  probe_params_buf = metal_buffer_for(device, host_probe_params)
  metal_dispatch_n(queue, probe_pipeline, [fps0_buf, fps1_buf, fps2_buf, fps3_buf, table0_buf, table1_buf, table2_buf, table3_buf, table_used_buf, table_pair_buf, target_buf, matches_buf, probe_params_buf], square)
  t3 = ccall("__w_clock_ms") ## i64

  hit_rank = 0 ## i64
  fingerprint_hits = 0 ## i64
  exact_checks = 0 ## i64
  indices = i64[4]
  left = 0 ## i64
  while left < count && hit_rank == 0
    right = left + 1 ## i64
    while right < count && hit_rank == 0
      query_index = left * count + right ## i64
      h = 0 ## i64
      while h < 16 && hit_rank == 0
        packed = host_matches[query_index * 16 + h] ## i64
        if packed > 0
          fingerprint_hits += 1
          other_left = packed / count ## i64
          other_right = packed - other_left * count ## i64
          indices[0] = left
          indices[1] = right
          indices[2] = other_left
          indices[3] = other_right
          exact_checks += 1
          if ffm_local_exact_shape(us, vs, ws, selected, cu, cv, cw, indices, udim, vdim, wdim) == 1
            hit_rank = ffrm_accept_and_dump(us, vs, ws, rank, selected, cu, cv, cw, indices, n, m, p, output_path)
        h += 1
      right += 1
    left += 1
  metrics[0] = count
  metrics[1] = pairs
  metrics[2] = active_cap
  metrics[3] = t1 - t0
  metrics[4] = t2 - t1
  metrics[5] = t3 - t2
  metrics[6] = fingerprint_hits
  metrics[7] = exact_checks
  hit_rank

-> ffrm_load_exact(seed_path, n, m, p)
  cap = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(cap)]
  rank = ffr_load_scheme_cap(state, seed_path, n, m, p, cap, 9292, 0, 1, 1, 1) ## i64
  if rank < 5
    return nil
  if ffr_verify_best_exact(state, n, m, p) != 1
    return nil
  state

-> ffrm_search_loaded(state, output_path, n, m, p, subsets, pool, nearby, offset, explicit_subset, metal_path, metallib_path = "")
  rank = ffr_best_rank(state) ## i64
  cap = ffr_default_capacity(n, m, p) ## i64
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  exported = ffw_export_best(state, us, vs, ws) ## i64
  if exported != rank
    return 0 - 10
  device = metal_device()
  library = nil
  if metallib_path != ""
    library = metal_load_library(device, metallib_path)
  if library == nil
    msl = read_file(metal_path)
    if msl == nil || msl.size() == 0
      return 0 - 11
    library = metal_compile_source(device, msl)
  enum_pipeline = metal_pipeline(library, "ffm_enumerate_pairs")
  probe_pipeline = metal_pipeline(library, "ffm_probe_pairs")
  queue = metal_queue(device)

  tested = 0 ## i64
  hit_rank = 0 ## i64
  total_candidates = 0 ## i64
  total_pairs = 0 ## i64
  total_fp_hits = 0 ## i64
  total_exact_checks = 0 ## i64
  total_enum_ms = 0 ## i64
  total_table_ms = 0 ## i64
  total_probe_ms = 0 ## i64
  processed = i64[subsets * 5]

  if explicit_subset != nil
    selected = explicit_subset
    valid = 1 ## i64
    i = 0 ## i64
    while i < 5
      if selected[i] < 0 || selected[i] >= rank
        valid = 0
      j = 0 ## i64
      while j < i
        if selected[j] == selected[i]
          valid = 0
        j += 1
      i += 1
    if valid == 0
      return 0 - 12
    z = ffm_sort_five(selected) ## i64
    cu = i64[pool]
    cv = i64[pool]
    cw = i64[pool]
    count = ffm_candidates(us, vs, ws, rank, selected, pool, nearby, cu, cv, cw) ## i64
    metrics = i64[8]
    hit_rank = ffrm_gpu_subset(device, enum_pipeline, probe_pipeline, queue, us, vs, ws, rank, selected, cu, cv, cw, count, n, m, p, output_path, metrics) ## i64
    tested = 1
    total_candidates = metrics[0]
    total_pairs = metrics[1]
    total_enum_ms = metrics[3]
    total_table_ms = metrics[4]
    total_probe_ms = metrics[5]
    total_fp_hits = metrics[6]
    total_exact_checks = metrics[7]
    << "GPU_RECT_MITM_SUBSET ordinal=1 indices=" + selected[0].to_s() + "," + selected[1].to_s() + "," + selected[2].to_s() + "," + selected[3].to_s() + "," + selected[4].to_s() + " candidates=" + count.to_s() + " fingerprint_hits=" + metrics[6].to_s() + " exact_checks=" + metrics[7].to_s() + " hit_rank=" + hit_rank.to_s()
  else
    pair_count = rank * (rank - 1) / 2 ## i64
    window = pair_count ## i64
    if window > 256
      window = 256
    effective_offset = offset % window ## i64
    want = effective_offset + subsets * 8 ## i64
    if want > pair_count
      want = pair_count
    scores = i64[want]
    lefts = i64[want]
    rights = i64[want]
    beam_count = ffm_pair_beam(us, vs, ws, rank, want, scores, lefts, rights) ## i64
    cursor = effective_offset ## i64
    while cursor < beam_count && tested < subsets && hit_rank == 0
      selected = i64[5]
      made = ffm_make_subset(us, vs, ws, rank, lefts[cursor], rights[cursor], selected) ## i64
      if made == 1
        if ffm_same_subset(processed, tested, selected) == 0
          j = 0 ## i64
          while j < 5
            processed[tested * 5 + j] = selected[j]
            j += 1
          cu = i64[pool]
          cv = i64[pool]
          cw = i64[pool]
          count = ffm_candidates(us, vs, ws, rank, selected, pool, nearby, cu, cv, cw) ## i64
          metrics = i64[8]
          hit_rank = ffrm_gpu_subset(device, enum_pipeline, probe_pipeline, queue, us, vs, ws, rank, selected, cu, cv, cw, count, n, m, p, output_path, metrics) ## i64
          tested += 1
          total_candidates += metrics[0]
          total_pairs += metrics[1]
          total_enum_ms += metrics[3]
          total_table_ms += metrics[4]
          total_probe_ms += metrics[5]
          total_fp_hits += metrics[6]
          total_exact_checks += metrics[7]
          << "GPU_RECT_MITM_SUBSET ordinal=" + tested.to_s() + " indices=" + selected[0].to_s() + "," + selected[1].to_s() + "," + selected[2].to_s() + "," + selected[3].to_s() + "," + selected[4].to_s() + " candidates=" + count.to_s() + " fingerprint_hits=" + metrics[6].to_s() + " exact_checks=" + metrics[7].to_s() + " hit_rank=" + hit_rank.to_s()
      cursor += 1
  hit = 0 ## i64
  if hit_rank > 0
    hit = 1
  << "GPU_RECT_MITM_RESULT tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + rank.to_s() + " tested=" + tested.to_s() + " candidates=" + total_candidates.to_s() + " pairs=" + total_pairs.to_s() + " enum_ms=" + total_enum_ms.to_s() + " table_ms=" + total_table_ms.to_s() + " probe_ms=" + total_probe_ms.to_s() + " fingerprint_hits=" + total_fp_hits.to_s() + " exact_checks=" + total_exact_checks.to_s() + " hit=" + hit.to_s() + " output_rank=" + hit_rank.to_s()
  hit

-> ffrm_search(seed_path, output_path, n, m, p, subsets, pool, nearby, offset, metal_path, metallib_path = "")
  if ffrm_plan_valid(n, m, p, subsets, pool, nearby, offset) == 0
    return 0 - 1
  if seed_path == output_path
    return 0 - 3
  z = write_file(output_path, "")
  state = ffrm_load_exact(seed_path, n, m, p)
  if state == nil
    return 0 - 2
  << "GPU_RECT_MITM_START tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + ffr_best_rank(state).to_s() + " subsets=" + subsets.to_s() + " pool=" + pool.to_s() + " nearby=" + nearby.to_s() + " offset=" + offset.to_s()
  ffrm_search_loaded(state, output_path, n, m, p, subsets, pool, nearby, offset, nil, metal_path, metallib_path)

-> ffrm_search_exact_subset(seed_path, output_path, n, m, p, pool, nearby, selected, metal_path, metallib_path = "")
  if ffrm_plan_valid(n, m, p, 1, pool, nearby, 0) == 0
    return 0 - 1
  if seed_path == output_path
    return 0 - 3
  z = write_file(output_path, "")
  state = ffrm_load_exact(seed_path, n, m, p)
  if state == nil
    return 0 - 2
  << "GPU_RECT_MITM_START tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + ffr_best_rank(state).to_s() + " subsets=1 pool=" + pool.to_s() + " nearby=" + nearby.to_s() + " offset=explicit"
  ffrm_search_loaded(state, output_path, n, m, p, 1, pool, nearby, 0, selected, metal_path, metallib_path)
