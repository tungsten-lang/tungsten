# GPU-suitable exact affine-code decoder for the <2,2,5> fixed dictionary.
#
# Every candidate is the known rank-18 anchor XOR a combination of rows from
# the complete tensor-column kernel.  The GPU is therefore never allowed to
# leave the exact solution coset; the host nevertheless rebuilds and fully
# verifies every result of rank at most 18 before publishing it.

use core/metal
use flipfleet_rect_archive_nullspace
use flipfleet_225_block_gl_parent_lib

# Complete radius-three coefficient-shell decoder.  A regular d^3 launch is
# intentionally used instead of uploading a 140 MB tuple table; only the
# sorted a<b<c sixth performs the ten-word popcount.  The first pass finds the
# minimum weight, and the second pass deterministically captures the smallest
# tuple at that weight, avoiding a racy weight/winner publication pair.
#
## i64[]: base, basis
## i32[]: best, params
@gpu fn ff225ad_triple_weight(base, basis, best, params)
  tid = gpu.thread_position_in_grid.x ## i32
  dimension = params[0] ## i32
  words = params[1] ## i32
  work = params[2] ## i32
  if tid < work
    square = dimension * dimension ## i32
    a = tid / square ## i32
    remainder = tid - a * square ## i32
    b = remainder / dimension ## i32
    c = remainder - b * dimension ## i32
    if a < b
      if b < c
        weight = 0 ## i32
        word = 0 ## i32
        while word < words
          value = base[word] ^ basis[a * words + word] ^ basis[b * words + word] ^ basis[c * words + word] ## i64
          # Fixed-cost 64-bit SWAR popcount.  The masks are positive signed i64
          # constants, so this lowers portably to ordinary MSL long arithmetic.
          value = value - ((value >> 1) & 6148914691236517205)
          value = (value & 3689348814741910323) + ((value >> 2) & 3689348814741910323)
          value = (value + (value >> 4)) & 1085102592571150095
          weight = weight + ((value * 72340172838076673) >> 56)
          word = word + 1
        old = gpu.atomic_min_i32(best, 0, weight) ## i32

## i64[]: base, basis
## i32[]: best, winner, params
@gpu fn ff225ad_triple_winner(base, basis, best, winner, params)
  tid = gpu.thread_position_in_grid.x ## i32
  dimension = params[0] ## i32
  words = params[1] ## i32
  work = params[2] ## i32
  if tid < work
    square = dimension * dimension ## i32
    a = tid / square ## i32
    remainder = tid - a * square ## i32
    b = remainder / dimension ## i32
    c = remainder - b * dimension ## i32
    if a < b
      if b < c
        weight = 0 ## i32
        word = 0 ## i32
        while word < words
          value = base[word] ^ basis[a * words + word] ^ basis[b * words + word] ^ basis[c * words + word] ## i64
          value = value - ((value >> 1) & 6148914691236517205)
          value = (value & 3689348814741910323) + ((value >> 2) & 3689348814741910323)
          value = (value + (value >> 4)) & 1085102592571150095
          weight = weight + ((value * 72340172838076673) >> 56)
          word = word + 1
        if weight == best[0]
          old = gpu.atomic_min_i32(winner, 0, tid) ## i32

