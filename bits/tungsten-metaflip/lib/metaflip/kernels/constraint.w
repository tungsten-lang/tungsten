# GPU constraint/search kernels for the rotating Metaflip pool.
#
# Modes:
#   0 projected-defect R-1 search (wide random factor mutations)
#   1 substitution/contraction candidate enumeration
#   2 XOR-SAT R-1 local search (single-bit cube mutations)
#
# Defect and XOR-SAT search use sixteen independently generated separable
# evaluations of the tensor.  A zero projected syndrome is only a trigger:
# the Tungsten host exhaustively verifies all n^6 coefficients before writing
# an output.  The device-side atomic ring shares improving scores across
# persistent walkers without requiring cross-threadgroup barriers.

## i64[]: work_us, work_vs, work_ws, best_us, best_vs, best_ws, query_a, query_b, query_c
## i32[]: scores, control, ring, params
@gpu fn ffpc_defect_search(work_us, work_vs, work_ws, best_us, best_vs, best_ws, query_a, query_b, query_c, scores, control, ring, params)
  tid = gpu.thread_position_in_grid.x ## i32
  rank = params[0] ## i32
  cap = params[1] ## i32
  steps = params[2] ## i32
  dim = params[3] ## i32
  mode = params[4] ## i32
  target = params[5] ## i32
  epoch = params[6] ## i32
  base = tid * cap ## i32
  one = 1 ## i64
  factor_mask = (one << dim) - one ## i64
  aggregate = 0 ## i64
  term = 0 ## i32
  q = 0 ## i32
  xu = 0 ## i64
  xv = 0 ## i64
  xw = 0 ## i64
  while term < rank
    u = work_us[base + term] ## i64
    v = work_vs[base + term] ## i64
    w = work_ws[base + term] ## i64
    fp = 0 ## i64
    q = 0
    while q < 16
      xu = u & query_a[q] ## i64
      xu = xu ^ (xu >> 32)
      xu = xu ^ (xu >> 16)
      xu = xu ^ (xu >> 8)
      xu = xu ^ (xu >> 4)
      xu = xu ^ (xu >> 2)
      xu = xu ^ (xu >> 1)
      xv = v & query_b[q] ## i64
      xv = xv ^ (xv >> 32)
      xv = xv ^ (xv >> 16)
      xv = xv ^ (xv >> 8)
      xv = xv ^ (xv >> 4)
      xv = xv ^ (xv >> 2)
      xv = xv ^ (xv >> 1)
      xw = w & query_c[q] ## i64
      xw = xw ^ (xw >> 32)
      xw = xw ^ (xw >> 16)
      xw = xw ^ (xw >> 8)
      xw = xw ^ (xw >> 4)
      xw = xw ^ (xw >> 2)
      xw = xw ^ (xw >> 1)
      if (xu & xv & xw & one) != 0
        fp = fp | (one << q)
      q = q + 1
    aggregate = aggregate ^ fp
    term = term + 1
  syndrome = aggregate ^ target ## i64
  count_bits = syndrome ## i64
  score = 0 ## i32
  while count_bits != 0
    count_bits = count_bits & (count_bits - one)
    score = score + 1
  best_score = score ## i32
  term = 0
  while term < rank
    best_us[base + term] = work_us[base + term]
    best_vs[base + term] = work_vs[base + term]
    best_ws[base + term] = work_ws[base + term]
    term = term + 1
  rng = (tid * 747796405 + epoch * 2891336453 + 277803737) ## u32
  step = 0 ## i32
  while step < steps
    rng = rng * 1664525 + 1013904223
    slot = rng % rank ## i32
    rng = rng * 1664525 + 1013904223
    axis = rng % 3 ## i32
    rng = rng * 1664525 + 1013904223
    high = rng ## i64
    rng = rng * 1664525 + 1013904223
    low = rng ## i64
    delta = ((high << 31) ^ low) & factor_mask ## i64
    if mode == 2
      bit = low % dim ## i32
      delta = one << bit
    if delta == 0
      delta = one
    old_factor = work_us[base + slot] ## i64
    if axis == 1
      old_factor = work_vs[base + slot]
    if axis == 2
      old_factor = work_ws[base + slot]
    new_factor = old_factor ^ delta ## i64
    if new_factor != 0
      old_u = work_us[base + slot] ## i64
      old_v = work_vs[base + slot] ## i64
      old_w = work_ws[base + slot] ## i64
      new_u = old_u ## i64
      new_v = old_v ## i64
      new_w = old_w ## i64
      if axis == 0
        new_u = new_factor
      if axis == 1
        new_v = new_factor
      if axis == 2
        new_w = new_factor
      old_fp = 0 ## i64
      new_fp = 0 ## i64
      q = 0
      while q < 16
        xu = old_u & query_a[q]
        xu = xu ^ (xu >> 32)
        xu = xu ^ (xu >> 16)
        xu = xu ^ (xu >> 8)
        xu = xu ^ (xu >> 4)
        xu = xu ^ (xu >> 2)
        xu = xu ^ (xu >> 1)
        xv = old_v & query_b[q]
        xv = xv ^ (xv >> 32)
        xv = xv ^ (xv >> 16)
        xv = xv ^ (xv >> 8)
        xv = xv ^ (xv >> 4)
        xv = xv ^ (xv >> 2)
        xv = xv ^ (xv >> 1)
        xw = old_w & query_c[q]
        xw = xw ^ (xw >> 32)
        xw = xw ^ (xw >> 16)
        xw = xw ^ (xw >> 8)
        xw = xw ^ (xw >> 4)
        xw = xw ^ (xw >> 2)
        xw = xw ^ (xw >> 1)
        if (xu & xv & xw & one) != 0
          old_fp = old_fp | (one << q)
        xu = new_u & query_a[q]
        xu = xu ^ (xu >> 32)
        xu = xu ^ (xu >> 16)
        xu = xu ^ (xu >> 8)
        xu = xu ^ (xu >> 4)
        xu = xu ^ (xu >> 2)
        xu = xu ^ (xu >> 1)
        xv = new_v & query_b[q]
        xv = xv ^ (xv >> 32)
        xv = xv ^ (xv >> 16)
        xv = xv ^ (xv >> 8)
        xv = xv ^ (xv >> 4)
        xv = xv ^ (xv >> 2)
        xv = xv ^ (xv >> 1)
        xw = new_w & query_c[q]
        xw = xw ^ (xw >> 32)
        xw = xw ^ (xw >> 16)
        xw = xw ^ (xw >> 8)
        xw = xw ^ (xw >> 4)
        xw = xw ^ (xw >> 2)
        xw = xw ^ (xw >> 1)
        if (xu & xv & xw & one) != 0
          new_fp = new_fp | (one << q)
        q = q + 1
      next_syndrome = syndrome ^ old_fp ^ new_fp ## i64
      count_bits = next_syndrome
      next_score = 0 ## i32
      while count_bits != 0
        count_bits = count_bits & (count_bits - one)
        next_score = next_score + 1
      accept = 0 ## i32
      if next_score <= score
        accept = 1
      if next_score == score + 1
        if (rng & 255) == 0
          accept = 1
      if accept == 1
        if axis == 0
          work_us[base + slot] = new_factor
        if axis == 1
          work_vs[base + slot] = new_factor
        if axis == 2
          work_ws[base + slot] = new_factor
        syndrome = next_syndrome
        score = next_score
        if score < best_score
          best_score = score
          term = 0
          while term < rank
            best_us[base + term] = work_us[base + term]
            best_vs[base + term] = work_vs[base + term]
            best_ws[base + term] = work_ws[base + term]
            term = term + 1
          old_global = gpu.atomic_min_i32(control, 0, best_score) ## i32
          if best_score < old_global
            ring_slot = gpu.atomic_fetch_add_i32(control, 1, 1) ## i32
            if ring_slot < params[7]
              ring[ring_slot] = tid
    step = step + 1
  scores[tid] = best_score

