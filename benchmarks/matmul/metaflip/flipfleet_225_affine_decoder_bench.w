# CPU geometry baseline for the archive32 <2,2,5> affine decoder.

use flipfleet_225_affine_decoder_lib

us = i64[700]
vs = i64[700]
ws = i64[700]
build_meta = i64[4]
started = ccall("__w_clock_ms") ## i64
count = ff225ad_build_archive32(us, vs, ws, build_meta) ## i64
if count < 1
  << "FF225_AFFINE_ERROR dictionary"
  exit(1)
words = (count + 63) / 64 ## i64
base = i64[words]
if ff225ad_anchor_mask(us, vs, ws, count, base) != 1
  << "FF225_AFFINE_ERROR anchor"
  exit(1)
basis = i64[count * words]
elimination = i64[8]
dimension = ffran_build_nullspace(us, vs, ws, count, 2, 2, 5, basis, elimination) ## i64
if dimension < 1 || elimination[2] + dimension != count
  << "FF225_AFFINE_ERROR nullspace"
  exit(1)
pair_meta = i64[8]
pair_started = ccall("__w_clock_ms") ## i64
best = ff225ad_scan_pairs(base, basis, dimension, words, pair_meta) ## i64
pair_ms = ccall("__w_clock_ms") - pair_started ## i64
relation_meta = i64[12]
relation_started = ccall("__w_clock_ms") ## i64
relation_min = ff225ad_pair_relation_stats(basis, dimension, words, relation_meta) ## i64
relation_ms = ccall("__w_clock_ms") - relation_started ## i64
elapsed = ccall("__w_clock_ms") - started ## i64
indices = i64[2]
indices[0] = pair_meta[2]
indices[1] = pair_meta[3]
gate_meta = i64[4]
gate = 0 ## i64
index_count = 2 ## i64
if pair_meta[2] < 0
  index_count = 0
if pair_meta[3] < 0 && index_count > 0
  index_count = 1
if best <= 18
  gate = ff225ad_gate_indices(us, vs, ws, count, base, basis, dimension, words, indices, index_count, gate_meta)
<< "FF225_AFFINE_GEOMETRY union=" + count.to_s() + " column_rank=" + elimination[2].to_s() + " dimension=" + dimension.to_s() + " words=" + words.to_s() + " base_weight=" + ff225ad_weight(base, 0, words).to_s() + " basis_weight_min=" + pair_meta[4].to_s() + " basis_weight_max=" + pair_meta[5].to_s() + " basis_weight_avg_milli=" + (pair_meta[6] * 1000 / dimension).to_s() + " odd_basis_rows=" + pair_meta[7].to_s() + " pair_combinations=" + pair_meta[0].to_s() + " pair_best=" + best.to_s() + " pair_a=" + pair_meta[2].to_s() + " pair_b=" + pair_meta[3].to_s() + " gated_rank=" + gate.to_s() + " pair_ms=" + pair_ms.to_s() + " elapsed_ms=" + elapsed.to_s()
<< "FF225_AFFINE_RELATIONS pairs=" + relation_meta[0].to_s() + " minimum=" + relation_min.to_s() + " min_a=" + relation_meta[2].to_s() + " min_b=" + relation_meta[3].to_s() + " le4=" + relation_meta[4].to_s() + " le6=" + relation_meta[5].to_s() + " le8=" + relation_meta[6].to_s() + " le12=" + relation_meta[7].to_s() + " le16=" + relation_meta[8].to_s() + " le24=" + relation_meta[9].to_s() + " le32=" + relation_meta[10].to_s() + " avg_milli=" + (relation_meta[11] * 1000 / relation_meta[0]).to_s() + " ms=" + relation_ms.to_s()