# Exact rank-band annealer.  Each lane owns one affine word in `states` and
# applies only uploaded tensor-kernel relations.  Equal/downhill moves are
# unconditional; small uphill moves are temperature-gated and can never cross
# `band`.  Stalled lanes rotate among independently exact rank-18 origins.
#
## i64[]: states, best_states, origins, generators
## i32[]: telemetry, params
@gpu fn ff225ad_band_walk(states, best_states, origins, generators, telemetry, params)
  lane = gpu.thread_position_in_grid.x ## i32
  lanes = params[0] ## i32
  words = params[1] ## i32
  pool_count = params[2] ## i32
  origin_count = params[3] ## i32
  steps = params[4] ## i32
  band = params[5] ## i32
  nonce = params[6] ## i32
  reset_steps = params[7] ## i32
  if lane < lanes
    state_offset = lane * words ## i32
    home = lane % origin_count ## i32
    current_weight = telemetry[lane * 5] ## i32
    best_weight = telemetry[lane * 5 + 1] ## i32
    best_distance = telemetry[lane * 5 + 2] ## i32
    accepts = telemetry[lane * 5 + 3] ## i32
    resets = telemetry[lane * 5 + 4] ## i32
    rng = ((lane + 1) * 1103515245 + nonce * 12345 + 1013904223) & 2147483647 ## i32
    if rng == 0
      rng = 1
    stall = 0 ## i32
    step = 0 ## i32
    while step < steps
      rng = (rng * 1103515245 + 12345) & 2147483647
      generator = rng % pool_count ## i32
      next_weight = 0 ## i32
      word = 0 ## i32
      while word < words
        value = states[state_offset + word] ^ generators[generator * words + word] ## i64
        value = value - ((value >> 1) & 6148914691236517205)
        value = (value & 3689348814741910323) + ((value >> 2) & 3689348814741910323)
        value = (value + (value >> 4)) & 1085102592571150095
        next_weight = next_weight + ((value * 72340172838076673) >> 56)
        word = word + 1
      accept = 0 ## i32
      if next_weight <= band
        if next_weight <= current_weight
          accept = 1
        else
          delta = next_weight - current_weight ## i32
          rng = (rng * 1103515245 + 12345) & 2147483647
          chance = 2 ## i32
          if delta == 1
            chance = 96
          if delta == 2
            chance = 48
          if delta == 3
            chance = 16
          if (rng & 255) < chance
            accept = 1
      if accept != 0
        word = 0
        while word < words
          states[state_offset + word] = states[state_offset + word] ^ generators[generator * words + word]
          word = word + 1
        current_weight = next_weight
        accepts = accepts + 1
        stall = 0
        if current_weight <= best_weight
          distance = 0 ## i32
          word = 0
          while word < words
            value = states[state_offset + word] ^ origins[home * words + word] ## i64
            value = value - ((value >> 1) & 6148914691236517205)
            value = (value & 3689348814741910323) + ((value >> 2) & 3689348814741910323)
            value = (value + (value >> 4)) & 1085102592571150095
            distance = distance + ((value * 72340172838076673) >> 56)
            word = word + 1
          if current_weight < best_weight
            best_weight = current_weight
            best_distance = distance
            word = 0
            while word < words
              best_states[state_offset + word] = states[state_offset + word]
              word = word + 1
          else
            if distance > best_distance
              best_distance = distance
              word = 0
              while word < words
                best_states[state_offset + word] = states[state_offset + word]
                word = word + 1
      else
        stall = stall + 1
      if stall >= reset_steps
        origin = (home + resets + 1) % origin_count ## i32
        word = 0
        current_weight = 0
        while word < words
          value = origins[origin * words + word] ## i64
          states[state_offset + word] = value
          value = value - ((value >> 1) & 6148914691236517205)
          value = (value & 3689348814741910323) + ((value >> 2) & 3689348814741910323)
          value = (value + (value >> 4)) & 1085102592571150095
          current_weight = current_weight + ((value * 72340172838076673) >> 56)
          word = word + 1
        resets = resets + 1
        stall = 0
      step = step + 1
    telemetry[lane * 5] = current_weight
    telemetry[lane * 5 + 1] = best_weight
    telemetry[lane * 5 + 2] = best_distance
    telemetry[lane * 5 + 3] = accepts
    telemetry[lane * 5 + 4] = resets