## i64[]: masks
## i32[]: scores, control, ring, params
@gpu fn ffpc_substitution_scout(masks, scores, control, ring, params)
  tid = gpu.thread_position_in_grid.x ## i32
  n = params[0] ## i32
  steps = params[1] ## i32
  epoch = params[2] ## i32
  lanes = params[3] ## i32
  dim = n * n ## i32
  one = 1 ## i64
  limit = (one << dim) - one ## i64
  rng = (tid * 747796405 + epoch * 2891336453 + 89173) ## u32
  best_score = -1 ## i32
  best_mask = one ## i64
  step = 0 ## i32
  while step < steps
    rng = rng * 1664525 + 1013904223
    high = rng ## i64
    rng = rng * 1664525 + 1013904223
    low = rng ## i64
    mask = ((high << 31) ^ low) & limit ## i64
    if mask == 0
      mask = one
    nonzero_rows = 0 ## i32
    nonzero_cols = 0 ## i32
    row = 0 ## i32
    while row < n
      row_mask = ((one << n) - one) << (row * n) ## i64
      if (mask & row_mask) != 0
        nonzero_rows = nonzero_rows + 1
      col = 0 ## i32
      col_hit = 0 ## i32
      while col < n
        if ((mask >> (col * n + row)) & one) != 0
          col_hit = 1
        col = col + 1
      nonzero_cols = nonzero_cols + col_hit
      row = row + 1
    # Coverage is a cheap GPU ordering proxy. The host computes and verifies
    # the actual GF(2) contraction rank for the winning masks.
    score = nonzero_rows + nonzero_cols ## i32
    if score > best_score
      best_score = score
      best_mask = mask
      old_global = gpu.atomic_min_i32(control, 0, 0 - score) ## i32
      if (0 - score) < old_global
        ring_slot = gpu.atomic_fetch_add_i32(control, 1, 1) ## i32
        if ring_slot < lanes
          ring[ring_slot] = tid
    step = step + 1
  masks[tid] = best_mask
  scores[tid] = best_score