args = argv()
if args.size() > 0
  source = read_file(args[0])
  if source == nil
    << "FF225_AFFINE_ERROR metal-source"
    exit(1)
  device = metal_device()
  library = metal_compile_source(device, source)
  if library == nil
    << "FF225_AFFINE_ERROR metal-compile"
    exit(1)
  queue = metal_queue(device)
  triple_indices = i64[3]
  triple_meta = i64[8]
  triple_best = ff225ad_scan_triples_gpu(device, library, queue, base, basis, dimension, words, triple_indices, triple_meta) ## i64
  if triple_best < 1
    << "FF225_AFFINE_ERROR triple-scan"
    exit(1)
  triple_gate_meta = i64[4]
  triple_gate = 0 ## i64
  if triple_best <= 18
    triple_gate = ff225ad_gate_indices(us, vs, ws, count, base, basis, dimension, words, triple_indices, 3, triple_gate_meta)
  << "FF225_AFFINE_GPU_TRIPLES regular_work=" + triple_meta[0].to_s() + " sorted_triples=" + triple_meta[1].to_s() + " best=" + triple_best.to_s() + " a=" + triple_indices[0].to_s() + " b=" + triple_indices[1].to_s() + " c=" + triple_indices[2].to_s() + " gated_rank=" + triple_gate.to_s() + " exact_relation=" + triple_gate_meta[1].to_s() + " pass1_ms=" + triple_meta[4].to_s() + " pass2_ms=" + triple_meta[5].to_s()

  lanes = 4096 ## i64
  steps = 10000 ## i64
  band = 24 ## i64
  pair_weight = 16 ## i64
  nonce = 225413 ## i64
  reset_steps = 2048 ## i64
  if args.size() > 1
    lanes = args[1].to_i()
  if args.size() > 2
    steps = args[2].to_i()
  if args.size() > 3
    band = args[3].to_i()
  if args.size() > 4
    pair_weight = args[4].to_i()
  if args.size() > 6
    nonce = args[6].to_i()
  if args.size() > 7
    reset_steps = args[7].to_i()
  origins = i64[37 * words]
  origin_count = ff225ad_build_origins(us, vs, ws, count, origins, words) ## i64
  if origin_count != 37
    << "FF225_AFFINE_ERROR origins"
    exit(1)
  pool = i64[8192 * words]
  pool_meta = i64[4]
  pool_count = ff225ad_build_sparse_pool(basis, dimension, words, pair_weight, pool, 8192, pool_meta) ## i64
  if pool_count < dimension
    << "FF225_AFFINE_ERROR pool"
    exit(1)
  band_mask = i64[words]
  band_meta = i64[8]
  band_best = ff225ad_band_gpu(device, library, queue, origins, origin_count, pool, pool_count, words, lanes, steps, band, nonce, reset_steps, band_mask, band_meta) ## i64
  if band_best < 1
    << "FF225_AFFINE_ERROR band-walk"
    exit(1)
  candidate = nil
  exact_gate = 0 ## i64
  min_origin_distance = count + 1 ## i64
  if band_best <= 18
    candidate = ff225ad_materialize(us, vs, ws, count, band_mask, 18)
    if candidate != nil
      exact_gate = 1
      origin = 0 ## i64
      while origin < origin_count
        distance = ff225ad_mask_distance(band_mask, 0, origins, origin * words, words) ## i64
        if distance < min_origin_distance
          min_origin_distance = distance
        origin += 1
      if args.size() > 5
        z = ffbc_write(args[5], candidate) ## i64
  << "FF225_AFFINE_GPU_BAND lanes=" + lanes.to_s() + " steps=" + steps.to_s() + " proposals=" + band_meta[0].to_s() + " pool=" + pool_count.to_s() + " basis_rows=" + pool_meta[0].to_s() + " sparse_pair_rows=" + pool_meta[1].to_s() + " band=" + band.to_s() + " nonce=" + nonce.to_s() + " reset_steps=" + reset_steps.to_s() + " accepts=" + band_meta[1].to_s() + " resets=" + band_meta[2].to_s() + " best=" + band_best.to_s() + " novelty_distance=" + band_meta[4].to_s() + " min_origin_distance=" + min_origin_distance.to_s() + " exact_gate=" + exact_gate.to_s() + " elapsed_ms=" + band_meta[6].to_s() + " proposals_per_sec=" + (band_meta[0] * 1000 / band_meta[6]).to_s()

  isd_restarts = 0 ## i64
  if args.size() > 8
    isd_restarts = args[8].to_i()
  if isd_restarts > 0
    isd_started = ccall("__w_clock_ms") ## i64
    isd_best = count + 1 ## i64
    prange_min = count + 1 ## i64
    prange_max = 0 ## i64
    pair_min = count + 1 ## i64
    triple_min = count + 1 ## i64
    exact_gates = 0 ## i64
    relation_failures = 0 ## i64
    hit_restart = 0 - 1 ## i64
    restart = 0 ## i64
    while restart < isd_restarts && isd_best > 17
      restart_basis = i64[count * words]
      free_coordinates = i64[count]
      restart_meta = i64[5]
      restart_dimension = ff225ad_random_systematic_basis(us, vs, ws, count, nonce + restart * 104729 + 1, restart_basis, free_coordinates, restart_meta) ## i64
      if restart_dimension != dimension
        << "FF225_AFFINE_ERROR isd-basis restart=" + restart.to_s()
        exit(1)
      # A direct tensor-zero check on a rotating basis row independently
      # audits the permutation/map boundary on every restart.
      audit_row = restart % dimension ## i64
      if ffran_relation_exact(us, vs, ws, count, 2, 2, 5, restart_basis, audit_row * words) != 1
        relation_failures += 1
        << "FF225_AFFINE_ERROR isd-relation restart=" + restart.to_s()
        exit(1)
      systematic = i64[words]
      prange_weight = ff225ad_systematic_origin(base, restart_basis, free_coordinates, dimension, words, systematic) ## i64
      if prange_weight < 1
        << "FF225_AFFINE_ERROR isd-origin restart=" + restart.to_s()
        exit(1)
      if prange_weight < prange_min
        prange_min = prange_weight
      if prange_weight > prange_max
        prange_max = prange_weight
      shell_meta = i64[8]
      shell_best = ff225ad_scan_pairs(systematic, restart_basis, dimension, words, shell_meta) ## i64
      if shell_best < pair_min
        pair_min = shell_best
      if shell_best < isd_best
        isd_best = shell_best
      if shell_best <= 18
        shell_indices = i64[2]
        shell_indices[0] = shell_meta[2]
        shell_indices[1] = shell_meta[3]
        shell_count = 2 ## i64
        if shell_meta[2] < 0
          shell_count = 0
        if shell_meta[3] < 0 && shell_count > 0
          shell_count = 1
        shell_gate_meta = i64[4]
        shell_gate = ff225ad_gate_indices(us, vs, ws, count, systematic, restart_basis, dimension, words, shell_indices, shell_count, shell_gate_meta) ## i64
        if shell_gate != shell_best
          << "FF225_AFFINE_ERROR isd-pair-gate restart=" + restart.to_s()
          exit(1)
        exact_gates += 1
        if shell_best <= 17
          hit_restart = restart
      if isd_best > 17
        isd_indices = i64[3]
        isd_triple_meta = i64[8]
        isd_triple = ff225ad_scan_triples_gpu(device, library, queue, systematic, restart_basis, dimension, words, isd_indices, isd_triple_meta) ## i64
        if isd_triple < triple_min
          triple_min = isd_triple
        if isd_triple < isd_best
          isd_best = isd_triple
        if isd_triple <= 18
          isd_gate_meta = i64[4]
          isd_gate = ff225ad_gate_indices(us, vs, ws, count, systematic, restart_basis, dimension, words, isd_indices, 3, isd_gate_meta) ## i64
          if isd_gate != isd_triple
            << "FF225_AFFINE_ERROR isd-triple-gate restart=" + restart.to_s()
            exit(1)
          exact_gates += 1
          if isd_triple <= 17
            hit_restart = restart
            hit_mask = i64[words]
            z = ffnd_copy(systematic, 0, hit_mask, 0, words) ## i64
            z = ffnd_xor(restart_basis, isd_indices[0] * words, hit_mask, 0, words)
            z = ffnd_xor(restart_basis, isd_indices[1] * words, hit_mask, 0, words)
            z = ffnd_xor(restart_basis, isd_indices[2] * words, hit_mask, 0, words)
            hit = ff225ad_materialize(us, vs, ws, count, hit_mask, 17)
            if hit == nil || hit.rank() != isd_triple
              << "FF225_AFFINE_ERROR isd-hit-materialize"
              exit(1)
            if args.size() > 5
              z = ffbc_write(args[5] + ".isd", hit) ## i64
      restart += 1
    isd_ms = ccall("__w_clock_ms") - isd_started ## i64
    shells = restart * (1 + dimension + dimension * (dimension - 1) / 2 + dimension * (dimension - 1) * (dimension - 2) / 6) ## i64
    << "FF225_AFFINE_ISD restarts=" + restart.to_s() + " requested=" + isd_restarts.to_s() + " candidates=" + shells.to_s() + " prange_min=" + prange_min.to_s() + " prange_max=" + prange_max.to_s() + " pair_min=" + pair_min.to_s() + " triple_min=" + triple_min.to_s() + " best=" + isd_best.to_s() + " exact_gates=" + exact_gates.to_s() + " relation_failures=" + relation_failures.to_s() + " hit_restart=" + hit_restart.to_s() + " elapsed_ms=" + isd_ms.to_s() + " candidates_per_sec=" + (shells * 1000 / isd_ms).to_s()