-> ff225ad_find(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      return i
    i += 1
  0 - 1

-> ff225ad_add_scheme(scheme, us, vs, ws, count) (FFBCScheme i64[] i64[] i64[] i64) i64
  if scheme == nil || ffbc_verify_exact(scheme) != 1
    return 0 - 1
  i = 0 ## i64
  while i < scheme.rank()
    u = scheme.us()[i] ## i64
    v = scheme.vs()[i] ## i64
    w = scheme.ws()[i] ## i64
    if ff225ad_find(us, vs, ws, count, u, v, w) < 0
      if count >= us.size() || count >= vs.size() || count >= ws.size()
        return 0 - 1
      us[count] = u
      vs[count] = v
      ws[count] = w
      count += 1
    i += 1
  count

-> ff225ad_archive_indices()
  selected = i64[32]
  selected[0] = 2577
  selected[1] = 1182
  selected[2] = 281
  selected[3] = 2650
  selected[4] = 293
  selected[5] = 1097
  selected[6] = 3822
  selected[7] = 151
  selected[8] = 692
  selected[9] = 89
  selected[10] = 1458
  selected[11] = 1181
  selected[12] = 1213
  selected[13] = 3363
  selected[14] = 636
  selected[15] = 1879
  selected[16] = 3169
  selected[17] = 30
  selected[18] = 456
  selected[19] = 1359
  selected[20] = 1530
  selected[21] = 2859
  selected[22] = 2958
  selected[23] = 2830
  selected[24] = 667
  selected[25] = 1082
  selected[26] = 2908
  selected[27] = 3000
  selected[28] = 1449
  selected[29] = 3587
  selected[30] = 3572
  selected[31] = 955
  selected

# Build the five production doors followed by the deterministic 32-parent
# maximin block-local GL archive.  The stable insertion order is shared with
# `flipfleet_225_union_subset_sat.w`.  meta: door union, final union, parents.
-> ff225ad_build_archive32(us, vs, ws, meta) (i64[] i64[] i64[] i64[]) i64
  if us.size() < 700 || vs.size() < 700 || ws.size() < 700 || meta.size() < 3
    return 0 - 1
  root = "benchmarks/matmul/metaflip/" ## String
  paths = []
  paths.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
  count = 0 ## i64
  i = 0 ## i64
  while i < paths.size()
    door = ffbc_load_exact(paths[i], 2, 2, 5, 32)
    if door == nil || door.rank() != 18
      return 0 - 1
    count = ff225ad_add_scheme(door, us, vs, ws, count)
    if count < 1
      return 0 - 1
    i += 1
  meta[0] = count

  leaf3 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 16)
  leaf2 = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
  outer = ff225gl_outer()
  if leaf3 == nil || leaf2 == nil || outer == nil
    return 0 - 1
  indices = ff225ad_archive_indices()
  i = 0
  while i < 32
    parent = ff225gl_parent(leaf3, leaf2, outer, ff225gl_alloc_n(), ff225gl_alloc_m(), ff225gl_alloc_p(), indices[i])
    if parent == nil || parent.rank() != 18
      return 0 - 1
    count = ff225ad_add_scheme(parent, us, vs, ws, count)
    if count < 1
      return 0 - 1
    i += 1
  meta[1] = count
  meta[2] = 32
  count