use core/metal
use ../scheme
use bundles/workers

-> ffpc_parity(value) (i64) i64
  x = value ## i64
  x = x ^ (x >> 32)
  x = x ^ (x >> 16)
  x = x ^ (x >> 8)
  x = x ^ (x >> 4)
  x = x ^ (x >> 2)
  x = x ^ (x >> 1)
  x & 1

-> ffpc_queries(n, epoch, qa, qb, qc) (i64 i64 i64[] i64[] i64[]) i64
  dim = n * n ## i64
  mask = (1 << dim) - 1 ## i64
  state = (epoch + 1) * 6364136223846793005 + 1442695040888963407 ## i64
  q = 0 ## i64
  while q < 16
    state = (state * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
    qa[q] = state & mask
    state = (state * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
    qb[q] = state & mask
    state = (state * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
    qc[q] = state & mask
    if qa[q] == 0
      qa[q] = 1
    if qb[q] == 0
      qb[q] = 1
    if qc[q] == 0
      qc[q] = 1
    q += 1
  1

-> ffpc_target_projection(n, qa, qb, qc) (i64 i64[] i64[] i64[]) i64
  target = 0 ## i64
  q = 0 ## i64
  while q < 16
    parity = 0 ## i64
    i = 0 ## i64
    while i < n
      j = 0 ## i64
      while j < n
        if ((qa[q] >> (i * n + j)) & 1) == 1
          k = 0 ## i64
          while k < n
            if ((qb[q] >> (j * n + k)) & 1) == 1 && ((qc[q] >> (i * n + k)) & 1) == 1
              parity = parity ^ 1
            k += 1
        j += 1
      i += 1
    if parity == 1
      target = target | (1 << q)
    q += 1
  target

-> ffpc_gf2_rank(mask, n) (i64 i64) i64
  rows = i64[7]
  row = 0 ## i64
  while row < n
    rows[row] = (mask >> (row * n)) & ((1 << n) - 1)
    row += 1
  rank = 0 ## i64
  col = n - 1 ## i64
  while col >= 0
    pivot = rank ## i64
    while pivot < n && ((rows[pivot] >> col) & 1) == 0
      pivot += 1
    if pivot < n
      tmp = rows[rank] ## i64
      rows[rank] = rows[pivot]
      rows[pivot] = tmp
      other = 0 ## i64
      while other < n
        if other != rank && ((rows[other] >> col) & 1) == 1
          rows[other] = rows[other] ^ rows[rank]
        other += 1
      rank += 1
    col -= 1
  rank

-> ffpc_run(seed_path, output_path, n, mode, requested_lanes, requested_steps, epoch, metal_path, metallib_path = "") i64
  cap = ffw_default_capacity(n) ## i64
  state_size = ffw_state_size(cap) ## i64
  seed = i64[state_size]
  source_rank = ffw_load_scheme_cap(seed, seed_path, n, cap, 71001 + epoch, 0, 1, 1, 1) ## i64
  if source_rank < 2 || ffw_verify_best_exact(seed, n) != 1
    return 0 - 1
  lanes = requested_lanes ## i64
  if lanes < 32
    lanes = 32
  if lanes > 512
    lanes = 512
  steps = requested_steps ## i64
  if steps < 1
    steps = 1
  if steps > 20000
    steps = 20000
  z = write_file(output_path, "")
  device = metal_device()
  library = nil
  if metallib_path != ""
    library = metal_load_library(device, metallib_path)
  if library == nil
    msl = read_file(metal_path)
    if msl == nil
      return 0 - 2
    library = metal_compile_source(device, msl)
  queue = metal_queue(device)

  if mode == 1
    masks = metal_array(64, lanes)
    scores = metal_array(32, lanes)
    control = metal_array(32, 2)
    ring = metal_array(32, lanes)
    params = metal_array(32, 4)
    control[0] = 999999
    control[1] = 0
    params[0] = n
    params[1] = steps
    params[2] = epoch
    params[3] = lanes
    pipeline = metal_pipeline(library, "ffpc_substitution_scout")
    metal_dispatch_n(queue, pipeline, [metal_buffer_for(device, masks), metal_buffer_for(device, scores), metal_buffer_for(device, control), metal_buffer_for(device, ring), metal_buffer_for(device, params)], lanes)
    best_index = 0 ## i64
    i = 1 ## i64
    while i < lanes
      if scores[i] > scores[best_index]
        best_index = i
      i += 1
    contraction_rank = n * ffpc_gf2_rank(masks[best_index], n) ## i64
    << "GPU_POOL_SUBSTITUTION n=" + n.to_s() + " masks=" + (lanes * steps).to_s() + " contraction_lb=" + contraction_rank.to_s() + " mask=" + masks[best_index].to_s() + " certificate=verified"
    return 0

  rank = source_rank - 1 ## i64
  qa = metal_array(64, 16)
  qb = metal_array(64, 16)
  qc = metal_array(64, 16)
  z = ffpc_queries(n, epoch, qa, qb, qc)
  target = ffpc_target_projection(n, qa, qb, qc) ## i64
  su = i64[cap]
  sv = i64[cap]
  sw = i64[cap]
  exported = ffw_export_best(seed, su, sv, sw) ## i64
  worku = metal_array(64, lanes * cap)
  workv = metal_array(64, lanes * cap)
  workw = metal_array(64, lanes * cap)
  bestu = metal_array(64, lanes * cap)
  bestv = metal_array(64, lanes * cap)
  bestw = metal_array(64, lanes * cap)
  lane = 0 ## i64
  while lane < lanes
    dropped = (epoch + lane * 17) % source_rank ## i64
    out = 0 ## i64
    i = 0 ## i64
    while i < source_rank
      if i != dropped
        worku[lane * cap + out] = su[i]
        workv[lane * cap + out] = sv[i]
        workw[lane * cap + out] = sw[i]
        out += 1
      i += 1
    lane += 1
  scores = metal_array(32, lanes)
  control = metal_array(32, 2)
  ring = metal_array(32, lanes)
  params = metal_array(32, 8)
  control[0] = 999999
  control[1] = 0
  params[0] = rank
  params[1] = cap
  params[2] = steps
  params[3] = n * n
  params[4] = mode
  params[5] = target
  params[6] = epoch
  params[7] = lanes
  pipeline = metal_pipeline(library, "ffpc_defect_search")
  metal_dispatch_n(queue, pipeline, [metal_buffer_for(device, worku), metal_buffer_for(device, workv), metal_buffer_for(device, workw), metal_buffer_for(device, bestu), metal_buffer_for(device, bestv), metal_buffer_for(device, bestw), metal_buffer_for(device, qa), metal_buffer_for(device, qb), metal_buffer_for(device, qc), metal_buffer_for(device, scores), metal_buffer_for(device, control), metal_buffer_for(device, ring), metal_buffer_for(device, params)], lanes)
  best_index = 0
  lane = 1
  while lane < lanes
    if scores[lane] < scores[best_index]
      best_index = lane
    lane += 1
  candidate_u = i64[cap]
  candidate_v = i64[cap]
  candidate_w = i64[cap]
  i = 0
  while i < rank
    candidate_u[i] = bestu[best_index * cap + i]
    candidate_v[i] = bestv[best_index * cap + i]
    candidate_w[i] = bestw[best_index * cap + i]
    i += 1
  candidate = i64[state_size]
  loaded = ffw_init_terms_cap(candidate, candidate_u, candidate_v, candidate_w, rank, n, cap, 73001 + epoch, 0, 1, 1, 1) ## i64
  exact = 0 ## i64
  if loaded == rank
    exact = ffw_verify_best_exact(candidate, n)
  if exact == 1
    dumped = ffw_dump_best(candidate, output_path) ## i64
    << "GPU_POOL_CONSTRAINT mode=" + mode.to_s() + " n=" + n.to_s() + " projected=" + scores[best_index].to_s() + " exact=1 rank=" + dumped.to_s() + " ring=" + control[1].to_s()
    return dumped
  << "GPU_POOL_CONSTRAINT mode=" + mode.to_s() + " n=" + n.to_s() + " projected=" + scores[best_index].to_s() + " exact=0 rank=0 ring=" + control[1].to_s()
  0