-> ff225ad_anchor_mask(us, vs, ws, count, mask) (i64[] i64[] i64[] i64 i64[]) i64
  root = "benchmarks/matmul/metaflip/" ## String
  anchor = ffbc_load_exact(root + "matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, 32)
  if anchor == nil || anchor.rank() != 18
    return 0
  z = ffnd_clear(mask, 0, mask.size()) ## i64
  i = 0 ## i64
  while i < anchor.rank()
    coordinate = ff225ad_find(us, vs, ws, count, anchor.us()[i], anchor.vs()[i], anchor.ws()[i]) ## i64
    if coordinate < 0
      return 0
    z = ffnd_set_mask_bit(mask, 0, coordinate)
    i += 1
  1

-> ff225ad_weight(mask, offset, words) (i64[] i64 i64) i64
  weight = 0 ## i64
  word = 0 ## i64
  while word < words
    weight += ffw_popcount(mask[offset + word])
    word += 1
  weight

-> ff225ad_mask_distance(left, left_offset, right, right_offset, words) (i64[] i64 i64[] i64 i64) i64
  distance = 0 ## i64
  word = 0 ## i64
  while word < words
    distance += ffw_popcount(left[left_offset + word] ^ right[right_offset + word])
    word += 1
  distance

-> ff225ad_xor_weight(base, basis, a, b, c, words) (i64[] i64[] i64 i64 i64 i64) i64
  weight = 0 ## i64
  word = 0 ## i64
  while word < words
    value = base[word] ## i64
    if a >= 0
      value = value ^ basis[a * words + word]
    if b >= 0
      value = value ^ basis[b * words + word]
    if c >= 0
      value = value ^ basis[c * words + word]
    weight += ffw_popcount(value)
    word += 1
  weight

-> ff225ad_relation_xor_weight(basis, a, b, words) (i64[] i64 i64 i64) i64
  weight = 0 ## i64
  word = 0 ## i64
  while word < words
    weight += ffw_popcount(basis[a * words + word] ^ basis[b * words + word])
    word += 1
  weight

# meta: pairs, minimum, min-a, min-b, <=4, <=6, <=8, <=12, <=16, <=24,
# <=32, sum weights.
-> ff225ad_pair_relation_stats(basis, dimension, words, meta) (i64[] i64 i64 i64[]) i64
  if dimension < 2 || words < 1 || meta.size() < 12
    return 0
  meta[1] = 0x7fffffff
  a = 0 ## i64
  while a < dimension - 1
    b = a + 1 ## i64
    while b < dimension
      weight = ff225ad_relation_xor_weight(basis, a, b, words) ## i64
      meta[0] += 1
      meta[11] += weight
      if weight < meta[1]
        meta[1] = weight
        meta[2] = a
        meta[3] = b
      if weight <= 4
        meta[4] += 1
      if weight <= 6
        meta[5] += 1
      if weight <= 8
        meta[6] += 1
      if weight <= 12
        meta[7] += 1
      if weight <= 16
        meta[8] += 1
      if weight <= 24
        meta[9] += 1
      if weight <= 32
        meta[10] += 1
      b += 1
    a += 1
  meta[1]

-> ff225ad_scheme_mask(scheme, us, vs, ws, count, mask, offset, words) (FFBCScheme i64[] i64[] i64[] i64 i64[] i64 i64) i64
  if scheme == nil || ffbc_verify_exact(scheme) != 1 || offset < 0 || offset + words > mask.size()
    return 0
  z = ffnd_clear(mask, offset, words) ## i64
  i = 0 ## i64
  while i < scheme.rank()
    coordinate = ff225ad_find(us, vs, ws, count, scheme.us()[i], scheme.vs()[i], scheme.ws()[i]) ## i64
    if coordinate < 0
      return 0
    mask[offset + coordinate / 64] = mask[offset + coordinate / 64] ^ (1 << (coordinate % 64))
    i += 1
  1

# Rebuild all five production doors and the 32 selected block parents as exact
# rank-18 origin words in the stable dictionary coordinate system.
-> ff225ad_build_origins(us, vs, ws, count, origins, words) (i64[] i64[] i64[] i64 i64[] i64) i64
  if origins.size() < 37 * words
    return 0
  root = "benchmarks/matmul/metaflip/" ## String
  paths = []
  paths.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
  made = 0 ## i64
  i = 0 ## i64
  while i < paths.size()
    scheme = ffbc_load_exact(paths[i], 2, 2, 5, 32)
    if scheme == nil || scheme.rank() != 18 || ff225ad_scheme_mask(scheme, us, vs, ws, count, origins, made * words, words) != 1
      return 0
    made += 1
    i += 1
  leaf3 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 16)
  leaf2 = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
  outer = ff225gl_outer()
  indices = ff225ad_archive_indices()
  if leaf3 == nil || leaf2 == nil || outer == nil
    return 0
  i = 0
  while i < 32
    scheme = ff225gl_parent(leaf3, leaf2, outer, ff225gl_alloc_n(), ff225gl_alloc_m(), ff225gl_alloc_p(), indices[i])
    if scheme == nil || scheme.rank() != 18 || ff225ad_scheme_mask(scheme, us, vs, ws, count, origins, made * words, words) != 1
      return 0
    made += 1
    i += 1
  made

# Copy the complete basis plus every pair-XOR relation no heavier than the
# requested threshold into a regular GPU move pool.  Duplicate rows are safe
# (and merely bias exposure), while avoiding host dedup keeps construction
# deterministic and cheap.  meta: basis rows, pair rows, total, truncated.
-> ff225ad_build_sparse_pool(basis, dimension, words, max_pair_weight, pool, max_rows, meta) (i64[] i64 i64 i64 i64[] i64 i64[]) i64
  if dimension < 1 || words < 1 || max_pair_weight < 1 || max_rows < dimension || pool.size() < max_rows * words || meta.size() < 4
    return 0
  count = 0 ## i64
  row = 0 ## i64
  while row < dimension
    z = ffnd_copy(basis, row * words, pool, count * words, words) ## i64
    count += 1
    row += 1
  meta[0] = count
  a = 0 ## i64
  while a < dimension - 1 && count < max_rows
    b = a + 1 ## i64
    while b < dimension && count < max_rows
      weight = ff225ad_relation_xor_weight(basis, a, b, words) ## i64
      if weight <= max_pair_weight
        word = 0 ## i64
        while word < words
          pool[count * words + word] = basis[a * words + word] ^ basis[b * words + word]
          word += 1
        count += 1
        meta[1] += 1
      b += 1
    if b < dimension
      meta[3] = 1
    a += 1
  meta[2] = count
  count

# Build a fresh systematic tensor-kernel basis after a deterministic random
# column permutation, then map every relation back to the stable dictionary
# coordinates.  In the elimination used by `ffran_build_nullspace`, the
# highest permutation position in a dependency is its unique free column.
# `free_coordinates[row]` records that stable coordinate.  meta: rank,
# nullity, reductions, permutation checksum, relation failures.
-> ff225ad_random_systematic_basis(us, vs, ws, count, seed, out_basis, free_coordinates, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  words = (count + 63) / 64 ## i64
  if count < 2 || out_basis.size() < count * words || free_coordinates.size() < count || meta.size() < 5
    return 0
  order = i64[count]
  i = 0 ## i64
  while i < count
    order[i] = i
    i += 1
  rng = seed & 2147483647 ## i64
  if rng == 0
    rng = 1
  i = count - 1
  while i > 0
    rng = (rng * 1103515245 + 12345) & 2147483647
    j = rng % (i + 1) ## i64
    swap = order[i] ## i64
    order[i] = order[j]
    order[j] = swap
    i -= 1
  perm_u = i64[count]
  perm_v = i64[count]
  perm_w = i64[count]
  checksum = 0 ## i64
  i = 0
  while i < count
    stable = order[i] ## i64
    perm_u[i] = us[stable]
    perm_v[i] = vs[stable]
    perm_w[i] = ws[stable]
    checksum = (checksum + (i + 1) * (stable + 1)) & 0x7fffffff
    i += 1
  temporary = i64[count * words]
  elimination = i64[5]
  nullity = ffran_build_nullspace(perm_u, perm_v, perm_w, count, 2, 2, 5, temporary, elimination) ## i64
  if nullity < 1 || elimination[2] + nullity != count
    return 0
  z = ffnd_clear(out_basis, 0, count * words) ## i64
  row = 0 ## i64
  while row < nullity
    free_position = 0 - 1 ## i64
    position = count - 1 ## i64
    while position >= 0 && free_position < 0
      if ffnd_mask_bit(temporary, row * words, position) != 0
        free_position = position
      position -= 1
    if free_position < 0
      return 0
    free_coordinates[row] = order[free_position]
    position = 0
    while position < count
      if ffnd_mask_bit(temporary, row * words, position) != 0
        stable = order[position] ## i64
        out_basis[row * words + stable / 64] = out_basis[row * words + stable / 64] ^ (1 << (stable % 64))
      position += 1
    # The mapped row remains an exact tensor-zero relation, and its free bit
    # must survive the coordinate permutation exactly once.
    if ffnd_mask_bit(out_basis, row * words, free_coordinates[row]) == 0
      meta[4] += 1
      return 0
    row += 1
  meta[0] = elimination[2]
  meta[1] = nullity
  meta[2] = elimination[4]
  meta[3] = checksum
  nullity

# Produce the unique affine solution supported only on the current pivot
# (information-set) columns.  This is the Prange origin.  Enumerating p basis
# rows around it is the Lee-Brickell p-error extension, not an arbitrary walk
# around the original rank-18 word.
-> ff225ad_systematic_origin(base, basis, free_coordinates, dimension, words, out) (i64[] i64[] i64[] i64 i64 i64[]) i64
  if dimension < 1 || words < 1 || out.size() < words
    return 0 - 1
  z = ffnd_copy(base, 0, out, 0, words) ## i64
  row = 0 ## i64
  while row < dimension
    coordinate = free_coordinates[row] ## i64
    if ffnd_mask_bit(out, 0, coordinate) != 0
      z = ffnd_xor(basis, row * words, out, 0, words)
    row += 1
  # Every free coordinate is now zero by the systematic-basis invariant.
  row = 0
  while row < dimension
    if ffnd_mask_bit(out, 0, free_coordinates[row]) != 0
      return 0 - 1
    row += 1
  ff225ad_weight(out, 0, words)

# Run one persistent rank-band epoch.  out_mask receives the best lane word.
# meta: proposals, accepts, resets, best weight, best distance, best lane,
# elapsed ms, host weight.
-> ff225ad_band_gpu(device, library, queue, origins, origin_count, generators, generator_count, words, lanes, steps, band, nonce, reset_steps, out_mask, meta) i64
  if device == nil || library == nil || queue == nil || origin_count < 1 || generator_count < 1 || words < 1 || lanes < 1 || steps < 1 || band < 1 || reset_steps < 1 || out_mask.size() < words || meta.size() < 8
    return 0 - 1
  gpu_origins = metal_array(64, origin_count * words)
  gpu_generators = metal_array(64, generator_count * words)
  i = 0 ## i64
  while i < origin_count * words
    gpu_origins[i] = origins[i]
    i += 1
  i = 0
  while i < generator_count * words
    gpu_generators[i] = generators[i]
    i += 1
  states = metal_array(64, lanes * words)
  best_states = metal_array(64, lanes * words)
  telemetry = metal_array(32, lanes * 5)
  lane = 0 ## i64
  while lane < lanes
    origin = lane % origin_count ## i64
    word = 0 ## i64
    while word < words
      value = origins[origin * words + word] ## i64
      states[lane * words + word] = value
      best_states[lane * words + word] = value
      word += 1
    weight = ff225ad_weight(origins, origin * words, words) ## i64
    telemetry[lane * 5] = weight
    telemetry[lane * 5 + 1] = weight
    lane += 1
  params = metal_array(32, 8)
  params[0] = lanes
  params[1] = words
  params[2] = generator_count
  params[3] = origin_count
  params[4] = steps
  params[5] = band
  params[6] = nonce
  params[7] = reset_steps
  pipeline = metal_pipeline(library, "ff225ad_band_walk")
  started = ccall("__w_clock_ms") ## i64
  metal_dispatch_n(queue, pipeline, [metal_buffer_for(device, states), metal_buffer_for(device, best_states), metal_buffer_for(device, gpu_origins), metal_buffer_for(device, gpu_generators), metal_buffer_for(device, telemetry), metal_buffer_for(device, params)], lanes)
  elapsed = ccall("__w_clock_ms") - started ## i64
  best_lane = 0 ## i64
  best_weight = telemetry[1] ## i64
  best_distance = telemetry[2] ## i64
  lane = 0
  while lane < lanes
    meta[1] += telemetry[lane * 5 + 3]
    meta[2] += telemetry[lane * 5 + 4]
    lane_weight = telemetry[lane * 5 + 1] ## i64
    lane_distance = telemetry[lane * 5 + 2] ## i64
    if lane_weight < best_weight || (lane_weight == best_weight && lane_distance > best_distance)
      best_lane = lane
      best_weight = lane_weight
      best_distance = lane_distance
    lane += 1
  word = 0
  while word < words
    out_mask[word] = best_states[best_lane * words + word]
    word += 1
  host_weight = ff225ad_weight(out_mask, 0, words) ## i64
  if host_weight != best_weight
    return 0 - 1
  meta[0] = lanes * steps
  meta[3] = best_weight
  meta[4] = best_distance
  meta[5] = best_lane
  meta[6] = elapsed
  meta[7] = host_weight
  best_weight

# Exhaust the coefficient shells of radius one and two on the CPU.  This is a
# cheap baseline and an independent oracle for the GPU triple decoder.
# meta: combinations, best weight, best a, best b, basis min/max/sum weight,
# odd-weight basis rows.
-> ff225ad_scan_pairs(base, basis, dimension, words, meta) (i64[] i64[] i64 i64 i64[]) i64
  if dimension < 1 || words < 1 || meta.size() < 7
    return 0 - 1
  best = ff225ad_weight(base, 0, words) ## i64
  best_a = 0 - 1 ## i64
  best_b = 0 - 1 ## i64
  min_row = 0x7fffffff ## i64
  max_row = 0 ## i64
  row_sum = 0 ## i64
  combinations = 0 ## i64
  a = 0 ## i64
  while a < dimension
    row_weight = ff225ad_weight(basis, a * words, words) ## i64
    if row_weight < min_row
      min_row = row_weight
    if row_weight > max_row
      max_row = row_weight
    row_sum += row_weight
    if (row_weight & 1) != 0
      meta[7] += 1
    weight = ff225ad_xor_weight(base, basis, a, 0 - 1, 0 - 1, words) ## i64
    combinations += 1
    if weight < best
      best = weight
      best_a = a
      best_b = 0 - 1
    b = a + 1 ## i64
    while b < dimension
      weight = ff225ad_xor_weight(base, basis, a, b, 0 - 1, words)
      combinations += 1
      if weight < best
        best = weight
        best_a = a
        best_b = b
      b += 1
    a += 1
  meta[0] = combinations
  meta[1] = best
  meta[2] = best_a
  meta[3] = best_b
  meta[4] = min_row
  meta[5] = max_row
  meta[6] = row_sum
  best

# Exhaust every sorted triple of basis coordinates on Metal.  `library` must
# contain the two kernels above.  out_indices receives the deterministic
# minimum tuple.  meta: regular work, sorted triples, best weight, winner tid,
# first-pass ms, second-pass ms.
-> ff225ad_scan_triples_gpu(device, library, queue, base, basis, dimension, words, out_indices, meta) i64
  if device == nil || library == nil || queue == nil || dimension < 3 || words < 1 || out_indices.size() < 3 || meta.size() < 6
    return 0 - 1
  work = dimension * dimension * dimension ## i64
  if work > 2147483647
    return 0 - 1
  gpu_base = metal_array(64, words)
  gpu_basis = metal_array(64, dimension * words)
  word = 0 ## i64
  while word < words
    gpu_base[word] = base[word]
    word += 1
  i = 0 ## i64
  while i < dimension * words
    gpu_basis[i] = basis[i]
    i += 1
  best = metal_array(32, 1)
  best[0] = 0x7fffffff
  winner = metal_array(32, 1)
  winner[0] = work
  params = metal_array(32, 3)
  params[0] = dimension
  params[1] = words
  params[2] = work
  base_buffer = metal_buffer_for(device, gpu_base)
  basis_buffer = metal_buffer_for(device, gpu_basis)
  best_buffer = metal_buffer_for(device, best)
  params_buffer = metal_buffer_for(device, params)
  weight_pipeline = metal_pipeline(library, "ff225ad_triple_weight")
  winner_pipeline = metal_pipeline(library, "ff225ad_triple_winner")
  started = ccall("__w_clock_ms") ## i64
  metal_dispatch_n(queue, weight_pipeline, [base_buffer, basis_buffer, best_buffer, params_buffer], work)
  first_ms = ccall("__w_clock_ms") - started ## i64
  started = ccall("__w_clock_ms")
  metal_dispatch_n(queue, winner_pipeline, [base_buffer, basis_buffer, best_buffer, metal_buffer_for(device, winner), params_buffer], work)
  second_ms = ccall("__w_clock_ms") - started
  tid = winner[0] ## i64
  if tid < 0 || tid >= work
    return 0 - 1
  square = dimension * dimension ## i64
  a = tid / square ## i64
  remainder = tid - a * square ## i64
  b = remainder / dimension ## i64
  c = remainder - b * dimension ## i64
  if a >= b || b >= c || c >= dimension
    return 0 - 1
  # Recompute on the host before trusting either the SWAR code or shared
  # memory visibility.
  host_weight = ff225ad_xor_weight(base, basis, a, b, c, words) ## i64
  if host_weight != best[0]
    return 0 - 1
  out_indices[0] = a
  out_indices[1] = b
  out_indices[2] = c
  meta[0] = work
  meta[1] = dimension * (dimension - 1) * (dimension - 2) / 6
  meta[2] = host_weight
  meta[3] = tid
  meta[4] = first_ms
  meta[5] = second_ms
  host_weight

-> ff225ad_materialize(us, vs, ws, count, mask, max_rank) (i64[] i64[] i64[] i64 i64[] i64)
  rank = ff225ad_weight(mask, 0, (count + 63) / 64) ## i64
  if rank < 1 || rank > max_rank
    return nil
  candidate = FFBCScheme.new(2, 2, 5, rank)
  slot = 0 ## i64
  coordinate = 0 ## i64
  while coordinate < count
    if ffnd_mask_bit(mask, 0, coordinate) != 0
      candidate.us()[slot] = us[coordinate]
      candidate.vs()[slot] = vs[coordinate]
      candidate.ws()[slot] = ws[coordinate]
      slot += 1
    coordinate += 1
  if slot != rank
    return nil
  candidate.set_rank(rank)
  if ffbc_verify_exact(candidate) != 1
    return nil
  candidate

# Full host gate for a basis combination returned by the GPU.  `indices`
# contains up to index_count generator rows.  meta: decoded weight, relation
# exact, candidate exact.
-> ff225ad_gate_indices(us, vs, ws, count, base, basis, dimension, words, indices, index_count, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64 i64 i64[] i64 i64[]) i64
  if index_count < 0 || index_count > indices.size() || meta.size() < 3
    return 0
  mask = i64[words]
  z = ffnd_copy(base, 0, mask, 0, words) ## i64
  i = 0 ## i64
  while i < index_count
    row = indices[i] ## i64
    if row < 0 || row >= dimension
      return 0
    z = ffnd_xor(basis, row * words, mask, 0, words)
    i += 1
  meta[0] = ff225ad_weight(mask, 0, words)
  # Independently prove that each selected row is a tensor-zero relation.
  relation = i64[words]
  i = 0
  while i < index_count
    z = ffnd_xor(basis, indices[i] * words, relation, 0, words)
    i += 1
  meta[1] = ffran_relation_exact(us, vs, ws, count, 2, 2, 5, relation, 0)
  if meta[1] != 1 || meta[0] > 18
    return 0
  candidate = ff225ad_materialize(us, vs, ws, count, mask, 18)
  if candidate == nil
    return 0
  meta[2] = 1
  candidate.rank()
